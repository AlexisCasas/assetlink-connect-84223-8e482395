import {
  CONFIGURATION_KEYS,
  CONFIGURATION_SHEET_NAME,
  CRITICALITY_EXCEL_CONTRACT_VERSION,
  type ParsedBulkWorkbook,
  type ParsedConfigurationSheet,
  type ParsedMatrixRow,
  type ParsedMatrixWorkbook,
} from '@/lib/criticalityExcel';
import { parseThresholdInput, validateThresholdValues } from '@/lib/criticalityThresholds';
import type {
  BulkCriticalityPreviewRow,
  BulkCriticalityRow,
  CriticalityMatrixPayloadParameter,
  CriticalityParameter,
  CriticalityThresholdValues,
} from '@/types/criticalityMatrix';

/**
 * Structural validation of the two Excel contracts, before anything reaches
 * the backend. This layer never computes a criticality score: the definitive
 * validation and the score always come from SQL
 * (replace_criticality_matrix / preview_bulk_asset_criticality, both built on
 * validate_and_score_asset_criticality). What lives here is only what the
 * backend cannot see — the shape of the spreadsheet itself, and the mapping
 * from human labels back to real ids.
 */

export interface ImportIssue {
  row?: number;
  message: string;
}

export interface MatrixImportPreview {
  parameters: CriticalityMatrixPayloadParameter[];
  errors: ImportIssue[];
  warnings: ImportIssue[];
  totalWeight: number;
  parameterCount: number;
  optionCount: number;
  /** Thresholds the import will apply; null when the file has no
   * "Configuración" sheet (legacy) — current thresholds are then kept. */
  thresholds: CriticalityThresholdValues | null;
  hasConfigurationSheet: boolean;
}

