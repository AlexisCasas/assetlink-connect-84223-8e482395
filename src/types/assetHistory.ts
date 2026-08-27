/** See get_asset_integrated_history in
 * 20260829110000_asset_integrated_history.sql for exactly which source
 * table backs each of these. */
export type AssetHistoryEventType =
  | 'asset_created'
  | 'asset_event'
  | 'request_created'
  | 'work_order_created'
  | 'activity_created'
  | 'technician_report'
  | 'material_used'
  | 'evidence_added'
  /** Reserved for a future inspections module — never emitted today. */
  | 'inspection_created';

/** Visual grouping used by AssetHistory.tsx — several event types share a
 * group (e.g. asset_created and asset_event are both "Evento del activo"). */
export type AssetHistoryGroup =
  | 'asset'
  | 'request'
  | 'work_order'
  | 'activity'
  | 'intervention'
  | 'material'
  | 'evidence';

export interface AssetHistoryItem {
  id: string;
  eventType: AssetHistoryEventType;
  eventLabel: string;
  eventDate: string;
  actorName: string | null;
  actorEmail: string | null;
  sourceTable: string;
  sourceId: string;
  title: string;
  description: string | null;
  status: string | null;
  metadata: Record<string, unknown>;
}
