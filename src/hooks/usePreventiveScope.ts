import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import {
  canFacilityManagerManageMeters,
  canFacilityManagerManagePreventive,
  canFacilityManagerRecordMeterReading,
  canFacilityManagerViewPreventive,
} from '@/lib/facilityManagement';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

/** Which organization the Preventive maintenance module operates on and what
 * the UI may offer there. UX only: every RPC re-checks. */
export interface PreventiveScope {
  mode: 'direct' | 'facility_manager';
  organizationId: string | null;
  organizationName: string | null;
  canView: boolean;
  unavailableReason?: string;
  /** Cards, plans (create/edit/activate) and skipping a cycle. */
  canManage: boolean;
  canRecordMeterReading: boolean;
  /** Create, correct, retire and replace meters. */
  canManageMeters: boolean;
  /** Turn an occurrence into a Request. Requests are not delegated yet
   * (9C.4): always false in delegated mode. */
  canPlanRequest: boolean;
  /** responsible_member_id is client-owned (needs the client roster). */
  canChooseResponsible: boolean;
  /** Inventory catalog/stock for card materials. Not delegated. */
  canUseInventory: boolean;
}

/** Exactly the rules PreventiveMaintenanceView applied before 9C.2. */
export function useDirectPreventiveScope(): PreventiveScope {
  const { currentOrganization, currentMembership } = useAuth();
  return useMemo(() => {
    const isClient = currentOrganization?.organizationType === 'client_company';
    const canManage = isClient && !!currentMembership?.isActive && ['owner', 'admin', 'manager'].includes(currentMembership.role);
    return {
      mode: 'direct',
      organizationId: currentOrganization?.id ?? null,
      organizationName: currentOrganization?.name ?? null,
      canView: isClient,
      unavailableReason: isClient ? undefined : 'Mantenimiento preventivo se administra desde una organización cliente.',
      canManage,
      canRecordMeterReading: true,
      canManageMeters: canManage,
      canPlanRequest: canManage,
      canChooseResponsible: canManage,
      canUseInventory: true,
    };
  }, [currentOrganization, currentMembership]);
}

export function buildDelegatedPreventiveScope(client: FacilityManagementOperationalClient): PreventiveScope {
  const canView = canFacilityManagerViewPreventive(client);
  return {
    mode: 'facility_manager',
    organizationId: client.clientOrganizationId,
    organizationName: client.clientOrganizationName,
    canView,
    unavailableReason: canView ? undefined : 'No tienes acceso delegado al mantenimiento preventivo de este cliente.',
    canManage: canFacilityManagerManagePreventive(client),
    canRecordMeterReading: canFacilityManagerRecordMeterReading(client),
    canManageMeters: canFacilityManagerManageMeters(client),
    canPlanRequest: false,
    canChooseResponsible: false,
    canUseInventory: false,
  };
}
