import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AssetHistoryItem } from '@/types/assetHistory';

/**
 * Consolidated "¿qué le ha pasado a este activo?" timeline via
 * get_asset_integrated_history (SECURITY DEFINER, tenant + operating-org
 * scoped — see docs/ASSET_INTEGRATED_HISTORY.md). Read-only: this history
 * is assembled live from source tables on every call, there is nothing to
 * write here.
 */
export function useAssetHistory(assetId: string | null | undefined) {
  const [items, setItems] = useState<AssetHistoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!assetId) {
      setItems([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_asset_integrated_history', {
        p_asset_id: assetId,
      });
      if (rpcError) throw rpcError;
      setItems((data ?? []).map((row) => ({
        id: row.id,
        eventType: row.event_type as AssetHistoryItem['eventType'],
        eventLabel: row.event_label,
        eventDate: row.event_date,
        actorName: row.actor_name,
        actorEmail: row.actor_email,
        sourceTable: row.source_table,
        sourceId: row.source_id,
        title: row.title,
        description: row.description,
        status: row.status,
        metadata: (row.metadata as Record<string, unknown>) ?? {},
      })));
    } catch (err) {
      setItems([]);
      setError(err instanceof Error ? err.message : 'No se pudo cargar el historial del activo.');
    } finally {
      setLoading(false);
    }
  }, [assetId]);

  useEffect(() => { void refresh(); }, [refresh]);

  return { items, loading, error, refresh };
}
