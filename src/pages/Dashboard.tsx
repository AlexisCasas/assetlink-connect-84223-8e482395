import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { Sidebar } from '@/components/layout/Sidebar';
import { AssetTree, AssetNode } from '@/components/assets/AssetTree';
import { AssetDetail } from '@/components/assets/AssetDetail';
import { TicketList } from '@/components/tickets/TicketList';
import { StatsCards } from '@/components/dashboard/StatsCards';

const Dashboard = () => {
  const { user } = useAuth();
  const [currentView, setCurrentView] = useState<'dashboard' | 'assets' | 'tickets' | 'requests'>('dashboard');
  const [selectedAsset, setSelectedAsset] = useState<AssetNode | null>(null);

  useEffect(() => {
    const hash = window.location.hash.replace('#', '');
    if (hash === 'assets' || hash === 'tickets' || hash === 'requests') {
      setCurrentView(hash as any);
    }
  }, []);

  const handleViewChange = (view: 'dashboard' | 'assets' | 'tickets' | 'requests') => {
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
      case 'tickets':
        return <TicketList />;
      case 'requests':
        if (user?.role === 'cliente') {
          return (
            <div className="p-6">
              <h2 className="text-2xl font-bold mb-4">Mis Solicitudes</h2>
              <p className="text-muted-foreground">Panel de solicitudes para clientes - En construcción</p>
            </div>
          );
        }
        return (
          <div className="p-6">
            <h2 className="text-2xl font-bold mb-4">Solicitudes Recibidas</h2>
            <p className="text-muted-foreground">Panel de solicitudes para proveedores - En construcción</p>
          </div>
        );
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
