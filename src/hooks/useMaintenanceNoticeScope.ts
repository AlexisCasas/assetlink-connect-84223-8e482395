import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import {
  canFacilityManagerManageMaintenanceNotices,
  canFacilityManagerReportMaintenanceNotice,
  canFacilityManagerViewCriticality,
  canFacilityManagerViewMaintenanceNotices,
} from '@/lib/facilityManagement';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

/** Which organization the Backlog (maintenance notices) operates on and what
 * the UI may offer there. UX only: every RPC re-checks. */
export interface MaintenanceNoticeScope {
  mode: 'direct' | 'facility_manager';
  organizationId: string | null;
  organizationName: string | null;
  canView: boolean;
  unavailableReason?: string;
  canReport: boolean;
  /** Review (priority, notes) and dismiss. */
  canManage: boolean;
  /** Turn a notice into a Request. Requests are not delegated yet (9C.4):
   * always false in delegated mode. */
  canConvertToRequest: boolean;
  /** responsible_member_id is client-owned (needs the client roster). */
  canChooseResponsible: boolean;
  /** Live asset criticality is shown only with criticality.view. */
  canViewCriticality: boolean;
  /** Delegated: new notices pick their asset from the minimal directory
   * (maintenance_notices.report does not imply assets.view). */
  assetDirectoryClientId: string | null;
}

/** Exactly the rules BacklogView applied before 9C.3. */
export function useDirectMaintenanceNoticeScope(): MaintenanceNoticeScope {
  const { currentOrganization, currentMembership } = useAuth();
  return useMemo(() => {
    const role = currentMembership?.isActive ? currentMembership.role : null;
    const canManage = !!role && ['owner', 'admin', 'manager'].includes(role);
    const isClient = currentOrganization?.organizationType === 'client_company';
    return {
      mode: 'direct',
      organizationId: currentOrganization?.id ?? null,
      organizationName: currentOrganization?.name ?? null,
      canView: isClient,
      unavailableReason: isClient ? undefined : 'El backlog de mantenimiento solo está disponible para organizaciones cliente.',
      canReport: !!role && ['owner', 'admin', 'manager', 'technician', 'requester'].includes(role),
      canManage,
      canConvertToRequest: canManage,
      canChooseResponsible: true,
      canViewCriticality: true,
      assetDirectoryClientId: null,
    };
  }, [currentOrganization, currentMembership]);
}

export function buildDelegatedMaintenanceNoticeScope(client: FacilityManagementOperationalClient): MaintenanceNoticeScope {
  const canView = canFacilityManagerViewMaintenanceNotices(client);
  return {
    mode: 'facility_manager',
    organizationId: client.clientOrganizationId,
    organizationName: client.clientOrganizationName,
    canView,
    unavailableReason: canView ? undefined : 'No tienes acceso delegado al backlog de este cliente.',
    canReport: canFacilityManagerReportMaintenanceNotice(client),
    canManage: canFacilityManagerManageMaintenanceNotices(client),
    canConvertToRequest: false,
    canChooseResponsible: false,
    canViewCriticality: canFacilityManagerViewCriticality(client),
    assetDirectoryClientId: client.clientOrganizationId,
  };
}
