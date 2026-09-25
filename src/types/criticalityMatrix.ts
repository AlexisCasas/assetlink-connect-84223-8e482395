import type { AssetCriticality } from '@/types/asset';

export interface CriticalityOption {
  id: string;
  /** Stable technical code — what the Excel round-trip keys on, never the
   * label. Unique (case-insensitive) among the ACTIVE options of its
   * parameter; auto-generated from the label when not supplied. */
  code: string;
  label: string;
  score: number;
  sequence: number;
  isActive: boolean;
}

export interface CriticalityParameter {
  id: string;
  /** Stable technical code — unique (case-insensitive) among the ACTIVE
   * parameters of the organization. See docs/CRITICALITY_V2_TEMPLATES_EXCEL.md. */
  code: string;
  name: string;
  description: string | null;
  weight: number;
  sequence: number;
  isActive: boolean;
  options: CriticalityOption[];
}

/** Payload shape of replace_criticality_matrix — the backend revalidates all
 * of it, this type only keeps the frontend honest about what it sends. */
export interface CriticalityMatrixPayloadOption {
  code: string;
  label: string;
  score: number;
  sequence: number;
  isActive: boolean;
}

export interface CriticalityMatrixPayloadParameter {
  code: string;
  name: string;
  description?: string | null;
  weight: number;
  sequence: number;
  isActive: boolean;
  options: CriticalityMatrixPayloadOption[];
}

export type CriticalityTemplateScope = 'system' | 'organization';

export interface CriticalityTemplateSummary {
  id: string;
  organizationId: string | null;
  scope: CriticalityTemplateScope;
  name: string;
  description: string | null;
  category: string | null;
  isActive: boolean;
  parameterCount: number;
  optionCount: number;
  totalWeight: number;
  createdAt: string;
}

export interface CriticalityTemplateOption {
  id: string;
  code: string;
  label: string;
  score: number;
  sequence: number;
  isActive: boolean;
}

export interface CriticalityTemplateParameter {
  id: string;
  code: string;
  name: string;
  description: string | null;
  weight: number;
  sequence: number;
  isActive: boolean;
  options: CriticalityTemplateOption[];
}

export interface CriticalityTemplateDetail {
  id: string;
  organizationId: string | null;
  scope: CriticalityTemplateScope;
  name: string;
  description: string | null;
  category: string | null;
  isActive: boolean;
  createdAt: string;
  /** null for legacy templates saved before thresholds existed: applying
   * them keeps the organization's current thresholds. */
  thresholds: CriticalityThresholdValues | null;
  /** Score range the template's matrix can produce, computed server-side. */
  minPossibleScore: number | null;
  maxPossibleScore: number | null;
  /** Categories the template's own thresholds can never reach with its own
   * matrix (server-side; empty for legacy templates). */
  unreachableCategories: AssetCriticality[];
  parameters: CriticalityTemplateParameter[];
}

/** The three configurable cut points. Each one is the INCLUSIVE lower bound
 * of its category: Baja < mediumMin ≤ Media < highMin ≤ Alta < criticalMin ≤ Muy Alta. */
export interface CriticalityThresholdValues {
  mediumMin: number;
  highMin: number;
  criticalMin: number;
}

/** get_criticality_thresholds / set_criticality_thresholds. Every derived
 * value (isDefault, score range, unreachable categories) comes from SQL. */
export interface CriticalityThresholds extends CriticalityThresholdValues {
  organizationId: string;
  /** True when the effective values are exactly the defaults — whether or
   * not a row exists (a "Restablecer" writes an explicit 25/50/75 row). */
  isDefault: boolean;
  defaults: CriticalityThresholdValues;
  updatedAt: string | null;
  updatedByName: string | null;
  activeMatrix: {
    parameterCount: number;
    minPossibleScore: number | null;
    maxPossibleScore: number | null;
  };
  unreachableCategories: AssetCriticality[];
}

/** Server-side preview of one evaluation (preview_bulk_asset_criticality
 * with a single row). Never computed in the browser. */
export interface CriticalityAssessmentPreview {
  valid: boolean;
  score: number | null;
  calculatedCriticality: AssetCriticality | null;
  errors: string[];
}

/** One asset's answers, as sent to preview_bulk_asset_criticality /
 * bulk_calculate_asset_criticality. `rowNumber` is the Excel row it came
 * from, so every message can point the user back at the file. */
export interface BulkCriticalityRow {
  rowNumber: number;
  assetId: string;
  answers: CriticalityAnswer[];
  notes?: string | null;
}

export interface BulkCriticalityPreviewRow {
  rowNumber: number;
  assetId: string | null;
  assetCode: string | null;
  assetName: string | null;
  valid: boolean;
  score: number | null;
  calculatedCriticality: AssetCriticality | null;
  errors: string[];
  warnings: string[];
}

export interface BulkCriticalityResult {
  evaluated: number;
  counts: Record<AssetCriticality, number>;
  results: Array<{
    rowNumber: number;
    assetId: string;
    assessmentId: string;
    score: number;
    calculatedCriticality: AssetCriticality;
  }>;
}

export interface CriticalityParameterInput {
  name: string;
  description?: string | null;
  weight: number;
  sequence: number;
  isActive?: boolean;
}

export interface CriticalityOptionInput {
  parameterId: string;
  label: string;
  score: number;
  sequence: number;
  isActive?: boolean;
}

/** One selected option per active parameter, sent to calculate_asset_criticality. */
export interface CriticalityAnswer {
  parameterId: string;
  optionId: string | null;
}

export interface CriticalityAssessmentAnswer {
  parameterId: string;
  parameterName: string;
  optionId: string | null;
  optionLabel: string | null;
  weight: number;
  optionScore: number;
  weightedScore: number;
}

export interface CriticalityAssessment {
  id: string;
  assetId: string;
  organizationId: string;
  score: number;
  /** Result of this evaluation's weighted score against the thresholds the
   * organization had at that moment (see `thresholds`). */
  calculatedCriticality: AssetCriticality;
  /** Frozen snapshot of the thresholds used. Later changes never rewrite it. */
  thresholds: CriticalityThresholdValues;
  /** Snapshot of assets.criticality right before this evaluation ran. */
  manualCriticality: AssetCriticality | null;
  /** Always equal to calculatedCriticality in this MVP — no manual override
   * of a calculated result yet. See docs/CONFIGURABLE_CRITICALITY_MATRIX.md. */
  effectiveCriticality: AssetCriticality;
  notes: string | null;
  createdByUserId: string | null;
  createdByName: string | null;
  createdAt: string;
  answers: CriticalityAssessmentAnswer[];
}
