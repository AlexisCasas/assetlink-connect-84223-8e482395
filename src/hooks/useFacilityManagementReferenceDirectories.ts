import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import type { AssetNodeType } from '@/types/asset';
import type { ProviderDirectoryEntry } from '@/types/providerRelationship';
import type { ClientBranch } from '@/types/request';

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

/** Delegated FM only: minimal asset directory to report a maintenance notice
 * (get_facility_management_maintenance_notice_assets). Pass null to disable. */
export function useFacilityManagementMaintenanceNoticeAssets(clientOrganizationId: string | null) {
  const query = useQuery({
    queryKey: ['fm-notice-assets', clientOrganizationId],
    enabled: !!clientOrganizationId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_facility_management_maintenance_notice_assets', { _client_organization_id: clientOrganizationId! });
      if (error) throw error;
      return data ?? [];
    },
  });
  return query.data ?? [];
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

// ---------------------------------------------------------------------------
// 9C.4 — Solicitudes (requests.create o requests.manage). Nunca el roster del
// cliente. Pasar null para desactivar.
// ---------------------------------------------------------------------------

/** Sucursales del cliente (activas e inactivas; el formulario solo ofrece
 * las activas, pero conserva la de una solicitud existente). Sin client_email. */
export function useFacilityManagementRequestBranches(clientOrganizationId: string | null) {
  const query = useQuery({
    queryKey: ['fm-request-branches', clientOrganizationId],
    enabled: !!clientOrganizationId,
    queryFn: async (): Promise<ClientBranch[]> => {
      const { data, error } = await supabase.rpc('get_facility_management_request_branches', { _client_organization_id: clientOrganizationId! });
      if (error) throw error;
      return (data ?? []).map((branch) => ({
        id: branch.id, name: branch.name, city: branch.city, site: branch.site, address: branch.address ?? undefined, isActive: branch.is_active,
      }));
    },
  });
  return { branches: query.data ?? [], loading: query.isLoading && !!clientOrganizationId };
}

export interface RequestAssetOption {
  id: string;
  name: string;
  code: string | null;
  nodeType: AssetNodeType;
  path: string;
}

/** Activos no archivados del cliente con su ruta. */
export function useFacilityManagementRequestAssets(clientOrganizationId: string | null) {
  const query = useQuery({
    queryKey: ['fm-request-assets', clientOrganizationId],
    enabled: !!clientOrganizationId,
    queryFn: async (): Promise<RequestAssetOption[]> => {
      const { data, error } = await supabase.rpc('get_facility_management_request_assets', { _client_organization_id: clientOrganizationId! });
      if (error) throw error;
      return (data ?? []).map((asset) => ({
        id: asset.id, name: asset.name, code: asset.code, nodeType: asset.node_type as AssetNodeType, path: asset.path || asset.name,
      }));
    },
  });
  return { assets: query.data ?? [], loading: query.isLoading && !!clientOrganizationId, error: query.isError ? 'No se pudieron cargar los activos del cliente.' : null };
}

/** Proveedores/subcontratistas con relación ACTIVA del cliente. */
export function useFacilityManagementRequestProviders(clientOrganizationId: string | null) {
  const query = useQuery({
    queryKey: ['fm-request-providers', clientOrganizationId],
    enabled: !!clientOrganizationId,
    queryFn: async (): Promise<ProviderDirectoryEntry[]> => {
      const { data, error } = await supabase.rpc('get_facility_management_request_providers', { _client_organization_id: clientOrganizationId! });
      if (error) throw error;
      return (data ?? []).map((provider) => ({
        organizationId: provider.organization_id,
        organizationName: provider.organization_name,
        organizationType: provider.organization_type,
        relationshipId: null,
        relationshipType: provider.organization_type === 'subcontractor_company' ? 'subcontracting' : 'provider',
        relationshipStatus: 'active',
        specialties: provider.specialties ?? [],
      }));
    },
  });
  return { directory: query.data ?? [], loading: query.isLoading && !!clientOrganizationId, error: query.isError ? 'No se pudieron cargar los proveedores del cliente.' : null };
}
