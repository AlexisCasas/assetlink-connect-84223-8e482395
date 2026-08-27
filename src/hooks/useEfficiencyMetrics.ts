import { useCallback, useMemo, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type {
  EfficiencyActivityMetric,
  EfficiencyGroupBy,
  EfficiencyGroupRow,
  EfficiencySummary,
} from '@/types/efficiency';

const toActivityMetric = (row: {
  activity_id: string;
  work_order_id: string;
  work_order_number: string;
  work_order_status: string;
  asset_id: string | null;
  asset_name: string | null;
  technician_member_id: string | null;
  technician_name: string | null;
  activity_description: string;
  activity_status: string;
  planned_hours: number | null;
  actual_hours: number;
  deviation_hours: number;
  deviation_percent: number | null;
  reports_count: number;
  first_started_at: string | null;
  last_finished_at: string | null;
  period_date: string | null;
}): EfficiencyActivityMetric => ({
  activityId: row.activity_id,
  workOrderId: row.work_order_id,
  workOrderNumber: row.work_order_number,
  workOrderStatus: row.work_order_status,
  assetId: row.asset_id,
  assetName: row.asset_name,
  technicianMemberId: row.technician_member_id,
  technicianName: row.technician_name,
  activityDescription: row.activity_description,
  activityStatus: row.activity_status,
  plannedHours: row.planned_hours,
  actualHours: row.actual_hours,
  deviationHours: row.deviation_hours,
  deviationPercent: row.deviation_percent,
  reportsCount: row.reports_count,
  firstStartedAt: row.first_started_at,
  lastFinishedAt: row.last_finished_at,
  periodDate: row.period_date,
});

/** Same safe-division rule as the RPCs: never divide by a null/zero
 * planned total. Recomputed here only for client-side groupings — the
 * per-activity value always comes straight from the server. */
const safeDeviationPercent = (plannedHours: number, actualHours: number): number | null => {
  if (plannedHours === 0) return null;
  return Math.round(((actualHours - plannedHours) / plannedHours) * 10000) / 100;
};

/**
 * Efficiency/deviation MVP: get_efficiency_activity_metrics +
 * get_efficiency_summary (both SECURITY DEFINER, owner/admin/manager or
 * platform_admin only — see docs/EFFICIENCY_DEVIATIONS.md). No grouped
 * RPC: groupBy() aggregates the already-fetched activity rows client-side
 * by work order / technician / asset, reusing the same safe-division rule.
 */
export function useEfficiencyMetrics(organizationId: string | null | undefined) {
  const [activities, setActivities] = useState<EfficiencyActivityMetric[]>([]);
  const [summary, setSummary] = useState<EfficiencySummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async (startDate: string | null, endDate: string | null) => {
    if (!organizationId) {
      setActivities([]);
      setSummary(null);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [activitiesResult, summaryResult] = await Promise.all([
        supabase.rpc('get_efficiency_activity_metrics', {
          p_organization_id: organizationId,
          p_start_date: startDate,
          p_end_date: endDate,
        }),
        supabase.rpc('get_efficiency_summary', {
          p_organization_id: organizationId,
          p_start_date: startDate,
          p_end_date: endDate,
        }),
      ]);

      if (activitiesResult.error) throw activitiesResult.error;
      if (summaryResult.error) throw summaryResult.error;

      setActivities((activitiesResult.data ?? []).map(toActivityMetric));

      const summaryRow = summaryResult.data?.[0];
      setSummary(summaryRow ? {
        completedWorkOrders: summaryRow.completed_work_orders,
        pendingWorkOrders: summaryRow.pending_work_orders,
        overdueWorkOrders: summaryRow.overdue_work_orders,
        plannedHoursTotal: summaryRow.planned_hours_total,
        actualHoursTotal: summaryRow.actual_hours_total,
        deviationHoursTotal: summaryRow.deviation_hours_total,
        deviationPercentTotal: summaryRow.deviation_percent_total,
        activitiesCount: summaryRow.activities_count,
        reportedActivitiesCount: summaryRow.reported_activities_count,
      } : null);
    } catch (err) {
      setActivities([]);
      setSummary(null);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los indicadores de eficiencia.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  const groupBy = useCallback((dimension: EfficiencyGroupBy): EfficiencyGroupRow[] => {
    const buckets = new Map<string, { label: string; planned: number; actual: number; count: number }>();
    for (const activity of activities) {
      let key: string;
      let label: string;
      if (dimension === 'work_order') {
        key = activity.workOrderId;
        label = activity.workOrderNumber;
      } else if (dimension === 'technician') {
        key = activity.technicianMemberId ?? 'unassigned';
        label = activity.technicianName ?? 'Sin técnico asignado';
      } else {
        key = activity.assetId ?? 'no-asset';
        label = activity.assetName ?? 'Sin activo asociado';
      }
      const bucket = buckets.get(key) ?? { label, planned: 0, actual: 0, count: 0 };
      bucket.planned += activity.plannedHours ?? 0;
      bucket.actual += activity.actualHours;
      bucket.count += 1;
      buckets.set(key, bucket);
    }
    return Array.from(buckets.entries()).map(([key, bucket]) => ({
      key,
      label: bucket.label,
      plannedHours: Math.round(bucket.planned * 100) / 100,
      actualHours: Math.round(bucket.actual * 100) / 100,
      deviationHours: Math.round((bucket.actual - bucket.planned) * 100) / 100,
      deviationPercent: safeDeviationPercent(bucket.planned, bucket.actual),
      activitiesCount: bucket.count,
    })).sort((a, b) => b.activitiesCount - a.activitiesCount);
  }, [activities]);

  const groupedByWorkOrder = useMemo(() => groupBy('work_order'), [groupBy]);
  const groupedByTechnician = useMemo(() => groupBy('technician'), [groupBy]);
  const groupedByAsset = useMemo(() => groupBy('asset'), [groupBy]);

  return {
    activities,
    summary,
    loading,
    error,
    refresh,
    groupedByWorkOrder,
    groupedByTechnician,
    groupedByAsset,
  };
}
