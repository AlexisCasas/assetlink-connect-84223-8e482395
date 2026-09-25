import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AssetCriticality } from '@/types/asset';
import type {
  CreateMaintenanceNoticeInput,
  MaintenanceNotice,
  MaintenanceNoticePriority,
  MaintenanceNoticeSource,
  MaintenanceNoticeSourceMetadata,
  MaintenanceNoticeStatus,
  TriageMaintenanceNoticeInput,
} from '@/types/maintenanceNotice';

interface RawMaintenanceNotice {
  id: string;
  organization_id: string;
  notice_number: string;
  asset_id: string;
  title: string;
  description: string;
  priority: string;
  status: string;
  source_type: string;
  source_id: string | null;
  source_metadata: Record<string, unknown> | null;
  asset_name_snapshot: string | null;
  asset_code_snapshot: string | null;
  asset_path_snapshot: string | null;
  branch_id_snapshot: string | null;
  branch_name_snapshot: string | null;
  asset_current_criticality: string | null;
  reported_by_user_id: string | null;
  reported_by_name: string | null;
  reported_at: string;
  responsible_member_id: string | null;
  responsible_name: string | null;
  triage_notes: string | null;
  triaged_by_name: string | null;
  triaged_at: string | null;
  converted_request_id: string | null;
  converted_request_number: string | null;
  converted_by_name: string | null;
  converted_at: string | null;
  dismissal_reason: string | null;
  dismissed_by_name: string | null;
  dismissed_at: string | null;
  created_at: string;
}

const toSourceMetadata = (raw: Record<string, unknown> | null): MaintenanceNoticeSourceMetadata => {
  const meta = raw ?? {};
  const asText = (value: unknown) => (typeof value === 'string' && value !== '' ? value : undefined);
  return {
    templateName: asText(meta.template_name),
    itemId: asText(meta.item_id),
    itemQuestion: asText(meta.item_question),
    responseLabel: asText(meta.response_label),
  };
};

const toNotice = (row: RawMaintenanceNotice): MaintenanceNotice => ({
  id: row.id,
  organizationId: row.organization_id,
  noticeNumber: row.notice_number,
  assetId: row.asset_id,
  title: row.title,
  description: row.description,
  priority: row.priority as MaintenanceNoticePriority,
  status: row.status as MaintenanceNoticeStatus,
  sourceType: row.source_type as MaintenanceNoticeSource,
  sourceId: row.source_id,
  sourceMetadata: toSourceMetadata(row.source_metadata),
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

/**
 * Backlog de mantenimiento. Todas las escrituras pasan por RPC
 * SECURITY DEFINER (create/triage/dismiss/convert): maintenance_notices no
 * tiene policies de INSERT/UPDATE/DELETE, así que el cliente no puede
 * inventar un correlativo, un snapshot ni un tenant aunque quisiera.
 * Ver docs/MAINTENANCE_BACKLOG_NOTICES.md.
 */
export function useMaintenanceNotices(organizationId: string | null | undefined) {
  const [notices, setNotices] = useState<MaintenanceNotice[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setNotices([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_maintenance_notices', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      setNotices(((data ?? []) as unknown as RawMaintenanceNotice[]).map(toNotice));
    } catch (err) {
      setNotices([]);
      setError(err instanceof Error ? err.message : 'No se pudo cargar el backlog de mantenimiento.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const createNotice = useCallback(async (input: CreateMaintenanceNoticeInput): Promise<MaintenanceNotice> => {
    if (!organizationId) throw new Error('Selecciona una organización activa.');
    setSaving(true);
    try {
      const { data, error: rpcError } = await supabase.rpc('create_maintenance_notice', {
        p_organization_id: organizationId,
        p_asset_id: input.assetId,
        p_title: input.title,
        p_description: input.description,
        p_priority: input.priority,
        p_source_type: input.source?.type ?? 'manual',
        p_source_id: input.source?.runId ?? null,
        p_source_item_id: input.source?.itemId ?? null,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return toNotice(data as unknown as RawMaintenanceNotice);
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

  const triageNotice = useCallback(async (input: TriageMaintenanceNoticeInput): Promise<void> => {
    setSaving(true);
    try {
      const { error: rpcError } = await supabase.rpc('triage_maintenance_notice', {
        p_notice_id: input.noticeId,
        // null = "no cambiar este campo" en la RPC.
        p_priority: input.priority ?? null,
        p_triage_notes: input.triageNotes ?? null,
        // responsibleMemberId: undefined = conservar, null = desasignar
        // (p_clear_responsible), UUID = asignar.
        p_responsible_member_id: input.responsibleMemberId ?? null,
        p_clear_responsible: input.responsibleMemberId === null,
      });
      if (rpcError) throw rpcError;
      await refresh();
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  const dismissNotice = useCallback(async (noticeId: string, reason: string): Promise<void> => {
    setSaving(true);
    try {
      const { error: rpcError } = await supabase.rpc('dismiss_maintenance_notice', {
        p_notice_id: noticeId,
        p_reason: reason,
      });
      if (rpcError) throw rpcError;
      await refresh();
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  /** Vincula un aviso con una solicitud YA guardada por persistRequest. No
   * crea la solicitud: eso lo hace el flujo normal de solicitudes. Es
   * idempotente para el mismo par aviso/solicitud, así que un reintento tras
   * un fallo de red no obliga a crear una segunda solicitud. */
  const convertNotice = useCallback(async (noticeId: string, requestId: string): Promise<void> => {
    setSaving(true);
    try {
      const { error: rpcError } = await supabase.rpc('convert_maintenance_notice', {
        p_notice_id: noticeId,
        p_request_id: requestId,
      });
      if (rpcError) throw rpcError;
      await refresh();
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  return { notices, loading, saving, error, refresh, createNotice, triageNotice, dismissNotice, convertNotice };
}
