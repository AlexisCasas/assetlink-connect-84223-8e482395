import { useQuery } from '@tanstack/react-query';
import {
  AlertTriangle, BarChart3, Boxes, ClipboardList,
  FileText, LockKeyhole, RefreshCw, ShieldAlert,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useAuth } from '@/contexts/AuthContext';
import { fetchDelegatedClientMetrics } from '@/lib/delegatedClientMetrics';
import { canFacilityManagerViewReports, canFacilityManagerViewWorkOrders } from '@/lib/facilityManagement';
import { navigateToEntity } from '@/lib/entityNavigation';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';
import { DelegatedClientTrendsPanel } from './DelegatedClientTrendsPanel';

type CardIcon = typeof ClipboardList;

function KpiCard({ label, value, icon: Icon, emphasis }: {
  label: string; value: number; icon: CardIcon; emphasis?: boolean;
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon aria-hidden="true" className={`h-4 w-4 ${emphasis && value > 0 ? 'text-destructive' : 'text-muted-foreground'}`} />
      </CardHeader>
      <CardContent>
        <div className={`text-2xl font-bold tabular-nums ${emphasis && value > 0 ? 'text-destructive' : ''}`}>
          {value.toLocaleString('es-PE')}
        </div>
      </CardContent>
    </Card>
  );
}

function RestrictedSection({ title }: { title: string }) {
  return (
    <Card>
      <CardContent className="flex items-center gap-3 py-5 text-muted-foreground">
        <LockKeyhole className="h-5 w-5 shrink-0" aria-hidden="true" />
        <div>
          <p className="font-medium text-foreground">{title}</p>
          <p className="text-sm">Sin acceso a estos indicadores. El cliente debe conceder el permiso del módulo.</p>
        </div>
      </CardContent>
    </Card>
  );
}

const STATUS_LABELS = [
  ['pending', 'Pendiente'],
  ['assigned', 'Asignada'],
  ['inProgress', 'En proceso'],
  ['completed', 'Completada'],
  ['closed', 'Cerrada'],
] as const;

