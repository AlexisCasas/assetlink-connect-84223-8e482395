import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import type { WorkOrder } from '@/hooks/useWorkOrders';

interface WorkOrderDetailDialogProps {
  workOrder: WorkOrder | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
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

export function WorkOrderDetailDialog({ workOrder, open, onOpenChange }: WorkOrderDetailDialogProps) {
  if (!workOrder) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <div className="flex items-start justify-between gap-4">
            <div>
              <DialogTitle>{workOrder.title || 'Orden sin título'}</DialogTitle>
              <DialogDescription className="mt-1">Orden #{workOrder.id.slice(0, 8).toUpperCase()}</DialogDescription>
            </div>
            <Badge variant="secondary">{statusLabels[workOrder.status] ?? workOrder.status}</Badge>
          </div>
        </DialogHeader>

        <div className="grid gap-4 text-sm sm:grid-cols-2">
          <DetailItem label="Solicitud asociada" value={workOrder.request_id} />
          <DetailItem label="Cotización aprobada" value={workOrder.quote_id} />
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
