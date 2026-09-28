export type PreventiveTriggerType = 'calendar' | 'meter';
export type PreventiveOccurrenceStatus = 'open' | 'planned' | 'completed' | 'skipped' | 'cancelled';
export type PreventiveTimingStatus = 'upcoming' | 'due' | 'overdue' | 'no_reading';
export type PreventiveFrequency = 'weekly' | 'monthly' | 'quarterly' | 'semiannual' | 'annual' | 'custom';

export interface MaintenanceCardTask {
  id?: string;
  sequence?: number;
  title: string;
  description?: string | null;
  estimated_hours?: number | null;
  is_required?: boolean;
}

export interface MaintenanceCardMaterial {
  id?: string;
  sequence?: number;
  material_id?: string | null;
  description: string;
  quantity: number;
  unit: string;
  notes?: string | null;
  material_code?: string | null;
  material_name?: string | null;
  current_stock?: number | null;
  material_is_active?: boolean | null;
  /** Delegated (Facility Manager) reads only: the line is linked to the
   * client's inventory catalog, whose ids/stock are never sent to the FM. */
  client_linked_material?: boolean;
}

export interface MaintenanceCard {
  id: string;
  organization_id: string;
  code: string;
  name: string;
  description: string | null;
  category: string | null;
  estimated_hours: number | null;
  procedure_notes: string | null;
  safety_notes: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  tasks: MaintenanceCardTask[];
  materials: MaintenanceCardMaterial[];
}

export interface MeterReading {
  id: string;
  value: number;
  recorded_at: string;
  notes: string | null;
  supersedes_reading_id: string | null;
  created_at: string;
}

export interface AssetMeter {
  id: string;
  organization_id: string;
  asset_id: string;
  name: string;
  unit: string;
  is_active: boolean;
  replaces_meter_id: string | null;
  retired_at: string | null;
  retirement_reason: string | null;
  created_at: string;
  readings: MeterReading[];
}

export interface PreventiveOccurrence {
  id: string;
  organization_id?: string;
  plan_id?: string;
  asset_id?: string;
  sequence: number;
  status: PreventiveOccurrenceStatus;
  due_at: string | null;
  due_meter_value: number | null;
  /** Null for a delegated Facility Manager: Requests / Work Orders are not
   * delegated, so their ids are never sent (9C.2). Always set in direct mode. */
  request_creation_id: string | null;
  request_id: string | null;
  work_order_id: string | null;
  scope_snapshot: Record<string, unknown>;
  planned_at: string | null;
  completed_at?: string | null;
  skipped_at?: string | null;
  skip_reason?: string | null;
  cancelled_at?: string | null;
  cancel_reason?: string | null;
  card_code?: string;
  card_name?: string;
  trigger_type?: PreventiveTriggerType;
  priority?: string;
  asset_name?: string;
  asset_code?: string | null;
}

export interface PreventivePlan {
  id: string;
  organization_id: string;
  asset_id: string;
  asset_name: string;
  asset_code: string | null;
  asset_path: string | null;
  card_id: string;
  card_code: string;
  card_name: string;
  trigger_type: PreventiveTriggerType;
  priority: 'low' | 'medium' | 'high' | 'urgent';
  default_request_type: 'internal' | 'external';
  responsible_member_id: string | null;
  planning_lead_days: number;
  frequency: PreventiveFrequency | null;
  custom_interval: number | null;
  custom_unit: 'days' | 'weeks' | 'months' | 'years' | null;
  first_due_at: string | null;
  meter_id: string | null;
  meter_name: string | null;
  meter_unit: string | null;
  interval_value: number | null;
  baseline_value: number | null;
  baseline_reading_id: string | null;
  meter_lead_value: number | null;
  latest_meter_value: number | null;
  latest_meter_recorded_at: string | null;
  meter_remaining_value: number | null;
  is_active: boolean;
  timing_status: PreventiveTimingStatus | null;
  current_occurrence: PreventiveOccurrence | null;
  created_at: string;
  updated_at: string;
}

export interface MaintenanceCardDraft {
  code: string;
  name: string;
  description?: string;
  category?: string;
  estimatedHours?: number | null;
  procedureNotes?: string;
  safetyNotes?: string;
  tasks: MaintenanceCardTask[];
  materials: MaintenanceCardMaterial[];
}

export interface PreventivePlanDraft {
  assetId: string;
  cardId: string;
  triggerType: PreventiveTriggerType;
  priority: PreventivePlan['priority'];
  defaultRequestType: PreventivePlan['default_request_type'];
  responsibleMemberId?: string | null;
  planningLeadDays: number;
  frequency?: PreventiveFrequency | null;
  customInterval?: number | null;
  customUnit?: PreventivePlan['custom_unit'];
  firstDueAt?: string | null;
  meterId?: string | null;
  intervalValue?: number | null;
  baselineReadingId?: string | null;
  meterLeadValue?: number | null;
}
