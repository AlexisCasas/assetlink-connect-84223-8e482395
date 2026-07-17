export type OrganizationType =
  | 'client_company'
  | 'provider_company'
  | 'facility_manager'
  | 'subcontractor_company'
  | 'platform_admin';

export type OrganizationMemberRole =
  | 'owner'
  | 'admin'
  | 'manager'
  | 'requester'
  | 'quote_manager'
  | 'technician'
  | 'operator'
  | 'viewer';

export type OrganizationRelationshipType = 'provider' | 'facility_management' | 'subcontracting';
export type OrganizationRelationshipStatus = 'pending' | 'active' | 'suspended' | 'ended';

export interface Organization {
  id: string;
  name: string;
  legalName: string | null;
  organizationType: OrganizationType;
  taxId: string | null;
  status: 'active' | 'suspended';
  settings: Record<string, unknown>;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface OrganizationMember {
  id: string;
  organizationId: string;
  userId: string;
  role: OrganizationMemberRole;
  isActive: boolean;
  invitedBy: string | null;
  joinedAt: string;
  updatedAt: string;
}

export interface OrganizationRelationship {
  id: string;
  sourceOrganizationId: string;
  targetOrganizationId: string;
  relationshipType: OrganizationRelationshipType;
  status: OrganizationRelationshipStatus;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
}
