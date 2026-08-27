import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/contexts/AuthContext';
import { usePermissions } from '@/hooks/usePermissions';
import { TechnicianSelect } from '@/components/members/TechnicianSelect';
import { PlannerSelect } from '@/components/members/PlannerSelect';
import { RequestAssetSummary } from '@/components/requests/RequestAssetSummary';
import {
  RequestTypeBadge,
  WorkOrderStatusBadge,
  WorkOrderPriorityBadge,
  WORK_ORDER_STATUS_LABELS,
  WORK_ORDER_PRIORITY_LABELS,
} from '@/components/requests/StatusBadge';
import { supabase } from '@/integrations/supabase/client';
import type { WorkOrder } from '@/hooks/useWorkOrders';

interface WorkOrderDetailDialogProps {
  workOrder: WorkOrder | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onUpdated?: (workOrder: WorkOrder) => void;
}

const formatDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : '—';

const formatAmount = (value: number | null) => value === null
  ? '—'
  : new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' }).format(value);

/** timestamptz (ISO) <-> <input type="datetime-local"> (local, no timezone). */
const toDatetimeLocalValue = (iso: string | null): string => {
  if (!iso) return '';
  const date = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};
const fromDatetimeLocalValue = (value: string): string | null => value ? new Date(value).toISOString() : null;

