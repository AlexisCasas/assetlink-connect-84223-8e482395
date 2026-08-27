import { useState } from 'react';
import { ClipboardList, Eye, MapPin, NotebookPen, Package, Play, CheckCircle2, RefreshCw } from 'lucide-react';
import { useTechnicianWorkOrders } from '@/hooks/useTechnicianWorkOrders';
import { useToast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  RequestTypeBadge,
  WorkOrderStatusBadge,
  WorkOrderPriorityBadge,
  WorkOrderActivityStatusBadge,
  WorkOrderMaterialWarningBadge,
} from '@/components/requests/StatusBadge';
import { TechnicianWorkLogDialog } from './TechnicianWorkLogDialog';
import { TechnicianWorkOrderDetailDialog } from './TechnicianWorkOrderDetailDialog';
import type { TechnicianWorkOrder } from '@/types/technicianWorkOrder';

const formatDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium' }).format(new Date(value))
  : '—';

export function TechnicianWorkView() {
  const { workOrders, loading, saving, error, refresh, updateProgress } = useTechnicianWorkOrders();
  const { toast } = useToast();

  const [logDialogTarget, setLogDialogTarget] = useState<TechnicianWorkOrder | null>(null);
  const [detailTarget, setDetailTarget] = useState<TechnicianWorkOrder | null>(null);

  const handleStart = async (workOrder: TechnicianWorkOrder) => {
    const ok = await updateProgress(workOrder.id, 'in_progress');
    toast(ok
      ? { title: 'Orden iniciada', description: `${workOrder.workOrderNumber} pasó a En ejecución.` }
      : { title: 'No se pudo iniciar la orden', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
  };

  const handleFinish = async (workOrder: TechnicianWorkOrder) => {
    const ok = await updateProgress(workOrder.id, 'completed');
    toast(ok
      ? { title: 'Orden finalizada', description: `${workOrder.workOrderNumber} pasó a Finalizada.` }
      : { title: 'No se pudo finalizar la orden', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
  };

  const handleLogSubmit = async (note: string, status?: string): Promise<boolean> => {
    if (!logDialogTarget) return false;
    const ok = await updateProgress(logDialogTarget.id, status, note || undefined);
    toast(ok
      ? { title: 'Trabajo registrado' }
      : { title: 'No se pudo registrar el trabajo', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
    return ok;
  };

  return (
    <div className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Mis órdenes de trabajo</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Solo tus órdenes asignadas — como técnico principal o en una actividad.
          </p>
        </div>
        <Button variant="outline" size="icon" onClick={() => void refresh()} disabled={loading}>
          <RefreshCw className="h-4 w-4" />
          <span className="sr-only">Actualizar</span>
        </Button>
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando tus órdenes de trabajo…</p>
      ) : error ? (
        <Card>
          <CardHeader><CardTitle>No se pudieron cargar tus órdenes de trabajo</CardTitle></CardHeader>
          <CardContent className="flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
            <span>{error}</span>
            <Button variant="outline" size="sm" onClick={() => void refresh()}><RefreshCw className="mr-2 h-4 w-4" />Reintentar</Button>
          </CardContent>
        </Card>
      ) : workOrders.length === 0 ? (
        <Card>
          <CardContent className="flex min-h-56 flex-col items-center justify-center gap-3 text-center">
            <ClipboardList className="h-10 w-10 text-muted-foreground" />
            <p className="font-medium">No tienes órdenes de trabajo asignadas.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {workOrders.map((workOrder) => {
            const canStart = workOrder.status === 'pending' || workOrder.status === 'assigned';
            const canFinish = workOrder.status === 'in_progress';
            return (
              <Card key={workOrder.id}>
                <CardHeader className="space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <CardTitle className="text-base">{workOrder.workOrderNumber}</CardTitle>
                      <p className="text-sm text-muted-foreground">{workOrder.title || 'Orden sin título'}</p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      <RequestTypeBadge type={workOrder.workOrderType} />
                      <WorkOrderStatusBadge status={workOrder.status} />
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
                    <span className="flex items-center gap-1">
                      <Package className="h-3.5 w-3.5" /> {workOrder.assetPath || workOrder.assetName || 'Sin activo'}
                    </span>
                    {workOrder.location && (
                      <span className="flex items-center gap-1">
                        <MapPin className="h-3.5 w-3.5" /> {workOrder.location}
                      </span>
                    )}
                    <span>Programada: {formatDate(workOrder.scheduledAt)}</span>
                    <span>Límite: {formatDate(workOrder.dueAt)}</span>
                    <WorkOrderPriorityBadge priority={workOrder.priority} />
                  </div>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="space-y-1">
                    <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Actividades</p>
                    {workOrder.activities.length === 0 ? (
                      <p className="text-xs text-muted-foreground">Sin actividades asignadas.</p>
                    ) : (
                      workOrder.activities.map((activity) => (
                        <div key={activity.id} className="flex items-center justify-between gap-2 text-xs">
                          <span className="truncate">{activity.description}{activity.estimatedHours != null ? ` (${activity.estimatedHours} h)` : ''}</span>
                          <WorkOrderActivityStatusBadge status={activity.status} />
                        </div>
                      ))
                    )}
                  </div>

                  <div className="space-y-1">
                    <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Materiales</p>
                    {workOrder.materials.length === 0 ? (
                      <p className="text-xs text-muted-foreground">Sin materiales registrados.</p>
                    ) : (
                      workOrder.materials.map((material) => (
                        <div key={material.id} className="flex items-center justify-between gap-2 text-xs">
                          <span className="truncate">{material.materialCode} — {material.plannedQuantity} {material.materialUnit}</span>
                          <WorkOrderMaterialWarningBadge status={material.warningStatus} />
                        </div>
                      ))
                    )}
                  </div>

                  <div className="flex flex-wrap gap-2 pt-1">
                    {canStart && (
                      <Button size="sm" onClick={() => void handleStart(workOrder)} disabled={saving}>
                        <Play className="mr-1 h-3.5 w-3.5" /> Iniciar
                      </Button>
                    )}
                    {canFinish && (
                      <Button size="sm" onClick={() => void handleFinish(workOrder)} disabled={saving}>
                        <CheckCircle2 className="mr-1 h-3.5 w-3.5" /> Finalizar
                      </Button>
                    )}
                    <Button size="sm" variant="outline" onClick={() => setLogDialogTarget(workOrder)} disabled={saving}>
                      <NotebookPen className="mr-1 h-3.5 w-3.5" /> Registrar trabajo
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => setDetailTarget(workOrder)}>
                      <Eye className="mr-1 h-3.5 w-3.5" /> Ver detalle
                    </Button>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      <TechnicianWorkLogDialog
        open={logDialogTarget !== null}
        onOpenChange={(open) => !open && setLogDialogTarget(null)}
        workOrder={logDialogTarget}
        saving={saving}
        onSubmit={handleLogSubmit}
      />

      <TechnicianWorkOrderDetailDialog
        open={detailTarget !== null}
        onOpenChange={(open) => !open && setDetailTarget(null)}
        workOrder={detailTarget}
      />
    </div>
  );
}
