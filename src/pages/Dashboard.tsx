import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { AssetTree, AssetNode } from '@/components/assets/AssetTree';
import { AssetDetail } from '@/components/assets/AssetDetail';
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
import { AdminConsole } from '@/components/admin/AdminConsole';

const Dashboard = () => {
  const { user } = useAuth();
  const [currentView, setCurrentView] = useState<'dashboard' | 'assets' | 'requests' | 'drafts' | 'public-requests' | 'profile' | 'notifications' | 'contact' | 'approved-providers' | 'branches' | 'work-orders' | 'admin'>('dashboard');
  const [selectedAsset, setSelectedAsset] = useState<AssetNode | null>(null);

  useEffect(() => {
    const hash = window.location.hash.replace('#', '');
    if (['assets','requests','drafts','public-requests','profile','notifications','approved-providers','branches','work-orders','contact','admin'].includes(hash)) {
      setCurrentView(hash as any);
    }
  }, []);

  const handleViewChange = (view: 'dashboard' | 'assets' | 'requests' | 'drafts' | 'public-requests' | 'profile' | 'notifications' | 'contact' | 'approved-providers' | 'branches' | 'work-orders' | 'admin') => {
    setCurrentView(view);
    window.location.hash = view;
  };

  const renderContent = () => {
    switch (currentView) {
      case 'assets':
        // Solo mostrar activos para clientes
        if (user?.role !== 'cliente') {
          return <StatsCards />;
        }
        return (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 h-full">
            <AssetTree onAssetSelect={setSelectedAsset} />
            <AssetDetail asset={selectedAsset} />
          </div>
        );
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
