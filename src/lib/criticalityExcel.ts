import type { CriticalityParameter } from '@/types/criticalityMatrix';

/**
 * Excel contract for the criticality module. ExcelJS is imported dynamically
 * on purpose: it is by far the heaviest dependency in the app, and nothing
 * here runs until the user actually opens an import/export flow — so it gets
 * code-split out of the main bundle instead of loading on every page.
 *
 * OneFacility only ever reads workbooks it generated itself (fixed sheet and
 * column names below). Arbitrary spreadsheets are deliberately NOT
 * interpreted — see docs/CRITICALITY_V2_TEMPLATES_EXCEL.md.
 */

export const MATRIX_SHEET_NAME = 'Matriz';
export const INSTRUCTIONS_SHEET_NAME = 'Instrucciones';
export const BULK_SHEET_NAME = 'Evaluaciones';
export const OPTIONS_SHEET_NAME = 'Opciones';

/** Exact, stable column order of the "Matriz" sheet — one row per option, the
 * parameter columns repeated on each of its option rows. */
export const MATRIX_COLUMNS = [
  'Código parámetro',
  'Parámetro',
  'Descripción',
  'Peso %',
  'Orden parámetro',
  'Código opción',
  'Opción',
  'Puntaje',
  'Orden opción',
  'Activo',
] as const;

/** Fixed leading columns of the "Evaluaciones" sheet. Everything between
 * these and "Notas" is one column per active parameter. */
export const BULK_FIXED_COLUMNS = ['ID interno', 'Código activo', 'Activo', 'Ruta'] as const;
export const BULK_NOTES_COLUMN = 'Notas';

export interface ParsedMatrixRow {
  rowNumber: number;
  parameterCode: string;
  parameterName: string;
  description: string;
  weight: string;
  parameterSequence: string;
  optionCode: string;
  optionLabel: string;
  score: string;
  optionSequence: string;
  active: string;
}

export interface ParsedBulkRow {
  rowNumber: number;
  assetId: string;
  assetCode: string;
  assetName: string;
  /** Parameter column header (human name) -> raw cell text. */
  answers: Record<string, string>;
  notes: string;
}

export interface ParsedBulkWorkbook {
  parameterHeaders: string[];
  rows: ParsedBulkRow[];
}

export interface BulkTemplateAsset {
  id: string;
  code: string | null;
  name: string;
  path: string;
}

/** Minimal shape of the ExcelJS pieces used here, so this module stays typed
 * without pulling ExcelJS's types into the main bundle. */
type AnyCellValue = unknown;

const loadExcelJs = async () => {
  const mod = await import('exceljs');
  return ((mod as unknown as { default?: unknown }).default ?? mod) as typeof import('exceljs');
};

/** ExcelJS cell values are a union (string | number | rich text | formula
 * result | hyperlink | date | null); everything the contract needs is text. */
const cellText = (value: AnyCellValue): string => {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'number' || typeof value === 'boolean') return String(value).trim();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') {
    const candidate = value as { text?: unknown; result?: unknown; richText?: Array<{ text?: string }> };
    if (Array.isArray(candidate.richText)) return candidate.richText.map((part) => part.text ?? '').join('').trim();
    if (candidate.text !== undefined) return cellText(candidate.text);
    if (candidate.result !== undefined) return cellText(candidate.result);
  }
  return '';
};

const toBlob = (buffer: ArrayBuffer | Uint8Array): Blob =>
  new Blob([buffer as BlobPart], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  });

export const downloadBlob = (blob: Blob, fileName: string): void => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
};

const fileDateStamp = (): string => new Date().toISOString().slice(0, 10);

const slugifyForFileName = (value: string): string =>
  (value || 'organizacion')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase() || 'organizacion';

export const matrixFileName = (organizationName: string): string =>
  `criticidad_${slugifyForFileName(organizationName)}_${fileDateStamp()}.xlsx`;

export const bulkTemplateFileName = (organizationName: string): string =>
  `criticidad_evaluacion_${slugifyForFileName(organizationName)}_${fileDateStamp()}.xlsx`;

export const bulkErrorsFileName = (organizationName: string): string =>
  `criticidad_errores_${slugifyForFileName(organizationName)}_${fileDateStamp()}.xlsx`;

