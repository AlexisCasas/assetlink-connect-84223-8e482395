/** Real-source operational traffic light — computed live from work orders,
 * inspection plans/runs/answers and assets.status. Never a manually-set
 * color, never a mirror table. See docs/ASSET_TRAFFIC_LIGHT.md. */
export type TrafficLightColor = 'green' | 'amber' | 'red';

export type TrafficLightSourceType =
  | 'asset_status'
  | 'work_order_overdue'
  | 'work_order_due_soon'
  | 'inspection_overdue'
  | 'inspection_due_soon'
  | 'inspection_failed';

export interface TrafficLightReason {
  severity: 'red' | 'amber';
  sourceType: TrafficLightSourceType;
  sourceTable: string;
  sourceId: string;
  title: string;
  description: string;
  eventDate: string | null;
  dueAt: string | null;
  /** Null for a sede-level reason not tied to any specific asset. */
  assetId: string | null;
  assetName: string | null;
}

/** One row per asset/node. direct_* is this asset's own sources only;
 * rollup_* is the worst color among itself and every descendant (via
 * assets.parent_asset_id) — for a leaf, rollup always equals direct. */
export interface AssetTrafficLight {
  assetId: string;
  organizationId: string;
  branchId: string | null;
  parentAssetId: string | null;
  assetName: string;
  assetCode: string | null;
  nodeType: string;
  status: string;
  /** Context only — never contributes to direct/rollup color by itself. */
  criticality: string | null;
  directColor: TrafficLightColor;
  rollupColor: TrafficLightColor;
  directSeverity: number;
  rollupSeverity: number;
  directReasons: TrafficLightReason[];
  rollupReasons: TrafficLightReason[];
  /** Descendant assets (never self) contributing a non-green rollup color. */
  causingAssetIds: string[];
  updatedAt: string;
}

export interface BranchTrafficLight {
  branchId: string;
  branchName: string;
  rollupColor: TrafficLightColor;
  rollupSeverity: number;
  causingAssetIds: string[];
  rollupReasons: TrafficLightReason[];
}
