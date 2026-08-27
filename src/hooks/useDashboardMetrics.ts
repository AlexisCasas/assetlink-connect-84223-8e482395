import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { DashboardMetrics } from '@/types/dashboardMetrics';

interface RawMetrics {
  total_assets: number;
  critical_assets: number;
  open_requests: number;
  open_work_orders: number;
  overdue_work_orders: number;
  upcoming_inspections: number;
  overdue_inspections: number;
  planned_hours: number;
  actual_hours: number;
  updated_at: string;
}

const toMetrics = (row: RawMetrics): DashboardMetrics => ({
  totalAssets: row.total_assets,
  criticalAssets: row.critical_assets,
  openRequests: row.open_requests,
  openWorkOrders: row.open_work_orders,
  overdueWorkOrders: row.overdue_work_orders,
  upcomingInspections: row.upcoming_inspections,
  overdueInspections: row.overdue_inspections,
  plannedHours: row.planned_hours,
  actualHours: row.actual_hours,
  updatedAt: row.updated_at,
});

/**
 * Real dashboard metrics via get_dashboard_metrics (SECURITY DEFINER,
 * owner/admin/manager or platform_admin only — see
 * docs/REAL_DASHBOARD_METRICS.md). Replaces the hardcoded numbers that
 * used to live in StatsCards.tsx.
 */
export function useDashboardMetrics(organizationId: string | null | undefined) {
  const [metrics, setMetrics] = useState<DashboardMetrics | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setMetrics(null);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_dashboard_metrics', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      const row = (data as unknown as RawMetrics[] | null)?.[0];
      setMetrics(row ? toMetrics(row) : null);
    } catch (err) {
      setMetrics(null);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar las métricas del dashboard.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  return { metrics, loading, error, refresh };
}

export type UseDashboardMetricsResult = ReturnType<typeof useDashboardMetrics>;