const INSTRUCTIONS: string[][] = [
  ['Cómo editar este archivo'],
  [''],
  ['1. No agregues, quites ni renombres columnas de la hoja "Matriz".'],
  ['2. Las filas se agrupan por "Código parámetro": repite el mismo código en cada una de sus opciones.'],
  ['3. "Código parámetro" y "Código opción" son los identificadores técnicos y deben ser únicos'],
  ['   (el código de opción, único dentro de su parámetro). Si cambias un código, se trata como uno nuevo.'],
  ['4. "Peso %" debe ser un número mayor o igual a 0.'],
  ['5. "Puntaje" debe ser un número mayor o igual a 0.'],
  ['6. "Orden parámetro" y "Orden opción" deben ser enteros mayores a 0.'],
  ['7. "Activo" acepta Sí / No.'],
  ['8. Que la suma de pesos sea 100% es lo recomendado, pero NO es obligatorio:'],
  ['   si no suma 100 verás una advertencia, no un error.'],
  [''],
  ['Al importar, OneFacility vuelve a validar todo el archivo y reemplaza la matriz activa.'],
  ['La configuración anterior queda desactivada (nunca se borra) y las evaluaciones'],
  ['históricas se conservan intactas.'],
];

/** Exports the live matrix — active and inactive — one row per option. */
export async function buildMatrixWorkbook(
  parameters: CriticalityParameter[],
  organizationName: string,
): Promise<Blob> {
  const ExcelJS = await loadExcelJs();
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'OneFacility';
  workbook.created = new Date();

  const sheet = workbook.addWorksheet(MATRIX_SHEET_NAME);
  sheet.addRow([...MATRIX_COLUMNS]);
  sheet.getRow(1).font = { bold: true };
  sheet.columns = MATRIX_COLUMNS.map((header) => ({ width: Math.max(14, header.length + 4) }));

  parameters.forEach((parameter) => {
    const optionRows = parameter.options.length > 0 ? parameter.options : [null];
    optionRows.forEach((option) => {
      sheet.addRow([
        parameter.code,
        parameter.name,
        parameter.description ?? '',
        parameter.weight,
        parameter.sequence,
        option?.code ?? '',
        option?.label ?? '',
        option?.score ?? '',
        option?.sequence ?? '',
        (option ? option.isActive : parameter.isActive) ? 'Sí' : 'No',
      ]);
    });
  });

  const instructions = workbook.addWorksheet(INSTRUCTIONS_SHEET_NAME);
  instructions.columns = [{ width: 110 }];
  INSTRUCTIONS.forEach((row) => instructions.addRow(row));
  instructions.getRow(1).font = { bold: true };

  void organizationName;
  return toBlob(await workbook.xlsx.writeBuffer());
}

export async function parseMatrixWorkbook(file: File): Promise<ParsedMatrixRow[]> {
  const ExcelJS = await loadExcelJs();
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(await file.arrayBuffer());

  const sheet = workbook.getWorksheet(MATRIX_SHEET_NAME);
  if (!sheet) {
    throw new Error(`El archivo no tiene una hoja "${MATRIX_SHEET_NAME}".`);
  }

  const headers = (sheet.getRow(1).values as AnyCellValue[] | undefined) ?? [];
  // ExcelJS row.values is 1-based (index 0 is always empty).
  const headerTexts = MATRIX_COLUMNS.map((_, index) => cellText(headers[index + 1]));
  const missing = MATRIX_COLUMNS.filter((column, index) => headerTexts[index] !== column);
  if (missing.length > 0) {
    throw new Error(`Faltan o cambiaron columnas en la hoja "${MATRIX_SHEET_NAME}": ${missing.join(', ')}.`);
  }

  const rows: ParsedMatrixRow[] = [];
  sheet.eachRow((row, rowNumber) => {
    if (rowNumber === 1) return;
    const values = row.values as AnyCellValue[];
    const cells = MATRIX_COLUMNS.map((_, index) => cellText(values[index + 1]));
    if (cells.every((cell) => cell === '')) return;
    rows.push({
      rowNumber,
      parameterCode: cells[0],
      parameterName: cells[1],
      description: cells[2],
      weight: cells[3],
      parameterSequence: cells[4],
      optionCode: cells[5],
      optionLabel: cells[6],
      score: cells[7],
      optionSequence: cells[8],
      active: cells[9],
    });
  });

  return rows;
}

/**
 * Bulk evaluation template: one row per evaluable asset, one column per
 * ACTIVE parameter (header = the parameter's human name), plus the fixed
 * reference columns. "ID interno" carries the real assets.id UUID — it is the
 * only technical identity; code/name/path are human reference only and are
 * never used to resolve an asset.
 */
