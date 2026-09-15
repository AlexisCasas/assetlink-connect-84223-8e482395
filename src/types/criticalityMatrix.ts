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
  parameters: CriticalityTemplateParameter[];
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
  /** Result of this evaluation's weighted score against the MVP thresholds. */
  calculatedCriticality: AssetCriticality;
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
