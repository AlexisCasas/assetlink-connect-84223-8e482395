import type { AssetCriticality } from '@/types/asset';

export interface CriticalityOption {
  id: string;
  label: string;
  score: number;
  sequence: number;
  isActive: boolean;
}

export interface CriticalityParameter {
  id: string;
  name: string;
  description: string | null;
  weight: number;
  sequence: number;
  isActive: boolean;
  options: CriticalityOption[];
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
