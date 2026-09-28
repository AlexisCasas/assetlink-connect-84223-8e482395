import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import {
  canFacilityManagerEditAssetCriticalityValue,
  canFacilityManagerEvaluateAssetCriticality,
  canFacilityManagerManageAssets,
  canFacilityManagerManagePreventive,
  canFacilityManagerReportMaintenanceNotice,
  canFacilityManagerViewAssetCriticalityAssessments,
  canFacilityManagerViewAssets,
  canFacilityManagerViewPreventive,
} from '@/lib/facilityManagement';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';

/** Which organization the Assets module operates on, and what the UI may
 * offer there. Every flag is UX only: RLS and the RPCs re-check everything.
 * - direct: the active organization is the client itself (historic flow).
 * - facility_manager: the active organization stays the FM; the target is a
 *   delegated client validated against get_my_facility_management_clients. */
export interface AssetScope {
  mode: 'direct' | 'facility_manager';
  organizationId: string | null;
  organizationName: string | null;
  canViewAssets: boolean;
  canManageAssets: boolean;
  accessReason?: string;
  /** Criticality matrix details + assessment history of an asset. */
  canViewCriticality: boolean;
  canEvaluateCriticality: boolean;
  /** Manual edit of assets.criticality in the asset form. Delegated mode
   * requires assets.manage AND criticality.view/manage (backend enforced). */
  canEditCriticalityValue: boolean;
  /** Traffic light, integrated history, maintenance notices, PDF report, QR
   * and the client's member directory. Direct mode only: those modules are
   * not delegated yet. */
  includesCrossModuleData: boolean;
  /** "Preventivo" tab of the asset sheet. Delegated since 9C.2 with its own
   * permission (preventive_maintenance.view), independent of assets.*. */
  canViewPreventive: boolean;
  /** "Crear plan" from the asset sheet. */
  canManagePreventive: boolean;
  /** "Crear aviso" from the asset sheet (maintenance_notices.report; the
   * asset is fixed). Delegated since 9C.3. */
  canReportMaintenanceNotice: boolean;
  /** default_responsible_member_id stays client-only (also enforced by a
   * backend trigger). */
  canEditDefaultResponsible: boolean;
}

/** Exactly the rules useAssets() applied before 9C.1. */
export function useDirectAssetScope(): AssetScope {
  const { currentOrganization, currentMembership } = useAuth();
  return useMemo(() => {
    const isClientCompany = currentOrganization?.organizationType === 'client_company';
    const hasActiveMembership = !!currentMembership?.isActive;
    const canManageAssets = isClientCompany && hasActiveMembership && ['owner', 'admin', 'manager'].includes(currentMembership!.role);

    let canViewAssets = false;
    let accessReason: string | undefined;
    if (!currentOrganization) {
      accessReason = 'Selecciona una organización cliente.';
    } else if (!isClientCompany) {
      accessReason = currentOrganization.organizationType === 'platform_admin'
        ? 'Los activos se administran desde la organización cliente, no desde la organización de plataforma.'
        : 'Los activos aún no están disponibles para organizaciones proveedoras.';
    } else if (!hasActiveMembership) {
      accessReason = 'No tienes una membresía activa en esta organización.';
    } else {
      canViewAssets = true;
    }

    return {
      mode: 'direct',
      organizationId: currentOrganization?.id ?? null,
      organizationName: currentOrganization?.name ?? null,
      canViewAssets,
      canManageAssets,
      accessReason,
      canViewCriticality: canViewAssets,
      canEvaluateCriticality: canManageAssets,
      canEditCriticalityValue: canManageAssets,
      includesCrossModuleData: true,
      canViewPreventive: true,
      canManagePreventive: canManageAssets,
      canReportMaintenanceNotice: hasActiveMembership
        && ['owner', 'admin', 'manager', 'technician', 'requester'].includes(currentMembership!.role),
      canEditDefaultResponsible: canManageAssets,
    };
  }, [currentOrganization, currentMembership]);
}

export function buildDelegatedAssetScope(client: FacilityManagementOperationalClient): AssetScope {
  const canViewAssets = canFacilityManagerViewAssets(client);
  return {
    mode: 'facility_manager',
    organizationId: client.clientOrganizationId,
    organizationName: client.clientOrganizationName,
    canViewAssets,
    canManageAssets: canFacilityManagerManageAssets(client),
    accessReason: canViewAssets ? undefined : 'No tienes acceso delegado a los activos de este cliente.',
    canViewCriticality: canFacilityManagerViewAssetCriticalityAssessments(client),
    canEvaluateCriticality: canFacilityManagerEvaluateAssetCriticality(client),
    canEditCriticalityValue: canFacilityManagerEditAssetCriticalityValue(client),
    includesCrossModuleData: false,
    canViewPreventive: canFacilityManagerViewPreventive(client),
    canManagePreventive: canFacilityManagerManagePreventive(client),
    canReportMaintenanceNotice: canFacilityManagerReportMaintenanceNotice(client),
    canEditDefaultResponsible: false,
  };
}