export function WorkOrderDetailDialog({ workOrder, open, onOpenChange, onUpdated }: WorkOrderDetailDialogProps) {
  const { currentOrganization } = useAuth();
  const { canPlanWork } = usePermissions();
  const { toast } = useToast();
  const [saving, setSaving] = useState(false);

  const [pendingPlannerId, setPendingPlannerId] = useState<string | null>(null);
  const [pendingMemberId, setPendingMemberId] = useState<string | null>(null);
  const [pendingScheduledAt, setPendingScheduledAt] = useState('');
  const [pendingDueAt, setPendingDueAt] = useState('');
  const [pendingPriority, setPendingPriority] = useState('medium');
  const [pendingStatus, setPendingStatus] = useState('pending');
  const [pendingObservations, setPendingObservations] = useState('');

  // Only owner/admin/manager of the operating organization (provider_organization_id
  // — for an internal OT this is the same organization as the client) plans
  // its own work. Viewing this dialog from any other organization, or as a
  // technician/viewer/requester, never shows the edit controls.
  const isProviderPlanner = !!workOrder
    && currentOrganization?.id === workOrder.provider_organization_id
    && canPlanWork;

  useEffect(() => {
    setPendingPlannerId(workOrder?.planner_member_id ?? null);
    setPendingMemberId(workOrder?.assigned_member_id ?? null);
    setPendingScheduledAt(toDatetimeLocalValue(workOrder?.scheduled_at ?? null));
    setPendingDueAt(toDatetimeLocalValue(workOrder?.due_at ?? null));
    setPendingPriority(workOrder?.priority ?? 'medium');
    setPendingStatus(workOrder?.status ?? 'pending');
    setPendingObservations(workOrder?.observations ?? '');
  }, [workOrder]);

  if (!workOrder) return null;

  const isDirty = workOrder && (
    pendingPlannerId !== (workOrder.planner_member_id ?? null)
    || pendingMemberId !== (workOrder.assigned_member_id ?? null)
    || pendingScheduledAt !== toDatetimeLocalValue(workOrder.scheduled_at)
    || pendingDueAt !== toDatetimeLocalValue(workOrder.due_at)
    || pendingPriority !== workOrder.priority
    || pendingStatus !== workOrder.status
    || pendingObservations !== (workOrder.observations ?? '')
  );

  const handleSave = async () => {
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('update_work_order_operations', {
        target_work_order_id: workOrder.id,
        target_planner_member_id: pendingPlannerId,
        target_assigned_member_id: pendingMemberId,
        target_scheduled_at: fromDatetimeLocalValue(pendingScheduledAt),
        target_due_at: fromDatetimeLocalValue(pendingDueAt),
        target_priority: pendingPriority,
        target_status: pendingStatus,
        target_observations: pendingObservations || null,
      });
      if (error) throw error;
      toast({ title: 'Orden de trabajo actualizada', description: 'Los cambios de planificación se guardaron correctamente.' });
      if (data) onUpdated?.(data);
    } catch (error) {
      toast({
        title: 'No se pudo actualizar la orden de trabajo',
        description: error instanceof Error ? error.message : 'Intenta nuevamente.',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <div className="flex items-start justify-between gap-4">
            <div>
              <DialogTitle>{workOrder.title || 'Orden sin título'}</DialogTitle>
              <DialogDescription className="mt-1">{workOrder.work_order_number}</DialogDescription>
            </div>
            <div className="flex items-center gap-2">
              <RequestTypeBadge type={workOrder.work_order_type} />
              <WorkOrderStatusBadge status={workOrder.status} />
            </div>
          </div>
        </DialogHeader>

        <div className="grid gap-4 text-sm sm:grid-cols-2">
          <DetailItem label="Solicitud origen" value={workOrder.request_id} />
          {workOrder.work_order_type === 'external' && (
            <DetailItem label="Cotización aprobada" value={workOrder.quote_id ?? '—'} />
          )}
          <DetailItem label="Organización cliente" value={workOrder.client_organization_id} />
          <DetailItem label="Organización proveedora" value={workOrder.provider_organization_id} />
          {workOrder.work_order_type === 'external' && (
            <DetailItem label="Importe total" value={formatAmount(workOrder.total_amount)} />
          )}
          <DetailItem label="Creada" value={formatDate(workOrder.created_at)} />
          <DetailItem label="Inicio" value={formatDate(workOrder.started_at)} />
          <DetailItem label="Completada" value={formatDate(workOrder.completed_at)} />
          {workOrder.cancelled_at && <DetailItem label="Cancelada" value={formatDate(workOrder.cancelled_at)} />}
        </div>

        {workOrder.asset_id ? (
          <RequestAssetSummary assetId={workOrder.asset_id} title="Activo asociado" />
        ) : (
          <p className="text-sm text-muted-foreground">Sin activo asociado.</p>
        )}

        {workOrder.description && (
          <div className="rounded-lg border bg-muted/30 p-3 text-sm">
            <p className="mb-1 font-medium">Descripción</p>
            <p className="whitespace-pre-wrap text-muted-foreground">{workOrder.description}</p>
          </div>
        )}

        <div className="rounded-lg border p-3 space-y-4">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Planificación operativa</p>

          {isProviderPlanner ? (
            <div className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1">
                  <Label>Planner</Label>
                  <PlannerSelect
                    organizationId={workOrder.provider_organization_id}
                    value={pendingPlannerId}
                    onChange={setPendingPlannerId}
                    disabled={saving}
                  />
                </div>
                <div className="space-y-1">
                  <Label>Técnico principal</Label>
                  <TechnicianSelect
                    organizationId={workOrder.provider_organization_id}
                    value={pendingMemberId}
                    onChange={setPendingMemberId}
                    disabled={saving}
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="wo-scheduled-at">Fecha programada</Label>
                  <Input
                    id="wo-scheduled-at"
                    type="datetime-local"
                    value={pendingScheduledAt}
                    onChange={(e) => setPendingScheduledAt(e.target.value)}
                    disabled={saving}
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="wo-due-at">Fecha límite</Label>
                  <Input
                    id="wo-due-at"
                    type="datetime-local"
                    value={pendingDueAt}
                    onChange={(e) => setPendingDueAt(e.target.value)}
                    disabled={saving}
                  />
                </div>
                <div className="space-y-1">
                  <Label>Prioridad</Label>
                  <Select value={pendingPriority} onValueChange={setPendingPriority} disabled={saving}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent className="bg-popover">
                      {Object.entries(WORK_ORDER_PRIORITY_LABELS).map(([value, label]) => (
                        <SelectItem key={value} value={value}>{label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label>Estado</Label>
                  <Select value={pendingStatus} onValueChange={setPendingStatus} disabled={saving}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent className="bg-popover">
                      {Object.entries(WORK_ORDER_STATUS_LABELS).map(([value, label]) => (
                        <SelectItem key={value} value={value}>{label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <div className="space-y-1">
                <Label htmlFor="wo-observations">Observaciones</Label>
                <Textarea
                  id="wo-observations"
                  value={pendingObservations}
                  onChange={(e) => setPendingObservations(e.target.value)}
                  disabled={saving}
                  rows={3}
                />
              </div>
              <Button size="sm" onClick={() => void handleSave()} disabled={saving || !isDirty}>
                {saving ? 'Guardando…' : 'Guardar cambios'}
              </Button>
            </div>
          ) : (
            <div className="grid gap-2 text-sm sm:grid-cols-2">
              <p><span className="text-muted-foreground">Planner: </span>{workOrder.planner_member_id ? 'Planner asignado' : 'Sin planner asignado'}</p>
              <p><span className="text-muted-foreground">Técnico: </span>{workOrder.assigned_member_id ? 'Técnico asignado' : 'Sin técnico asignado'}</p>
              <p><span className="text-muted-foreground">Programada: </span>{formatDate(workOrder.scheduled_at)}</p>
              <p><span className="text-muted-foreground">Fecha límite: </span>{formatDate(workOrder.due_at)}</p>
              <p className="flex items-center gap-2"><span className="text-muted-foreground">Prioridad:</span> <WorkOrderPriorityBadge priority={workOrder.priority} /></p>
              <p className="flex items-center gap-2"><span className="text-muted-foreground">Estado:</span> <WorkOrderStatusBadge status={workOrder.status} /></p>
              {workOrder.observations && (
                <p className="sm:col-span-2"><span className="text-muted-foreground">Observaciones: </span>{workOrder.observations}</p>
              )}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 break-all text-foreground">{value}</p>
    </div>
  );
}
