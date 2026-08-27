import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface AssignableTechnician {
  memberId: string;
  userId: string;
  name: string;
  email: string;
}

/**
 * Lists active technicians of a single organization via the
 * `get_assignable_technicians` RPC (SECURITY DEFINER). The RPC itself
 * re-validates that the caller is owner/admin/manager of that organization
 * (or platform admin) and never returns technicians from another
 * organization — this hook does not, and must not, query
 * organization_members or auth.users directly.
 */
export function useOrganizationTechnicians(organizationId: string | null | undefined) {
  const [technicians, setTechnicians] = useState<AssignableTechnician[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setTechnicians([]);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_assignable_technicians', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      setTechnicians((data ?? []).map((row) => ({
        memberId: row.member_id,
        userId: row.user_id,
        name: row.name,
        email: row.email,
      })));
    } catch (err) {
      setTechnicians([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los técnicos.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  return { technicians, loading, error, refresh };
}
