import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';
import type { Asset, AssetCriticality, AssetNodeType, AssetStatus } from '@/types/asset';
import type { AssetTrafficLight, TrafficLightReason } from '@/types/assetTrafficLight';
import type { PreventivePlan } from '@/types/preventiveMaintenance';
import type { InspectionPlan, InspectionRunSummary } from '@/types/inspection';
import type { MaintenanceNotice } from '@/types/maintenanceNotice';
import type { AssetHistoryItem } from '@/types/assetHistory';
import type { CriticalityAssessment } from '@/types/criticalityMatrix';
import type { AssignablePlanner } from '@/hooks/useOrganizationPlanners';

/**
 * Read-only fetchers for the asset report snapshot. Each one calls EXACTLY
 * the same RPC/table the corresponding feature hook already uses (see
 * docs/ASSET_REPORT.md → "Fuentes") — this file does not introduce a new
 * source of truth, it only re-reads the existing ones without the React
 * state machinery those hooks carry (a loader run once per click has no use
 * for subscriptions/refresh loops). Nothing here mutates anything.
 */

type AssetRow = Database['public']['Tables']['assets']['Row'];

const toAsset = (row: AssetRow): Asset => ({
  id: row.id,
  organizationId: row.organization_id,
  branchId: row.branch_id,
  parentAssetId: row.parent_asset_id,
  assetCategoryId: row.asset_category_id,
  code: row.code,
  name: row.name,
  description: row.description,
  nodeType: row.node_type as AssetNodeType,
  status: row.status as AssetStatus,
  criticality: row.criticality as AssetCriticality | null,
  manufacturer: row.manufacturer,
  model: row.model,
  serialNumber: row.serial_number,
  barcode: row.barcode,
  qrCode: row.qr_code,
  purchaseDate: row.purchase_date,
  warrantyUntil: row.warranty_until,
  locationText: row.location_text,
  imageUrl: row.image_url,
  technicalData: (row.technical_data as Record<string, unknown> | null) ?? {},
  metadata: (row.metadata as Record<string, unknown> | null) ?? {},
  defaultResponsibleMemberId: row.default_responsible_member_id,
  createdByUserId: row.created_by_user_id,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

/** Re-reads the asset row fresh at generation time (never trusts a possibly
 * stale in-memory copy) — RLS re-validates access exactly like any other
 * read. */
export const fetchReportAsset = async (assetId: string): Promise<Asset> => {
  const { data, error } = await supabase.from('assets').select('*').eq('id', assetId).single();
  if (error || !data) throw error ?? new Error('Activo no encontrado.');
  return toAsset(data);
};

/** Null when the asset has no branch, or the branch cannot be resolved
 * (never thrown as a fatal error — the sede is optional context). */
export const fetchReportBranchName = async (branchId: string | null): Promise<string | null> => {
  if (!branchId) return null;
  const { data, error } = await supabase.from('client_branches').select('name').eq('id', branchId).maybeSingle();
  if (error) throw error;
  return data?.name ?? null;
};

export const fetchReportCategoryName = async (categoryId: string | null): Promise<string | null> => {
  if (!categoryId) return null;
  const { data, error } = await supabase.from('asset_categories').select('name').eq('id', categoryId).maybeSingle();
  if (error) throw error;
  return data?.name ?? null;
};

/** Same directory AssetDetail resolves the default responsible against for
 * an owner/admin/manager (the only roles that can generate a report) — see
 * useOrganizationPlanners. Also used to resolve preventive plan
 * responsibles, which get_preventive_maintenance_plans does not name. */
export const fetchReportPlanners = async (organizationId: string): Promise<AssignablePlanner[]> => {
  const { data, error } = await supabase.rpc('get_assignable_planners', { p_organization_id: organizationId });
  if (error) throw error;
  return (data ?? []).map((row) => ({ memberId: row.member_id, userId: row.user_id, name: row.name, email: row.email }));
};

interface RawAssessmentRow {
  id: string; asset_id: string; organization_id: string; score: number;
  calculated_criticality: string; manual_criticality: string | null; effective_criticality: string;
  notes: string | null; created_by_user_id: string | null; created_by_name: string | null; created_at: string;
  answers: Array<{
    parameter_id: string; parameter_name: string; option_id: string | null; option_label: string | null;
    weight: number; option_score: number; weighted_score: number;
  }> | null;
  threshold_medium_min: number | string; threshold_high_min: number | string; threshold_critical_min: number | string;
}

export const fetchReportAssessments = async (assetId: string): Promise<CriticalityAssessment[]> => {
  const { data, error } = await supabase.rpc('get_asset_criticality_assessments', { p_asset_id: assetId });
  if (error) throw error;
  return ((data ?? []) as unknown as RawAssessmentRow[]).map((row) => ({
    id: row.id,
    assetId: row.asset_id,
    organizationId: row.organization_id,
    score: row.score,
    calculatedCriticality: row.calculated_criticality as AssetCriticality,
    manualCriticality: row.manual_criticality as AssetCriticality | null,
    effectiveCriticality: row.effective_criticality as AssetCriticality,
    notes: row.notes,
    createdByUserId: row.created_by_user_id,
    createdByName: row.created_by_name,
    createdAt: row.created_at,
    answers: (row.answers ?? []).map((answer) => ({
      parameterId: answer.parameter_id,
      parameterName: answer.parameter_name,
      optionId: answer.option_id,
      optionLabel: answer.option_label,
      weight: answer.weight,
      optionScore: answer.option_score,
      weightedScore: answer.weighted_score,
    })),
    thresholds: {
      mediumMin: Number(row.threshold_medium_min),
      highMin: Number(row.threshold_high_min),
      criticalMin: Number(row.threshold_critical_min),
    },
  }));
};

const toReason = (row: {
  severity: string; source_type: string; source_table: string; source_id: string;
  title: string; description: string; event_date: string | null; due_at: string | null;
  asset_id: string | null; asset_name: string | null;
}): TrafficLightReason => ({
  severity: row.severity as TrafficLightReason['severity'],
  sourceType: row.source_type as TrafficLightReason['sourceType'],
  sourceTable: row.source_table,
  sourceId: row.source_id,
  title: row.title,
  description: row.description,
  eventDate: row.event_date,
  dueAt: row.due_at,
  assetId: row.asset_id,
  assetName: row.asset_name,
});

/** Org-wide (get_asset_traffic_light has no per-asset parameter) — the
 * caller filters to the one asset it needs. */
export const fetchReportTrafficLight = async (organizationId: string): Promise<AssetTrafficLight[]> => {
  const { data, error } = await supabase.rpc('get_asset_traffic_light', { p_organization_id: organizationId });
  if (error) throw error;
  return ((data ?? []) as unknown as Array<{
    asset_id: string; organization_id: string; branch_id: string | null; parent_asset_id: string | null;
    asset_name: string; asset_code: string | null; node_type: string; status: string; criticality: string | null;
    direct_color: string; rollup_color: string; direct_severity: number; rollup_severity: number;
    direct_reasons: Parameters<typeof toReason>[0][] | null; rollup_reasons: Parameters<typeof toReason>[0][] | null;
    causing_asset_ids: string[] | null; updated_at: string;
  }>).map((row) => ({
    assetId: row.asset_id,
    organizationId: row.organization_id,
    branchId: row.branch_id,
    parentAssetId: row.parent_asset_id,
    assetName: row.asset_name,
    assetCode: row.asset_code,
    nodeType: row.node_type,
    status: row.status,
    criticality: row.criticality,
    directColor: row.direct_color as AssetTrafficLight['directColor'],
    rollupColor: row.rollup_color as AssetTrafficLight['rollupColor'],
    directSeverity: row.direct_severity,
    rollupSeverity: row.rollup_severity,
    directReasons: (row.direct_reasons ?? []).map(toReason),
    rollupReasons: (row.rollup_reasons ?? []).map(toReason),
    causingAssetIds: row.causing_asset_ids ?? [],
    updatedAt: row.updated_at,
  }));
};

/** Org-wide (get_preventive_maintenance_plans has no per-asset parameter) —
 * the RPC row shape already matches PreventivePlan 1:1 (snake_case), same
 * as usePreventiveMaintenance's own direct cast. */
export const fetchReportPreventivePlans = async (organizationId: string): Promise<PreventivePlan[]> => {
  const { data, error } = await supabase.rpc('get_preventive_maintenance_plans', { p_organization_id: organizationId });
  if (error) throw error;
  return (data ?? []) as unknown as PreventivePlan[];
};

const toInspectionPlan = (row: {
  id: string; template_id: string; template_name: string; branch_id: string | null; branch_name: string | null;
  area_asset_id: string | null; area_asset_name: string | null; asset_id: string | null; asset_name: string | null;
  responsible_member_id: string | null; responsible_name: string | null; title: string; description: string | null;
  frequency: string; custom_interval: number | null; custom_unit: string | null; start_date: string;
  next_due_at: string | null; is_active: boolean; created_at: string;
  alert_rules: Array<{ id: string; alert_type: string; days_before: number | null; label: string | null; is_active: boolean }> | null;
}): InspectionPlan => ({
  id: row.id,
  templateId: row.template_id,
  templateName: row.template_name,
  branchId: row.branch_id,
  branchName: row.branch_name,
  areaAssetId: row.area_asset_id,
  areaAssetName: row.area_asset_name,
  assetId: row.asset_id,
  assetName: row.asset_name,
  responsibleMemberId: row.responsible_member_id,
  responsibleName: row.responsible_name,
  hasResponsible: row.responsible_member_id !== null,
  title: row.title,
  description: row.description,
  frequency: row.frequency as InspectionPlan['frequency'],
  customInterval: row.custom_interval,
  customUnit: row.custom_unit as InspectionPlan['customUnit'],
  startDate: row.start_date,
  nextDueAt: row.next_due_at,
  isActive: row.is_active,
  createdAt: row.created_at,
  alertRules: (row.alert_rules ?? []).map((rule) => ({
    id: rule.id,
    planId: row.id,
    alertType: rule.alert_type as InspectionPlan['alertRules'][number]['alertType'],
    daysBefore: rule.days_before,
    label: rule.label,
    isActive: rule.is_active,
  })),
});

/** Org-wide, include_inactive=true so a deactivated plan is still shown
 * (labeled inactive) instead of silently disappearing from the report. */
export const fetchReportInspectionPlans = async (organizationId: string): Promise<InspectionPlan[]> => {
  const { data, error } = await supabase.rpc('get_inspection_plans', { p_organization_id: organizationId, p_include_inactive: true });
  if (error) throw error;
  return ((data ?? []) as unknown as Parameters<typeof toInspectionPlan>[0][]).map(toInspectionPlan);
};

const toRunSummary = (row: {
  id: string; organization_id: string; plan_id: string | null; template_id: string; template_name: string;
  branch_name: string | null; area_asset_name: string | null; asset_name: string | null;
  responsible_member_id: string | null; responsible_name: string | null; scheduled_for: string | null;
  started_at: string | null; completed_at: string | null; status: string; result: string | null;
}): InspectionRunSummary => ({
  id: row.id,
  organizationId: row.organization_id,
  planId: row.plan_id,
  templateId: row.template_id,
  templateName: row.template_name,
  branchName: row.branch_name,
  areaAssetName: row.area_asset_name,
  assetName: row.asset_name,
  responsibleMemberId: row.responsible_member_id,
  responsibleName: row.responsible_name,
  hasResponsible: row.responsible_member_id !== null,
  scheduledFor: row.scheduled_for,
  startedAt: row.started_at,
  completedAt: row.completed_at,
  status: row.status as InspectionRunSummary['status'],
  result: row.result as InspectionRunSummary['result'],
});

/** Org-wide. Correlated to a plan via `planId` (uuid, not the run's asset
 * name text column) — see fetchReportInspectionPlans; runs are matched to
 * THIS asset only through the plan they belong to. */
export const fetchReportInspectionRuns = async (organizationId: string): Promise<InspectionRunSummary[]> => {
  const { data, error } = await supabase.rpc('get_inspection_runs', { p_organization_id: organizationId });
  if (error) throw error;
  return ((data ?? []) as unknown as Parameters<typeof toRunSummary>[0][]).map(toRunSummary);
};

const toNotice = (row: {
  id: string; organization_id: string; notice_number: string; asset_id: string; title: string; description: string;
  priority: string; status: string; source_type: string; source_id: string | null;
  source_metadata: Record<string, unknown> | null; asset_name_snapshot: string | null; asset_code_snapshot: string | null;
  asset_path_snapshot: string | null; branch_id_snapshot: string | null; branch_name_snapshot: string | null;
  asset_current_criticality: string | null; reported_by_user_id: string | null; reported_by_name: string | null;
  reported_at: string; responsible_member_id: string | null; responsible_name: string | null; triage_notes: string | null;
  triaged_by_name: string | null; triaged_at: string | null; converted_request_id: string | null;
  converted_request_number: string | null; converted_by_name: string | null; converted_at: string | null;
  dismissal_reason: string | null; dismissed_by_name: string | null; dismissed_at: string | null; created_at: string;
}): MaintenanceNotice => ({
  id: row.id,
  organizationId: row.organization_id,
  noticeNumber: row.notice_number,
  assetId: row.asset_id,
  title: row.title,
  description: row.description,
  priority: row.priority as MaintenanceNotice['priority'],
  status: row.status as MaintenanceNotice['status'],
  sourceType: row.source_type as MaintenanceNotice['sourceType'],
  sourceId: row.source_id,
  sourceMetadata: {
    templateName: typeof row.source_metadata?.template_name === 'string' ? row.source_metadata.template_name : undefined,
    itemId: typeof row.source_metadata?.item_id === 'string' ? row.source_metadata.item_id : undefined,
    itemQuestion: typeof row.source_metadata?.item_question === 'string' ? row.source_metadata.item_question : undefined,
    responseLabel: typeof row.source_metadata?.response_label === 'string' ? row.source_metadata.response_label : undefined,
  },
  assetNameSnapshot: row.asset_name_snapshot,
  assetCodeSnapshot: row.asset_code_snapshot,
  assetPathSnapshot: row.asset_path_snapshot,
  branchIdSnapshot: row.branch_id_snapshot,
  branchNameSnapshot: row.branch_name_snapshot,
  assetCurrentCriticality: (row.asset_current_criticality as AssetCriticality | null) ?? null,
  reportedByUserId: row.reported_by_user_id,
  reportedByName: row.reported_by_name,
  reportedAt: row.reported_at,
  responsibleMemberId: row.responsible_member_id,
  responsibleName: row.responsible_name,
  triageNotes: row.triage_notes,
  triagedByName: row.triaged_by_name,
  triagedAt: row.triaged_at,
  convertedRequestId: row.converted_request_id,
  convertedRequestNumber: row.converted_request_number,
  convertedByName: row.converted_by_name,
  convertedAt: row.converted_at,
  dismissalReason: row.dismissal_reason,
  dismissedByName: row.dismissed_by_name,
  dismissedAt: row.dismissed_at,
  createdAt: row.created_at,
});

/** Org-wide (get_maintenance_notices has no per-asset parameter). */
export const fetchReportNotices = async (organizationId: string): Promise<MaintenanceNotice[]> => {
  const { data, error } = await supabase.rpc('get_maintenance_notices', { p_organization_id: organizationId });
  if (error) throw error;
  return ((data ?? []) as unknown as Parameters<typeof toNotice>[0][]).map(toNotice);
};

/** The single source for the operational history section — never rebuilt
 * from requests/work orders/interventions directly. Keeps the RPC's own
 * `ORDER BY event_date DESC`. */
export const fetchReportHistory = async (assetId: string): Promise<AssetHistoryItem[]> => {
  const { data, error } = await supabase.rpc('get_asset_integrated_history', { p_asset_id: assetId });
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: row.id,
    eventType: row.event_type as AssetHistoryItem['eventType'],
    eventLabel: row.event_label,
    eventDate: row.event_date,
    actorName: row.actor_name,
    actorEmail: row.actor_email,
    sourceTable: row.source_table,
    sourceId: row.source_id,
    title: row.title,
    description: row.description,
    status: row.status,
    metadata: (row.metadata as Record<string, unknown>) ?? {},
  }));
};
