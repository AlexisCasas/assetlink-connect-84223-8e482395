import { Boxes, AlertTriangle, FileText, ClipboardList, Clock, CalendarClock, CalendarX, Timer, ShieldAlert } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { usePermissions } from '@/hooks/usePermissions';
import { useDashboardMetrics } from '@/hooks/useDashboardMetrics';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

const formatHours = (hours: number) => `${(Math.round(hours * 100) / 100).toFixed(2)} h`;

interface MetricCardProps {
  title: string;
  value: string;
  icon: typeof Boxes;
  tone?: 'default' | 'warning' | 'destructive';
}

const TONE_CLASS: Record<NonNullable<MetricCardProps['tone']>, string> = {
  default: '',
  warning: 'text-warning',
  destructive: 'text-destructive',
};

function MetricCard({ title, value, icon: Icon, tone = 'default' }: MetricCardProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
        <Icon className={`h-4 w-4 ${tone === 'default' ? 'text-muted-foreground' : TONE_CLASS[tone]}`} />
      </CardHeader>
      <CardContent>
        <div className={`text-2xl font-bold ${TONE_CLASS[tone]}`}>{value}</div>
      </CardContent>
    </Card>
  );
}

/**
 * Real dashboard metrics — replaces the hardcoded numbers that used to
 * live in StatsCards.tsx (see docs/REAL_DASHBOARD_METRICS.md). Every
 * number comes from get_dashboard_metrics, computed live from
 * assets/requests/work_orders/inspection_plans and
 * get_efficiency_summary — never sample/example data.
 *
 * Gated to owner/admin/manager (matching the RPC's own authorization,
 * stricter than TrafficLightSummaryCard which any active member —
 * including technician — can see): this is an organization-wide
 * operational summary (open/overdue counts, aggregate hours), not a
 * single asset's or plan's own data a technician would already have
 * access to elsewhere.
 */
export function DashboardMetricsCards() {
  const { currentOrganization } = useAuth();
  const { canPlanWork } = usePermissions();
  const { metrics, loading, error } = useDashboardMetrics(canPlanWork ? currentOrganization?.id : undefined);

  if (!currentOrganization) return null;

  if (!canPlanWork) {
    return (
      <Card>
        <CardContent className="flex min-h-24 items-center justify-center py-6 text-center">
          <p className="text-sm text-muted-foreground">Sin acceso a métricas operativas.</p>
        </CardContent>
      </Card>
    );
  }

  if (loading) {
    return <p className="text-sm text-muted-foreground">Cargando métricas…</p>;
  }

  if (error) {
    return <p className="text-sm text-destructive">{error}</p>;
  }

  if (!metrics) {
    return (
      <Card>
        <CardContent className="flex min-h-24 items-center justify-center py-6 text-center">
          <p className="text-sm text-muted-foreground">Sin datos disponibles todavía.</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      <MetricCard title="Activos" value={String(metrics.totalAssets)} icon={Boxes} />
      <MetricCard title="Activos con criticidad muy alta" value={String(metrics.criticalAssets)} icon={ShieldAlert} tone={metrics.criticalAssets > 0 ? 'warning' : 'default'} />
      <MetricCard title="Solicitudes abiertas" value={String(metrics.openRequests)} icon={FileText} />
      <MetricCard title="OT abiertas" value={String(metrics.openWorkOrders)} icon={ClipboardList} />
      <MetricCard title="OT vencidas" value={String(metrics.overdueWorkOrders)} icon={AlertTriangle} tone={metrics.overdueWorkOrders > 0 ? 'destructive' : 'default'} />
      <MetricCard title="Inspecciones próximas" value={String(metrics.upcomingInspections)} icon={CalendarClock} tone={metrics.upcomingInspections > 0 ? 'warning' : 'default'} />
      <MetricCard title="Inspecciones vencidas" value={String(metrics.overdueInspections)} icon={CalendarX} tone={metrics.overdueInspections > 0 ? 'destructive' : 'default'} />
      <MetricCard title="Horas planificadas" value={formatHours(metrics.plannedHours)} icon={Clock} />
      <MetricCard title="Horas reales" value={formatHours(metrics.actualHours)} icon={Timer} />
    </div>
  );
}
