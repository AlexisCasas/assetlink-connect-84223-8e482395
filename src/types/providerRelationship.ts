import type { OrganizationRelationshipStatus, OrganizationRelationshipType, OrganizationType } from './organization';

/** One row from get_provider_relationship_directory: a provider-facing
 * organization (provider_company / facility_manager / subcontractor_company)
 * visible to the calling client, plus that client's own relationship to it
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

export const PROVIDER_ORGANIZATION_TYPES: OrganizationType[] = [
  'provider_company',
  'facility_manager',
  'subcontractor_company',
];

export const isProviderFacingOrganizationType = (organizationType: OrganizationType): boolean =>
  (PROVIDER_ORGANIZATION_TYPES as string[]).includes(organizationType);
