import { useEffect, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
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
import { useOrganizationTechnicians } from '@/hooks/useOrganizationTechnicians';
import { TechnicianSelect } from '@/components/members/TechnicianSelect';
import { supabase } from '@/integrations/supabase/client';
import type { WorkOrder } from '@/hooks/useWorkOrders';

interface WorkOrderDetailDialogProps {
  workOrder: WorkOrder | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAssigned?: (workOrder: WorkOrder) => void;
}

const statusLabels: Record<string, string> = {
  created: 'Creada',
  in_progress: 'En progreso',
  completed: 'Completada',
  cancelled: 'Cancelada',
};

const formatDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : '—';

const formatAmount = (value: number | null) => value === null
  ? '—'
  : new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' }).format(value);

export function WorkOrderDetailDialog({ workOrder, open, onOpenChange, onAssigned }: WorkOrderDetailDialogProps) {
  const { currentOrganization } = useAuth();
  const { canPlanWork } = usePermissions();
  const { toast } = useToast();
  const [saving, setSaving] = useState(false);
  const [pendingMemberId, setPendingMemberId] = useState<string | null>(null);

  // Only the provider organization plans its own technicians' work; viewing
  // this dialog as the client organization never shows the assign control.
  const isProviderPlanner = !!workOrder
    && currentOrganization?.id === workOrder.provider_organization_id
    && canPlanWork;

  const { technicians } = useOrganizationTechnicians(workOrder?.provider_organization_id);

  useEffect(() => {
    setPendingMemberId(workOrder?.assigned_member_id ?? null);
  }, [workOrder?.id, workOrder?.assigned_member_id]);

  if (!workOrder) return null;

  const assignedTechnician = technicians.find((technician) => technician.memberId === workOrder.assigned_member_id);

  const handleSaveAssignment = async () => {
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('assign_work_order_technician', {
        target_work_order_id: workOrder.id,
        target_member_id: pendingMemberId,
      });
      if (error) throw error;
      toast({
        title: pendingMemberId ? 'Técnico asignado' : 'Asignación removida',
        description: pendingMemberId
          ? 'El técnico fue asignado a la orden de trabajo.'
          : 'La orden de trabajo quedó sin técnico asignado.',
      });
      if (data) onAssigned?.(data);
    } catch (error) {
      toast({
        title: 'No se pudo asignar el técnico',
        description: error instanceof Error ? error.message : 'Intenta nuevamente.',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <div className="flex items-start justify-between gap-4">
            <div>
              <DialogTitle>{workOrder.title || 'Orden sin título'}</DialogTitle>
              <DialogDescription className="mt-1">Orden #{workOrder.id.slice(0, 8).toUpperCase()}</DialogDescription>
            </div>
            <div className="flex items-center gap-2">
              {workOrder.quote_id === null && (
                <Badge variant="outline" className="bg-violet-500/10 text-violet-600 border-violet-500/20">Solicitud interna</Badge>
              )}
              <Badge variant="secondary">{statusLabels[workOrder.status] ?? workOrder.status}</Badge>
            </div>
          </div>
        </DialogHeader>

        <div className="grid gap-4 text-sm sm:grid-cols-2">
          <DetailItem label="Solicitud asociada" value={workOrder.request_id} />
          <DetailItem label="Cotización aprobada" value={workOrder.quote_id ?? 'No aplica (solicitud interna)'} />
          <DetailItem label="Organización cliente" value={workOrder.client_organization_id} />
          <DetailItem label="Organización proveedora" value={workOrder.provider_organization_id} />
          <DetailItem label="Importe total" value={formatAmount(workOrder.total_amount)} />
          <DetailItem label="Creada" value={formatDate(workOrder.created_at)} />
          <DetailItem label="Inicio" value={formatDate(workOrder.started_at)} />
          <DetailItem label="Completada" value={formatDate(workOrder.completed_at)} />
          {workOrder.cancelled_at && <DetailItem label="Cancelada" value={formatDate(workOrder.cancelled_at)} />}
        </div>

        {workOrder.description && (
          <div className="rounded-lg border bg-muted/30 p-3 text-sm">
            <p className="mb-1 font-medium">Descripción</p>
            <p className="whitespace-pre-wrap text-muted-foreground">{workOrder.description}</p>
          </div>
        )}

        <div className="rounded-lg border p-3">
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">Técnico asignado</p>
          {isProviderPlanner ? (
            <div className="space-y-3">
              <TechnicianSelect
                organizationId={workOrder.provider_organization_id}
                value={pendingMemberId}
                onChange={setPendingMemberId}
                disabled={saving}
              />
              <Button
                size="sm"
                onClick={() => void handleSaveAssignment()}
                disabled={saving || pendingMemberId === (workOrder.assigned_member_id ?? null)}
              >
                {saving ? 'Guardando…' : 'Guardar asignación'}
              </Button>
            </div>
          ) : (
            <p className="text-sm">
              {workOrder.assigned_member_id
                ? (assignedTechnician ? `${assignedTechnician.name} (${assignedTechnician.email})` : 'Técnico asignado')
                : 'Sin técnico asignado'}
            </p>
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
