import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { notifyPreventiveMaintenanceRefresh, subscribePreventiveMaintenanceRefresh } from '@/lib/preventiveMaintenanceRefresh';
import type { AssetMeter } from '@/types/preventiveMaintenance';

const errorText = (error: unknown, fallback: string) => error instanceof Error ? error.message : fallback;

export function useAssetMeters(assetId: string | null | undefined, organizationId?: string | null) {
  const [meters, setMeters] = useState<AssetMeter[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refreshSource = useRef(Symbol('asset-meters'));

  const refresh = useCallback(async (background = false) => {
    if (!assetId) { setMeters([]); setError(null); return; }
    if (!background) { setLoading(true); setError(null); }
    try {
      const { data, error: rpcError } = await supabase.rpc('get_asset_meters', {
        p_asset_id: assetId, p_include_inactive: true,
      });
      if (rpcError) throw rpcError;
      setMeters((data ?? []) as unknown as AssetMeter[]);
      setError(null);
      return true;
    } catch (cause) {
      if (!background) setMeters([]);
      setError(errorText(cause, 'No se pudieron cargar los medidores.'));
      return false;
    } finally {
      if (!background) setLoading(false);
    }
  }, [assetId]);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => subscribePreventiveMaintenanceRefresh((change) => {
    if (change.source !== refreshSource.current && change.assetId === assetId) {
      void refresh(true);
    }
  }), [assetId, refresh]);

  const mutate = useCallback(async (operation: () => PromiseLike<{ error: { message: string } | null }>) => {
    setSaving(true); setError(null);
    try {
      const result = await operation();
      if (result.error) throw result.error;
      notifyPreventiveMaintenanceRefresh({ organizationId, assetId, source: refreshSource.current });
      await refresh(true);
      return true;
    } catch (cause) {
      setError(errorText(cause, 'No se pudo guardar la lectura del medidor.'));
      return false;
    } finally {
      setSaving(false);
    }
  }, [assetId, organizationId, refresh]);

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
