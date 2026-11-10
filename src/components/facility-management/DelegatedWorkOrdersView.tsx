import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { canFacilityManagerManageInternalWorkOrders } from '@/lib/facilityManagement';
import { DelegatedWorkOrderPlanningForm } from './DelegatedWorkOrderPlanningForm';
import { ClipboardList, Eye, LockKeyhole, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import {
  RequestTypeBadge,
  WorkOrderPriorityBadge,
  WorkOrderStatusBadge,
} from '@/components/requests/StatusBadge';
import {
  fetchDelegatedWorkOrder,
  fetchDelegatedWorkOrders,
  type DelegatedWorkOrder,
  type DelegatedWorkOrderStatusFilter,
} from '@/lib/delegatedWorkOrders';
import { navigateToEntity } from '@/lib/entityNavigation';
import { isValidUuid } from '@/lib/providerHelpers';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

const PAGE_SIZE = 20;
const statusOptions: { value: DelegatedWorkOrderStatusFilter; label: string }[] = [
  { value: 'all', label: 'Todos los estados' },
  { value: 'pending', label: 'Pendientes' },
  { value: 'assigned', label: 'Asignadas' },
  { value: 'in_progress', label: 'En progreso' },
  { value: 'completed', label: 'Completadas' },
  { value: 'closed', label: 'Cerradas' },
];

function formatDate(value: string | null): string {
  if (!value) return '—';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? '—'
    : new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium' }).format(parsed);
}

function formatPrice(order: DelegatedWorkOrder): string {
  if (!order.pricesVisible && order.workOrderType === 'external') return 'Importe restringido';
  if (order.totalAmount === null) return '—';
  return new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' })
    .format(order.totalAmount);
}

function DetailField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1">
      <dt className="text-xs font-medium text-muted-foreground">{label}</dt>
      <dd className="break-words text-sm">{children}</dd>
    </div>
  );
}

