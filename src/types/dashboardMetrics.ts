/** Real operational dashboard metrics — one row from get_dashboard_metrics,
 * every count computed live from real sources (assets, requests,
 * work_orders, inspection_plans/_alert_rules, and get_efficiency_summary
 * for hours). Never mock data. See docs/REAL_DASHBOARD_METRICS.md. */
export interface DashboardMetrics {
  totalAssets: number;
  criticalAssets: number;
  openRequests: number;
  openWorkOrders: number;
  overdueWorkOrders: number;
  upcomingInspections: number;
  overdueInspections: number;
  plannedHours: number;
  actualHours: number;
  updatedAt: string;
}
