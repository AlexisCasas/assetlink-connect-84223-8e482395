export interface TechnicianWorkOrderActivity {
  id: string;
  description: string;
  estimatedHours: number | null;
  status: string;
  sequence: number;
  dueAt: string | null;
  /** Sum of the caller's own work_order_activity_reports.actual_hours for
   * this activity — 0 when none have been submitted yet. */
  actualHoursTotal: number;
  reportsCount: number;
}

export interface TechnicianWorkOrderMaterial {
  id: string;
  materialCode: string;
  materialName: string;
  materialUnit: string;
  plannedQuantity: number;
  usedQuantity: number;
  currentStock: number;
  warningStatus: 'ok' | 'no_stock' | 'insufficient_stock';
}

export interface TechnicianWorkOrder {
  id: string;
  workOrderNumber: string;
  workOrderType: string;
  title: string | null;
  status: string;
  priority: string;
  scheduledAt: string | null;
  dueAt: string | null;
  assetId: string | null;
  assetName: string | null;
  assetPath: string | null;
  /** Asset's own location_text, falling back to its branch name — see
   * get_my_technician_work_orders in 20260828170000_technician_work_view.sql. */
  location: string | null;
  organizationId: string;
  requestId: string;
  activities: TechnicianWorkOrderActivity[];
  materials: TechnicianWorkOrderMaterial[];
}

export interface TechnicianWorkLog {
  id: string;
  note: string;
  statusFrom: string | null;
  statusTo: string | null;
  memberName: string;
  memberEmail: string;
  createdAt: string;
}
