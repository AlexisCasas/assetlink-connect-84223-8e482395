import { Fragment, useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { cn } from '@/lib/utils';
import {
  RequestTypeBadge,
  WorkOrderStatusBadge,
  WorkOrderPriorityBadge,
  WorkOrderActivityStatusBadge,
  WorkOrderMaterialWarningBadge,
} from '@/components/requests/StatusBadge';
import { ActivityReportDialog } from './ActivityReportDialog';
import type { TechnicianWorkLog, TechnicianWorkOrder } from '@/types/technicianWorkOrder';

interface TechnicianWorkOrderDetailDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  workOrder: TechnicianWorkOrder | null;
  /** Activity to highlight/scroll to, from a deep link
   * (#work-orders?workOrder=...&activity=...). MVP: highlight + locate
   * only — never auto-opens the report form. */
  focusActivityId?: string;
}

const formatDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : '—';

/**
 * Purpose-built read-only detail for the technician view — deliberately not
 * a reuse of WorkOrderDetailDialog: that component expects a full
 * work_orders row and gates editing on `currentOrganization` matching the
 * OT's own organization, which does not hold reliably here since "Mis
 * órdenes" is intentionally organization-agnostic (a technician may have
 * work across more than one organization at once). This dialog only ever
 * displays what get_my_technician_work_orders already returned, plus the
 * work log history.
 */
export function TechnicianWorkOrderDetailDialog({ open, onOpenChange, workOrder, focusActivityId }: TechnicianWorkOrderDetailDialogProps) {
  const [logs, setLogs] = useState<TechnicianWorkLog[]>([]);
  const [loadingLogs, setLoadingLogs] = useState(false);
  const [reportingActivityId, setReportingActivityId] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !focusActivityId) return;
    // Deferred one tick so the dialog's own open animation/layout has
    // already happened before we scroll within it.
    const timer = setTimeout(() => {
      document.getElementById(`technician-activity-${focusActivityId}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 0);
    return () => clearTimeout(timer);
  }, [open, focusActivityId, workOrder]);

  useEffect(() => {
    if (!open || !workOrder) return;
    setLoadingLogs(true);
    void (async () => {
      const { data, error } = await supabase.rpc('get_work_order_work_logs', { p_work_order_id: workOrder.id });
      if (!error) {
        setLogs((data ?? []).map((row) => ({
          id: row.id,
          note: row.note,
          statusFrom: row.status_from,
          statusTo: row.status_to,
          memberName: row.member_name,
          memberEmail: row.member_email,
          createdAt: row.created_at,
        })));
      }
      setLoadingLogs(false);
    })();
  }, [open, workOrder]);

  if (!workOrder) return null;

  return (
    <Fragment>
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <div className="flex items-start justify-between gap-4">
            <div>
              <DialogTitle>{workOrder.title || 'Orden sin título'}</DialogTitle>
              <DialogDescription className="mt-1">{workOrder.workOrderNumber}</DialogDescription>
            </div>
            <div className="flex items-center gap-2">
              <RequestTypeBadge type={workOrder.workOrderType} />
              <WorkOrderStatusBadge status={workOrder.status} />
            </div>
          </div>
        </DialogHeader>

        <div className="grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Activo</p>
            <p className="mt-1">{workOrder.assetPath || workOrder.assetName || 'Sin activo asociado'}</p>
          </div>
          <div>
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Ubicación</p>
            <p className="mt-1">{workOrder.location || '—'}</p>
          </div>
          <div>
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Programada</p>
            <p className="mt-1">{formatDate(workOrder.scheduledAt)}</p>
          </div>
          <div>
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Fecha límite</p>
            <p className="mt-1">{formatDate(workOrder.dueAt)}</p>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Prioridad</span>
            <WorkOrderPriorityBadge priority={workOrder.priority} />
          </div>
        </div>

        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Actividades asignadas</p>
          {workOrder.activities.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sin actividades asignadas.</p>
          ) : (
            <div className="space-y-2">
              {workOrder.activities.map((activity) => (
                <div
                  key={activity.id}
                  id={`technician-activity-${activity.id}`}
                  className={cn(
                    'flex items-center justify-between gap-2 rounded-md border p-2 text-sm',
                    activity.id === focusActivityId && 'ring-2 ring-primary bg-primary/5',
                  )}
                >
                  <div className="min-w-0">
                    <p className="truncate">{activity.sequence}. {activity.description}{activity.estimatedHours != null ? ` — ${activity.estimatedHours} h` : ''}</p>
                    {activity.reportsCount > 0 && (
                      <p className="text-xs text-muted-foreground">Real: {activity.actualHoursTotal} h</p>
                    )}
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <WorkOrderActivityStatusBadge status={activity.status} />
                    <Button size="sm" variant="outline" className="h-6 px-2" onClick={() => setReportingActivityId(activity.id)}>
                      Reportar
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Materiales</p>
          {workOrder.materials.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sin materiales registrados.</p>
          ) : (
            <div className="space-y-2">
              {workOrder.materials.map((material) => (
                <div key={material.id} className="flex items-center justify-between gap-2 rounded-md border p-2 text-sm">
                  <span>{material.materialCode} — {material.materialName} ({material.plannedQuantity} {material.materialUnit})</span>
                  <WorkOrderMaterialWarningBadge status={material.warningStatus} />
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Registro de trabajo</p>
          {loadingLogs ? (
            <p className="text-sm text-muted-foreground">Cargando…</p>
          ) : logs.length === 0 ? (
            <p className="text-sm text-muted-foreground">Sin registros todavía.</p>
          ) : (
            <div className="space-y-2">
              {logs.map((log) => (
                <div key={log.id} className="rounded-md border p-2 text-sm">
                  <p>{log.note}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {log.memberName} · {formatDate(log.createdAt)}
                    {log.statusFrom && log.statusTo ? ` · ${log.statusFrom} → ${log.statusTo}` : ''}
                  </p>
                </div>
              ))}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>

    <ActivityReportDialog
      open={reportingActivityId !== null}
      onOpenChange={(open) => !open && setReportingActivityId(null)}
      activityId={reportingActivityId}
      onSaved={() => {}}
    />
    </Fragment>
  );
}