export function DelegatedClientMetricsView({ client }: { client: FacilityManagementOperationalClient }) {
  const { user, currentOrganization } = useAuth();
  const allowed = currentOrganization?.organizationType === 'facility_manager'
    && currentOrganization.id === client.facilityManagerOrganizationId
    && canFacilityManagerViewReports(client);

  const query = useQuery({
    queryKey: [
      'fm-client-kpi-9c7',
      user?.id ?? null,
      currentOrganization?.id ?? null,
      client.relationshipId,
      client.clientOrganizationId,
    ],
    enabled: !!user?.id && !!allowed,
    queryFn: () => fetchDelegatedClientMetrics(client.clientOrganizationId, client.relationshipId),
    staleTime: 0,
    gcTime: 0,
    retry: false,
    refetchOnWindowFocus: true,
  });

  if (!allowed) {
    return <div className="p-6" role="status">Sin acceso a indicadores de este cliente.</div>;
  }

  const data = query.data;
  return (
    <div className="space-y-6 p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="mb-2 flex items-center gap-2">
            <BarChart3 className="h-6 w-6 text-primary" aria-hidden="true" />
            <h1 className="text-2xl font-bold">Indicadores de clientes</h1>
            <Badge variant="outline">Solo lectura</Badge>
          </div>
          <p className="text-sm text-muted-foreground">
            Resumen actual de {client.clientOrganizationName}. Las cifras corresponden únicamente a este cliente.
          </p>
          {data && (
            <p className="mt-2 text-xs text-muted-foreground" data-testid="fm-kpi-as-of">
              Actualizado: {new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(data.asOf))}
            </p>
          )}
        </div>
        <Button size="sm" variant="outline" onClick={() => void query.refetch()} disabled={query.isFetching}>
          <RefreshCw className={`mr-2 h-4 w-4 ${query.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
          Actualizar
        </Button>
      </div>

      {query.isPending && <p role="status" className="text-sm text-muted-foreground">Cargando indicadores autorizados…</p>}
      {query.isError && (
        <Card role="alert">
          <CardContent className="space-y-2 py-5">
            <p className="font-medium text-destructive">No se pudieron cargar los indicadores.</p>
            <p className="text-sm text-muted-foreground">{query.error instanceof Error ? query.error.message : 'Error de consulta.'}</p>
          </CardContent>
        </Card>
      )}

      {data && (
        <>
          <section className="space-y-3" aria-label="Órdenes de trabajo">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-lg font-semibold">Órdenes de trabajo</h2>
              {canFacilityManagerViewWorkOrders(client) && (
                <Button size="sm" variant="link" onClick={() => navigateToEntity({
                  view: 'managed-work-orders',
                  managedClientId: client.clientOrganizationId,
                })}>Ver órdenes</Button>
              )}
            </div>
            {data.workOrders ? (
              <>
                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                  <KpiCard label="Órdenes totales" value={data.workOrders.total} icon={ClipboardList} />
                  <KpiCard label="Órdenes abiertas" value={data.workOrders.open} icon={FileText} />
                  <KpiCard label="Órdenes abiertas vencidas" value={data.workOrders.overdueOpen} icon={AlertTriangle} emphasis />
                </div>
                <div className="grid gap-4 lg:grid-cols-2">
                  <Card>
                    <CardHeader><CardTitle className="text-sm">Distribución por estado</CardTitle></CardHeader>
                    <CardContent className="space-y-3">
                      {STATUS_LABELS.map(([key, label]) => {
                        const count = data.workOrders?.byStatus[key] ?? 0;
                        const percent = data.workOrders?.total ? 100 * count / data.workOrders.total : 0;
                        return (
                          <div key={key} className="space-y-1">
                            <div className="flex justify-between text-sm">
                              <span>{label}</span><span className="tabular-nums">{count}</span>
                            </div>
                            <div className="h-2 overflow-hidden rounded-full bg-muted">
                              <div className="h-full rounded-full bg-primary" style={{ width: `${percent}%` }} />
                            </div>
                          </div>
                        );
                      })}
                    </CardContent>
                  </Card>
                  <Card>
                    <CardHeader><CardTitle className="text-sm">Origen de las órdenes</CardTitle></CardHeader>
                    <CardContent className="grid grid-cols-2 gap-4">
                      <div><p className="text-sm text-muted-foreground">Internas</p>
                        <p className="mt-2 text-2xl font-semibold tabular-nums">{data.workOrders.byType.internal}</p>
                      </div>
                      <div><p className="text-sm text-muted-foreground">Externas</p>
                        <p className="mt-2 text-2xl font-semibold tabular-nums">{data.workOrders.byType.external}</p>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </>
            ) : <RestrictedSection title="Órdenes de trabajo" />}
          </section>

          <div className="grid gap-6 lg:grid-cols-2">
            <section className="space-y-3" aria-label="Solicitudes">
              <h2 className="text-lg font-semibold">Solicitudes</h2>
              {data.requests
                ? <KpiCard label="Solicitudes abiertas" value={data.requests.open} icon={FileText} />
                : <RestrictedSection title="Solicitudes" />}
            </section>
            <section className="space-y-3" aria-label="Activos">
              <h2 className="text-lg font-semibold">Activos</h2>
              {data.assets
                ? <div className="grid gap-4 sm:grid-cols-2">
                    <KpiCard label="Activos vigentes" value={data.assets.active} icon={Boxes} />
                    <KpiCard label="Criticidad muy alta" value={data.assets.critical} icon={ShieldAlert} />
                  </div>
                : <RestrictedSection title="Activos" />}
            </section>
          </div>

          <p className="text-xs text-muted-foreground">
            Las tarjetas anteriores representan una fotografía actual de órdenes, solicitudes y activos.
            No incluyen importes, horas, técnicos ni información privada del proveedor.
          </p>
          <DelegatedClientTrendsPanel client={client} />
        </>
      )}
    </div>
  );
}
