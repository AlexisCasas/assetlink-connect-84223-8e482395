import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from 'recharts';
import { BarChart3, CalendarDays, LockKeyhole, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import type { ChartConfig } from '@/components/ui/chart';
import { useAuth } from '@/contexts/AuthContext';
import {
  dateRangeError,
  fetchDelegatedClientTrends,
  PILOT_TRENDS_TIME_ZONE,
  shiftCalendarDate,
  todayInLima,
} from '@/lib/delegatedClientTrends';
import { visibleDelegatedClientTrends } from '@/lib/delegatedClientTrendsVisibility';
import { canFacilityManagerViewReports } from '@/lib/facilityManagement';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

const ORDER_CHART_CONFIG = {
  created: { label: 'OT creadas', color: 'hsl(var(--primary))' },
  completed: { label: 'OT finalizadas', color: 'hsl(var(--chart-2))' },
} satisfies ChartConfig;

const REQUEST_CHART_CONFIG = {
  created: { label: 'Solicitudes creadas', color: 'hsl(var(--primary))' },
} satisfies ChartConfig;

type DaysPreset = '30' | '90' | '180' | 'custom';
const PRESETS = [30, 90, 180] as const;

function sum(rows: { created: number }[], key: 'created'): number;
function sum(rows: { completed: number }[], key: 'completed'): number;
function sum(rows: { created?: number; completed?: number }[], key: 'created' | 'completed') {
  return rows.reduce((result, day) => result + (day[key] ?? 0), 0);
}

function ReadonlySection({ name }: { name: string }) {
  return (
    <Card>
      <CardContent className="flex gap-3 py-5 text-muted-foreground">
        <LockKeyhole className="h-5 w-5 shrink-0" aria-hidden="true" />
        <div>
          <p className="font-medium text-foreground">{name}</p>
          <p className="text-sm">Sin acceso. Solicita al cliente el permiso de lectura del módulo.</p>
        </div>
      </CardContent>
    </Card>
  );
}

function DailyTable({ rows, label, includesCompleted }: {
  rows: Array<{ date: string; created: number; completed?: number }>;
  label: string;
  includesCompleted: boolean;
}) {
  return (
    <details className="rounded-lg border">
      <summary className="cursor-pointer px-4 py-3 text-sm font-medium">
        Ver tabla diaria — {label} ({rows.length} días)
      </summary>
      <div className="max-h-80 overflow-auto px-2 pb-3">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Fecha (Perú)</TableHead>
              <TableHead className="text-right">Creadas</TableHead>
              {includesCompleted && <TableHead className="text-right">Finalizadas</TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.date}>
                <TableCell className="tabular-nums">{row.date}</TableCell>
                <TableCell className="text-right tabular-nums">{row.created}</TableCell>
                {includesCompleted && <TableCell className="text-right tabular-nums">{row.completed ?? 0}</TableCell>}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </details>
  );
}

export function DelegatedClientTrendsPanel({ client }: { client: FacilityManagementOperationalClient }) {
  const { user, currentOrganization } = useAuth();
  const [preset, setPreset] = useState<DaysPreset>('90');
  const [endDate, setEndDate] = useState(todayInLima);
  const [startDate, setStartDate] = useState(() => shiftCalendarDate(todayInLima(), -89));
  const rangeError = dateRangeError(startDate, endDate);

  const allowed = currentOrganization?.organizationType === 'facility_manager'
    && currentOrganization.id === client.facilityManagerOrganizationId
    && canFacilityManagerViewReports(client);

  const query = useQuery({
    queryKey: [
      'fm-client-trends-9c7-b2',
      user?.id ?? null, currentOrganization?.id ?? null,
      client.relationshipId, client.clientOrganizationId,
      startDate, endDate, PILOT_TRENDS_TIME_ZONE,
    ],
    enabled: !!user?.id && !!allowed && !rangeError,
    queryFn: () => fetchDelegatedClientTrends(client.clientOrganizationId, client.relationshipId, startDate, endDate),
    retry: false,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: true,
  });

  const setDays = (days: typeof PRESETS[number]) => {
    const today = todayInLima();
    setStartDate(shiftCalendarDate(today, 1 - days));
    setEndDate(today);
    setPreset(String(days) as DaysPreset);
  };

  const data = visibleDelegatedClientTrends(query, !!allowed, !rangeError);
  const orders = data?.workOrders?.daily ?? null;
  const requests = data?.requests?.daily ?? null;
  const orderTotals = useMemo(() => orders
    ? { created: sum(orders, 'created'), completed: sum(orders, 'completed') }
    : null, [orders]);
  const requestTotal = useMemo(() => requests ? sum(requests, 'created') : null, [requests]);

  if (!allowed) return null;

  return (
    <section aria-label="Tendencias históricas" className="space-y-5" data-testid="fm-client-trends">
      <div className="flex flex-wrap items-center gap-2">
        <BarChart3 className="h-5 w-5 text-primary" aria-hidden="true" />
        <h2 className="text-xl font-semibold">Tendencias históricas</h2>
        <span className="text-xs text-muted-foreground">Eventos registrados · Perú (America/Lima)</span>
      </div>
      <p className="text-sm text-muted-foreground">
        Muestra cuántas órdenes y solicitudes se crearon cada día y cuántas órdenes se finalizaron.
        No reconstruye estados abiertos o vencidos en fechas anteriores ni calcula SLA históricos.
      </p>

      <Card>
        <CardContent className="space-y-4 pt-5">
          <fieldset className="flex flex-wrap items-center gap-2">
            <legend className="mb-2 text-sm font-medium">Período de consulta</legend>
            {PRESETS.map((days) => (
              <Button key={days} type="button" size="sm"
                variant={preset === String(days) ? 'default' : 'outline'}
                aria-pressed={preset === String(days)}
                onClick={() => setDays(days)}>
                Últimos {days} días
              </Button>
            ))}
            {preset === 'custom' && <span className="text-xs text-muted-foreground">Período personalizado</span>}
          </fieldset>
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor="fm-trends-start">Desde (incluido)</Label>
              <Input id="fm-trends-start" type="date" value={startDate}
                onChange={(event) => { setStartDate(event.target.value); setPreset('custom'); }} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="fm-trends-end">Hasta (incluido)</Label>
              <Input id="fm-trends-end" type="date" value={endDate}
                onChange={(event) => { setEndDate(event.target.value); setPreset('custom'); }} />
            </div>
          </div>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="flex items-center gap-2 text-xs text-muted-foreground">
              <CalendarDays className="h-4 w-4" aria-hidden="true" />
              Máximo 366 días · zona horaria {PILOT_TRENDS_TIME_ZONE} · extremos incluidos
            </p>
            <Button type="button" size="sm" variant="outline"
              disabled={!!rangeError || query.isFetching}
              onClick={() => void query.refetch()}>
              <RefreshCw className={`mr-2 h-4 w-4 ${query.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
              Actualizar tendencias
            </Button>
          </div>
        </CardContent>
      </Card>

      {rangeError && <p role="alert" className="text-sm text-destructive">{rangeError}</p>}
      {!rangeError && query.isPending && (
        <p role="status" className="text-sm text-muted-foreground">Consultando tendencias autorizadas…</p>
      )}
      {!rangeError && query.isFetching && !query.isPending && (
        <p role="status" className="text-sm text-muted-foreground">
          Revalidando permisos y tendencias…
        </p>
      )}
      {!rangeError && query.isError && (
        <Card role="alert">
          <CardContent className="space-y-2 py-5">
            <p className="font-medium text-destructive">No se pudieron cargar las tendencias.</p>
            <p className="text-sm text-muted-foreground">
              {query.error instanceof Error ? query.error.message : 'Error de consulta.'}
            </p>
          </CardContent>
        </Card>
      )}

      {data && (
        <>
          <p className="text-xs text-muted-foreground">
            Corte de consulta: {new Intl.DateTimeFormat('es-PE', {
              timeZone: PILOT_TRENDS_TIME_ZONE, dateStyle: 'medium', timeStyle: 'short',
            }).format(new Date(data.asOf))} · Fechas de Perú
          </p>
          <div className="grid gap-6 xl:grid-cols-2">
            <section aria-label="Tendencias de órdenes de trabajo" className="space-y-3">
              {orders && orderTotals ? (
                <>
                  <Card>
                    <CardHeader>
                      <CardTitle className="text-base">Órdenes creadas y finalizadas</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-3">
                      <div className="grid grid-cols-2 gap-3 text-sm">
                        <div><p className="text-muted-foreground">Creadas en el período</p>
                          <p className="text-2xl font-semibold tabular-nums">{orderTotals.created}</p></div>
                        <div><p className="text-muted-foreground">Finalizadas en el período</p>
                          <p className="text-2xl font-semibold tabular-nums">{orderTotals.completed}</p></div>
                      </div>
                      {orderTotals.created === 0 && orderTotals.completed === 0 && (
                        <p className="text-sm text-muted-foreground" role="status">
                          No se registraron creaciones ni finalizaciones de OT en este período.
                        </p>
                      )}
                      <ChartContainer config={ORDER_CHART_CONFIG} className="h-64 w-full">
                        <BarChart data={orders} accessibilityLayer>
                          <CartesianGrid vertical={false} />
                          <XAxis dataKey="date" minTickGap={28} tickFormatter={(value: string) => value.slice(5)} />
                          <YAxis allowDecimals={false} width={35} />
                          <ChartTooltip content={<ChartTooltipContent />} />
                          <Bar dataKey="created" fill="var(--color-created)" radius={2} />
                          <Bar dataKey="completed" fill="var(--color-completed)" radius={2} />
                        </BarChart>
                      </ChartContainer>
                    </CardContent>
                  </Card>
                  <DailyTable rows={orders} label="órdenes de trabajo" includesCompleted />
                </>
              ) : <ReadonlySection name="Tendencias de órdenes de trabajo" />}
            </section>
            <section aria-label="Tendencias de solicitudes" className="space-y-3">
              {requests && requestTotal !== null ? (
                <>
                  <Card>
                    <CardHeader><CardTitle className="text-base">Solicitudes creadas</CardTitle></CardHeader>
                    <CardContent className="space-y-3">
                      <p className="text-xs text-muted-foreground">Incluye borradores, porque se trata de creaciones, no de solicitudes enviadas.</p>
                      <p className="text-2xl font-semibold tabular-nums">{requestTotal}</p>
                      {requestTotal === 0 && (
                        <p className="text-sm text-muted-foreground" role="status">
                          No se registraron solicitudes creadas en este período.
                        </p>
                      )}
                      <ChartContainer config={REQUEST_CHART_CONFIG} className="h-64 w-full">
                        <BarChart data={requests} accessibilityLayer>
                          <CartesianGrid vertical={false} />
                          <XAxis dataKey="date" minTickGap={28} tickFormatter={(value: string) => value.slice(5)} />
                          <YAxis allowDecimals={false} width={35} />
                          <ChartTooltip content={<ChartTooltipContent />} />
                          <Bar dataKey="created" fill="var(--color-created)" radius={2} />
                        </BarChart>
                      </ChartContainer>
                    </CardContent>
                  </Card>
                  <DailyTable rows={requests} label="solicitudes" includesCompleted={false} />
                </>
              ) : <ReadonlySection name="Tendencias de solicitudes" />}
            </section>
          </div>
          <p className="text-xs text-muted-foreground">
            Los números anteriores corresponden a eventos ocurridos dentro del período seleccionado.
            Las tarjetas de la parte superior de la página muestran el estado actual, no un corte histórico.
          </p>
        </>
      )}
    </section>
  );
}
