import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { AssetMeter } from '@/types/preventiveMaintenance';

export function useAssetMeters(assetId: string | null | undefined) {
  const [meters, setMeters] = useState<AssetMeter[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!assetId) { setMeters([]); setError(null); return; }
    setLoading(true); setError(null);
    const { data, error: rpcError } = await supabase.rpc('get_asset_meters', {
      p_asset_id: assetId, p_include_inactive: true,
    });
    if (rpcError) { setMeters([]); setError(rpcError.message); }
    else setMeters((data ?? []) as unknown as AssetMeter[]);
    setLoading(false);
  }, [assetId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const mutate = useCallback(async (operation: () => PromiseLike<{ error: { message: string } | null }>) => {
    setSaving(true); setError(null);
    const result = await operation();
    if (result.error) { setError(result.error.message); setSaving(false); return false; }
    await refresh(); setSaving(false); return true;
  }, [refresh]);

  const createMeter = useCallback((organizationId: string, name: string, unit: string, initialValue: number, recordedAt: string) => {
    if (!assetId) return Promise.resolve(false);
    return mutate(() => supabase.rpc('create_asset_meter', {
      p_organization_id: organizationId, p_asset_id: assetId, p_name: name, p_unit: unit,
      p_initial_value: initialValue, p_recorded_at: recordedAt, p_notes: null,
    }));
  }, [assetId, mutate]);

  const recordReading = useCallback((meterId: string, value: number, recordedAt: string, notes?: string) => mutate(() =>
    supabase.rpc('record_asset_meter_reading', {
      p_meter_id: meterId, p_value: value, p_recorded_at: recordedAt, p_notes: notes || null,
    })
  ), [mutate]);

  const correctReading = useCallback((readingId: string, value: number, reason: string, notes?: string) => mutate(() =>
    supabase.rpc('correct_asset_meter_reading', {
      p_reading_id: readingId, p_value: value, p_reason: reason, p_notes: notes || null,
    })
  ), [mutate]);

  const retireMeter = useCallback((meterId: string, reason: string) => mutate(() =>
    supabase.rpc('retire_asset_meter', { p_meter_id: meterId, p_reason: reason })
  ), [mutate]);

  const replaceMeter = useCallback((meterId: string, name: string, unit: string, value: number, recordedAt: string, reason: string) => mutate(() =>
    supabase.rpc('replace_asset_meter', {
      p_meter_id: meterId, p_name: name, p_unit: unit, p_initial_value: value,
      p_recorded_at: recordedAt, p_reason: reason, p_notes: null,
    })
  ), [mutate]);

  return { meters, loading, saving, error, refresh, createMeter, recordReading, correctReading, retireMeter, replaceMeter };
}
