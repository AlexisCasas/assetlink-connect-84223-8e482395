/** 'daily' is a legacy technical value kept only for backward compatibility
 * with any pre-existing plan row — the MVP UI never offers it as a choice.
 * See docs/INSPECTION_SCHEDULING_ALERTS.md. */
export type InspectionFrequency = 'one_time' | 'daily' | 'weekly' | 'monthly' | 'quarterly' | 'semiannual' | 'annual' | 'custom';

export type InspectionCustomUnit = 'days' | 'weeks' | 'months' | 'years';

export type InspectionRunStatus = 'scheduled' | 'in_progress' | 'completed' | 'cancelled' | 'overdue';

export type InspectionRunResult = 'passed' | 'failed' | 'not_applicable';

export type InspectionAlertType = 'before_due' | 'overdue';

/** Configurable "avisar N días antes" / "avisar cuando esté vencido" rule
 * for one plan — works identically for ITSE, luces de emergencia, techos,
 * or any other template's plan. Never ITSE-specific. */
export interface InspectionAlertRule {
  id: string;
  planId: string;
  alertType: InspectionAlertType;
  /** Required (>= 0) for before_due; always null for overdue. */
  daysBefore: number | null;
  label: string | null;
  isActive: boolean;
}

/** Local draft shape for the plan form's "Alertas" section — no id yet,
 * matches the p_rules payload replace_inspection_plan_alert_rules expects. */
export interface InspectionAlertRuleDraft {
  alertType: InspectionAlertType;
  daysBefore: number | null;
  label: string;
}

/** One row per plan — flat, already resolved (template/target/responsible
 * names), matching get_inspection_plans. */
export interface InspectionPlan {
  id: string;
  templateId: string;
  templateName: string;
  branchId: string | null;
  branchName: string | null;
  areaAssetId: string | null;
  areaAssetName: string | null;
  assetId: string | null;
  assetName: string | null;
  responsibleMemberId: string | null;
  responsibleName: string | null;
  title: string;
  description: string | null;
  frequency: InspectionFrequency;
  /** Only meaningful when frequency = 'custom'; null otherwise. */
  customInterval: number | null;
  customUnit: InspectionCustomUnit | null;
  startDate: string;
  nextDueAt: string | null;
  isActive: boolean;
  createdAt: string;
  alertRules: InspectionAlertRule[];
}

export interface InspectionPlanInput {
  templateId: string;
  title: string;
  branchId?: string | null;
  areaAssetId?: string | null;
  assetId?: string | null;
  responsibleMemberId?: string | null;
  description?: string | null;
  frequency: InspectionFrequency;
  customInterval?: number | null;
  customUnit?: InspectionCustomUnit | null;
  startDate: string;
  nextDueAt?: string | null;
  isActive?: boolean;
}

export interface InspectionRunAnswer {
  id?: string;
  templateItemId: string;
  responseOptionId: string | null;
  itemQuestion: string;
  responseLabel: string | null;
  responseValue: string | null;
  isFailure: boolean;
  observations: string | null;
}

export interface InspectionRunEvidence {
  id?: string;
  answerId?: string | null;
  templateItemId?: string | null;
  fileName: string;
  fileUrl: string | null;
  filePath: string | null;
  mimeType: string | null;
  sizeBytes: number | null;
  notes: string | null;
}

/** Full bundle returned by get_inspection_run_detail: header + active
 * template items/options + any answers/evidences already saved. */
export interface InspectionRunDetail {
  id: string;
  organizationId: string;
  planId: string | null;
  templateId: string;
  templateName: string;
  branchId: string | null;
  branchName: string | null;
  areaAssetId: string | null;
  areaAssetName: string | null;
  assetId: string | null;
  assetName: string | null;
  responsibleMemberId: string | null;
  responsibleName: string | null;
  scheduledFor: string | null;
  startedAt: string | null;
  completedAt: string | null;
  status: InspectionRunStatus;
  result: InspectionRunResult | null;
  notes: string | null;
  createdAt: string;
  items: Array<{
    id: string;
    section: string | null;
    question: string;
    helpText: string | null;
    sequence: number;
    isRequired: boolean;
  }>;
  responseOptions: Array<{
    id: string;
    label: string;
    value: string;
    isFailure: boolean;
    sequence: number;
  }>;
  answers: InspectionRunAnswer[];
  evidences: InspectionRunEvidence[];
}

/** Flat row for the ejecuciones/historial list — same shape as the
 * inspection_runs table itself, plus resolved names. */
export interface InspectionRunSummary {
  id: string;
  organizationId: string;
  planId: string | null;
  templateId: string;
  templateName: string;
  branchName: string | null;
  areaAssetName: string | null;
  assetName: string | null;
  responsibleMemberId: string | null;
  responsibleName: string | null;
  scheduledFor: string | null;
  startedAt: string | null;
  completedAt: string | null;
  status: InspectionRunStatus;
  result: InspectionRunResult | null;
}

/** Per-item selection while filling out a run — local UI state, not the
 * server payload shape (see submitInspectionRun in useInspectionRuns.ts
 * for the mapping). */
export interface InspectionRunAnswerDraft {
  templateItemId: string;
  responseOptionId: string | null;
  observations: string;
  evidenceFileName: string;
  evidenceFileUrl: string;
}
