import { useState, useEffect } from 'react';
import { Sidebar } from '@/components/layout/Sidebar';
import { AssetTree } from '@/components/assets/AssetTree';
import { AssetDetail } from '@/components/assets/AssetDetail';
import { TicketList } from '@/components/tickets/TicketList';
import { StatsCards } from '@/components/dashboard/StatsCards';

interface AssetNode {
  id: string;
  name: string;
  type: 'society' | 'company' | 'asset_class' | 'asset' | 'sub_asset';
  children?: AssetNode[];
  status?: 'active' | 'maintenance' | 'inactive';
}

const Index = () => {
  const [selectedAsset, setSelectedAsset] = useState<AssetNode | null>(null);
  const [currentView, setCurrentView] = useState<string>('dashboard');

  // Listen to hash changes for navigation
  useEffect(() => {
    const handleHashChange = () => {
      const hash = window.location.hash.replace('#', '');
      setCurrentView(hash || 'dashboard');
    };

    window.addEventListener('hashchange', handleHashChange);
    handleHashChange(); // Initial load

    return () => window.removeEventListener('hashchange', handleHashChange);
  }, []);

  const handleSelectAsset = (asset: AssetNode) => {
    setSelectedAsset(asset);
  };

  const renderContent = () => {
    switch (currentView) {
      case 'assets':
        return (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 h-full">
            <AssetTree onSelectAsset={handleSelectAsset} />
            <AssetDetail asset={selectedAsset} />
          </div>
        );
      case 'tickets':
        return <TicketList />;
      default:
        return (
          <div className="space-y-6">
            <div>
              <h1 className="text-3xl font-bold text-foreground mb-2">Dashboard de Mantenimiento</h1>
              <p className="text-muted-foreground">
                Gestiona tus activos, tickets y proveedores desde un solo lugar
              </p>
            </div>
            <StatsCards />
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <AssetTree onSelectAsset={handleSelectAsset} />
              <TicketList />
            </div>
          </div>
        );
    }
  };

  return (
    <div className="flex h-screen bg-background">
      <Sidebar />
      <main className="flex-1 overflow-auto">
        <div className="p-6 h-full">
          {renderContent()}
        </div>
      </main>
    </div>
  );
};

export default Index;