export interface BulkImportPreparation {
  /** Rows resolvable to real ids — these are the ones sent to the server. */
  rows: BulkCriticalityRow[];
  /** Rows already known to be invalid client-side (bad UUID, unknown option
   * label). They are shown in the preview but never sent. */
  clientInvalidRows: BulkCriticalityPreviewRow[];
  /** Problems with the file itself (missing/ambiguous parameter columns). */
  structuralErrors: string[];
  warnings: string[];
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const parseNumber = (raw: string): number | null => {
  const normalized = raw.replace(',', '.').trim();
  if (normalized === '') return null;
  const value = Number(normalized);
  return Number.isFinite(value) ? value : null;
};

const TRUE_VALUES = new Set(['sí', 'si', 's', 'true', 'verdadero', '1', 'x']);
const FALSE_VALUES = new Set(['no', 'n', 'false', 'falso', '0']);

const parseActive = (raw: string): boolean | null => {
  const normalized = raw.trim().toLowerCase();
  if (normalized === '') return true;
  if (TRUE_VALUES.has(normalized)) return true;
  if (FALSE_VALUES.has(normalized)) return false;
  return null;
};

const normalizeKey = (value: string): string =>
  value.trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

/**
 * Turns the flat "one row per option" sheet back into the nested payload
 * replace_criticality_matrix expects, reporting every problem found instead
 * of stopping at the first one (the user should see the whole list at once).
 */
export function validateMatrixRows(rows: ParsedMatrixRow[]): MatrixImportPreview {
  const errors: ImportIssue[] = [];
  const warnings: ImportIssue[] = [];
  const byCode = new Map<string, CriticalityMatrixPayloadParameter & { sourceRow: number }>();
  const optionCodesByParameter = new Map<string, Set<string>>();

  if (rows.length === 0) {
    errors.push({ message: 'La hoja "Matriz" no tiene filas de datos.' });
    return { parameters: [], errors, warnings, totalWeight: 0, parameterCount: 0, optionCount: 0, thresholds: null, hasConfigurationSheet: false };
  }

  rows.forEach((row) => {
    const at = row.rowNumber;

    if (row.parameterCode === '') {
      errors.push({ row: at, message: 'Falta el código de parámetro.' });
      return;
    }
    if (row.parameterName === '') {
      errors.push({ row: at, message: `Parámetro ${row.parameterCode}: falta el nombre.` });
      return;
    }

    const weight = parseNumber(row.weight);
    if (weight === null) {
      errors.push({ row: at, message: `Parámetro ${row.parameterCode}: "Peso %" debe ser numérico.` });
      return;
    }
    if (weight < 0) {
      errors.push({ row: at, message: `Parámetro ${row.parameterCode}: el peso no puede ser negativo.` });
      return;
    }

    const parameterSequence = parseNumber(row.parameterSequence);
    if (parameterSequence === null || !Number.isInteger(parameterSequence) || parameterSequence <= 0) {
      errors.push({ row: at, message: `Parámetro ${row.parameterCode}: "Orden parámetro" debe ser un entero mayor a 0.` });
      return;
    }

    const activeFlag = parseActive(row.active);
    if (activeFlag === null) {
      errors.push({ row: at, message: `Fila ${at}: "Activo" debe ser Sí o No.` });
      return;
    }

    const key = normalizeKey(row.parameterCode);
    const existing = byCode.get(key);

    if (!existing) {
      byCode.set(key, {
        code: row.parameterCode,
        name: row.parameterName,
        description: row.description === '' ? null : row.description,
        weight,
        sequence: parameterSequence,
        // A parameter row is active unless every one of its rows says No —
        // the flag lives per option row in the sheet, so the parameter takes
        // the value of its first row.
        isActive: activeFlag,
        options: [],
        sourceRow: at,
      });
      optionCodesByParameter.set(key, new Set());
    } else {
      // Same code repeated with different parameter-level data is exactly the
      // inconsistency the contract warns about.
      if (existing.name !== row.parameterName) {
        errors.push({ row: at, message: `Código ${row.parameterCode}: el nombre difiere del usado en la fila ${existing.sourceRow}.` });
      }
      if (existing.weight !== weight) {
        errors.push({ row: at, message: `Código ${row.parameterCode}: el peso difiere del usado en la fila ${existing.sourceRow}.` });
      }
      if (existing.sequence !== parameterSequence) {
        errors.push({ row: at, message: `Código ${row.parameterCode}: el orden difiere del usado en la fila ${existing.sourceRow}.` });
      }
    }

    // An empty option block is allowed only as the "parameter without options"
    // placeholder the export writes; it is rejected later if the parameter is
    // active, because an active parameter must be answerable.
    if (row.optionCode === '' && row.optionLabel === '' && row.score === '') return;

    const parameter = byCode.get(key)!;
    if (row.optionCode === '') {
      errors.push({ row: at, message: `Parámetro ${row.parameterCode}: falta el código de opción.` });
      return;
    }
    if (row.optionLabel === '') {
      errors.push({ row: at, message: `Parámetro ${row.parameterCode}: falta la etiqueta de la opción ${row.optionCode}.` });
      return;
    }

    const score = parseNumber(row.score);
    if (score === null) {
      errors.push({ row: at, message: `Opción ${row.optionCode}: "Puntaje" debe ser numérico.` });
      return;
    }
    if (score < 0) {
      errors.push({ row: at, message: `Opción ${row.optionCode}: el puntaje no puede ser negativo.` });
      return;
    }

    const optionSequence = parseNumber(row.optionSequence);
    if (optionSequence === null || !Number.isInteger(optionSequence) || optionSequence <= 0) {
      errors.push({ row: at, message: `Opción ${row.optionCode}: "Orden opción" debe ser un entero mayor a 0.` });
      return;
    }

    const optionCodes = optionCodesByParameter.get(key)!;
    const optionKey = normalizeKey(row.optionCode);
    if (optionCodes.has(optionKey)) {
      errors.push({ row: at, message: `Parámetro ${row.parameterCode}: el código de opción ${row.optionCode} está repetido.` });
      return;
    }
    optionCodes.add(optionKey);

    parameter.options.push({
      code: row.optionCode,
      label: row.optionLabel,
      score,
      sequence: optionSequence,
      isActive: activeFlag,
    });
  });

  const parameters = Array.from(byCode.values()).map(({ sourceRow, ...parameter }) => {
    void sourceRow;
    return parameter;
  });

  parameters.forEach((parameter) => {
    if (parameter.isActive && parameter.options.filter((option) => option.isActive).length === 0) {
      errors.push({ message: `Parámetro ${parameter.code}: un parámetro activo necesita al menos una opción activa.` });
    }
  });

  const totalWeight = Math.round(
    parameters.filter((parameter) => parameter.isActive).reduce((sum, parameter) => sum + parameter.weight, 0) * 100,
  ) / 100;

  if (parameters.length > 0 && totalWeight !== 100) {
    warnings.push({
      message: `La suma de pesos activos es ${totalWeight}% (lo recomendado es 100%). Puedes importar igual.`,
    });
  }

  return {
    parameters,
    errors,
    warnings,
    totalWeight,
    parameterCount: parameters.length,
    optionCount: parameters.reduce((sum, parameter) => sum + parameter.options.length, 0),
    thresholds: null,
    hasConfigurationSheet: false,
  };
}

/**
 * Structural check of the "Configuración" sheet. The backend
 * (replace_criticality_configuration) revalidates the same rules; this only
 * lets the preview show problems before anything is sent.
 */
export function validateConfigurationSheet(configuration: ParsedConfigurationSheet): {
  thresholds: CriticalityThresholdValues | null;
  errors: ImportIssue[];
} {
  const errors: ImportIssue[] = [];
  const sheet = `Hoja "${CONFIGURATION_SHEET_NAME}"`;

  if (configuration.version !== CRITICALITY_EXCEL_CONTRACT_VERSION) {
    errors.push({
      message: configuration.version === ''
        ? `${sheet}: falta "${CONFIGURATION_KEYS.version}".`
        : `${sheet}: versión de contrato "${configuration.version}" no soportada (se esperaba ${CRITICALITY_EXCEL_CONTRACT_VERSION}).`,
    });
  }

  const fields = [
    ['mediumMin', CONFIGURATION_KEYS.mediumMin],
    ['highMin', CONFIGURATION_KEYS.highMin],
    ['criticalMin', CONFIGURATION_KEYS.criticalMin],
  ] as const;
  const values: Partial<CriticalityThresholdValues> = {};
  fields.forEach(([field, label]) => {
    const raw = configuration[field];
    const value = parseThresholdInput(raw);
    if (value === null) {
      errors.push({
        message: raw === ''
          ? `${sheet}: falta "${label}".`
          : `${sheet}: "${label}" debe ser un número >= 0 con como máximo 2 decimales (valor: "${raw}").`,
      });
    } else {
      values[field] = value;
    }
  });

  if (errors.length > 0) return { thresholds: null, errors };

  const thresholds = values as CriticalityThresholdValues;
  validateThresholdValues(thresholds).forEach((message) => errors.push({ message: `${sheet}: ${message}` }));
  return { thresholds: errors.length > 0 ? null : thresholds, errors };
}

/** Arguments of replace_criticality_configuration (snake_case payload).
 * thresholds = null (legacy file) keeps the organization's current ones. */
export function toReplaceConfigurationArgs(
  parameters: CriticalityMatrixPayloadParameter[],
  thresholds: CriticalityThresholdValues | null,
) {
  return {
    p_thresholds: thresholds
      ? { medium_min: thresholds.mediumMin, high_min: thresholds.highMin, critical_min: thresholds.criticalMin }
      : null,
    p_matrix: {
      parameters: parameters.map((parameter) => ({
        code: parameter.code,
        name: parameter.name,
        description: parameter.description ?? null,
        weight: parameter.weight,
        sequence: parameter.sequence,
        is_active: parameter.isActive,
        options: parameter.options.map((option) => ({
          code: option.code,
          label: option.label,
          score: option.score,
          sequence: option.sequence,
          is_active: option.isActive,
        })),
      })),
    },
  };
}

/** Matrix sheet + optional "Configuración" sheet, as one preview. Any
 * threshold error blocks the whole import: matrix and thresholds are applied
 * together or not at all. */
export function validateMatrixWorkbook(parsed: ParsedMatrixWorkbook): MatrixImportPreview {
  const preview = validateMatrixRows(parsed.rows);
  if (!parsed.configuration) return preview;
  const { thresholds, errors } = validateConfigurationSheet(parsed.configuration);
  return {
    ...preview,
    errors: [...preview.errors, ...errors],
    thresholds,
    hasConfigurationSheet: true,
  };
}

/**
 * Maps the "Evaluaciones" sheet onto real parameter/option ids using the
 * CURRENTLY loaded live matrix. Column headers are the human parameter names
 * (that is what the user sees and edits); ambiguity or drift between the file
 * and the live matrix is reported rather than guessed.
 */
export function prepareBulkRows(
  parsed: ParsedBulkWorkbook,
  activeParameters: CriticalityParameter[],
): BulkImportPreparation {
  const structuralErrors: string[] = [];
  const warnings: string[] = [];

  const parametersByName = new Map<string, CriticalityParameter[]>();
  activeParameters.forEach((parameter) => {
    const key = normalizeKey(parameter.name);
    parametersByName.set(key, [...(parametersByName.get(key) ?? []), parameter]);
  });

  // header -> parameter (only unambiguous matches are usable)
  const headerToParameter = new Map<string, CriticalityParameter>();
  parsed.parameterHeaders.forEach((header) => {
    const matches = parametersByName.get(normalizeKey(header)) ?? [];
    if (matches.length === 1) {
      headerToParameter.set(header, matches[0]);
    } else if (matches.length > 1) {
      structuralErrors.push(`La columna "${header}" coincide con más de un parámetro activo con el mismo nombre. Renombra los parámetros para poder importar.`);
    } else {
      warnings.push(`La columna "${header}" no corresponde a ningún parámetro activo y será ignorada.`);
    }
  });

  const coveredParameterIds = new Set(Array.from(headerToParameter.values()).map((parameter) => parameter.id));
  activeParameters.forEach((parameter) => {
    if (!coveredParameterIds.has(parameter.id)) {
      structuralErrors.push(`Falta la columna del parámetro activo "${parameter.name}". Descarga la plantilla nuevamente.`);
    }
  });

  const rows: BulkCriticalityRow[] = [];
  const clientInvalidRows: BulkCriticalityPreviewRow[] = [];

  parsed.rows.forEach((row) => {
    const errors: string[] = [];

    if (!UUID_PATTERN.test(row.assetId)) {
      errors.push('El "ID interno" no es un identificador válido de activo. No modifiques esa columna.');
    }

    const answers: BulkCriticalityRow['answers'] = [];

    headerToParameter.forEach((parameter, header) => {
      const raw = row.answers[header] ?? '';
      if (raw === '') {
        errors.push(`Falta ${parameter.name}`);
        return;
      }
      const option = parameter.options.find(
        (candidate) => candidate.isActive && normalizeKey(candidate.label) === normalizeKey(raw),
      );
      if (!option) {
        errors.push(`La opción "${raw}" no existe para ${parameter.name}`);
        return;
      }
      answers.push({ parameterId: parameter.id, optionId: option.id });
    });

    if (errors.length > 0) {
      clientInvalidRows.push({
        rowNumber: row.rowNumber,
        assetId: UUID_PATTERN.test(row.assetId) ? row.assetId : null,
        assetCode: row.assetCode || null,
        assetName: row.assetName || null,
        valid: false,
        score: null,
        calculatedCriticality: null,
        errors,
        warnings: [],
      });
      return;
    }

    rows.push({
      rowNumber: row.rowNumber,
      assetId: row.assetId,
      answers,
      notes: row.notes === '' ? null : row.notes,
    });
  });

  return { rows, clientInvalidRows, structuralErrors, warnings };
}
