import { useEffect, useMemo, useRef, useState } from 'react';
import { ClipboardList, Eye, Package, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import { useWorkOrders, type WorkOrder } from '@/hooks/useWorkOrders';
import { useOrganizationTechnicians } from '@/hooks/useOrganizationTechnicians';
import { useOrganizationPlanners } from '@/hooks/useOrganizationPlanners';
import { useAssets } from '@/hooks/useAssets';
import { buildAssetPathMap } from '@/lib/assetTree';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { RequestTypeBadge, WorkOrderStatusBadge, WorkOrderPriorityBadge } from '@/components/requests/StatusBadge';
import { WorkOrderDetailDialog } from './WorkOrderDetailDialog';

interface WorkOrdersListProps {
  /** Deep-link target from a notification (#work-orders?workOrder=...) —
   * Dashboard parses the hash and passes these down; this component never
   * reads window.location.hash itself. */
  focusWorkOrderId?: string;
  focusActivityId?: string;
}

const shortId = (id: string) => id.slice(0, 8).toUpperCase();
const formatDate = (value: string) => new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium' }).format(new Date(value));
const formatDateOrDash = (value: string | null) => value ? formatDate(value) : '—';
const formatAmount = (value: number | null) => value === null ? '—' : new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' }).format(value);

export function WorkOrdersList({ focusWorkOrderId, focusActivityId }: WorkOrdersListProps) {
  const { currentOrganization } = useAuth();
  const { toast } = useToast();
  const { workOrders, loading, error, refetch } = useWorkOrders();
  const [selectedWorkOrder, setSelectedWorkOrder] = useState<WorkOrder | null>(null);

  // Guards against reprocessing the same focusWorkOrderId on every render
  // (e.g. once the dialog opens and this component re-renders) — only acts
  // again if the deep link target itself actually changes.
  const processedFocusIdRef = useRef<string | null>(null);
  useEffect(() => {
    if (!focusWorkOrderId || loading) return;
    if (processedFocusIdRef.current === focusWorkOrderId) return;
    processedFocusIdRef.current = focusWorkOrderId;

    const found = workOrders.find((workOrder) => workOrder.id === focusWorkOrderId);
    if (found) {
      setSelectedWorkOrder(found);
    } else {
      toast({
        title: 'No se pudo abrir la orden de trabajo',
        description: 'Puede haber sido eliminada o ya no tienes acceso.',
        variant: 'destructive',
      });
    }
  }, [focusWorkOrderId, loading, workOrders, toast]);

  const isClientView = currentOrganization?.organizationType === 'client_company';
  const isPlatformView = currentOrganization?.organizationType === 'platform_admin';

  // Resolved against the viewer's own organization. This is correct for
  // both origins: for an external OT the technician/planner belong to the
  // provider organization (unresolvable, and rightly so, for a client
  // viewer — the list/RPC simply comes back empty for them); for an
  // internal OT provider_organization_id === client_organization_id, so a
  // client viewer resolves their own staff for their own internal OTs.
  const { technicians } = useOrganizationTechnicians(currentOrganization?.id);
  const { planners } = useOrganizationPlanners(currentOrganization?.id);
  const { assets: linkedAssets, assetTree } = useAssets();
  const assetsById = useMemo(() => new Map(linkedAssets.map((asset) => [asset.id, asset])), [linkedAssets]);
  const assetPaths = useMemo(() => buildAssetPathMap(assetTree), [assetTree]);

  if (!currentOrganization) return <EmptyState message="Sin organización asignada" />;
  if (loading) return <EmptyState message="Cargando órdenes de trabajo…" />;

  if (error) {
    return (
      <Card>
        <CardHeader><CardTitle>No se pudieron cargar las órdenes de trabajo</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
          <span>{error.message}</span>
          <Button variant="outline" size="sm" onClick={() => void refetch()}><RefreshCw className="mr-2 h-4 w-4" />Reintentar</Button>
        </CardContent>
      </Card>
    );
  }

  if (workOrders.length === 0) return <EmptyState message="No hay órdenes de trabajo para esta organización" />;

  return (
    <>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0">
          <div>
            <CardTitle>Órdenes de trabajo</CardTitle>
            <p className="mt-1 text-sm text-muted-foreground">Órdenes generadas desde cotizaciones aprobadas o solicitudes internas.</p>
          </div>
          <Button variant="outline" size="icon" onClick={() => void refetch()}><RefreshCw className="h-4 w-4" /><span className="sr-only">Actualizar listado</span></Button>
        </CardHeader>
        <CardContent className="px-0 sm:px-6">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader><TableRow>
                <TableHead>Correlativo</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead className="hidden md:table-cell">Solicitud</TableHead>
                <TableHead>Activo</TableHead>
                <TableHead className="hidden lg:table-cell">Planner</TableHead>
                <TableHead>Técnico</TableHead>
                <TableHead className="hidden xl:table-cell">Programada</TableHead>
                <TableHead>Fecha límite</TableHead>
                <TableHead>Prioridad</TableHead>
                <TableHead>Estado</TableHead>
                <TableHead className="hidden lg:table-cell">{isPlatformView ? 'Cliente / proveedor' : isClientView ? 'Proveedor' : 'Cliente'}</TableHead>
                <TableHead className="hidden lg:table-cell">Importe</TableHead>
                <TableHead className="text-right">Detalle</TableHead>
              </TableRow></TableHeader>
              <TableBody>{workOrders.map((workOrder) => {
                const technicianName = workOrder.assigned_member_id
                  ? (technicians.find((technician) => technician.memberId === workOrder.assigned_member_id)?.name ?? 'Técnico asignado')
                  : '—';
                const plannerName = workOrder.planner_member_id
                  ? (planners.find((planner) => planner.memberId === workOrder.planner_member_id)?.name ?? 'Planner asignado')
                  : '—';
                const linkedAsset = workOrder.asset_id ? assetsById.get(workOrder.asset_id) : undefined;
                const assetPath = workOrder.asset_id ? assetPaths.get(workOrder.asset_id) : undefined;

                return (
                  <TableRow key={workOrder.id}>
                    <TableCell>
                      <p className="font-medium">{workOrder.work_order_number}</p>
                      <p className="text-xs text-muted-foreground truncate max-w-[180px]">{workOrder.title || 'Orden sin título'}</p>
                    </TableCell>
                    <TableCell><RequestTypeBadge type={workOrder.work_order_type} /></TableCell>
                    <TableCell className="hidden md:table-cell font-mono text-xs text-muted-foreground">#{shortId(workOrder.request_id)}</TableCell>
                    <TableCell>
                      {workOrder.asset_id ? (
                        <div className="flex items-center gap-1.5 max-w-[200px]" title={assetPath || undefined}>
                          <Package className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                          <div className="min-w-0">
                            <p className="truncate text-sm">{linkedAsset?.name || 'Activo vinculado'}</p>
                            {assetPath && <p className="truncate text-xs text-muted-foreground">{assetPath}</p>}
                          </div>
                        </div>
                      ) : <span className="text-sm text-muted-foreground">—</span>}
                    </TableCell>
                    <TableCell className="hidden lg:table-cell text-sm">{plannerName}</TableCell>
                    <TableCell className="text-sm">{technicianName}</TableCell>
                    <TableCell className="hidden xl:table-cell">{formatDateOrDash(workOrder.scheduled_at)}</TableCell>
                    <TableCell>{formatDateOrDash(workOrder.due_at)}</TableCell>
                    <TableCell><WorkOrderPriorityBadge priority={workOrder.priority} /></TableCell>
                    <TableCell><WorkOrderStatusBadge status={workOrder.status} /></TableCell>
                    <TableCell className="hidden lg:table-cell font-mono text-xs text-muted-foreground">
                      {isPlatformView ? `${shortId(workOrder.client_organization_id)} / ${shortId(workOrder.provider_organization_id)}` : isClientView ? shortId(workOrder.provider_organization_id) : shortId(workOrder.client_organization_id)}
                    </TableCell>
                    <TableCell className="hidden lg:table-cell">{formatAmount(workOrder.total_amount)}</TableCell>
                    <TableCell className="text-right"><Button variant="ghost" size="icon" onClick={() => setSelectedWorkOrder(workOrder)}><Eye className="h-4 w-4" /><span className="sr-only">Ver detalle</span></Button></TableCell>
                  </TableRow>
                );
              })}</TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
      <WorkOrderDetailDialog
        workOrder={selectedWorkOrder}
        open={selectedWorkOrder !== null}
        onOpenChange={(open) => !open && setSelectedWorkOrder(null)}
        onUpdated={(updated) => { setSelectedWorkOrder(updated); void refetch(); }}
        focusActivityId={selectedWorkOrder?.id === focusWorkOrderId ? focusActivityId : undefined}
      />
    </>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <Card><CardContent className="flex min-h-56 flex-col items-center justify-center gap-3 text-center">
      <ClipboardList className="h-10 w-10 text-muted-foreground" />
      <p className="font-medium">{message}</p>
      <p className="max-w-sm text-sm text-muted-foreground">Las órdenes de trabajo se crean al aprobar una cotización y se mostrarán aquí.</p>
    </CardContent></Card>
  );
}
