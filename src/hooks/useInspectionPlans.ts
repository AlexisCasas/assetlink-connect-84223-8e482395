import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { InspectionFrequency, InspectionPlan, InspectionPlanInput } from '@/types/inspection';

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
  start_date: string;
  next_due_at: string | null;
  is_active: boolean;
  created_at: string;
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
  startDate: row.start_date,
  nextDueAt: row.next_due_at,
  isActive: row.is_active,
  createdAt: row.created_at,
});

/**
 * Recurring inspection schedules (sede/área/activo + responsable +
 * periodicidad) for one organization. get_inspection_plans/upsert_inspection_plan
 * — both SECURITY DEFINER, see docs/GENERIC_CHECKLISTS_INSPECTIONS.md.
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
      setPlans((data ?? []).map(toPlan));
    } catch (err) {
      setPlans([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los planes de inspección.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const savePlan = useCallback(async (input: InspectionPlanInput, planId?: string): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_inspection_plan', {
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
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar el plan de inspección.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

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
    savePlan,
    createRunFromPlan,
  };
}

export type UseInspectionPlansResult = ReturnType<typeof useInspectionPlans>;
