import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { AssetsView } from '@/components/assets/AssetsView';
import { RequestList } from '@/components/requests/RequestList';
import { DraftList } from '@/components/requests/DraftList';
import { ProviderRequestList } from '@/components/requests/ProviderRequestList';
import { DashboardMetricsCards } from '@/components/dashboard/DashboardMetricsCards';
import { TrafficLightSummaryCard } from '@/components/dashboard/TrafficLightSummaryCard';
import { OrganizationProfile } from '@/components/organization/OrganizationProfile';
import { PublicRequestList } from '@/components/requests/PublicRequestList';
import { NotificationList } from '@/components/notifications/NotificationList';
import { ContactList } from '@/components/contact/ContactList';
import { ApprovedProvidersList } from '@/components/providers/ApprovedProvidersList';
import { BranchesList } from '@/components/branches/BranchesList';
import { WorkOrdersList } from '@/components/work-orders/WorkOrdersList';
import { InventoryView } from '@/components/inventory/InventoryView';
import { TechnicianWorkView } from '@/components/technician/TechnicianWorkView';
import { AdminConsole } from '@/components/admin/AdminConsole';
import { OrganizationUsersView } from '@/components/organization/OrganizationUsersView';
import { EfficiencyDashboard } from '@/components/analytics/EfficiencyDashboard';
import { CriticalityMatrixView } from '@/components/criticality/CriticalityMatrixView';
import { InspectionsView } from '@/components/inspections/InspectionsView';
import { BacklogView } from '@/components/backlog/BacklogView';
import { PreventiveMaintenanceView } from '@/components/preventive-maintenance/PreventiveMaintenanceView';
import { PreventiveMaintenanceSummaryCard } from '@/components/dashboard/PreventiveMaintenanceSummaryCard';
import { FacilityManagementAccessDenied, FacilityManagementView } from '@/components/facility-management/FacilityManagementView';
import { DelegatedAssetsModule, DelegatedCriticalityModule } from '@/components/facility-management/DelegatedModules';
import { getFacilityManagementMode } from '@/lib/facilityManagement';
import { isProviderFacingOrganizationType } from '@/types/providerRelationship';
import { useToast } from '@/hooks/use-toast';
import { parseEntityHash, type DashboardView, type ParsedEntityHash } from '@/lib/entityNavigation';

// A platform_admin organization only manages Administración; every other
// operational view falls back to it, including direct hash navigation.
const PLATFORM_ADMIN_ALLOWED_VIEWS: DashboardView[] = ['admin', 'notifications'];

const EMPTY_FOCUS: ParsedEntityHash = { view: null };

