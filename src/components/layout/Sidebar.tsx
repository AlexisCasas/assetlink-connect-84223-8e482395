import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { useAuth, UserRole } from '@/contexts/AuthContext';
import { OrganizationSwitcher } from '@/components/organization/OrganizationSwitcher';
import { NotificationBell } from '@/components/notifications/NotificationBell';
import { useOrganizationNotifications } from '@/hooks/useOrganizationNotifications';
import { 
  LayoutDashboard,
  Package,
  FileText,
  ChevronLeft,
  ChevronRight,
  LogOut,
  AlertCircle,
  Settings,
  Globe,
  Bell,
  MessageSquare,
  Users,
  Building2,
  ClipboardList
  ,Shield
} from 'lucide-react';

interface SidebarProps {
  className?: string;
  onViewChange?: (view: 'dashboard' | 'assets' | 'requests' | 'drafts' | 'public-requests' | 'profile' | 'notifications' | 'contact' | 'approved-providers' | 'branches' | 'work-orders' | 'admin') => void;
  currentView?: string;
  userRole?: UserRole;
}

const organizationTypeLabels = {
  client_company: 'Cliente',
  provider_company: 'Proveedor',
  facility_manager: 'Facility Manager',
  subcontractor_company: 'Subcontratista',
  platform_admin: 'Administrador',
} as const;

const membershipRoleLabels = {
  owner: 'Propietario',
  admin: 'Administrador',
  manager: 'Gestor',
  requester: 'Solicitante',
  quote_manager: 'Cotizador',
  technician: 'Tecnico',
  operator: 'Operador',
  viewer: 'Lector',
} as const;

