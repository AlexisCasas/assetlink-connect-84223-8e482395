import { ASSET_CRITICALITY_LABELS, ASSET_CRITICALITY_ORDER } from '@/lib/assetLabels';
import type { AssetCriticality } from '@/types/asset';
import type { CriticalityThresholdValues, CriticalityThresholds } from '@/types/criticalityMatrix';

/**
 * Criticality thresholds helpers. Nothing here classifies a score: the only
 * classification lives in SQL (classify_criticality_score, used by
 * validate_and_score_asset_criticality). This module only maps the server
 * payload, formats the configured ranges for display, and pre-validates what
 * the user types so obvious mistakes are shown before a round trip — the
 * backend revalidates everything anyway.
 */

interface RawThresholdValues {
  medium_min: number | string;
  high_min: number | string;
  critical_min: number | string;
}

export interface RawCriticalityThresholds extends RawThresholdValues {
  organization_id: string;
  is_default: boolean;
  defaults: RawThresholdValues;
  updated_at: string | null;
  updated_by_name: string | null;
  active_matrix: {
    parameter_count: number;
    min_possible_score: number | string | null;
    max_possible_score: number | string | null;
  };
  unreachable_categories: string[] | null;
}

const toNumberOrNull = (value: number | string | null | undefined): number | null =>
  value === null || value === undefined ? null : Number(value);

export const toThresholdValues = (raw: RawThresholdValues): CriticalityThresholdValues => ({
  mediumMin: Number(raw.medium_min),
  highMin: Number(raw.high_min),
  criticalMin: Number(raw.critical_min),
});

const isCriticality = (value: string): value is AssetCriticality =>
  (ASSET_CRITICALITY_ORDER as string[]).includes(value);

export const toCriticalityCategories = (values: string[] | null | undefined): AssetCriticality[] =>
  (values ?? []).filter(isCriticality);

export const toCriticalityThresholds = (raw: RawCriticalityThresholds): CriticalityThresholds => ({
  ...toThresholdValues(raw),
  organizationId: raw.organization_id,
  isDefault: raw.is_default,
  defaults: toThresholdValues(raw.defaults),
  updatedAt: raw.updated_at,
  updatedByName: raw.updated_by_name,
  activeMatrix: {
    parameterCount: raw.active_matrix?.parameter_count ?? 0,
    minPossibleScore: toNumberOrNull(raw.active_matrix?.min_possible_score),
    maxPossibleScore: toNumberOrNull(raw.active_matrix?.max_possible_score),
  },
  unreachableCategories: toCriticalityCategories(raw.unreachable_categories),
});

export const formatThresholdNumber = (value: number): string =>
  new Intl.NumberFormat('es-PE', { maximumFractionDigits: 2 }).format(value);

export const formatThresholdTriplet = (values: CriticalityThresholdValues): string =>
  `${formatThresholdNumber(values.mediumMin)} / ${formatThresholdNumber(values.highMin)} / ${formatThresholdNumber(values.criticalMin)}`;

export interface ThresholdRange {
  criticality: AssetCriticality;
  label: string;
  range: string;
}

/** The four configured ranges as text. Lower bounds are inclusive. */
export const thresholdRanges = (values: CriticalityThresholdValues): ThresholdRange[] => {
  const m = formatThresholdNumber(values.mediumMin);
  const h = formatThresholdNumber(values.highMin);
  const c = formatThresholdNumber(values.criticalMin);
  return [
    { criticality: 'low', label: ASSET_CRITICALITY_LABELS.low, range: `score < ${m}` },
    { criticality: 'medium', label: ASSET_CRITICALITY_LABELS.medium, range: `${m} ≤ score < ${h}` },
    { criticality: 'high', label: ASSET_CRITICALITY_LABELS.high, range: `${h} ≤ score < ${c}` },
    { criticality: 'critical', label: ASSET_CRITICALITY_LABELS.critical, range: `score ≥ ${c}` },
  ];
};

export const THRESHOLDS_CHANGE_NOTICE =
  'Los cambios aplican a evaluaciones nuevas. Las evaluaciones anteriores conservan su clasificación y los umbrales utilizados.';

export const THRESHOLD_FIELD_LABELS: Record<keyof CriticalityThresholdValues, string> = {
  mediumMin: 'Media desde',
  highMin: 'Alta desde',
  criticalMin: 'Muy Alta desde',
};

/** Accepts "25", "25.5", "25,50". Rejects negatives, more than 2 decimals,
 * exponents and anything non-numeric. Returns null when invalid. */
export const parseThresholdInput = (raw: string): number | null => {
  const normalized = raw.trim().replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(normalized)) return null;
  const value = Number(normalized);
  return Number.isFinite(value) && value <= 99999999.99 ? value : null;
};

/** Same rules the server enforces (assert_valid_criticality_thresholds),
 * reported as messages for the form / import preview. */
export const validateThresholdValues = (values: CriticalityThresholdValues): string[] => {
  const errors: string[] = [];
  if (!(values.mediumMin < values.highMin && values.highMin < values.criticalMin)) {
    errors.push('Los umbrales deben ser estrictamente ascendentes: Media < Alta < Muy Alta.');
  }
  return errors;
};
