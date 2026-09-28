import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { canFacilityManagerOpenModule } from '@/lib/facilityManagement';
import type {
  FacilityManagementOperationalClient,
  FacilityManagementOperationalModule,
} from '@/types/facilityManagement';

/** Clients the current user OPERATES for from the active Facility Manager
 * organization (get_my_facility_management_clients: active relationship,
 * active client + FM, active membership assigned to it). Filtered to the
 * currently selected FM so a user in two FMs never mixes one FM's
 * relationship with the other's membership/role. currentOrganization stays
 * the FM; nothing is persisted as authorization. */
export function useFacilityManagementOperationalClients() {
  const { currentOrganization, user } = useAuth();
  const facilityManagerId = currentOrganization?.organizationType === 'facility_manager' ? currentOrganization.id : null;

  const query = useQuery({
    queryKey: ['fm-operational-clients', user?.id ?? null, facilityManagerId],
    enabled: !!facilityManagerId && !!user?.id,
    staleTime: 30_000,
    queryFn: async (): Promise<FacilityManagementOperationalClient[]> => {
      const { data, error } = await supabase.rpc('get_my_facility_management_clients');
      if (error) throw error;
      return (data ?? [])
        .filter((row) => row.facility_manager_organization_id === facilityManagerId)
        .map((row) => ({
          relationshipId: row.relationship_id,
          clientOrganizationId: row.client_organization_id,
          clientOrganizationName: row.client_organization_name,
          facilityManagerOrganizationId: row.facility_manager_organization_id,
          facilityManagerOrganizationName: row.facility_manager_organization_name,
          membershipRole: row.membership_role,
          permissions: row.permissions ?? [],
        }));
    },
  });

  return {
    isFacilityManagerContext: !!facilityManagerId,
    clients: query.data ?? [],
    loading: !!facilityManagerId && query.isLoading,
    error: query.isError ? 'No se pudieron cargar tus clientes operativos.' : null,
  };
}

export type ManagedClientResolution =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'none' }
  | { status: 'unavailable' }
  | { status: 'choose'; eligible: FacilityManagementOperationalClient[] }
  | { status: 'ready'; client: FacilityManagementOperationalClient; eligible: FacilityManagementOperationalClient[] };

/** Resolves the operated client for a delegated module from an explicit
 * `managedClient` hash param. The param is only a request: it must match a
 * client the backend returned for this user AND module; otherwise nothing
 * is queried ("unavailable"). Zero eligible clients => "none"; exactly one
 * with no param => auto-selected; several => "choose". */
export function useManagedClient(
  module: FacilityManagementOperationalModule,
  requestedClientId: string | undefined,
): ManagedClientResolution {
  const { clients, loading, error } = useFacilityManagementOperationalClients();
  return useMemo<ManagedClientResolution>(() => {
    if (loading) return { status: 'loading' };
    if (error) return { status: 'error', message: error };
    const eligible = clients.filter((client) => canFacilityManagerOpenModule(client, module));
    if (requestedClientId) {
      const client = eligible.find((candidate) => candidate.clientOrganizationId === requestedClientId);
      return client ? { status: 'ready', client, eligible } : { status: 'unavailable' };
    }
    if (eligible.length === 0) return { status: 'none' };
    if (eligible.length === 1) return { status: 'ready', client: eligible[0], eligible };
    return { status: 'choose', eligible };
  }, [clients, loading, error, module, requestedClientId]);
}
