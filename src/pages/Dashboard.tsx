import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { AssetTree, AssetNode } from '@/components/assets/AssetTree';
import { AssetDetail } from '@/components/assets/AssetDetail';
import { RequestList } from '@/components/requests/RequestList';
import { DraftList } from '@/components/requests/DraftList';
import { ProviderRequestList } from '@/components/requests/ProviderRequestList';
import { TeamMemberView } from '@/components/requests/TeamMemberView';
import { StatsCards } from '@/components/dashboard/StatsCards';

const Dashboard = () => {
  const { user } = useAuth();
  const [currentView, setCurrentView] = useState<'dashboard' | 'assets' | 'requests' | 'drafts'>('dashboard');
  const [selectedAsset, setSelectedAsset] = useState<AssetNode | null>(null);

  useEffect(() => {
    const hash = window.location.hash.replace('#', '');
    if (hash === 'assets' || hash === 'requests' || hash === 'drafts') {
      setCurrentView(hash as any);
    }
  }, []);

  const handleViewChange = (view: 'dashboard' | 'assets' | 'requests' | 'drafts') => {
    setCurrentView(view);
    window.location.hash = view;
  };

  const renderContent = () => {
    switch (currentView) {
      case 'assets':
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
          return <TeamMemberView />;
        }
        return <ProviderRequestList />;
      case 'drafts':
        return <DraftList />;
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

export default Dashboard;
