import { useCallback, useMemo } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toFacilityManagementErrorMessage } from '@/lib/facilityManagement';
import type { OrganizationRelationshipStatus } from '@/types/organization';
import type {
  FacilityManagementMember,
  FacilityManagementPermission,
  FacilityManagementPortfolioEntry,
  FacilityManagementRelationship,
  FacilityManagerDirectoryEntry,
} from '@/types/facilityManagement';

const fail = (error: unknown): never => {
  throw new Error(toFacilityManagementErrorMessage(error));
};

/** Única puerta del frontend a las RPCs de delegación Cliente -> Facility
 * Manager (9A/9B). Nunca escribe directo en organization_relationships,
 * facility_management_permissions ni facility_management_relationship_members.
 * currentOrganization solo define el contexto visual: cada RPC vuelve a
 * validar rol, tenant y estado en el servidor con auth.uid(). */
export function useFacilityManagement() {
  const { currentOrganization } = useAuth();
  const currentOrganizationId = currentOrganization?.id ?? null;

  // ---- Cliente ----------------------------------------------------------
  const listDirectory = useCallback(async (clientId: string): Promise<FacilityManagerDirectoryEntry[]> => {
    const { data, error } = await supabase.rpc('get_facility_manager_directory', { _client_organization_id: clientId });
    if (error) fail(error);
    return (data ?? []).map((row) => ({
      facilityManagerOrganizationId: row.facility_manager_organization_id,
      facilityManagerOrganizationName: row.facility_manager_organization_name,
      relationshipId: row.relationship_id ?? null,
      relationshipStatus: row.relationship_status ?? null,
    }));
  }, []);

  const getRelationships = useCallback(async (clientId: string): Promise<FacilityManagementRelationship[]> => {
    const { data, error } = await supabase.rpc('get_facility_management_relationships', { _client_organization_id: clientId });
    if (error) fail(error);
    return (data ?? []).map((row) => ({
      relationshipId: row.relationship_id,
      clientOrganizationId: row.client_organization_id,
      clientOrganizationName: row.client_organization_name,
      facilityManagerOrganizationId: row.facility_manager_organization_id,
      facilityManagerOrganizationName: row.facility_manager_organization_name,
      status: row.relationship_status,
      permissions: row.permissions ?? [],
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    }));
  }, []);

  const createRelationship = useCallback(async (facilityManagerOrgId: string): Promise<string> => {
    if (!currentOrganizationId) throw new Error('Selecciona una organización antes de vincular un Facility Manager.');
    const { data, error } = await supabase.rpc('create_facility_management_relationship', {
      _client_organization_id: currentOrganizationId,
      _facility_manager_organization_id: facilityManagerOrgId,
    });
    if (error) fail(error);
    return data as string;
  }, [currentOrganizationId]);

  const setPermissions = useCallback(async (relationshipId: string, permissions: FacilityManagementPermission[]) => {
    const { error } = await supabase.rpc('set_facility_management_permissions', {
      _relationship_id: relationshipId,
      _permissions: permissions,
    });
    if (error) fail(error);
  }, []);

  const setStatus = useCallback(async (relationshipId: string, status: OrganizationRelationshipStatus) => {
    const { error } = await supabase.rpc('set_facility_management_relationship_status', {
      _relationship_id: relationshipId,
      _status: status,
    });
    if (error) fail(error);
  }, []);

  // ---- Cliente y FM -----------------------------------------------------
  const getMembers = useCallback(async (relationshipId: string): Promise<FacilityManagementMember[]> => {
    const { data, error } = await supabase.rpc('get_facility_management_members', { _relationship_id: relationshipId });
    if (error) fail(error);
    return (data ?? []).map((row) => ({
      relationshipId: row.relationship_id,
      organizationMemberId: row.organization_member_id,
      userId: row.user_id,
      name: row.member_name,
      email: row.member_email,
      role: row.membership_role,
      membershipIsActive: row.membership_is_active,
      assignedAt: row.assigned_at,
    }));
  }, []);

  // ---- Facility Manager -------------------------------------------------
  const getPortfolio = useCallback(async (): Promise<FacilityManagementPortfolioEntry[]> => {
    const { data, error } = await supabase.rpc('get_my_facility_management_portfolio');
    if (error) fail(error);
    return (data ?? []).map((row) => ({
      relationshipId: row.relationship_id,
      clientOrganizationId: row.client_organization_id,
      clientOrganizationName: row.client_organization_name,
      clientOrganizationStatus: row.client_organization_status,
      facilityManagerOrganizationId: row.facility_manager_organization_id,
      facilityManagerOrganizationName: row.facility_manager_organization_name,
      status: row.relationship_status,
      permissions: row.permissions ?? [],
      assignedMemberCount: Number(row.assigned_member_count ?? 0),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    }));
  }, []);

  /** membershipIds = organization_members.id del propio FM (nunca user_id). */
  const setMembers = useCallback(async (relationshipId: string, membershipIds: string[]) => {
    const { error } = await supabase.rpc('set_facility_management_members', {
      _relationship_id: relationshipId,
      _organization_member_ids: membershipIds,
    });
    if (error) fail(error);
  }, []);

  return useMemo(() => ({
    listDirectory,
    getRelationships,
    createRelationship,
    setPermissions,
    setStatus,
    getMembers,
    getPortfolio,
    setMembers,
  }), [listDirectory, getRelationships, createRelationship, setPermissions, setStatus, getMembers, getPortfolio, setMembers]);
}
