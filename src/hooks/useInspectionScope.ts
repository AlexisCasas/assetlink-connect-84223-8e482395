import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { usePermissions } from '@/hooks/usePermissions';
import {
  canFacilityManagerExecuteInspections,
  canFacilityManagerManageInspections,
  canFacilityManagerViewInspections,
} from '@/lib/facilityManagement';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

/** Which organization the Inspections module operates on and what the UI may
 * offer there. UX only: every RPC re-checks.
 * - direct: the active organization is the client (historic flow).
 * - facility_manager: the active organization stays the FM; the target is a
 *   delegated client validated against get_my_facility_management_clients. */
export interface InspectionScope {
  mode: 'direct' | 'facility_manager';
  organizationId: string | null;
  organizationName: string | null;
  canView: boolean;
  /** Templates, items, options, plans and alert rules. */
  canPlan: boolean;
  /** Create a run from a plan and complete it. */
  canExecute: boolean;
  /** Direct technicians only list runs assigned to their client membership.
   * Delegated: null — the FM membership is never compared with the client's
   * responsible_member_id; assignment to the relationship is the scope. */
  runsResponsibleMemberId: string | null;
  preferRunsTab: boolean;
  /** responsible_member_id is client-owned: only the client picks it (from
   * its own roster). A delegated FM keeps whatever the client assigned. */
  canChooseResponsible: boolean;
  /** Namespace of the plan-draft sessionStorage key (UX only, never
   * authority). Includes FM + client in delegated mode. */
  draftScopeKey: string | null;
}

/** Exactly the rules InspectionsView applied before 9C.2. */
export function useDirectInspectionScope(): InspectionScope {
  const { currentOrganization, currentMembership } = useAuth();
  const { canPlanWork, isTechnician } = usePermissions();
  return useMemo(() => ({
    mode: 'direct',
    organizationId: currentOrganization?.id ?? null,
    organizationName: currentOrganization?.name ?? null,
    canView: !!currentOrganization,
    canPlan: canPlanWork,
    canExecute: true,
    runsResponsibleMemberId: isTechnician && currentMembership ? currentMembership.id : null,
    preferRunsTab: isTechnician,
    canChooseResponsible: true,
    draftScopeKey: currentOrganization?.id ?? null,
  }), [currentOrganization, currentMembership, canPlanWork, isTechnician]);
}

export function buildDelegatedInspectionScope(client: FacilityManagementOperationalClient): InspectionScope {
  const canPlan = canFacilityManagerManageInspections(client);
  return {
    mode: 'facility_manager',
    organizationId: client.clientOrganizationId,
    organizationName: client.clientOrganizationName,
    canView: canFacilityManagerViewInspections(client),
    canPlan,
    canExecute: canFacilityManagerExecuteInspections(client),
    runsResponsibleMemberId: null,
    preferRunsTab: !canPlan,
    canChooseResponsible: false,
    draftScopeKey: `fm:${client.facilityManagerOrganizationId}:${client.clientOrganizationId}`,
  };
}
