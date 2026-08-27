import { useEffect } from 'react';
import { BarChart3 } from 'lucide-react';
import { useActivityReports } from '@/hooks/useActivityReports';

interface WorkOrderActivityReportsSummaryProps {
  workOrderId: string;
}

const formatDate = (value: string) => new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));

const REPORT_STATUS_LABELS: Record<string, string> = {
  pending: 'Pendiente',
  in_progress: 'En ejecución',
  completed: 'Finalizada',
  blocked: 'Bloqueada',
};

/**
 * Read-only "planificación vs ejecución real" for planner/admin (and
 * technicians, who only ever see their own reports here — the RPC itself
 * enforces that split, see docs/TECHNICIAN_ACTIVITY_REPORTS.md). Reuses
 * get_activity_reports_for_work_order — no separate consolidated endpoint.
 */
export function WorkOrderActivityReportsSummary({ workOrderId }: WorkOrderActivityReportsSummaryProps) {
  const { reports, loadingReports, loadReportsForWorkOrder } = useActivityReports();

  useEffect(() => { void loadReportsForWorkOrder(workOrderId); }, [workOrderId, loadReportsForWorkOrder]);

  const totalEstimated = reports.reduce((sum, report) => sum + (report.estimatedHours ?? 0), 0);
  const totalActual = reports.reduce((sum, report) => sum + report.actualHours, 0);

  return (
    <div className="rounded-lg border p-3 space-y-3">
      <p className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        <BarChart3 className="h-3.5 w-3.5" /> Planificación vs ejecución real
      </p>

      {loadingReports ? (
        <p className="text-sm text-muted-foreground">Cargando reportes…</p>
      ) : reports.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aún no hay reportes de ejecución para esta OT.</p>
      ) : (
        <div className="space-y-3">
          <div className="space-y-2">
            {reports.map((report) => {
              const diff = Math.round((report.hoursDifference) * 100) / 100;
              return (
                <div key={report.id} className="rounded-md border p-2 text-sm">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-medium">{report.activityDescription}</span>
                    <span className="text-xs text-muted-foreground">{REPORT_STATUS_LABELS[report.finalStatus] ?? report.finalStatus}</span>
                  </div>
                  <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted-foreground">
                    <span>Técnico: {report.technicianName}</span>
                    <span>Estimado: {report.estimatedHours ?? '—'} h</span>
                    <span>Real: {report.actualHours} h</span>
                    <span>Diferencia: {diff > 0 ? `+${diff}` : diff} h</span>
                    <span>{formatDate(report.startedAt)} – {formatDate(report.finishedAt)}</span>
                  </div>
                  {report.observations && <p className="mt-1 text-xs">{report.observations}</p>}
                  {report.materials.length > 0 && (
                    <p className="mt-1 text-xs text-muted-foreground">
                      Materiales: {report.materials.map((material) => `${material.materialCode} (${material.quantityUsed})`).join(', ')}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
          <p className="text-sm font-medium">
            Total estimado: {Math.round(totalEstimated * 100) / 100} h · Total real: {Math.round(totalActual * 100) / 100} h
          </p>
        </div>
      )}
    </div>
  );
}
