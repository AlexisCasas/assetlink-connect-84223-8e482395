import { useEffect, useState } from 'react';
import { BarChart3, CheckCircle2, Clock, AlertTriangle, RefreshCw } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { useEfficiencyMetrics } from '@/hooks/useEfficiencyMetrics';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { formatDeviationHours, formatDeviationPercent, deviationColorClass } from '@/lib/efficiencyFormat';
import type { EfficiencyGroupRow } from '@/types/efficiency';

const formatHours = (hours: number) => `${Math.round(hours * 100) / 100} h`;

export function EfficiencyDashboard() {
  const { currentOrganization } = useAuth();
  const { activities, summary, loading, error, refresh, groupedByWorkOrder, groupedByTechnician, groupedByAsset } = useEfficiencyMetrics(currentOrganization?.id);
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  useEffect(() => {
    void refresh(startDate || null, endDate || null);
    // Only re-run automatically when the organization changes — date
    // filters apply on the explicit "Actualizar" click below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentOrganization?.id]);

  const handleUpdate = () => void refresh(startDate || null, endDate || null);

  if (!currentOrganization) {
    return (
      <div className="p-6">
        <Card><CardContent className="flex min-h-56 flex-col items-center justify-center gap-3 text-center">
          <BarChart3 className="h-10 w-10 text-muted-foreground" />
          <p className="font-medium">Sin organización asignada</p>
        </CardContent></Card>
      </div>
    );
  }

  const renderGroupTable = (rows: EfficiencyGroupRow[], firstColumnLabel: string) => (
    rows.length === 0 ? (
      <p className="py-6 text-center text-sm text-muted-foreground">Sin datos para este período.</p>
    ) : (
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{firstColumnLabel}</TableHead>
              <TableHead>Actividades</TableHead>
              <TableHead>Planificado</TableHead>
              <TableHead>Real</TableHead>
              <TableHead>Diferencia</TableHead>
              <TableHead>% desviación</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.key}>
                <TableCell className="font-medium">{row.label}</TableCell>
                <TableCell>{row.activitiesCount}</TableCell>
                <TableCell>{formatHours(row.plannedHours)}</TableCell>
                <TableCell>{formatHours(row.actualHours)}</TableCell>
                <TableCell className={deviationColorClass(row.deviationPercent)}>{formatDeviationHours(row.deviationHours)}</TableCell>
                <TableCell className={deviationColorClass(row.deviationPercent)}>{formatDeviationPercent(row.deviationPercent)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    )
  );

  return (
    <div className="space-y-6 p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Eficiencia</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Planificado vs. real por actividad — información operativa, no una comparación de desempeño entre técnicos.
          </p>
        </div>
      </div>

      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 pt-6">
          <div className="space-y-1">
            <Label htmlFor="efficiency-start-date">Fecha inicio</Label>
            <Input id="efficiency-start-date" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="efficiency-end-date">Fecha fin</Label>
            <Input id="efficiency-end-date" type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
          </div>
          <Button onClick={handleUpdate} disabled={loading}>
            <RefreshCw className="mr-2 h-4 w-4" /> Actualizar
          </Button>
        </CardContent>
      </Card>

      {error && <p className="text-sm text-destructive">{error}</p>}

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando indicadores…</p>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground">OT terminadas</CardTitle>
                <CheckCircle2 className="h-4 w-4 text-green-600" />
              </CardHeader>
              <CardContent><div className="text-2xl font-bold">{summary?.completedWorkOrders ?? 0}</div></CardContent>
            </Card>
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground">OT pendientes</CardTitle>
                <Clock className="h-4 w-4 text-blue-600" />
              </CardHeader>
              <CardContent><div className="text-2xl font-bold">{summary?.pendingWorkOrders ?? 0}</div></CardContent>
            </Card>
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground">OT vencidas</CardTitle>
                <AlertTriangle className="h-4 w-4 text-red-600" />
              </CardHeader>
              <CardContent><div className="text-2xl font-bold">{summary?.overdueWorkOrders ?? 0}</div></CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-muted-foreground">Horas planificadas</CardTitle></CardHeader>
              <CardContent><div className="text-2xl font-bold">{formatHours(summary?.plannedHoursTotal ?? 0)}</div></CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-muted-foreground">Horas reales</CardTitle></CardHeader>
              <CardContent><div className="text-2xl font-bold">{formatHours(summary?.actualHoursTotal ?? 0)}</div></CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-muted-foreground">Desviación vs. plan</CardTitle></CardHeader>
              <CardContent>
                <div className={`text-2xl font-bold ${deviationColorClass(summary?.deviationPercentTotal ?? null)}`}>
                  {formatDeviationHours(summary?.deviationHoursTotal ?? 0)}
                </div>
                <p className={`text-sm ${deviationColorClass(summary?.deviationPercentTotal ?? null)}`}>
                  {formatDeviationPercent(summary?.deviationPercentTotal ?? null)}
                </p>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader><CardTitle className="text-base">Detalle por actividad</CardTitle></CardHeader>
            <CardContent className="px-0 sm:px-6">
              {activities.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">Sin actividades reportadas en este período.</p>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>OT</TableHead>
                        <TableHead>Activo</TableHead>
                        <TableHead>Actividad</TableHead>
                        <TableHead>Técnico</TableHead>
                        <TableHead>Estado</TableHead>
                        <TableHead>Planificado</TableHead>
                        <TableHead>Real</TableHead>
                        <TableHead>Diferencia</TableHead>
                        <TableHead>% desviación</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {activities.map((activity) => (
                        <TableRow key={activity.activityId}>
                          <TableCell className="font-mono text-xs">{activity.workOrderNumber}</TableCell>
                          <TableCell>{activity.assetName ?? '—'}</TableCell>
                          <TableCell className="max-w-[220px] truncate" title={activity.activityDescription}>{activity.activityDescription}</TableCell>
                          <TableCell>{activity.technicianName ?? '—'}</TableCell>
                          <TableCell>{activity.activityStatus}</TableCell>
                          <TableCell>{activity.plannedHours != null ? formatHours(activity.plannedHours) : '—'}</TableCell>
                          <TableCell>{formatHours(activity.actualHours)}</TableCell>
                          <TableCell className={deviationColorClass(activity.deviationPercent)}>{formatDeviationHours(activity.deviationHours)}</TableCell>
                          <TableCell className={deviationColorClass(activity.deviationPercent)}>{formatDeviationPercent(activity.deviationPercent)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle className="text-base">Agregaciones</CardTitle></CardHeader>
            <CardContent>
              <Tabs defaultValue="work_order">
                <TabsList>
                  <TabsTrigger value="work_order">Por OT</TabsTrigger>
                  <TabsTrigger value="technician">Por técnico</TabsTrigger>
                  <TabsTrigger value="asset">Por activo</TabsTrigger>
                </TabsList>
                <TabsContent value="work_order">{renderGroupTable(groupedByWorkOrder, 'Orden de trabajo')}</TabsContent>
                <TabsContent value="technician">{renderGroupTable(groupedByTechnician, 'Técnico')}</TabsContent>
                <TabsContent value="asset">{renderGroupTable(groupedByAsset, 'Activo')}</TabsContent>
              </Tabs>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