const Dashboard = () => {
  const { user, organizations, currentOrganization, currentMembership, setCurrentOrganization } = useAuth();
  const { toast } = useToast();
  const isPlatformAdminOrg = currentOrganization?.organizationType === 'platform_admin';
  const isTechnicianRole = !!currentMembership?.isActive && currentMembership.role === 'technician';
  const [currentView, setCurrentView] = useState<DashboardView>(isPlatformAdminOrg ? 'admin' : 'dashboard');
  // Entity ids parsed from the current hash's query string (?request=...,
  // ?workOrder=..., etc.) — Dashboard parses once here and hands the ids
  // down as props; the target components never read window.location.hash
  // themselves (see docs/NOTIFICATION_DEEP_LINKS.md).
  const [focus, setFocus] = useState<ParsedEntityHash>(EMPTY_FOCUS);

  // Reads and reacts to window.location.hash — on mount (so a deep link
  // survives F5 or a pasted URL, not just a client-side click) and on every
  // 'hashchange' (browser Back/Forward, or any code setting the hash,
  // including navigateToEntity()). isPlatformAdminOrg/organizations/
  // currentOrganization?.id are dependencies so this also re-evaluates right
  // after an org switch below settles.
  useEffect(() => {
    const syncFromHash = () => {
      const parsed = parseEntityHash(window.location.hash);
      const hashView = parsed.view;
      if (!hashView) return;

      const nextView = isPlatformAdminOrg && !PLATFORM_ADMIN_ALLOWED_VIEWS.includes(hashView) ? 'admin' : hashView;

      // ?org=<uuid>: only relevant when it actually names a different
      // organization than the one currently active. Never a bypass — it
      // only ever switches to an organization already present in this
      // user's own `organizations` (loaded from their real
      // organization_members rows), exactly like OrganizationSwitcher does.
      if (parsed.organizationId && parsed.organizationId !== currentOrganization?.id) {
        const target = organizations.find((organization) => organization.id === parsed.organizationId);
        if (target) {
          setCurrentOrganization(target.id);
          // Re-render with the new currentOrganization will re-run this
          // effect (currentOrganization?.id is a dependency below) and pick
          // up the matching branch on the next pass — don't open anything
          // yet against the still-stale organization.
          return;
        }
        toast({
          title: 'Sin acceso a la organización del enlace',
          description: 'No tienes acceso a la organización relacionada con este enlace.',
          variant: 'destructive',
        });
        setCurrentView(nextView);
        setFocus(EMPTY_FOCUS);
        if (nextView !== hashView) window.location.hash = nextView;
        return;
      }

      setCurrentView(nextView);
      setFocus(nextView === hashView ? parsed : EMPTY_FOCUS);
      // Only rewrite the hash when platform-admin forced a different view
      // than what was requested — a normal view with query params (the
      // common case) must never be stripped back down to a bare view name.
      if (nextView !== hashView) window.location.hash = nextView;
    };

    syncFromHash();
    window.addEventListener('hashchange', syncFromHash);
    return () => window.removeEventListener('hashchange', syncFromHash);
  }, [isPlatformAdminOrg, organizations, currentOrganization?.id, setCurrentOrganization, toast]);

  const handleViewChange = (view: DashboardView) => {
    const nextView = isPlatformAdminOrg && !PLATFORM_ADMIN_ALLOWED_VIEWS.includes(view) ? 'admin' : view;
    setCurrentView(nextView);
    setFocus(EMPTY_FOCUS);
    window.location.hash = nextView;
  };

  const renderContent = () => {
    switch (currentView) {
      case 'assets':
        // Facility Manager (9C.1): delegated mode. currentOrganization stays
        // the FM; the operated client comes from ?managedClient= validated
        // against get_my_facility_management_clients(), and RLS re-checks.
        if (currentOrganization?.organizationType === 'facility_manager') {
          return <DelegatedAssetsModule managedClientId={focus.managedClientId} focusAssetId={focus.assetId} />;
        }
        // Activos es un módulo de organizaciones cliente; platform_admin y
        // proveedores no operan activos en esta fase. Not normally
        // reachable via the sidebar (its "Activos" item only renders for
        // client_company orgs) — only via a stale/direct #assets hash.
        if (currentOrganization?.organizationType !== 'client_company') {
          return (
            <div className="flex h-full items-center justify-center p-6">
              <p className="text-sm text-muted-foreground">Los activos se administran desde una organización cliente.</p>
            </div>
          );
        }
        return <AssetsView focusAssetId={focus.assetId} />;
      case 'requests':
        if (user?.role === 'cliente') {
          return <RequestList focusRequestId={focus.requestId} focusQuoteId={focus.quoteId} />;
        }
        if (user?.role === 'team_member') {
          return <LegacyAssignmentsPlaceholder />;
        }
        // Provider side: only provider_company / subcontractor_company. A
        // facility_manager is mapped to the legacy 'proveedor' role but is
        // not provider-facing (Fase 1 · Punto 9B), even via a direct hash.
        if (!isProviderFacingOrganizationType(currentOrganization?.organizationType)) return <ProviderFacingAccessDenied />;
        return <ProviderRequestList focusRequestId={focus.requestId} focusQuoteId={focus.quoteId} />;
      case 'drafts':
        return <DraftList />;
      case 'public-requests':
        if (!isProviderFacingOrganizationType(currentOrganization?.organizationType)) return <ProviderFacingAccessDenied />;
        return <PublicRequestList />;
      case 'profile':
        return <OrganizationProfile />;
      case 'notifications':
        return <NotificationList />;
      case 'contact':
        return <ContactList />;
      case 'approved-providers':
        // Proveedores Homologados solo tiene sentido en contexto de una
        // organización client_company (es quien homologa proveedores) — no
        // solo user.role='cliente', también accesible por hash directo.
        if (currentOrganization?.organizationType !== 'client_company') {
          return (
            <div className="flex h-full items-center justify-center p-6">
              <p className="text-sm text-muted-foreground">Esta vista solo está disponible para organizaciones cliente.</p>
            </div>
          );
        }
        return <ApprovedProvidersList />;
      case 'branches':
        return <BranchesList />;
      case 'work-orders':
        // A technician only ever sees their own assigned work — even via
        // direct hash navigation, never the organization's full list. The
        // same canonical #work-orders?workOrder=... link works for both:
        // Dashboard only decides which component renders it.
        if (isTechnicianRole) {
          return <TechnicianWorkView focusWorkOrderId={focus.workOrderId} focusActivityId={focus.activityId} />;
        }
        return <WorkOrdersList focusWorkOrderId={focus.workOrderId} focusActivityId={focus.activityId} />;
      case 'my-work-orders':
        return <TechnicianWorkView focusWorkOrderId={focus.workOrderId} focusActivityId={focus.activityId} />;
      case 'inventory':
        return <InventoryView />;
      case 'efficiency':
        return <EfficiencyDashboard />;
      case 'criticality':
        if (currentOrganization?.organizationType === 'facility_manager') {
          return <DelegatedCriticalityModule managedClientId={focus.managedClientId} />;
        }
        return <CriticalityMatrixView />;
      case 'inspections':
        return <InspectionsView focusPlanId={focus.inspectionPlanId} focusRunId={focus.inspectionRunId} />;
      case 'preventive-maintenance':
        return <PreventiveMaintenanceView focusPlanId={focus.preventivePlanId} focusOccurrenceId={focus.preventiveOccurrenceId} focusAssetId={focus.preventiveAssetId} />;
      case 'backlog':
        // BacklogView se defiende sola de un #backlog directo desde una
        // organización que no es cliente; el gating del sidebar nunca es la
        // autorización.
        return <BacklogView focusNoticeId={focus.noticeId} />;
      case 'admin': return <AdminConsole />;
      case 'users':
        // Sidebar ya oculta este ítem fuera de owner/admin de una
        // organización no platform_admin; el gate real vive en el
        // servidor (list_organization_access/update_organization_member).
        return <div className="p-6"><OrganizationUsersView /></div>;
      case 'facility-management':
        // Gate real para #facility-management directo (no solo ocultar el
        // ítem del Sidebar); las RPCs 9A/9B vuelven a autorizar en el servidor.
        if (!getFacilityManagementMode(currentOrganization, currentMembership)) return <FacilityManagementAccessDenied />;
        return <FacilityManagementView />;
      default:
        // Real dashboard — see docs/REAL_DASHBOARD_METRICS.md.
        // DashboardMetricsCards gates itself to owner/admin/manager (same
        // as the RPC it calls); TrafficLightSummaryCard is visible to any
        // active member including technician (per the previous phase).
        // platform_admin orgs never reach this case (forced to 'admin'
        // above); technician sees TrafficLightSummaryCard but not the
        // organization-wide metrics cards.
        return (
          <div className="space-y-6 p-6">
            <TrafficLightSummaryCard />
            <PreventiveMaintenanceSummaryCard />
            <DashboardMetricsCards />
          </div>
        );
    }
  };

  return (
    <div className="flex h-screen bg-background">
      <Sidebar onViewChange={handleViewChange} currentView={currentView} userRole={user?.role} />
      <main className="flex-1 overflow-auto">
        {renderContent()}
      </main>
    </div>
  );
};

const ProviderFacingAccessDenied = () => (
  <div className="flex h-full items-center justify-center p-6">
    <p className="text-sm text-muted-foreground">
      Esta vista solo está disponible para organizaciones proveedoras o subcontratistas.
    </p>
  </div>
);

const LegacyAssignmentsPlaceholder = () => (
  <div className="p-6">
    <div className="rounded-lg border bg-card p-8 text-center">
      <h2 className="text-xl font-semibold mb-2">Asignación pendiente</h2>
      <p className="text-muted-foreground">
        El flujo de asignaciones está pendiente de migración tenant-aware.
      </p>
    </div>
  </div>
);

export default Dashboard;
