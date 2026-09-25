import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toCriticalityThresholds, type RawCriticalityThresholds } from '@/lib/criticalityThresholds';
import type { CriticalityThresholdValues, CriticalityThresholds } from '@/types/criticalityMatrix';

/**
 * Classification thresholds of one organization (get_criticality_thresholds /
 * set_criticality_thresholds — SECURITY DEFINER; read for any active member or
 * platform_admin, write for owner/admin/manager or platform_admin). Without an
 * explicit configuration the server returns the defaults (25/50/75), so this
 * hook never hardcodes them.
 */
export function useCriticalityThresholds(organizationId: string | null | undefined) {
  const [thresholds, setThresholds] = useState<CriticalityThresholds | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setThresholds(null);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_criticality_thresholds', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      setThresholds(data ? toCriticalityThresholds(data as unknown as RawCriticalityThresholds) : null);
    } catch (err) {
      setThresholds(null);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los umbrales de criticidad.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  /** Returns null on success, or the server's message on failure. */
  const saveThresholds = useCallback(async (values: CriticalityThresholdValues): Promise<string | null> => {
    if (!organizationId) return 'Sin organización activa.';
    setSaving(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('set_criticality_thresholds', {
        p_organization_id: organizationId,
        p_medium_min: values.mediumMin,
        p_high_min: values.highMin,
        p_critical_min: values.criticalMin,
      });
      if (rpcError) throw rpcError;
      if (data) setThresholds(toCriticalityThresholds(data as unknown as RawCriticalityThresholds));
      return null;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'No se pudieron guardar los umbrales.';
      setError(message);
      return message;
    } finally {
      setSaving(false);
    }
  }, [organizationId]);

  return { thresholds, loading, saving, error, refresh, saveThresholds };
}

export type UseCriticalityThresholdsResult = ReturnType<typeof useCriticalityThresholds>;
