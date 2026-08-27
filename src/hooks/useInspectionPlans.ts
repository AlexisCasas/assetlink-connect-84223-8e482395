import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type {
  InspectionAlertRule,
  InspectionAlertRuleDraft,
  InspectionCustomUnit,
  InspectionFrequency,
  InspectionPlan,
  InspectionPlanInput,
} from '@/types/inspection';

interface RawAlertRule {
  id: string;
  alert_type: string;
  days_before: number | null;
  label: string | null;
  is_active: boolean;
}

const toAlertRule = (row: RawAlertRule, planId: string): InspectionAlertRule => ({
  id: row.id,
  planId,
  alertType: row.alert_type as InspectionAlertRule['alertType'],
  daysBefore: row.days_before,
  label: row.label,
  isActive: row.is_active,
});

interface RawPlan {
  id: string;
  template_id: string;
  template_name: string;
  branch_id: string | null;
  branch_name: string | null;
  area_asset_id: string | null;
  area_asset_name: string | null;
  asset_id: string | null;
  asset_name: string | null;
  responsible_member_id: string | null;
  responsible_name: string | null;
  title: string;
  description: string | null;
  frequency: string;
  custom_interval: number | null;
  custom_unit: string | null;
  start_date: string;
  next_due_at: string | null;
  is_active: boolean;
  created_at: string;
  alert_rules: RawAlertRule[] | null;
}

const toPlan = (row: RawPlan): InspectionPlan => ({
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
  title: row.title,
  description: row.description,
  frequency: row.frequency as InspectionFrequency,
  customInterval: row.custom_interval,
  customUnit: row.custom_unit as InspectionCustomUnit | null,
  startDate: row.start_date,
  nextDueAt: row.next_due_at,
  isActive: row.is_active,
  createdAt: row.created_at,
  alertRules: (row.alert_rules ?? []).map((rule) => toAlertRule(rule, row.id)),
});

/**
 * Recurring inspection schedules (sede/área/activo + responsable +
 * periodicidad + alertas configurables) for one organization.
 * get_inspection_plans/upsert_inspection_plan/replace_inspection_plan_alert_rules
 * — all SECURITY DEFINER, see docs/INSPECTION_SCHEDULING_ALERTS.md.
 */
export function useInspectionPlans(organizationId: string | null | undefined) {
  const [plans, setPlans] = useState<InspectionPlan[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setPlans([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_inspection_plans', {
        p_organization_id: organizationId,
        p_include_inactive: true,
      });
      if (rpcError) throw rpcError;
      setPlans(((data ?? []) as unknown as RawPlan[]).map(toPlan));
    } catch (err) {
      setPlans([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los planes de inspección.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const savePlan = useCallback(async (input: InspectionPlanInput, planId?: string): Promise<string | null> => {
    if (!organizationId) return null;
    setSaving(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('upsert_inspection_plan', {
        p_organization_id: organizationId,
        p_template_id: input.templateId,
        p_title: input.title,
        p_branch_id: input.branchId ?? null,
        p_area_asset_id: input.areaAssetId ?? null,
        p_asset_id: input.assetId ?? null,
        p_responsible_member_id: input.responsibleMemberId ?? null,
        p_description: input.description ?? null,
        p_frequency: input.frequency,
        p_start_date: input.startDate,
        p_next_due_at: input.nextDueAt ?? null,
        p_plan_id: planId ?? null,
        p_is_active: input.isActive ?? true,
        p_custom_interval: input.frequency === 'custom' ? input.customInterval ?? null : null,
        p_custom_unit: input.frequency === 'custom' ? input.customUnit ?? null : null,
      });
      if (rpcError) throw rpcError;
      const saved = data as { id: string } | null;
      return saved?.id ?? null;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar el plan de inspección.');
      return null;
    } finally {
      setSaving(false);
    }
  }, [organizationId]);

  // Full replace, not incremental — keeps the plan form simple (no
  // per-rule add/remove round trips). Safe because no other table
  // references a specific alert rule row.
  const replaceAlertRules = useCallback(async (planId: string, rules: InspectionAlertRuleDraft[]): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('replace_inspection_plan_alert_rules', {
        p_plan_id: planId,
        p_rules: rules.map((rule) => ({
          alert_type: rule.alertType,
          days_before: rule.alertType === 'before_due' ? rule.daysBefore : null,
          label: rule.label.trim() || null,
        })),
      });
      if (rpcError) throw rpcError;
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudieron guardar las alertas del plan.');
      return false;
    } finally {
      setSaving(false);
    }
  }, []);

  // Saves the plan, then replaces its alert rules — sequential (the plan
  // must exist before rules can reference it), surfaced as one call so the
  // dialog only needs a single "Guardar" action.
  const savePlanWithAlertRules = useCallback(async (input: InspectionPlanInput, planId: string | undefined, rules: InspectionAlertRuleDraft[]): Promise<boolean> => {
    const savedPlanId = await savePlan(input, planId);
    if (!savedPlanId) return false;
    const rulesOk = await replaceAlertRules(savedPlanId, rules);
    await refresh();
    return rulesOk;
  }, [savePlan, replaceAlertRules, refresh]);

  const createRunFromPlan = useCallback(async (planId: string): Promise<string | null> => {
    setSaving(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('create_inspection_run_from_plan', {
        p_plan_id: planId,
      });
      if (rpcError) throw rpcError;
      return (data as { id: string } | null)?.id ?? null;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo crear la ejecución.');
      return null;
    } finally {
      setSaving(false);
    }
  }, []);

  return {
    plans,
    activePlans: plans.filter((plan) => plan.isActive),
    loading,
    saving,
    error,
    refresh,
    savePlanWithAlertRules,
    createRunFromPlan,
  };
}

export type UseInspectionPlansResult = ReturnType<typeof useInspectionPlans>;