export async function buildBulkTemplateWorkbook(
  assets: BulkTemplateAsset[],
  parameters: CriticalityParameter[],
  organizationName: string,
): Promise<Blob> {
  const ExcelJS = await loadExcelJs();
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'OneFacility';
  workbook.created = new Date();

  const sheet = workbook.addWorksheet(BULK_SHEET_NAME);
  const header = [...BULK_FIXED_COLUMNS, ...parameters.map((parameter) => parameter.name), BULK_NOTES_COLUMN];
  sheet.addRow(header);
  sheet.getRow(1).font = { bold: true };
  sheet.columns = header.map((title, index) => ({
    width: index === 0 ? 38 : Math.max(16, title.length + 4),
  }));

  assets.forEach((asset) => {
    sheet.addRow([asset.id, asset.code ?? '', asset.name, asset.path, ...parameters.map(() => ''), '']);
  });

  const optionsSheet = workbook.addWorksheet(OPTIONS_SHEET_NAME);
  optionsSheet.addRow(['Código parámetro', 'Parámetro', 'Valores permitidos']);
  optionsSheet.getRow(1).font = { bold: true };
  optionsSheet.columns = [{ width: 26 }, { width: 34 }, { width: 80 }];
  parameters.forEach((parameter) => {
    optionsSheet.addRow([
      parameter.code,
      parameter.name,
      parameter.options.map((option) => option.label).join(' / '),
    ]);
  });

  // Dropdown per parameter column, using the option labels. Best-effort: if a
  // parameter has no options the column simply stays free text.
  parameters.forEach((parameter, parameterIndex) => {
    if (parameter.options.length === 0) return;
    const columnIndex = BULK_FIXED_COLUMNS.length + parameterIndex + 1;
    const formula = `"${parameter.options.map((option) => option.label.replace(/"/g, "'")).join(',')}"`;
    if (formula.length > 255) return; // Excel's inline list limit — skip, the Opciones sheet still documents it.
    for (let rowIndex = 2; rowIndex <= assets.length + 1; rowIndex += 1) {
      sheet.getCell(rowIndex, columnIndex).dataValidation = {
        type: 'list',
        allowBlank: true,
        formulae: [formula],
      };
    }
  });

  void organizationName;
  return toBlob(await workbook.xlsx.writeBuffer());
}

export async function parseBulkWorkbook(file: File): Promise<ParsedBulkWorkbook> {
  const ExcelJS = await loadExcelJs();
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(await file.arrayBuffer());

  const sheet = workbook.getWorksheet(BULK_SHEET_NAME);
  if (!sheet) {
    throw new Error(`El archivo no tiene una hoja "${BULK_SHEET_NAME}".`);
  }

  const headerValues = (sheet.getRow(1).values as AnyCellValue[] | undefined) ?? [];
  const headers: string[] = [];
  for (let index = 1; index < headerValues.length; index += 1) {
    headers.push(cellText(headerValues[index]));
  }

  BULK_FIXED_COLUMNS.forEach((column, index) => {
    if (headers[index] !== column) {
      throw new Error(`La hoja "${BULK_SHEET_NAME}" no tiene la columna "${column}" en la posición esperada.`);
    }
  });

  const notesIndex = headers.lastIndexOf(BULK_NOTES_COLUMN);
  const parameterHeaders = headers.slice(
    BULK_FIXED_COLUMNS.length,
    notesIndex === -1 ? headers.length : notesIndex,
  ).filter((header) => header !== '');

  const rows: ParsedBulkRow[] = [];
  sheet.eachRow((row, rowNumber) => {
    if (rowNumber === 1) return;
    const values = row.values as AnyCellValue[];
    const assetId = cellText(values[1]);
    const assetCode = cellText(values[2]);
    const assetName = cellText(values[3]);
    const answers: Record<string, string> = {};
    parameterHeaders.forEach((header, index) => {
      answers[header] = cellText(values[BULK_FIXED_COLUMNS.length + index + 1]);
    });
    const notes = notesIndex === -1 ? '' : cellText(values[notesIndex + 1]);

    const hasAnyAnswer = Object.values(answers).some((value) => value !== '');
    if (assetId === '' && !hasAnyAnswer) return;

    rows.push({ rowNumber, assetId, assetCode, assetName, answers, notes });
  });

  return { parameterHeaders, rows };
}

/** Downloadable report of the rows that were left out of an import. */
export async function buildBulkErrorsWorkbook(
  rows: Array<{ rowNumber: number; assetCode: string | null; assetName: string | null; errors: string[] }>,
): Promise<Blob> {
  const ExcelJS = await loadExcelJs();
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'OneFacility';
  const sheet = workbook.addWorksheet('Errores');
  sheet.addRow(['Fila', 'Código activo', 'Activo', 'Errores']);
  sheet.getRow(1).font = { bold: true };
  sheet.columns = [{ width: 10 }, { width: 20 }, { width: 40 }, { width: 90 }];
  rows.forEach((row) => {
    sheet.addRow([row.rowNumber, row.assetCode ?? '', row.assetName ?? '', row.errors.join(' | ')]);
  });
  return toBlob(await workbook.xlsx.writeBuffer());
}
