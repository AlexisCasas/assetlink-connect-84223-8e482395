import { useMemo } from 'react';
import { AssetsView } from '@/components/assets/AssetsView';
import { BacklogView } from '@/components/backlog/BacklogView';
import { CriticalityMatrixView, type CriticalityScope } from '@/components/criticality/CriticalityMatrixView';
import { InspectionsView } from '@/components/inspections/InspectionsView';
import { PreventiveMaintenanceView } from '@/components/preventive-maintenance/PreventiveMaintenanceView';
import { DraftList } from '@/components/requests/DraftList';
import { RequestList } from '@/components/requests/RequestList';
import { buildDelegatedAssetScope } from '@/hooks/useAssetScope';
import { buildDelegatedInspectionScope } from '@/hooks/useInspectionScope';
import { buildDelegatedMaintenanceNoticeScope } from '@/hooks/useMaintenanceNoticeScope';
import { buildDelegatedPreventiveScope } from '@/hooks/usePreventiveScope';
import { buildDelegatedRequestScope } from '@/hooks/useRequestScope';
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

function DelegatedInspections({ client, focusPlanId, focusRunId }: { client: FacilityManagementOperationalClient; focusPlanId?: string; focusRunId?: string }) {
  const scope = useMemo(() => buildDelegatedInspectionScope(client), [client]);
  return <InspectionsView scope={scope} focusPlanId={focusPlanId} focusRunId={focusRunId} />;
}

function DelegatedPreventive({ client, focusPlanId, focusOccurrenceId, focusAssetId }: {
  client: FacilityManagementOperationalClient; focusPlanId?: string; focusOccurrenceId?: string; focusAssetId?: string;
}) {
  const scope = useMemo(() => buildDelegatedPreventiveScope(client), [client]);
  return <PreventiveMaintenanceView scope={scope} focusPlanId={focusPlanId} focusOccurrenceId={focusOccurrenceId} focusAssetId={focusAssetId} />;
}

function DelegatedBacklog({ client, focusNoticeId }: { client: FacilityManagementOperationalClient; focusNoticeId?: string }) {
  const scope = useMemo(() => buildDelegatedMaintenanceNoticeScope(client), [client]);
  return <BacklogView scope={scope} focusNoticeId={focusNoticeId} />;
}

function DelegatedRequests({ client, focusRequestId }: { client: FacilityManagementOperationalClient; focusRequestId?: string }) {
  const scope = useMemo(() => buildDelegatedRequestScope(client), [client]);
  // focusQuoteId is never passed: quotes are not delegated.
  return <RequestList scope={scope} focusRequestId={focusRequestId} />;
}

function DelegatedDrafts({ client }: { client: FacilityManagementOperationalClient }) {
  const scope = useMemo(() => buildDelegatedRequestScope(client), [client]);
  return <DraftList scope={scope} />;
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

/** #inspections for an active facility_manager organization (9C.2). */
export function DelegatedInspectionsModule({ managedClientId, focusPlanId, focusRunId }: { managedClientId?: string; focusPlanId?: string; focusRunId?: string }) {
  return (
    <ManagedClientGate module="inspections" requestedClientId={managedClientId}>
      {(client) => <DelegatedInspections key={client.clientOrganizationId} client={client} focusPlanId={focusPlanId} focusRunId={focusRunId} />}
    </ManagedClientGate>
  );
}

/** #preventive-maintenance for an active facility_manager organization (9C.2). */
export function DelegatedPreventiveMaintenanceModule({ managedClientId, focusPlanId, focusOccurrenceId, focusAssetId }: {
  managedClientId?: string; focusPlanId?: string; focusOccurrenceId?: string; focusAssetId?: string;
}) {
  return (
    <ManagedClientGate module="preventive-maintenance" requestedClientId={managedClientId}>
      {(client) => <DelegatedPreventive key={client.clientOrganizationId} client={client} focusPlanId={focusPlanId} focusOccurrenceId={focusOccurrenceId} focusAssetId={focusAssetId} />}
    </ManagedClientGate>
  );
}

/** #backlog for an active facility_manager organization (9C.3). */
export function DelegatedBacklogModule({ managedClientId, focusNoticeId }: { managedClientId?: string; focusNoticeId?: string }) {
  return (
    <ManagedClientGate module="backlog" requestedClientId={managedClientId}>
      {(client) => <DelegatedBacklog key={client.clientOrganizationId} client={client} focusNoticeId={focusNoticeId} />}
    </ManagedClientGate>
  );
}

/** #requests for an active facility_manager organization (9C.4). `quote=`
 * from the hash is ignored on purpose. */
export function DelegatedRequestsModule({ managedClientId, focusRequestId }: { managedClientId?: string; focusRequestId?: string }) {
  return (
    <ManagedClientGate module="requests" requestedClientId={managedClientId}>
      {(client) => <DelegatedRequests key={client.clientOrganizationId} client={client} focusRequestId={focusRequestId} />}
    </ManagedClientGate>
  );
}

/** #drafts for an active facility_manager organization (9C.4): only the
 * caller's own drafts, only with requests.create. */
export function DelegatedDraftsModule({ managedClientId }: { managedClientId?: string }) {
  return (
    <ManagedClientGate module="drafts" requestedClientId={managedClientId}>
      {(client) => <DelegatedDrafts key={client.clientOrganizationId} client={client} />}
    </ManagedClientGate>
  );
}
