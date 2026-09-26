import { sanitizeFilenameSegment } from '@/lib/assetQr';
import type { Asset } from '@/types/asset';
import type { PreventiveFrequency, PreventiveTimingStatus, PreventiveTriggerType } from '@/types/preventiveMaintenance';
import type { InspectionFrequency, InspectionRunResult, InspectionRunStatus } from '@/types/inspection';

/**
 * Small, report-only formatting helpers. No fonts are embedded (approved
 * decision: use the PDF engine's standard fonts only), so any character
 * outside WinAnsi that could show up in free text coming from the database
 * is normalized to plain ASCII here — never in the stored data itself.
 */

const SYMBOL_REPLACEMENTS: Array<[RegExp, string]> = [
  [/→/g, '-'],
  [/≤/g, '<='],
  [/≥/g, '>='],
];

/** Trims and normalizes problematic symbols for the PDF's standard fonts.
 * Never mutates the source value — only used while building the report
 * snapshot / rendering the document. */
export const pdfText = (value: string | null | undefined): string => {
  if (!value) return '';
  return SYMBOL_REPLACEMENTS.reduce((acc, [pattern, replacement]) => acc.replace(pattern, replacement), value);
};

const DATE_FORMATTER = new Intl.DateTimeFormat('es-PE', { day: '2-digit', month: '2-digit', year: 'numeric' });
const DATETIME_FORMATTER = new Intl.DateTimeFormat('es-PE', {
  day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit',
});

export const formatReportDate = (value: string | null | undefined): string => {
  if (!value) return 'No especificado';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 'No especificado' : DATE_FORMATTER.format(date);
};

export const formatReportDateTime = (value: string | null | undefined): string => {
  if (!value) return 'No especificado';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? 'No especificado' : DATETIME_FORMATTER.format(date);
};

/** `reporte-activo-<codigo-o-nombre>-<uuid8>-YYYYMMDD.pdf` — same slugging
 * rule as the QR filename (Punto 4), kept in this module rather than
 * assetQr.ts since it is specific to the report, not the QR feature. */
export const buildAssetReportFilename = (asset: { id: string; name: string; code: string | null }, generatedAt: Date): string => {
  const base = asset.code?.trim() || asset.name;
  const slug = sanitizeFilenameSegment(base);
  const shortId = asset.id.slice(0, 8);
  const yyyy = generatedAt.getFullYear();
  const mm = String(generatedAt.getMonth() + 1).padStart(2, '0');
  const dd = String(generatedAt.getDate()).padStart(2, '0');
  return `reporte-activo-${slug}-${shortId}-${yyyy}${mm}${dd}.pdf`;
};

/** Humanizes a technicalData key for display: `plan_mantenimiento` →
 * "Plan Mantenimiento". Purely cosmetic — never used to reinterpret the
 * value. */
const humanizeKey = (key: string): string => key
  .replace(/[_-]+/g, ' ')
  .trim()
  .split(' ')
  .filter(Boolean)
  .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
  .join(' ');

/** Only primitive (string/number/boolean) values are shown, humanized keys,
 * skipping null/undefined/objects/arrays — never prints raw JSON. */
export const extractTechnicalFields = (technicalData: Record<string, unknown>): Array<{ label: string; value: string }> =>
  Object.entries(technicalData)
    .filter(([, value]) => value !== null && value !== undefined && (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean'))
    .filter(([, value]) => !(typeof value === 'string' && value.trim() === ''))
    .map(([key, value]) => ({ label: humanizeKey(key), value: pdfText(String(value)) }));

export const PREVENTIVE_TRIGGER_LABELS: Record<PreventiveTriggerType, string> = {
  calendar: 'Calendario',
  meter: 'Medidor',
};

export const PREVENTIVE_FREQUENCY_LABELS: Record<PreventiveFrequency, string> = {
  weekly: 'Semanal',
  monthly: 'Mensual',
  quarterly: 'Trimestral',
  semiannual: 'Semestral',
  annual: 'Anual',
  custom: 'Personalizada',
};

/** Same wording AssetDetail already shows in its "Preventivo" tab. */
export const PREVENTIVE_TIMING_STATUS_LABELS: Record<PreventiveTimingStatus, string> = {
  no_reading: 'Sin lectura de medidor',
  overdue: 'Vencido',
  due: 'Por atender',
  upcoming: 'Próximo',
};

/** Same wording InspectionsView already uses for its plan/run lists. */
export const INSPECTION_FREQUENCY_LABELS: Record<InspectionFrequency, string> = {
  one_time: 'Única vez',
  daily: 'Diaria',
  weekly: 'Semanal',
  monthly: 'Mensual',
  quarterly: 'Trimestral',
  semiannual: 'Semestral',
  annual: 'Anual',
  custom: 'Personalizada',
};

export const INSPECTION_RESULT_LABELS: Record<InspectionRunResult, string> = {
  passed: 'Conforme',
  failed: 'No conforme',
  not_applicable: 'No aplica',
};

/** Same wording InspectionsView already uses for a run's own status
 * (independent from its result — a run can be "Cancelada" with no result). */
export const INSPECTION_RUN_STATUS_LABELS: Record<InspectionRunStatus, string> = {
  scheduled: 'Programada',
  in_progress: 'En progreso',
  completed: 'Completada',
  cancelled: 'Cancelada',
  overdue: 'Vencida',
};

export const CUSTOM_UNIT_LABELS: Record<'days' | 'weeks' | 'months' | 'years', string> = {
  days: 'días',
  weeks: 'semanas',
  months: 'meses',
  years: 'años',
};

/** Walks `parentAssetId` from the already-loaded asset list (never a new
 * query) up to the root, returning names oldest-ancestor-first, own asset
 * last. Bounded by a visited-set so a corrupted/cyclic parent chain can
 * never loop forever — it just stops early instead. */
export const resolveAssetPathNames = (allAssets: Asset[], asset: Asset): string[] => {
  const byId = new Map(allAssets.map((item) => [item.id, item]));
  const names: string[] = [];
  const visited = new Set<string>();
  let current: Asset | undefined = asset;
  while (current && !visited.has(current.id)) {
    visited.add(current.id);
    names.unshift(current.name);
    current = current.parentAssetId ? byId.get(current.parentAssetId) : undefined;
  }
  return names;
};
