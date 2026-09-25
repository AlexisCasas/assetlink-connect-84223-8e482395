import type { AssetCriticality } from '@/types/asset';

/**
 * Un aviso NO es una solicitud y NO es una orden de trabajo: es el reporte
 * de que algo falla, antes de decidir si se va a intervenir. Por eso tiene
 * su propio dominio (maintenance_notices) y no es un estado de `requests`.
 * Cuando se decide intervenir, el aviso se CONVIERTE: se crea una solicitud
 * normal por el flujo de siempre y el aviso queda vinculado a ella.
 */

export type MaintenanceNoticePriority = 'low' | 'medium' | 'high' | 'urgent';

/** open = reportado, sin revisar · triaged = revisado y priorizado ·
 * converted = ya generó una solicitud · dismissed = descartado con motivo
 * (nunca se borra). */
export type MaintenanceNoticeStatus = 'open' | 'triaged' | 'converted' | 'dismissed';

export type MaintenanceNoticeSource = 'manual' | 'inspection_run';

/** Trazabilidad del origen "inspección", congelada por el backend al crear
 * el aviso: qué checklist, qué pregunta y qué respuesta lo motivaron. */
export interface MaintenanceNoticeSourceMetadata {
  templateName?: string;
  itemId?: string;
  itemQuestion?: string;
  responseLabel?: string;
}

export interface MaintenanceNotice {
  id: string;
  organizationId: string;
  /** Correlativo AV-<año>-<6 dígitos>, único por organización y año. Lo
   * genera el servidor; el frontend nunca lo calcula ni lo envía. */
  noticeNumber: string;
  assetId: string;
  title: string;
  description: string;
  priority: MaintenanceNoticePriority;
  status: MaintenanceNoticeStatus;
  sourceType: MaintenanceNoticeSource;
  sourceId: string | null;
  sourceMetadata: MaintenanceNoticeSourceMetadata;

  /** Cómo se veía el activo cuando se reportó el aviso. Se congela en el
   * servidor para que el histórico no cambie si después renombran o mueven
   * el activo. */
  assetNameSnapshot: string | null;
  assetCodeSnapshot: string | null;
  assetPathSnapshot: string | null;
  branchIdSnapshot: string | null;
  branchNameSnapshot: string | null;

  /** Criticidad VIGENTE del activo (no un snapshot): es contexto para
   * priorizar hoy, no un dato histórico del aviso. */
  assetCurrentCriticality: AssetCriticality | null;

  reportedByUserId: string | null;
  reportedByName: string | null;
  reportedAt: string;

  responsibleMemberId: string | null;
  responsibleName: string | null;

  triageNotes: string | null;
  triagedByName: string | null;
  triagedAt: string | null;

  convertedRequestId: string | null;
  convertedRequestNumber: string | null;
  convertedByName: string | null;
  convertedAt: string | null;

  dismissalReason: string | null;
  dismissedByName: string | null;
  dismissedAt: string | null;

  createdAt: string;
}

export interface CreateMaintenanceNoticeInput {
  assetId: string;
  title: string;
  description: string;
  priority: MaintenanceNoticePriority;
  /** Solo para avisos creados desde una no conformidad de una inspección.
   * El backend revalida que esa respuesta exista y sea is_failure. */
  source?: {
    type: 'inspection_run';
    runId: string;
    itemId: string;
  };
}

export interface TriageMaintenanceNoticeInput {
  noticeId: string;
  priority?: MaintenanceNoticePriority;
  triageNotes?: string;
  /** undefined = keep the current responsible (not revalidated), null =
   * unassign, UUID = assign (validated server-side). */
  responsibleMemberId?: string | null;
}

export interface BacklogFilterState {
  status: MaintenanceNoticeStatus | 'all' | 'pending';
  priority: MaintenanceNoticePriority | 'all';
  branchId: string | 'all';
  source: MaintenanceNoticeSource | 'all';
  search: string;
}

export const MAINTENANCE_NOTICE_PRIORITY_LABELS: Record<MaintenanceNoticePriority, string> = {
  low: 'Baja',
  medium: 'Media',
  high: 'Alta',
  urgent: 'Urgente',
};

export const MAINTENANCE_NOTICE_PRIORITY_COLORS: Record<MaintenanceNoticePriority, string> = {
  low: 'bg-slate-500/10 text-slate-600 border-slate-500/20',
  medium: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  high: 'bg-orange-500/10 text-orange-600 border-orange-500/20',
  urgent: 'bg-red-500/10 text-red-600 border-red-500/20',
};

export const MAINTENANCE_NOTICE_STATUS_LABELS: Record<MaintenanceNoticeStatus, string> = {
  open: 'Sin revisar',
  triaged: 'Revisado',
  converted: 'Convertido en solicitud',
  dismissed: 'Descartado',
};

export const MAINTENANCE_NOTICE_STATUS_COLORS: Record<MaintenanceNoticeStatus, string> = {
  open: 'bg-amber-500/10 text-amber-600 border-amber-500/20',
  triaged: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  converted: 'bg-emerald-500/10 text-emerald-600 border-emerald-500/20',
  dismissed: 'bg-slate-500/10 text-slate-500 border-slate-500/20',
};

export const MAINTENANCE_NOTICE_SOURCE_LABELS: Record<MaintenanceNoticeSource, string> = {
  manual: 'Reporte manual',
  inspection_run: 'Inspección',
};
