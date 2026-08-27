import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AssetTrafficLight, BranchTrafficLight, TrafficLightReason } from '@/types/assetTrafficLight';

interface RawReason {
  severity: string;
  source_type: string;
  source_table: string;
  source_id: string;
  title: string;
  description: string;
  event_date: string | null;
  due_at: string | null;
  asset_id: string | null;
  asset_name: string | null;
}

const toReason = (row: RawReason): TrafficLightReason => ({
  severity: row.severity as TrafficLightReason['severity'],
  sourceType: row.source_type as TrafficLightReason['sourceType'],
  sourceTable: row.source_table,
  sourceId: row.source_id,
  title: row.title,
  description: row.description,
  eventDate: row.event_date,
  dueAt: row.due_at,
  assetId: row.asset_id,
  assetName: row.asset_name,
});

interface RawAssetRow {
  asset_id: string;
  organization_id: string;
  branch_id: string | null;
  parent_asset_id: string | null;
  asset_name: string;
  asset_code: string | null;
  node_type: string;
  status: string;
  criticality: string | null;
  direct_color: string;
  rollup_color: string;
  direct_severity: number;
  rollup_severity: number;
  direct_reasons: RawReason[] | null;
  rollup_reasons: RawReason[] | null;
  causing_asset_ids: string[] | null;
  updated_at: string;
}

const toAssetTrafficLight = (row: RawAssetRow): AssetTrafficLight => ({
  assetId: row.asset_id,
  organizationId: row.organization_id,
  branchId: row.branch_id,
  parentAssetId: row.parent_asset_id,
  assetName: row.asset_name,
  assetCode: row.asset_code,
  nodeType: row.node_type,
  status: row.status,
  criticality: row.criticality,
  directColor: row.direct_color as AssetTrafficLight['directColor'],
  rollupColor: row.rollup_color as AssetTrafficLight['rollupColor'],
  directSeverity: row.direct_severity,
  rollupSeverity: row.rollup_severity,
  directReasons: (row.direct_reasons ?? []).map(toReason),
  rollupReasons: (row.rollup_reasons ?? []).map(toReason),
  causingAssetIds: row.causing_asset_ids ?? [],
  updatedAt: row.updated_at,
});

interface RawBranchRow {
  branch_id: string;
  branch_name: string;
  rollup_color: string;
  rollup_severity: number;
  causing_asset_ids: string[] | null;
  rollup_reasons: RawReason[] | null;
}

const toBranchTrafficLight = (row: RawBranchRow): BranchTrafficLight => ({
  branchId: row.branch_id,
  branchName: row.branch_name,
  rollupColor: row.rollup_color as BranchTrafficLight['rollupColor'],
  rollupSeverity: row.rollup_severity,
  causingAssetIds: row.causing_asset_ids ?? [],
  rollupReasons: (row.rollup_reasons ?? []).map(toReason),
});

/**
 * Operational traffic light for assets/áreas/sedes — computed live via
 * get_asset_traffic_light/get_branch_traffic_light (both SECURITY DEFINER,
 * read-only, no mirror table). See docs/ASSET_TRAFFIC_LIGHT.md.
 */
export function useAssetTrafficLight(organizationId: string | null | undefined) {
  const [assets, setAssets] = useState<AssetTrafficLight[]>([]);
  const [branches, setBranches] = useState<BranchTrafficLight[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setAssets([]);
      setBranches([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [assetResult, branchResult] = await Promise.all([
        supabase.rpc('get_asset_traffic_light', { p_organization_id: organizationId }),
        supabase.rpc('get_branch_traffic_light', { p_organization_id: organizationId }),
      ]);
      if (assetResult.error) throw assetResult.error;
      if (branchResult.error) throw branchResult.error;
      setAssets(((assetResult.data ?? []) as unknown as RawAssetRow[]).map(toAssetTrafficLight));
      setBranches(((branchResult.data ?? []) as unknown as RawBranchRow[]).map(toBranchTrafficLight));
    } catch (err) {
      setAssets([]);
      setBranches([]);
      setError(err instanceof Error ? err.message : 'No se pudo cargar el semáforo operativo.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const byAssetId = new Map(assets.map((a) => [a.assetId, a]));
  const getAsset = useCallback((assetId: string) => byAssetId.get(assetId) ?? null, [assets]);

  const summary = assets.reduce(
    (acc, a) => {
      acc[a.directColor] += 1;
      return acc;
    },
    { green: 0, amber: 0, red: 0 } as Record<'green' | 'amber' | 'red', number>,
  );

  return { assets, branches, loading, error, refresh, getAsset, summary };
}

export type UseAssetTrafficLightResult = ReturnType<typeof useAssetTrafficLight>;