function WorkOrderDetail({
  client,
  orderId,
  onClose,
  onSaved,
}: {
  client: FacilityManagementOperationalClient;
  orderId: string | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { currentOrganization, user } = useAuth();
  const validId = !!orderId && isValidUuid(orderId);
  const query = useQuery({
    queryKey: [
      'fm-delegated-work-order-detail',
      user?.id,
      currentOrganization?.id,
      client.relationshipId,
      client.clientOrganizationId,
      orderId,
    ],
    queryFn: () => fetchDelegatedWorkOrder(client.clientOrganizationId, orderId!),
    enabled: validId && !!user?.id,
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: 'always',
  });

  const order = validId && query.isSuccess ? query.data : null;
  // Client-side eligibility is only a UI hint: the B2.1 RPC revalidates
  // the active relationship, assignment, three grants and OT status on save.
  const canPlan = !!order
    && canFacilityManagerManageInternalWorkOrders(client)
    && order.workOrderType === 'internal'
    && ['pending', 'assigned', 'in_progress'].includes(order.status);

  return (
    <Dialog open={!!orderId} onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Detalle de orden de trabajo</DialogTitle>
          <DialogDescription>
            Información autorizada de {client.clientOrganizationName}.
            {canPlan ? ' Puedes coordinar prioridad y fechas de esta OT interna.' : ' Vista de solo lectura.'}
          </DialogDescription>
        </DialogHeader>
        {!validId || query.isError ? (
          <div role="alert" className="space-y-3 rounded-md border p-4">
            <p>La orden no está disponible o ya no tienes acceso a ella.</p>
            <Button size="sm" variant="outline" onClick={() => void query.refetch()}>Reintentar</Button>
          </div>
        ) : query.isLoading || !order ? (
          <p className="py-6 text-sm text-muted-foreground" role="status">Verificando acceso y cargando detalle…</p>
        ) : (
          <div className="space-y-5" data-testid="delegated-work-order-detail">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-lg font-semibold">{order.workOrderNumber}</span>
              <RequestTypeBadge type={order.workOrderType} />
              <WorkOrderStatusBadge status={order.status} />
              <WorkOrderPriorityBadge priority={order.priority} />
              <Badge variant="outline">{canPlan ? 'Planificación autorizada' : 'Solo lectura'}</Badge>
            </div>
            <h3 className="text-base font-medium">{order.title}</h3>
            <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <DetailField label="Solicitud">{order.requestNumber ?? '—'}</DetailField>
              <DetailField label="Operación">{order.operatorLabel}</DetailField>
              <DetailField label="Activo">{order.assetLabel ?? 'No disponible con tus permisos'}</DetailField>
              <DetailField label="Prioridad"><WorkOrderPriorityBadge priority={order.priority} /></DetailField>
              <DetailField label="Programada">{formatDate(order.scheduledAt)}</DetailField>
              <DetailField label="Fecha límite">{formatDate(order.dueAt)}</DetailField>
              <DetailField label="Inicio">{formatDate(order.startedAt)}</DetailField>
              <DetailField label="Finalización">{formatDate(order.completedAt)}</DetailField>
              <DetailField label="Planificador">{order.hasPlanner ? 'Asignado' : 'Sin asignar'}</DetailField>
              <DetailField label="Técnico">{order.hasTechnician ? 'Asignado' : 'Sin asignar'}</DetailField>
            </dl>
            {order.description && (
              <div className="space-y-1">
                <p className="text-xs font-medium text-muted-foreground">Descripción</p>
                <p className="whitespace-pre-wrap text-sm">{order.description}</p>
              </div>
            )}
            {canPlan && (
              <DelegatedWorkOrderPlanningForm
                key={`${order.id}:${order.priority}:${order.scheduledAt ?? ''}:${order.dueAt ?? ''}`}
                clientOrganizationId={client.clientOrganizationId}
                workOrder={order}
                onSaved={() => {
                  void query.refetch();
                  onSaved();
                }}
              />
            )}
            <div className="rounded-md border bg-muted/30 p-4">
              <p className="text-xs text-muted-foreground">Importe de la orden</p>
              <p className="mt-1 font-semibold">{formatPrice(order)}</p>
              {!order.pricesVisible && order.workOrderType === 'external' && (
                <p className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
                  <LockKeyhole className="h-3.5 w-3.5" /> El cliente no ha autorizado visualizar este importe.
                </p>
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              La planificación operativa, los materiales, los reportes y las acciones de cierre corresponden a la organización ejecutora.
            </p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

/** 9C.6-C1/C2.1: B1 safe reads; B2.1 internal-only planning when authorized.
 * The ManagedClientGate is mounted by DelegatedWorkOrdersModule, and every RPC
 * re-checks the active relationship, member assignment, roles and grants.
 * Never mount WorkOrdersList/useWorkOrders/WorkOrderDetailDialog here. */
export function DelegatedWorkOrdersView({
  client,
  focusWorkOrderId,
}: {
  client: FacilityManagementOperationalClient;
  focusWorkOrderId?: string;
}) {
  const { currentOrganization, user } = useAuth();
  const [status, setStatus] = useState<DelegatedWorkOrderStatusFilter>('all');
  const [page, setPage] = useState(0);

  const query = useQuery({
    queryKey: [
      'fm-delegated-work-orders',
      user?.id,
      currentOrganization?.id,
      client.relationshipId,
      client.clientOrganizationId,
      status,
      page,
    ],
    queryFn: () => fetchDelegatedWorkOrders(client.clientOrganizationId, status, PAGE_SIZE, page * PAGE_SIZE),
    enabled: !!user?.id,
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: 'always',
  });

  const openDetail = (id: string) => {
    navigateToEntity({ view: 'managed-work-orders', managedClientId: client.clientOrganizationId, workOrderId: id });
  };

  const closeDetail = () => {
    navigateToEntity({ view: 'managed-work-orders', managedClientId: client.clientOrganizationId });
  };

  const items = query.data?.items ?? [];
  const total = query.data?.total ?? 0;
  const start = total > 0 ? page * PAGE_SIZE + 1 : 0;
  const end = Math.min(total, (page + 1) * PAGE_SIZE);

  return (
    <div className="space-y-5 p-6" data-testid="delegated-work-orders">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold">
            <ClipboardList className="h-6 w-6 text-primary" /> Órdenes de trabajo
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Seguimiento de órdenes de {client.clientOrganizationName}. No puedes modificar la ejecución del proveedor.
          </p>
        </div>
        <Button variant="outline" size="sm" disabled={query.isFetching} onClick={() => void query.refetch()}>
          <RefreshCw className="mr-2 h-4 w-4" /> Actualizar
        </Button>
      </div>

      <Card>
        <CardHeader className="gap-3 sm:flex-row sm:items-center sm:justify-between">
          <CardTitle className="text-lg">Órdenes del cliente</CardTitle>
          <div className="w-full sm:w-56">
            <Select value={status} onValueChange={(value) => {
              setStatus(value as DelegatedWorkOrderStatusFilter);
              setPage(0);
            }}>
              <SelectTrigger aria-label="Filtrar órdenes por estado"><SelectValue placeholder="Estado" /></SelectTrigger>
              <SelectContent>
                {statusOptions.map(({ value, label }) => (
                  <SelectItem key={value} value={value}>{label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </CardHeader>
        <CardContent>
          {query.isLoading ? (
            <p role="status" className="py-8 text-center text-sm text-muted-foreground">Cargando órdenes autorizadas…</p>
          ) : query.isError ? (
            <div role="alert" className="space-y-3 py-6 text-center">
              <p className="text-sm text-destructive">No se pudo consultar las órdenes. Comprueba que sigues asignado y que el cliente mantiene los permisos.</p>
              <Button variant="outline" onClick={() => void query.refetch()}>Reintentar</Button>
            </div>
          ) : items.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              No hay órdenes disponibles para este cliente con el estado seleccionado.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Orden</TableHead>
                    <TableHead>Tipo</TableHead>
                    <TableHead>Solicitud</TableHead>
                    <TableHead>Estado</TableHead>
                    <TableHead>Prioridad</TableHead>
                    <TableHead className="hidden lg:table-cell">Programada</TableHead>
                    <TableHead>Fecha límite</TableHead>
                    <TableHead className="hidden lg:table-cell">Importe</TableHead>
                    <TableHead className="text-right">Detalle</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {items.map((order) => (
                    <TableRow key={order.id}>
                      <TableCell>
                        <p className="font-medium">{order.workOrderNumber}</p>
                        <p className="max-w-[220px] truncate text-xs text-muted-foreground">{order.title}</p>
                      </TableCell>
                      <TableCell><RequestTypeBadge type={order.workOrderType} /></TableCell>
                      <TableCell className="text-sm">{order.requestNumber ?? '—'}</TableCell>
                      <TableCell><WorkOrderStatusBadge status={order.status} /></TableCell>
                      <TableCell><WorkOrderPriorityBadge priority={order.priority} /></TableCell>
                      <TableCell className="hidden lg:table-cell">{formatDate(order.scheduledAt)}</TableCell>
                      <TableCell>{formatDate(order.dueAt)}</TableCell>
                      <TableCell className="hidden lg:table-cell text-sm">{formatPrice(order)}</TableCell>
                      <TableCell className="text-right">
                        <Button size="sm" variant="ghost" onClick={() => openDetail(order.id)} aria-label={`Ver detalle de ${order.workOrderNumber}`}>
                          <Eye className="h-4 w-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}

          {!query.isError && !query.isLoading && total > 0 && (
            <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t pt-4">
              <p className="text-xs text-muted-foreground">Mostrando {start}–{end} de {total} órdenes</p>
              <div className="flex items-center gap-2">
                <Button size="sm" variant="outline" disabled={page === 0 || query.isFetching} onClick={() => setPage((p) => Math.max(0, p - 1))}>
                  Anterior
                </Button>
                <Button size="sm" variant="outline" disabled={end >= total || query.isFetching} onClick={() => setPage((p) => p + 1)}>
                  Siguiente
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
      <WorkOrderDetail
        client={client}
        orderId={focusWorkOrderId ?? null}
        onClose={closeDetail}
        onSaved={() => void query.refetch()}
      />
    </div>
  );
}
