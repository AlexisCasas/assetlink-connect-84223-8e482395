import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface CoordinationContact {
  memberId: string;
  userId: string;
  name: string;
  email: string;
}

/**
 * Lists active members (any role) of a single organization via the
 * `get_coordination_contacts` RPC (SECURITY DEFINER). The RPC re-validates
 * that the caller is an active member of that organization (or platform
 * admin) and never returns members from another organization — this hook
 * does not, and must not, query organization_members or auth.users directly.
 */
export function useCoordinationContacts(organizationId: string | null | undefined) {
  const [contacts, setContacts] = useState<CoordinationContact[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setContacts([]);
      setError(null);
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_coordination_contacts', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      setContacts((data ?? []).map((row) => ({
        memberId: row.member_id,
        userId: row.user_id,
        name: row.name,
        email: row.email,
      })));
    } catch (err) {
      setContacts([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los contactos de la organización.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  return { contacts, loading, error, refresh };
}
