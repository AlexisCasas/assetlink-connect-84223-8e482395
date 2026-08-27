/** Planned vs. real per activity. These are operational counts, never a
 * technician performance ranking — see docs/EFFICIENCY_DEVIATIONS.md. */
export interface EfficiencyActivityMetric {
  activityId: string;
  workOrderId: string;
  workOrderNumber: string;
  workOrderStatus: string;
  assetId: string | null;
  assetName: string | null;
  technicianMemberId: string | null;
  technicianName: string | null;
  activityDescription: string;
  activityStatus: string;
  /** null when the activity has no estimated_hours — never divide by it. */
  plannedHours: number | null;
  actualHours: number;
  deviationHours: number;
  /** null when plannedHours is null or 0 — safe-division rule, see docs. */
  deviationPercent: number | null;
  reportsCount: number;
  firstStartedAt: string | null;
  lastFinishedAt: string | null;
  periodDate: string | null;
}

export interface EfficiencySummary {
  completedWorkOrders: number;
  pendingWorkOrders: number;
  overdueWorkOrders: number;
  plannedHoursTotal: number;
  actualHoursTotal: number;
  deviationHoursTotal: number;
  deviationPercentTotal: number | null;
  activitiesCount: number;
  reportedActivitiesCount: number;
}

export interface EfficiencyDateFilter {
  startDate: string | null;
  endDate: string | null;
}

/** Client-side grouping dimension over EfficiencyActivityMetric rows — no
 * separate grouped-metrics RPC, see docs/EFFICIENCY_DEVIATIONS.md. */
export type EfficiencyGroupBy = 'work_order' | 'technician' | 'asset';

export interface EfficiencyGroupRow {
  key: string;
  label: string;
  plannedHours: number;
  actualHours: number;
  deviationHours: number;
  deviationPercent: number | null;
  activitiesCount: number;
}
