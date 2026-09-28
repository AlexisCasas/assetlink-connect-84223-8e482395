import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

export interface ReferenceBranchOption {
  id: string;
  name: string;
  isActive: boolean;
}

export interface ReferenceAssetOption {
  id: string;
  name: string;
  code: string | null;
  status: string;
  /** Never exposed to a delegated FM (client-owned). */
  defaultResponsibleMemberId: null;
}

interface InspectionTargetsPayload {
  branches?: Array<{ id: string; name: string; is_active: boolean }>;
  assets?: Array<{ id: string; name: string; code: string | null; status: string }>;
}

/** Delegated FM only: minimal branch/asset directory to plan inspections
 * (get_facility_management_inspection_targets). Pass null to disable. */
export function useFacilityManagementInspectionTargets(clientOrganizationId: string | null) {
  const query = useQuery({
    queryKey: ['fm-inspection-targets', clientOrganizationId],
    enabled: !!clientOrganizationId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_facility_management_inspection_targets', { _client_organization_id: clientOrganizationId! });
      if (error) throw error;
      const payload = (data ?? {}) as InspectionTargetsPayload;
      return {
        branches: (payload.branches ?? []).map((branch): ReferenceBranchOption => ({ id: branch.id, name: branch.name, isActive: branch.is_active })),
        assets: (payload.assets ?? []).map((asset): ReferenceAssetOption => ({
          id: asset.id, name: asset.name, code: asset.code, status: asset.status, defaultResponsibleMemberId: null,
        })),
      };
    },
  });
  return { branches: query.data?.branches ?? [], assets: query.data?.assets ?? [], loading: query.isLoading && !!clientOrganizationId };
}

/** Delegated FM only: minimal asset directory for preventive plans and
 * meters (get_facility_management_preventive_assets). Pass null to disable. */
export function useFacilityManagementPreventiveAssets(clientOrganizationId: string | null) {
  const query = useQuery({
    queryKey: ['fm-preventive-assets', clientOrganizationId],
    enabled: !!clientOrganizationId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_facility_management_preventive_assets', { _client_organization_id: clientOrganizationId! });
      if (error) throw error;
      return data ?? [];
    },
  });
  return query.data ?? [];
}
