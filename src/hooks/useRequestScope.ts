import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import {
  canFacilityManagerApproveQuotes,
  canFacilityManagerCreateRequests,
  canFacilityManagerManageRequests,
  canFacilityManagerViewQuotes,
  canFacilityManagerViewRequests,
} from '@/lib/facilityManagement';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

/** Which organization Requests operate on, through which transport, and what
 * the UI may offer there. UX only: RLS (direct) and the delegated RPCs
 * re-check everything. `managedClientId` is visual context, never an
 * authorization input. */
export interface RequestScope {
  mode: 'direct' | 'facility_manager';
  /** The client organization that owns the requests. */
  organizationId: string | null;
  organizationName: string | null;
  managedClientId: string | null;
  canView: boolean;
  canCreate: boolean;
  /** Edit and annul sent requests. */
  canManage: boolean;
  /** Edit / send / delete the caller's own drafts. */
  canManageOwnDraft: boolean;
  /** Public vs private invitations. */
  canManageAudience: boolean;
  /** Quotes are delegated since 9C.5 (quotes.view); "Generar OT" is not. */
  canViewQuotes: boolean;
  /** Approve / reject quotes on behalf of the client (quotes.approve). */
  canApproveQuotes: boolean;
  canGenerateWorkOrder: boolean;
  /** The client roster (coordination contacts, "Encargado") and the client
   * technician directory stay private to the client's own members. */
  canUseClientMemberDirectory: boolean;
  canUseClientTechnicianDirectory: boolean;
}

/** Exactly what RequestList / DraftList / RequestForm did before 9C.4. */
export function useDirectRequestScope(): RequestScope {
  const { currentOrganization } = useAuth();
  return useMemo(() => ({
    mode: 'direct',
    organizationId: currentOrganization?.id ?? null,
    organizationName: currentOrganization?.name ?? null,
    managedClientId: null,
    canView: true,
    canCreate: true,
    canManage: true,
    canManageOwnDraft: true,
    canManageAudience: true,
    canViewQuotes: true,
    canApproveQuotes: true,
    canGenerateWorkOrder: true,
    canUseClientMemberDirectory: true,
    canUseClientTechnicianDirectory: true,
  }), [currentOrganization]);
}

export function buildDelegatedRequestScope(client: FacilityManagementOperationalClient): RequestScope {
  const canCreate = canFacilityManagerCreateRequests(client);
  const canManage = canFacilityManagerManageRequests(client);
  return {
    mode: 'facility_manager',
    organizationId: client.clientOrganizationId,
    organizationName: client.clientOrganizationName,
    managedClientId: client.clientOrganizationId,
    canView: canFacilityManagerViewRequests(client),
    canCreate,
    canManage,
    canManageOwnDraft: canCreate,
    canManageAudience: canCreate || canManage,
    canViewQuotes: canFacilityManagerViewQuotes(client),
    canApproveQuotes: canFacilityManagerApproveQuotes(client),
    canGenerateWorkOrder: false,
    canUseClientMemberDirectory: false,
    canUseClientTechnicianDirectory: false,
  };
}
