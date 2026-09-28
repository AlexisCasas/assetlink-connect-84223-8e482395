import type { Database } from '@/integrations/supabase/types';
import type { OrganizationMemberRole, OrganizationRelationshipStatus } from './organization';

/** Códigos internos del enum public.facility_management_permission (tipo
 * generado; nunca se redefinen a mano). */
export type FacilityManagementPermission = Database['public']['Enums']['facility_management_permission'];

/** get_facility_manager_directory: empresas FM activas + la relación del
 * cliente con cada una (null si todavía no existe). */
export interface FacilityManagerDirectoryEntry {
  facilityManagerOrganizationId: string;
  facilityManagerOrganizationName: string;
  relationshipId: string | null;
  relationshipStatus: OrganizationRelationshipStatus | null;
}

/** get_facility_management_relationships: vista del cliente. */
export interface FacilityManagementRelationship {
  relationshipId: string;
  clientOrganizationId: string;
  clientOrganizationName: string;
  facilityManagerOrganizationId: string;
  facilityManagerOrganizationName: string;
  status: OrganizationRelationshipStatus;
  permissions: FacilityManagementPermission[];
  createdAt: string;
  updatedAt: string;
}

/** get_my_facility_management_portfolio: cartera administrativa del FM. */
export interface FacilityManagementPortfolioEntry {
  relationshipId: string;
  clientOrganizationId: string;
  clientOrganizationName: string;
  clientOrganizationStatus: string;
  facilityManagerOrganizationId: string;
  facilityManagerOrganizationName: string;
  status: OrganizationRelationshipStatus;
  permissions: FacilityManagementPermission[];
  assignedMemberCount: number;
  createdAt: string;
  updatedAt: string;
}

/** get_facility_management_members: persona del FM asignada a la relación. */
export interface FacilityManagementMember {
  relationshipId: string;
  organizationMemberId: string;
  userId: string;
  name: string;
  email: string;
  role: OrganizationMemberRole;
  membershipIsActive: boolean;
  assignedAt: string;
}

export type FacilityManagementMode = 'client' | 'facility_manager';

/** get_my_facility_management_clients: a client this user OPERATES for (active
 * relationship, active client + FM, active membership assigned to it). */
export interface FacilityManagementOperationalClient {
  relationshipId: string;
  clientOrganizationId: string;
  clientOrganizationName: string;
  facilityManagerOrganizationId: string;
  facilityManagerOrganizationName: string;
  membershipRole: OrganizationMemberRole;
  permissions: FacilityManagementPermission[];
}

/** Delegated modules wired in 9C.1. */
export type FacilityManagementOperationalModule = 'assets' | 'criticality';

export interface FacilityManagementPermissionGroup {
  key: string;
  label: string;
  permissions: { code: FacilityManagementPermission; label: string }[];
}
