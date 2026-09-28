import type { OrganizationRelationshipStatus, OrganizationRelationshipType, OrganizationType } from './organization';

/** One row from get_provider_relationship_directory: a provider_company or
 * subcontractor_company (facility_manager left this directory in Fase 1 ·
 * Punto 9B — see get_facility_manager_directory) visible to the calling client, plus that client's own relationship to it
 * (if any) and the provider's own specialties. Never carries email/phone/
 * members/other-tenant data — the RPC is the only allowed read path. */
export interface ProviderDirectoryEntry {
  organizationId: string;
  organizationName: string;
  organizationType: OrganizationType;
  relationshipId: string | null;
  relationshipType: OrganizationRelationshipType;
  relationshipStatus: OrganizationRelationshipStatus | null;
  specialties: string[];
}

/** Provider-facing organization types: the only ones that receive
 * invitations, see the marketplace and quote. Mirrors the backend helper
 * is_provider_facing_organization. facility_manager is NOT provider-facing
 * in the MVP (Fase 1 · Punto 9B): it manages the client's processes through
 * delegated permissions instead. */
export const PROVIDER_ORGANIZATION_TYPES: OrganizationType[] = [
  'provider_company',
  'subcontractor_company',
];

/** UI gate for provider-facing features (provider request list, public
 * marketplace, quoting, specialties). Never infer it from the legacy
 * user.role === 'proveedor', which AuthContext still maps facility_manager to. */
export const isProviderFacingOrganizationType = (organizationType: OrganizationType | null | undefined): boolean =>
  !!organizationType && (PROVIDER_ORGANIZATION_TYPES as string[]).includes(organizationType);
