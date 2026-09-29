import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type {
  InspectionRunAnswer,
  InspectionRunDetail,
  InspectionRunEvidence,
  InspectionRunResult,
  InspectionRunStatus,
  InspectionRunSummary,
} from '@/types/inspection';

interface RawRunSummary {
  id: string;
  organization_id: string;
  plan_id: string | null;
  template_id: string;
  template_name: string;
  branch_name: string | null;
  area_asset_name: string | null;
  asset_name: string | null;
  responsible_member_id: string | null;
  responsible_name: string | null;
  has_responsible: boolean;
  scheduled_for: string | null;
  started_at: string | null;
  completed_at: string | null;
  status: string;
  result: string | null;
}

const toRunSummary = (row: RawRunSummary): InspectionRunSummary => ({
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
  hasResponsible: !!row.has_responsible,
  scheduledFor: row.scheduled_for,
  startedAt: row.started_at,
  completedAt: row.completed_at,
  status: row.status as InspectionRunStatus,
  result: row.result as InspectionRunResult | null,
});

interface RawRunDetail {
  id: string;
  organization_id: string;
  plan_id: string | null;
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
  has_responsible: boolean;
  scheduled_for: string | null;
  started_at: string | null;
  completed_at: string | null;
  status: string;
  result: string | null;
  notes: string | null;
  created_at: string;
  items: Array<{ id: string; section: string | null; question: string; help_text: string | null; sequence: number; is_required: boolean }>;
  response_options: Array<{ id: string; label: string; value: string; is_failure: boolean; sequence: number }>;
  answers: Array<{ id: string; template_item_id: string; response_option_id: string | null; item_question: string; response_label: string | null; response_value: string | null; is_failure: boolean; observations: string | null }>;
  evidences: Array<{ id: string; answer_id: string | null; file_name: string; file_url: string | null; file_path: string | null; mime_type: string | null; size_bytes: number | null; notes: string | null }>;
}

const toRunDetail = (row: RawRunDetail): InspectionRunDetail => ({
  id: row.id,
  organizationId: row.organization_id,
  planId: row.plan_id,
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
  hasResponsible: !!row.has_responsible,
  scheduledFor: row.scheduled_for,
  startedAt: row.started_at,
  completedAt: row.completed_at,
  status: row.status as InspectionRunStatus,
  result: row.result as InspectionRunResult | null,
  notes: row.notes,
  createdAt: row.created_at,
  items: (row.items ?? []).map((item) => ({
    id: item.id,
    section: item.section,
    question: item.question,
    helpText: item.help_text,
    sequence: item.sequence,
    isRequired: item.is_required,
  })),
  responseOptions: (row.response_options ?? []).map((option) => ({
    id: option.id,
    label: option.label,
    value: option.value,
    isFailure: option.is_failure,
    sequence: option.sequence,
  })),
  answers: (row.answers ?? []).map((answer): InspectionRunAnswer => ({
    id: answer.id,
    templateItemId: answer.template_item_id,
    responseOptionId: answer.response_option_id,
    itemQuestion: answer.item_question,
    responseLabel: answer.response_label,
    responseValue: answer.response_value,
    isFailure: answer.is_failure,
    observations: answer.observations,
  })),
  evidences: (row.evidences ?? []).map((evidence): InspectionRunEvidence => ({
    id: evidence.id,
    answerId: evidence.answer_id,
    fileName: evidence.file_name,
    fileUrl: evidence.file_url,
    filePath: evidence.file_path,
    mimeType: evidence.mime_type,
    sizeBytes: evidence.size_bytes,
    notes: evidence.notes,
  })),
});

export interface SubmitInspectionRunAnswerInput {
  templateItemId: string;
  responseOptionId: string | null;
  observations?: string | null;
}

export interface SubmitInspectionRunEvidenceInput {
  templateItemId?: string | null;
  fileName: string;
  fileUrl?: string | null;
  filePath?: string | null;
  mimeType?: string | null;
  sizeBytes?: number | null;
  notes?: string | null;
}

/**
 * Concrete inspection executions — list (get_inspection_runs, added beyond
 * the original spec's RPC list because no other clean read path exists,
 * see the migration comment), detail (get_inspection_run_detail), and
 * submission (submit_inspection_run). All SECURITY DEFINER, see
 * docs/GENERIC_CHECKLISTS_INSPECTIONS.md.
 */
export function useInspectionRuns(organizationId: string | null | undefined) {
  const [runs, setRuns] = useState<InspectionRunSummary[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setRuns([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_inspection_runs', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      setRuns(((data ?? []) as unknown as RawRunSummary[]).map(toRunSummary));
    } catch (err) {
      setRuns([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar las ejecuciones de inspección.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const loadRunDetail = useCallback(async (runId: string): Promise<InspectionRunDetail | null> => {
    const { data, error: rpcError } = await supabase.rpc('get_inspection_run_detail', { p_run_id: runId });
    if (rpcError) throw rpcError;
    if (!data) return null;
    return toRunDetail(data as unknown as RawRunDetail);
  }, []);

  const submitRun = useCallback(async (
    runId: string,
    startedAt: string,
    completedAt: string,
    answers: SubmitInspectionRunAnswerInput[],
    evidences: SubmitInspectionRunEvidenceInput[],
    notes: string | null,
  ): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('submit_inspection_run', {
        p_run_id: runId,
        p_started_at: startedAt,
        p_completed_at: completedAt,
        p_answers: answers.map((answer) => ({
          template_item_id: answer.templateItemId,
          response_option_id: answer.responseOptionId,
          observations: answer.observations ?? null,
        })),
        p_evidences: evidences.map((evidence) => ({
          template_item_id: evidence.templateItemId ?? null,
          file_name: evidence.fileName,
          file_url: evidence.fileUrl ?? null,
          file_path: evidence.filePath ?? null,
          mime_type: evidence.mimeType ?? null,
          size_bytes: evidence.sizeBytes ?? null,
          notes: evidence.notes ?? null,
        })),
        p_notes: notes,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar la ejecución de la inspección.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  return {
    runs,
    loading,
    saving,
    error,
    refresh,
    loadRunDetail,
    submitRun,
  };
}

export type UseInspectionRunsResult = ReturnType<typeof useInspectionRuns>;
