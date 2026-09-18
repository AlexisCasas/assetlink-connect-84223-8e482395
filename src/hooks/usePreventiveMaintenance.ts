import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { Json } from '@/integrations/supabase/types';
import type {
  MaintenanceCard,
  MaintenanceCardDraft,
  PreventiveOccurrence,
  PreventivePlan,
  PreventivePlanDraft,
} from '@/types/preventiveMaintenance';

const errorText = (error: unknown, fallback: string) => error instanceof Error ? error.message : fallback;

export function usePreventiveMaintenance(organizationId: string | null | undefined, assetId?: string | null) {
  const [cards, setCards] = useState<MaintenanceCard[]>([]);
  const [plans, setPlans] = useState<PreventivePlan[]>([]);
  const [occurrences, setOccurrences] = useState<PreventiveOccurrence[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setCards([]); setPlans([]); setOccurrences([]); setError(null);
      return;
    }
    setLoading(true); setError(null);
    try {
      const [cardsResult, plansResult, occurrencesResult] = await Promise.all([
        supabase.rpc('get_maintenance_cards', { p_organization_id: organizationId, p_include_inactive: true }),
        supabase.rpc('get_preventive_maintenance_plans', { p_organization_id: organizationId }),
        supabase.rpc('get_preventive_maintenance_occurrences', {
          p_organization_id: organizationId,
          p_asset_id: assetId ?? null,
          p_status: null,
        }),
      ]);
      if (cardsResult.error) throw cardsResult.error;
      if (plansResult.error) throw plansResult.error;
      if (occurrencesResult.error) throw occurrencesResult.error;
      setCards((cardsResult.data ?? []) as unknown as MaintenanceCard[]);
      const allPlans = (plansResult.data ?? []) as unknown as PreventivePlan[];
      setPlans(assetId ? allPlans.filter((plan) => plan.asset_id === assetId) : allPlans);
      setOccurrences((occurrencesResult.data ?? []) as unknown as PreventiveOccurrence[]);
    } catch (cause) {
      setCards([]); setPlans([]); setOccurrences([]);
      setError(errorText(cause, 'No se pudo cargar mantenimiento preventivo.'));
    } finally { setLoading(false); }
  }, [assetId, organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const mutate = useCallback(async (operation: () => PromiseLike<{ error: { message: string } | null }>) => {
    setSaving(true); setError(null);
    try {
      const result = await operation();
      if (result.error) throw result.error;
      await refresh();
      return true;
    } catch (cause) {
      setError(errorText(cause, 'No se pudo completar la operación.'));
      return false;
    } finally { setSaving(false); }
  }, [refresh]);

  const saveCard = useCallback((draft: MaintenanceCardDraft, cardId?: string) => {
    if (!organizationId) return Promise.resolve(false);
    return mutate(() => supabase.rpc('save_maintenance_card', {
      p_organization_id: organizationId,
      p_code: draft.code,
      p_name: draft.name,
      p_description: draft.description || null,
      p_category: draft.category || null,
      p_estimated_hours: draft.estimatedHours ?? null,
      p_procedure_notes: draft.procedureNotes || null,
      p_safety_notes: draft.safetyNotes || null,
      p_tasks: draft.tasks as unknown as Json,
      p_materials: draft.materials as unknown as Json,
      p_card_id: cardId ?? null,
    }));
  }, [mutate, organizationId]);

  const setCardActive = useCallback((cardId: string, active: boolean) => mutate(() =>
    supabase.rpc('set_maintenance_card_active', { p_card_id: cardId, p_is_active: active })
  ), [mutate]);

  const savePlan = useCallback((draft: PreventivePlanDraft, planId?: string) => {
    if (!organizationId) return Promise.resolve(false);
    return mutate(() => supabase.rpc('save_preventive_maintenance_plan', {
      p_organization_id: organizationId,
      p_asset_id: draft.assetId,
      p_card_id: draft.cardId,
      p_trigger_type: draft.triggerType,
      p_priority: draft.priority,
      p_default_request_type: draft.defaultRequestType,
      p_responsible_member_id: draft.responsibleMemberId ?? null,
      p_planning_lead_days: draft.planningLeadDays,
      p_frequency: draft.triggerType === 'calendar' ? draft.frequency ?? null : null,
      p_custom_interval: draft.triggerType === 'calendar' ? draft.customInterval ?? null : null,
      p_custom_unit: draft.triggerType === 'calendar' ? draft.customUnit ?? null : null,
      p_first_due_at: draft.triggerType === 'calendar' ? draft.firstDueAt ?? null : null,
      p_meter_id: draft.triggerType === 'meter' ? draft.meterId ?? null : null,
      p_interval_value: draft.triggerType === 'meter' ? draft.intervalValue ?? null : null,
      p_baseline_reading_id: draft.triggerType === 'meter' ? draft.baselineReadingId ?? null : null,
      p_meter_lead_value: draft.triggerType === 'meter' ? draft.meterLeadValue ?? null : null,
      p_plan_id: planId ?? null,
    }));
  }, [mutate, organizationId]);

  const setPlanActive = useCallback((planId: string, active: boolean, reason?: string) => mutate(() =>
    supabase.rpc('set_preventive_maintenance_plan_active', {
      p_plan_id: planId, p_is_active: active, p_reason: reason ?? null,
    })
  ), [mutate]);

  const skipOccurrence = useCallback((occurrenceId: string, reason: string) => mutate(() =>
    supabase.rpc('skip_preventive_maintenance_occurrence', { p_occurrence_id: occurrenceId, p_reason: reason })
  ), [mutate]);

  const linkRequest = useCallback((occurrenceId: string, requestId: string) => mutate(() =>
    supabase.rpc('plan_preventive_maintenance_occurrence', { p_occurrence_id: occurrenceId, p_request_id: requestId })
  ), [mutate]);

  return {
    cards, plans, occurrences, loading, saving, error, refresh,
    saveCard, setCardActive, savePlan, setPlanActive, skipOccurrence, linkRequest,
  };
}
