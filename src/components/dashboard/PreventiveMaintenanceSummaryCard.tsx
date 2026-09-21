import { AlertTriangle, CalendarClock, Gauge } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import { usePreventiveMaintenance } from '@/hooks/usePreventiveMaintenance';
import { navigateToEntity } from '@/lib/entityNavigation';

export function PreventiveMaintenanceSummaryCard() {
  const { currentOrganization } = useAuth();
  const enabled = currentOrganization?.organizationType === 'client_company';
  const { plans, loading } = usePreventiveMaintenance(enabled ? currentOrganization?.id : null);
  if (!enabled) return null;
  const active = plans.filter((plan) => plan.is_active);
  const overdue = active.filter((plan) => plan.timing_status === 'overdue').length;
  const due = active.filter((plan) => plan.timing_status === 'due').length;
  const withoutReading = active.filter((plan) => plan.timing_status === 'no_reading').length;
  return <Card><CardHeader className="flex flex-row items-center justify-between"><CardTitle className="text-base"><CalendarClock className="mr-2 inline h-4 w-4" />Mantenimiento preventivo</CardTitle><Button size="sm" variant="outline" onClick={() => navigateToEntity({ view: 'preventive-maintenance' })}>Ver planes</Button></CardHeader><CardContent className="grid grid-cols-2 gap-3 md:grid-cols-4"><Metric label="Planes activos" value={loading ? '—' : active.length} /><Metric label="Por atender" value={loading ? '—' : due} /><Metric label="Vencidos" value={loading ? '—' : overdue} alert={overdue > 0} /><Metric label="Sin lectura" value={loading ? '—' : withoutReading} gauge={withoutReading > 0} /></CardContent></Card>;
}

function Metric({ label, value, alert, gauge }: { label: string; value: number | string; alert?: boolean; gauge?: boolean }) {
  return <div className="rounded-md border p-3"><div className="flex items-center gap-1 text-xs text-muted-foreground">{alert && <AlertTriangle className="h-3 w-3 text-destructive" />}{gauge && <Gauge className="h-3 w-3" />}{label}</div><p className="mt-1 text-2xl font-semibold">{value}</p></div>;
}
