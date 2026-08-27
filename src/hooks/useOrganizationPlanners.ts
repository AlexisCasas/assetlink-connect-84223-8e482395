import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface AssignablePlanner {
  memberId: string;
  userId: string;
  name: string;
  email: string;
}

/**
 * Lists active owner/admin/manager ("Planner / Gestor") members of a single
 * organization via the `get_assignable_planners` RPC (SECURITY DEFINER) —
 * same pattern as useOrganizationTechnicians, mirrored for the planner role
 * set. The RPC re-validates that the caller is owner/admin/manager of that
 * organization (or platform admin) and never returns members from another
 * organization.
 */
export function useOrganizationPlanners(organizationId: string | null | undefined) {
  const [planners, setPlanners] = useState<AssignablePlanner[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setPlanners([]);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_assignable_planners', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      setPlanners((data ?? []).map((row) => ({
        memberId: row.member_id,
        userId: row.user_id,
        name: row.name,
        email: row.email,
      })));
    } catch (err) {
      setPlanners([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los planners.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  return { planners, loading, error, refresh };
}