export function Sidebar({ className, onViewChange, currentView = 'dashboard', userRole }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const { user, logout, currentOrganization, currentMembership, memberships, organizations } = useAuth();
  const { unreadCount } = useOrganizationNotifications(1);
  const visualRole = currentOrganization
    ? `${organizationTypeLabels[currentOrganization.organizationType]}${currentMembership ? ` · ${membershipRoleLabels[currentMembership.role]}` : ''}`
    : 'Sin organizacion asignada';
  const canViewWorkOrders = currentOrganization !== null && [
    'client_company',
    'provider_company',
    'facility_manager',
    'platform_admin',
  ].includes(currentOrganization.organizationType);
  const canManage = memberships.some(m => m.isActive && ['owner','admin'].includes(m.role) && organizations.some(o => o.id === m.organizationId && o.organizationType === 'platform_admin'));

  return (
    <aside className={cn(
      "of-sidebar flex min-h-screen shrink-0 flex-col border-r border-white/10 bg-onefacility-navy text-white shadow-xl transition-all duration-300",
      collapsed ? "w-[72px]" : "w-72",
      className
    )}>
      {/* Header */}
      <div className={cn("relative flex h-[76px] items-center border-b border-white/10 px-3", collapsed ? "justify-center" : "justify-between")}>
        {!collapsed && (
          <div className="flex h-11 items-center rounded-xl bg-white px-3 shadow-soft">
            <img src="/brand/logo-primary.png" alt="OneFacility" className="h-7 w-auto" />
          </div>
        )}
        {collapsed && (
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white shadow-soft">
            <img src="/brand/isotipo-primary.png" alt="OneFacility" className="h-7 w-7 object-contain" />
          </div>
        )}
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setCollapsed(!collapsed)}
          className={cn("of-sidebar-action h-8 w-8 p-0", collapsed && "absolute left-[54px] top-6 z-10 rounded-full border border-white/15 bg-onefacility-navy shadow-md")}
          aria-label={collapsed ? 'Expandir navegación' : 'Colapsar navegación'}
        >
          {collapsed ? (
            <ChevronRight className="h-4 w-4" />
          ) : (
            <ChevronLeft className="h-4 w-4" />
          )}
        </Button>
      </div>

      <div className="of-sidebar-organization py-3">
        <OrganizationSwitcher collapsed={collapsed} />
      </div>
      <div className="of-sidebar-utility px-3 pb-3">
        <NotificationBell collapsed={collapsed} />
      </div>

      {/* Navigation */}
      <nav className="flex-1 space-y-1.5 overflow-y-auto px-3 pb-5">
        <Button
          variant={currentView === 'dashboard' ? "default" : "ghost"}
          className={cn(
            "w-full justify-start",
            collapsed && "justify-center px-2"
          )}
          onClick={() => onViewChange?.('dashboard')}
        >
          <LayoutDashboard className={cn(
            "h-4 w-4",
            !collapsed && "mr-2"
          )} />
          {!collapsed && 'Dashboard'}
        </Button>

        {canManage && <Button variant={currentView === 'admin' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('admin')}><Shield className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Administración'}</Button>}

        {canViewWorkOrders && (
          <Button
            variant={currentView === 'work-orders' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('work-orders')}
          >
            <ClipboardList className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Órdenes de trabajo'}
          </Button>
        )}
        
        {userRole === 'cliente' && (
          <Button
            variant={currentView === 'assets' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('assets')}
          >
            <Package className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Activos'}
          </Button>
        )}

        {userRole === 'cliente' && (
          <>
            <Button
              variant={currentView === 'requests' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('requests')}
            >
              <FileText className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && 'Mis solicitudes'}
            </Button>
            
            <Button
              variant={currentView === 'drafts' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('drafts')}
            >
              <AlertCircle className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && 'Borradores'}
            </Button>

            <Button
              variant={currentView === 'approved-providers' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('approved-providers')}
            >
              <Users className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && 'Proveedores Homologados'}
            </Button>

            <Button
              variant={currentView === 'branches' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('branches')}
            >
              <Building2 className={cn("h-4 w-4", !collapsed && "mr-2")} />
              {!collapsed && 'Sucursales'}
            </Button>

            <Button
              variant={currentView === 'notifications' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('notifications')}
            >
              <Bell className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && (
                <>
                  <span>Notificaciones</span>
                  {unreadCount > 0 && (
                    <Badge variant="destructive" className="ml-auto">
                      {unreadCount}
                    </Badge>
                  )}
                </>
              )}
              {collapsed && unreadCount > 0 && (
                <Badge variant="destructive" className="absolute top-1 right-1 h-2 w-2 p-0" />
              )}
            </Button>
          </>
        )}

        {userRole === 'proveedor' && (
          <>
            <Button
              variant={currentView === 'requests' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('requests')}
            >
              <FileText className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && 'Solicitudes'}
            </Button>
            
            <Button
              variant={currentView === 'public-requests' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('public-requests')}
            >
              <Globe className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && 'Solicitudes Públicas'}
            </Button>
            
            <Button
              variant={currentView === 'profile' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('profile')}
            >
              <Settings className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && 'Perfil organización'}
            </Button>

            <Button
              variant={currentView === 'notifications' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('notifications')}
            >
              <Bell className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && (
                <>
                  <span>Notificaciones</span>
                  {unreadCount > 0 && (
                    <Badge variant="destructive" className="ml-auto">
                      {unreadCount}
                    </Badge>
                  )}
                </>
              )}
              {collapsed && unreadCount > 0 && (
                <Badge variant="destructive" className="absolute top-1 right-1 h-2 w-2 p-0" />
              )}
            </Button>
          </>
        )}

        {userRole === 'team_member' && (
          <>
            <Button
              variant={currentView === 'requests' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('requests')}
            >
              <FileText className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && 'Mis Asignaciones'}
            </Button>

            <Button
              variant={currentView === 'notifications' ? "default" : "ghost"}
              className={cn(
                "w-full justify-start",
                collapsed && "justify-center px-2"
              )}
              onClick={() => onViewChange?.('notifications')}
            >
              <Bell className={cn(
                "h-4 w-4",
                !collapsed && "mr-2"
              )} />
              {!collapsed && (
                <>
                  <span>Notificaciones</span>
                  {unreadCount > 0 && (
                    <Badge variant="destructive" className="ml-auto">
                      {unreadCount}
                    </Badge>
                  )}
                </>
              )}
              {collapsed && unreadCount > 0 && (
                <Badge variant="destructive" className="absolute top-1 right-1 h-2 w-2 p-0" />
              )}
            </Button>
          </>
        )}
        
        <Button
          variant="ghost"
          className={cn(
            "w-full justify-start",
            collapsed && "justify-center px-2"
          )}
          disabled
          title="Chat pendiente de migracion tenant-aware"
        >
          <MessageSquare className={cn(
            "h-4 w-4",
            !collapsed && "mr-2"
          )} />
          {!collapsed && (
            <>
              <span>Chat pendiente</span>
            </>
          )}
        </Button>
      </nav>

      {/* User Profile */}
      <div className="space-y-3 border-t border-white/10 bg-black/10 p-3">
        <div className={cn(
          "flex items-center gap-3 rounded-xl bg-white/[0.06] p-2.5",
          collapsed && "justify-center"
        )}>
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-onefacility-blue text-sm font-semibold text-white ring-2 ring-white/15">
            {user?.name?.[0]?.toUpperCase() || 'U'}
          </div>
          {!collapsed && (
            <div className="flex-1 min-w-0">
              <p className="truncate text-sm font-medium text-white">{user?.name || user?.email}</p>
              <p className="truncate text-xs text-white/55">{visualRole}</p>
            </div>
          )}
        </div>
        {!collapsed && (
          <Button
            variant="ghost"
            size="sm"
            className="of-sidebar-action w-full border border-white/10 bg-white/[0.04] text-white/80 hover:text-white"
            onClick={logout}
          >
            <LogOut className="h-4 w-4 mr-2" />
            Cerrar Sesión
          </Button>
        )}
      </div>
    </aside>
  );
}
