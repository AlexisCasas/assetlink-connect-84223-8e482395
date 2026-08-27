import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { AssetsView } from '@/components/assets/AssetsView';
import { RequestList } from '@/components/requests/RequestList';
import { DraftList } from '@/components/requests/DraftList';
import { ProviderRequestList } from '@/components/requests/ProviderRequestList';
import { StatsCards } from '@/components/dashboard/StatsCards';
import { OrganizationProfile } from '@/components/organization/OrganizationProfile';
import { PublicRequestList } from '@/components/requests/PublicRequestList';
import { NotificationList } from '@/components/notifications/NotificationList';
import { ContactList } from '@/components/contact/ContactList';
import { ApprovedProvidersList } from '@/components/providers/ApprovedProvidersList';
import { BranchesList } from '@/components/branches/BranchesList';
import { WorkOrdersList } from '@/components/work-orders/WorkOrdersList';
import { InventoryView } from '@/components/inventory/InventoryView';
import { AdminConsole } from '@/components/admin/AdminConsole';

type DashboardView = 'dashboard' | 'assets' | 'requests' | 'drafts' | 'public-requests' | 'profile' | 'notifications' | 'contact' | 'approved-providers' | 'branches' | 'work-orders' | 'inventory' | 'admin';

const ALL_VIEWS: DashboardView[] = ['dashboard', 'assets', 'requests', 'drafts', 'public-requests', 'profile', 'notifications', 'approved-providers', 'branches', 'work-orders', 'inventory', 'contact', 'admin'];
// A platform_admin organization only manages Administración; every other
// operational view falls back to it, including direct hash navigation.
const PLATFORM_ADMIN_ALLOWED_VIEWS: DashboardView[] = ['admin', 'notifications'];

const Dashboard = () => {
  const { user, currentOrganization } = useAuth();
  const isPlatformAdminOrg = currentOrganization?.organizationType === 'platform_admin';
  const [currentView, setCurrentView] = useState<DashboardView>(isPlatformAdminOrg ? 'admin' : 'dashboard');

  useEffect(() => {
    const hash = window.location.hash.replace('#', '');
    const hashView = ALL_VIEWS.includes(hash as DashboardView) ? (hash as DashboardView) : null;

    if (isPlatformAdminOrg) {
      const nextView = hashView && PLATFORM_ADMIN_ALLOWED_VIEWS.includes(hashView) ? hashView : 'admin';
      setCurrentView(nextView);
      if (hash !== nextView) window.location.hash = nextView;
      return;
    }

    if (hashView) setCurrentView(hashView);
  }, [isPlatformAdminOrg]);

  const handleViewChange = (view: DashboardView) => {
    const nextView = isPlatformAdminOrg && !PLATFORM_ADMIN_ALLOWED_VIEWS.includes(view) ? 'admin' : view;
    setCurrentView(nextView);
    window.location.hash = nextView;
  };

  const renderContent = () => {
    switch (currentView) {
      case 'assets':
        // Activos es un módulo de organizaciones cliente; platform_admin y
        // proveedores no operan activos en esta fase.
        if (currentOrganization?.organizationType !== 'client_company') {
          return <StatsCards />;
        }
        return <AssetsView />;
      case 'requests':
        if (user?.role === 'cliente') {
          return <RequestList />;
        }
        if (user?.role === 'team_member') {
          return <LegacyAssignmentsPlaceholder />;
        }
        return <ProviderRequestList />;
      case 'drafts':
        return <DraftList />;
      case 'public-requests':
        return <PublicRequestList />;
      case 'profile':
        return <OrganizationProfile />;
      case 'notifications':
        return <NotificationList />;
      case 'contact':
        return <ContactList />;
      case 'approved-providers':
        return <ApprovedProvidersList />;
      case 'branches':
        return <BranchesList />;
      case 'work-orders':
        return <WorkOrdersList />;
      case 'inventory':
        return <InventoryView />;
      case 'admin': return <AdminConsole />;
      default:
        return <StatsCards />;
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
