import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AssetCriticality } from '@/types/asset';
import type {
  CriticalityAnswer,
  CriticalityAssessment,
  CriticalityAssessmentAnswer,
  CriticalityOptionInput,
  CriticalityParameter,
  CriticalityParameterInput,
} from '@/types/criticalityMatrix';

interface RawOption {
  id: string;
  label: string;
  score: number;
  sequence: number;
  is_active: boolean;
}

interface RawParameter {
  id: string;
  name: string;
  description: string | null;
  weight: number;
  sequence: number;
  is_active: boolean;
  options: RawOption[];
}

const toOption = (row: RawOption) => ({
  id: row.id,
  label: row.label,
  score: row.score,
  sequence: row.sequence,
  isActive: row.is_active,
});

const toParameter = (row: RawParameter): CriticalityParameter => ({
  id: row.id,
  name: row.name,
  description: row.description,
  weight: row.weight,
  sequence: row.sequence,
  isActive: row.is_active,
  options: (row.options ?? []).map(toOption),
});

interface RawAssessmentAnswer {
  parameter_id: string;
  parameter_name: string;
  option_id: string | null;
  option_label: string | null;
  weight: number;
  option_score: number;
  weighted_score: number;
}

interface RawAssessment {
  id: string;
  asset_id: string;
  organization_id: string;
  score: number;
  calculated_criticality: string;
  manual_criticality: string | null;
  effective_criticality: string;
  notes: string | null;
  created_by_user_id: string | null;
  created_by_name: string | null;
  created_at: string;
  answers: RawAssessmentAnswer[];
}

const toAssessmentAnswer = (row: RawAssessmentAnswer): CriticalityAssessmentAnswer => ({
  parameterId: row.parameter_id,
  parameterName: row.parameter_name,
  optionId: row.option_id,
  optionLabel: row.option_label,
  weight: row.weight,
  optionScore: row.option_score,
  weightedScore: row.weighted_score,
});

const toAssessment = (row: RawAssessment): CriticalityAssessment => ({
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
  answers: (row.answers ?? []).map(toAssessmentAnswer),
});

/**
 * Configurable criticality matrix for one organization
 * (get_criticality_matrix/upsert_criticality_parameter/upsert_criticality_option/
 * set_criticality_*_active — all SECURITY DEFINER, owner/admin/manager or
 * platform_admin only for writes, see docs/CONFIGURABLE_CRITICALITY_MATRIX.md),
 * plus per-asset evaluation (calculate_asset_criticality) and history
 * (get_asset_criticality_assessments). One hook covers both the management
 * view and the per-asset "Evaluar criticidad" flow so there is a single
 * source of truth for the matrix shape.
 */
export function useCriticalityMatrix(organizationId: string | null | undefined) {
  const [matrix, setMatrix] = useState<CriticalityParameter[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setMatrix([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      // include_inactive=true: the management view needs to see deactivated
      // parameters/options too (to reactivate them) — active-only filtering
      // for the "Evaluar criticidad" dialog is then done client-side via
      // activeParameters below, with no second round trip.
      const { data, error: rpcError } = await supabase.rpc('get_criticality_matrix', {
        p_organization_id: organizationId,
        p_include_inactive: true,
      });
      if (rpcError) throw rpcError;
      setMatrix(((data ?? []) as unknown as RawParameter[]).map(toParameter));
    } catch (err) {
      setMatrix([]);
      setError(err instanceof Error ? err.message : 'No se pudo cargar la matriz de criticidad.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const activeParameters = useMemo(
    () => matrix
      .filter((parameter) => parameter.isActive)
      .map((parameter) => ({ ...parameter, options: parameter.options.filter((option) => option.isActive) })),
    [matrix],
  );

  const totalActiveWeight = useMemo(
    () => Math.round(activeParameters.reduce((sum, parameter) => sum + parameter.weight, 0) * 100) / 100,
    [activeParameters],
  );

  const saveParameter = useCallback(async (input: CriticalityParameterInput, parameterId?: string): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_criticality_parameter', {
        p_organization_id: organizationId,
        p_name: input.name,
        p_description: input.description ?? null,
        p_weight: input.weight,
        p_sequence: input.sequence,
        p_parameter_id: parameterId ?? null,
        p_is_active: input.isActive ?? true,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar el parámetro.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

  const saveOption = useCallback(async (input: CriticalityOptionInput, optionId?: string): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_criticality_option', {
        p_parameter_id: input.parameterId,
        p_label: input.label,
        p_score: input.score,
        p_sequence: input.sequence,
        p_option_id: optionId ?? null,
        p_is_active: input.isActive ?? true,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar la opción.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  const toggleParameterActive = useCallback(async (parameterId: string, isActive: boolean): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('set_criticality_parameter_active', {
        p_parameter_id: parameterId,
        p_is_active: isActive,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo actualizar el parámetro.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  const toggleOptionActive = useCallback(async (optionId: string, isActive: boolean): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('set_criticality_option_active', {
        p_option_id: optionId,
        p_is_active: isActive,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo actualizar la opción.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  const calculateCriticality = useCallback(async (assetId: string, answers: CriticalityAnswer[], notes?: string | null): Promise<CriticalityAssessment | null> => {
    setSaving(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('calculate_asset_criticality', {
        p_asset_id: assetId,
        p_answers: answers.map((answer) => ({ parameter_id: answer.parameterId, option_id: answer.optionId })),
        p_notes: notes ?? null,
      });
      if (rpcError) throw rpcError;
      if (!data) return null;
      return toAssessment(data as unknown as RawAssessment);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo calcular la criticidad del activo.');
      return null;
    } finally {
      setSaving(false);
    }
  }, []);

  const loadAssessments = useCallback(async (assetId: string): Promise<CriticalityAssessment[]> => {
    const { data, error: rpcError } = await supabase.rpc('get_asset_criticality_assessments', {
      p_asset_id: assetId,
    });
    if (rpcError) throw rpcError;
    return ((data ?? []) as unknown as RawAssessment[]).map(toAssessment);
  }, []);

  return {
    matrix,
    activeParameters,
    totalActiveWeight,
    loading,
    saving,
    error,
    refresh,
    saveParameter,
    saveOption,
    toggleParameterActive,
    toggleOptionActive,
    calculateCriticality,
    loadAssessments,
  };
}

export type UseCriticalityMatrixResult = ReturnType<typeof useCriticalityMatrix>;
