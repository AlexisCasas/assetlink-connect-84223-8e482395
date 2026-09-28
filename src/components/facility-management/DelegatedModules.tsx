import { useMemo } from 'react';
import { AssetsView } from '@/components/assets/AssetsView';
import { CriticalityMatrixView, type CriticalityScope } from '@/components/criticality/CriticalityMatrixView';
import { buildDelegatedAssetScope } from '@/hooks/useAssetScope';
import {
  canFacilityManagerEvaluateAssetCriticality,
  canFacilityManagerManageCriticality,
} from '@/lib/facilityManagement';
import type { FacilityManagementOperationalClient } from '@/types/facilityManagement';
import { ManagedClientGate } from './ManagedClientGate';

function DelegatedAssets({ client, focusAssetId }: { client: FacilityManagementOperationalClient; focusAssetId?: string }) {
  const scope = useMemo(() => buildDelegatedAssetScope(client), [client]);
  return <AssetsView scope={scope} focusAssetId={focusAssetId} />;
}

function DelegatedCriticality({ client }: { client: FacilityManagementOperationalClient }) {
  const scope = useMemo<CriticalityScope>(() => ({
    organizationId: client.clientOrganizationId,
    organizationName: client.clientOrganizationName,
    canManageMatrix: canFacilityManagerManageCriticality(client),
    canEvaluateAssets: canFacilityManagerEvaluateAssetCriticality(client),
    assetScope: buildDelegatedAssetScope(client),
  }), [client]);
  return <CriticalityMatrixView scope={scope} />;
}

/** #assets for an active facility_manager organization (9C.1). */
export function DelegatedAssetsModule({ managedClientId, focusAssetId }: { managedClientId?: string; focusAssetId?: string }) {
  return (
    <ManagedClientGate module="assets" requestedClientId={managedClientId}>
      {(client) => <DelegatedAssets key={client.clientOrganizationId} client={client} focusAssetId={focusAssetId} />}
    </ManagedClientGate>
  );
}

/** #criticality for an active facility_manager organization (9C.1). */
export function DelegatedCriticalityModule({ managedClientId }: { managedClientId?: string }) {
  return (
    <ManagedClientGate module="criticality" requestedClientId={managedClientId}>
      {(client) => <DelegatedCriticality key={client.clientOrganizationId} client={client} />}
    </ManagedClientGate>
  );
}
