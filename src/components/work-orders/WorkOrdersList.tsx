import { useState } from 'react';
import { ClipboardList, Eye, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useWorkOrders, type WorkOrder } from '@/hooks/useWorkOrders';
import { useOrganizationTechnicians } from '@/hooks/useOrganizationTechnicians';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { WorkOrderDetailDialog } from './WorkOrderDetailDialog';

const statusLabels: Record<string, string> = {
  created: 'Creada',
  in_progress: 'En progreso',
  completed: 'Completada',
  cancelled: 'Cancelada',
};

const shortId = (id: string) => id.slice(0, 8).toUpperCase();
const formatDate = (value: string) => new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium' }).format(new Date(value));
const formatAmount = (value: number | null) => value === null ? '—' : new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' }).format(value);

export function WorkOrdersList() {
  const { currentOrganization } = useAuth();
  const { workOrders, loading, error, refetch } = useWorkOrders();
  const [selectedWorkOrder, setSelectedWorkOrder] = useState<WorkOrder | null>(null);

  const isClientView = currentOrganization?.organizationType === 'client_company';
  const isPlatformView = currentOrganization?.organizationType === 'platform_admin';
  const isProviderView = !isClientView && !isPlatformView;
  // Only fetched (and only ever succeeds) when viewing as the provider
  // organization with a planner-tier role — used purely to show the
  // assigned technician's name next to each order, read-only here.
  const { technicians } = useOrganizationTechnicians(isProviderView ? currentOrganization?.id : null);

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
            <p className="mt-1 text-sm text-muted-foreground">Órdenes generadas desde cotizaciones aprobadas.</p>
          </div>
          <Button variant="outline" size="icon" onClick={() => void refetch()}><RefreshCw className="h-4 w-4" /><span className="sr-only">Actualizar listado</span></Button>
        </CardHeader>
        <CardContent className="px-0 sm:px-6">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader><TableRow>
                <TableHead>Orden</TableHead><TableHead>Estado</TableHead><TableHead>Solicitud</TableHead>
                <TableHead>{isPlatformView ? 'Cliente / proveedor' : isClientView ? 'Proveedor' : 'Cliente'}</TableHead>
                {isProviderView && <TableHead>Técnico</TableHead>}
                <TableHead>Importe</TableHead><TableHead>Creada</TableHead><TableHead className="text-right">Detalle</TableHead>
              </TableRow></TableHeader>
              <TableBody>{workOrders.map((workOrder) => (
                <TableRow key={workOrder.id}>
                  <TableCell><p className="font-medium">{workOrder.title || 'Orden sin título'}</p><p className="text-xs text-muted-foreground">#{shortId(workOrder.id)}</p></TableCell>
                  <TableCell><Badge variant="secondary">{statusLabels[workOrder.status] ?? workOrder.status}</Badge></TableCell>
                  <TableCell className="font-mono text-xs">#{shortId(workOrder.request_id)}</TableCell>
                  <TableCell className="font-mono text-xs text-muted-foreground">
                    {isPlatformView ? `${shortId(workOrder.client_organization_id)} / ${shortId(workOrder.provider_organization_id)}` : isClientView ? shortId(workOrder.provider_organization_id) : shortId(workOrder.client_organization_id)}
                  </TableCell>
                  {isProviderView && (
                    <TableCell className="text-sm">
                      {technicians.find((technician) => technician.memberId === workOrder.assigned_member_id)?.name ?? (workOrder.assigned_member_id ? 'Técnico asignado' : '—')}
                    </TableCell>
                  )}
                  <TableCell>{formatAmount(workOrder.total_amount)}</TableCell><TableCell>{formatDate(workOrder.created_at)}</TableCell>
                  <TableCell className="text-right"><Button variant="ghost" size="icon" onClick={() => setSelectedWorkOrder(workOrder)}><Eye className="h-4 w-4" /><span className="sr-only">Ver detalle</span></Button></TableCell>
                </TableRow>
              ))}</TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
      <WorkOrderDetailDialog
        workOrder={selectedWorkOrder}
        open={selectedWorkOrder !== null}
        onOpenChange={(open) => !open && setSelectedWorkOrder(null)}
        onAssigned={(updated) => { setSelectedWorkOrder(updated); void refetch(); }}
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
