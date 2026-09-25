import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toReplaceConfigurationArgs } from '@/lib/criticalityImportValidation';
import type { AssetCriticality } from '@/types/asset';
import type {
  BulkCriticalityPreviewRow,
  BulkCriticalityResult,
  BulkCriticalityRow,
  CriticalityAnswer,
  CriticalityAssessment,
  CriticalityAssessmentAnswer,
  CriticalityAssessmentPreview,
  CriticalityMatrixPayloadParameter,
  CriticalityOptionInput,
  CriticalityParameter,
  CriticalityParameterInput,
  CriticalityThresholdValues,
} from '@/types/criticalityMatrix';

interface RawOption {
  id: string;
  code: string;
  label: string;
  score: number;
  sequence: number;
  is_active: boolean;
}

interface RawParameter {
  id: string;
  code: string;
  name: string;
  description: string | null;
  weight: number;
  sequence: number;
  is_active: boolean;
  options: RawOption[];
}

const toOption = (row: RawOption) => ({
  id: row.id,
  code: row.code,
  label: row.label,
  score: row.score,
  sequence: row.sequence,
  isActive: row.is_active,
});

const toParameter = (row: RawParameter): CriticalityParameter => ({
  id: row.id,
  code: row.code,
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
  threshold_medium_min: number | string;
  threshold_high_min: number | string;
  threshold_critical_min: number | string;
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
  thresholds: {
    mediumMin: Number(row.threshold_medium_min),
    highMin: Number(row.threshold_high_min),
    criticalMin: Number(row.threshold_critical_min),
  },
});

const toAnswerPayload = (answers: CriticalityAnswer[]) =>
  answers.map((answer) => ({ parameter_id: answer.parameterId, option_id: answer.optionId }));

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

  /** Excel import: replaces the whole active matrix and — when the file has a
   * "Configuración" sheet — the thresholds, in ONE transaction
   * (replace_criticality_configuration). thresholds = null (legacy file)
   * keeps the organization's current thresholds. The backend revalidates the
   * entire payload, deactivates — never deletes — the previous configuration,
   * and aborts everything if either part is invalid. */
  const replaceConfiguration = useCallback(async (
    parameters: CriticalityMatrixPayloadParameter[],
    thresholds: CriticalityThresholdValues | null,
  ): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('replace_criticality_configuration', {
        p_organization_id: organizationId,
        ...toReplaceConfigurationArgs(parameters, thresholds),
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo reemplazar la matriz de criticidad.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

  /** "Nueva matriz en blanco": deactivates every currently active parameter
   * (and their active options) for the organization in one transaction —
   * never deletes, never touches templates or historical assessments/
   * assets.criticality. Idempotent when there is nothing active already. */
  const clearActiveMatrix = useCallback(async (): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('clear_active_criticality_matrix', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo limpiar la matriz de criticidad.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

  /** Server-side dry run of a bulk evaluation: the score/criticality it
   * returns comes from the same SQL engine the real evaluation uses
   * (validate_and_score_asset_criticality) — never recomputed in JS. */
  const previewBulk = useCallback(async (rows: BulkCriticalityRow[]): Promise<BulkCriticalityPreviewRow[]> => {
    if (!organizationId) return [];
    const { data, error: rpcError } = await supabase.rpc('preview_bulk_asset_criticality', {
      p_organization_id: organizationId,
      p_rows: rows.map((row) => ({
        row_number: row.rowNumber,
        asset_id: row.assetId,
        answers: toAnswerPayload(row.answers),
      })),
    });
    if (rpcError) throw rpcError;
    return (data ?? []).map((row) => ({
      rowNumber: row.row_number ?? 0,
      assetId: row.asset_id,
      assetCode: row.asset_code,
      assetName: row.asset_name,
      valid: row.valid ?? false,
      score: row.score === null || row.score === undefined ? null : Number(row.score),
      calculatedCriticality: (row.calculated_criticality ?? null) as BulkCriticalityPreviewRow['calculatedCriticality'],
      errors: ((row.errors ?? []) as unknown as string[]),
      warnings: ((row.warnings ?? []) as unknown as string[]),
    }));
  }, [organizationId]);

  /** Preview of ONE evaluation for the "Evaluar criticidad" dialog. It reuses
   * preview_bulk_asset_criticality with a single row, so score and class come
   * from the exact SQL engine calculate_asset_criticality uses (same
   * permissions, no writes, tenant enforced) — the browser never scores or
   * classifies. */
  const previewAssessment = useCallback(async (assetId: string, answers: CriticalityAnswer[]): Promise<CriticalityAssessmentPreview> => {
    const [row] = await previewBulk([{ rowNumber: 1, assetId, answers }]);
    if (!row) {
      return { valid: false, score: null, calculatedCriticality: null, errors: ['No se pudo calcular la vista previa.'] };
    }
    return { valid: row.valid, score: row.score, calculatedCriticality: row.calculatedCriticality, errors: row.errors };
  }, [previewBulk]);

  /** Applies a subset the user already accepted in the preview. The backend
   * revalidates every row first and aborts the whole subset if any is no
   * longer valid — never partial writes. Each row always creates a NEW
   * assessment; previous ones are never overwritten. */
  const applyBulk = useCallback(async (rows: BulkCriticalityRow[]): Promise<BulkCriticalityResult | null> => {
    if (!organizationId) return null;
    setSaving(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('bulk_calculate_asset_criticality', {
        p_organization_id: organizationId,
        p_rows: rows.map((row) => ({
          row_number: row.rowNumber,
          asset_id: row.assetId,
          notes: row.notes ?? null,
          answers: row.answers.map((answer) => ({ parameter_id: answer.parameterId, option_id: answer.optionId })),
        })),
      });
      if (rpcError) throw rpcError;
      return data as unknown as BulkCriticalityResult;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudieron aplicar las evaluaciones.');
      return null;
    } finally {
      setSaving(false);
    }
  }, [organizationId]);

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
    replaceConfiguration,
    clearActiveMatrix,
    previewBulk,
    previewAssessment,
    applyBulk,
    loadAssessments,
  };
}

export type UseCriticalityMatrixResult = ReturnType<typeof useCriticalityMatrix>;
