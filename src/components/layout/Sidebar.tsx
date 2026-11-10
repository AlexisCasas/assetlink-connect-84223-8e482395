import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { useAuth, UserRole } from '@/contexts/AuthContext';
import { OrganizationSwitcher } from '@/components/organization/OrganizationSwitcher';
import { NotificationBell } from '@/components/notifications/NotificationBell';
import { useOrganizationNotifications } from '@/hooks/useOrganizationNotifications';
import { ORGANIZATION_ROLE_LABELS } from '@/lib/organizationRoles';
import { FACILITY_MANAGEMENT_NAV_LABELS, getFacilityManagementMode } from '@/lib/facilityManagement';
import { isProviderFacingOrganizationType } from '@/types/providerRelationship';
import { useFacilityManagementOperationalClients } from '@/hooks/useFacilityManagementOperationalClients';
import { canFacilityManagerCreateRequests, canFacilityManagerViewAssets, canFacilityManagerViewCriticality, canFacilityManagerViewInspections, canFacilityManagerViewMaintenanceNotices, canFacilityManagerViewPreventive, canFacilityManagerViewRequests, canFacilityManagerViewWorkOrders } from '@/lib/facilityManagement';
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
  ClipboardList,
  Boxes,
  Wrench,
  BarChart3,
  Gauge,
  ClipboardCheck
  ,CalendarClock
  ,Shield
  ,AlertTriangle
  ,Briefcase
} from 'lucide-react';

interface SidebarProps {
  className?: string;
  onViewChange?: (view: 'dashboard' | 'assets' | 'requests' | 'drafts' | 'public-requests' | 'profile' | 'notifications' | 'contact' | 'approved-providers' | 'branches' | 'work-orders' | 'managed-work-orders' | 'my-work-orders' | 'inventory' | 'efficiency' | 'criticality' | 'inspections' | 'preventive-maintenance' | 'backlog' | 'admin' | 'users' | 'facility-management') => void;
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

export function Sidebar({ className, onViewChange, currentView = 'dashboard', userRole }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const { user, logout, currentOrganization, currentMembership, memberships, organizations } = useAuth();
  const { unreadCount } = useOrganizationNotifications(1);
  const visualRole = currentOrganization
    ? `${organizationTypeLabels[currentOrganization.organizationType]}${currentMembership ? ` · ${ORGANIZATION_ROLE_LABELS[currentMembership.role]}` : ''}`
    : 'Sin organizacion asignada';
  const isPlatformAdminOrg = currentOrganization?.organizationType === 'platform_admin';
  const isOperatingOrg = currentOrganization !== null && !isPlatformAdminOrg && [
    'client_company',
    'provider_company',
    'facility_manager',
  ].includes(currentOrganization.organizationType);
  const isTechnicianRole = !!currentMembership?.isActive && currentMembership.role === 'technician';
  // A technician gets their own filtered "Mis órdenes" instead of the
  // general "Órdenes de trabajo" list — showing both would let them just
  // click the general one and see the whole organization's work, defeating
  // the point of a technician-scoped view. Every other role on an
  // operating organization keeps "Órdenes de trabajo" unchanged.
  const canViewWorkOrders = isOperatingOrg && !isTechnicianRole;
  const canViewMyWorkOrders = isOperatingOrg && isTechnicianRole;
  const canManage = memberships.some(m => m.isActive && ['owner','admin'].includes(m.role) && organizations.some(o => o.id === m.organizationId && o.organizationType === 'platform_admin'));
  const canViewAssets = currentOrganization?.organizationType === 'client_company';
  // Inventory belongs to the organization that operates work (same set as
  // isOperatingOrg — client/provider/facility_manager, never
  // platform_admin), and only to its planners (owner/admin/manager): they
  // are the ones who create warehouses/materials and assign them to OTs.
  const canViewInventory = isOperatingOrg && !!currentMembership?.isActive && ['owner', 'admin', 'manager'].includes(currentMembership.role);
  // Eficiencia is operational analytics over the organization's own work
  // orders: same owner/admin/manager-of-an-operating-org gate as inventory,
  // and deliberately never shown to a technician (no cross-technician
  // comparison surface) nor to a platform_admin org (no operating-org
  // context to scope it to).
  const canViewEfficiency = isOperatingOrg && !!currentMembership?.isActive && ['owner', 'admin', 'manager'].includes(currentMembership.role);
  // Criticidad configures the matrix behind assets.criticality, and assets
  // only ever belong to client_company organizations in this codebase
  // (same scope as canViewAssets, not the broader isOperatingOrg used by
  // work-order-centric modules) — provider/facility_manager orgs have no
  // assets to evaluate. Same owner/admin/manager gate as inventory/efficiency.
  const canViewCriticality = canViewAssets && !!currentMembership?.isActive && ['owner', 'admin', 'manager'].includes(currentMembership.role);
  // Inspecciones hangs off activos/sedes, so same client_company-only scope
  // as Activos/Criticidad — but unlike those, technician IS included here:
  // a technician needs to see and execute their own assigned inspections,
  // even though they cannot edit templates/plans (gated inside
  // InspectionsView itself via canPlanWork, not at the nav level).
  const canViewInspections = canViewAssets && !!currentMembership?.isActive && ['owner', 'admin', 'manager', 'technician'].includes(currentMembership.role);
  const canViewPreventiveMaintenance = canViewAssets && !!currentMembership?.isActive;
  // El backlog de avisos es del cliente dueño de los activos, igual que
  // Activos/Criticidad/Inspecciones. Se muestra a todo el que puede
  // REPORTAR (incluidos technician y requester); quien solo puede leer ve
  // los avisos pero sin acciones, y las de gestión las vuelve a validar el
  // backend. Ocultar el ítem nunca es la autorización.
  const canViewBacklog = canViewAssets && !!currentMembership?.isActive && ['owner', 'admin', 'manager', 'technician', 'requester'].includes(currentMembership.role);
  // Fase 1 · Punto 6B: "Usuarios" es la gestión productiva de la propia
  // organización (invitar, roles, reenviar/cancelar invitaciones) — nunca
  // se muestra en el tenant platform_admin, que usa Administración
  // (AdminConsole) para gestionar OTRAS organizaciones. Solo owner/admin:
  // el mismo gate que ya protege list_organization_access/
  // update_organization_member en el servidor, replicado aquí solo para no
  // mostrar un botón que el backend rechazaría.
  const canViewUsers = !isPlatformAdminOrg && !!currentMembership?.isActive && ['owner', 'admin'].includes(currentMembership.role);
  // Fase 1 · Punto 9B: owner/admin de un cliente ("Facility Managers") o de
  // un Facility Manager ("Clientes administrados"). Mismo destino, distinta
  // variante; Dashboard aplica el mismo gate para #facility-management
  // directo y las RPCs vuelven a autorizar en el servidor.
  const facilityManagementMode = getFacilityManagementMode(currentOrganization, currentMembership);
  // Provider request list + public marketplace: only provider_company /
  // subcontractor_company. userRole === 'proveedor' alone is not enough —
  // AuthContext still maps facility_manager to it for legacy compatibility.
  const isProviderMarketplaceOrg = isProviderFacingOrganizationType(currentOrganization?.organizationType);
  // Fase 1 · Punto 9C.1: delegated operation for a facility_manager org —
  // only when at least one OPERATIONAL client (assigned + active) grants the
  // permission AND the user's FM role allows it. Never just because a
  // relationship exists. UX only: Dashboard/RLS re-check.
  const { clients: operationalClients } = useFacilityManagementOperationalClients();
  const canViewDelegatedAssets = operationalClients.some(canFacilityManagerViewAssets);
  const canViewDelegatedCriticality = operationalClients.some(canFacilityManagerViewCriticality);
  const canViewDelegatedInspections = operationalClients.some(canFacilityManagerViewInspections);
  const canViewDelegatedPreventive = operationalClients.some(canFacilityManagerViewPreventive);
  const canViewDelegatedBacklog = operationalClients.some(canFacilityManagerViewMaintenanceNotices);
  const canViewDelegatedRequests = operationalClients.some(canFacilityManagerViewRequests);
  const canViewDelegatedDrafts = operationalClients.some(canFacilityManagerCreateRequests);
  const canViewDelegatedWorkOrders = operationalClients.some(canFacilityManagerViewWorkOrders);

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
        {!isPlatformAdminOrg && (
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
        )}

        {canManage && <Button variant={currentView === 'admin' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('admin')}><Shield className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Administración'}</Button>}

        {canViewUsers && <Button variant={currentView === 'users' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('users')}><Users className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Usuarios'}</Button>}

        {facilityManagementMode && <Button variant={currentView === 'facility-management' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('facility-management')}><Briefcase className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && FACILITY_MANAGEMENT_NAV_LABELS[facilityManagementMode]}</Button>}

        {canViewDelegatedAssets && <Button variant={currentView === 'assets' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('assets')}><Package className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Activos de clientes'}</Button>}

        {canViewDelegatedCriticality && <Button variant={currentView === 'criticality' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('criticality')}><Gauge className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Criticidad de clientes'}</Button>}

        {canViewDelegatedInspections && <Button variant={currentView === 'inspections' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('inspections')}><ClipboardCheck className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Inspecciones de clientes'}</Button>}

        {canViewDelegatedPreventive && <Button variant={currentView === 'preventive-maintenance' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('preventive-maintenance')}><CalendarClock className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Preventivo de clientes'}</Button>}

        {canViewDelegatedBacklog && <Button variant={currentView === 'backlog' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('backlog')}><AlertTriangle className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Backlog de clientes'}</Button>}

        {canViewDelegatedRequests && <Button variant={currentView === 'requests' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('requests')}><FileText className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Solicitudes de clientes'}</Button>}

        {canViewDelegatedDrafts && <Button variant={currentView === 'drafts' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('drafts')}><AlertCircle className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Borradores de clientes'}</Button>}

        {canViewDelegatedWorkOrders && <Button variant={currentView === 'managed-work-orders' ? 'default' : 'ghost'} className={cn('w-full justify-start', collapsed && 'justify-center px-2')} onClick={() => onViewChange?.('managed-work-orders')}><ClipboardList className={cn('h-4 w-4', !collapsed && 'mr-2')} />{!collapsed && 'Órdenes de clientes'}</Button>}

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

        {canViewMyWorkOrders && (
          <Button
            variant={currentView === 'my-work-orders' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('my-work-orders')}
          >
            <Wrench className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Mis órdenes'}
          </Button>
        )}

        {canViewInventory && (
          <Button
            variant={currentView === 'inventory' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('inventory')}
          >
            <Boxes className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Inventario'}
          </Button>
        )}

        {canViewEfficiency && (
          <Button
            variant={currentView === 'efficiency' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('efficiency')}
          >
            <BarChart3 className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Eficiencia'}
          </Button>
        )}

        {canViewAssets && (
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

        {canViewCriticality && (
          <Button
            variant={currentView === 'criticality' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('criticality')}
          >
            <Gauge className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Criticidad'}
          </Button>
        )}

        {canViewInspections && (
          <Button
            variant={currentView === 'inspections' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('inspections')}
          >
            <ClipboardCheck className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Inspecciones'}
          </Button>
        )}

        {canViewPreventiveMaintenance && (
          <Button
            variant={currentView === 'preventive-maintenance' ? "default" : "ghost"}
            className={cn("w-full justify-start", collapsed && "justify-center px-2")}
            onClick={() => onViewChange?.('preventive-maintenance')}
          >
            <CalendarClock className={cn("h-4 w-4", !collapsed && "mr-2")} />
            {!collapsed && 'Mantenimiento preventivo'}
          </Button>
        )}

        {canViewBacklog && (
          <Button
            variant={currentView === 'backlog' ? "default" : "ghost"}
            className={cn(
              "w-full justify-start",
              collapsed && "justify-center px-2"
            )}
            onClick={() => onViewChange?.('backlog')}
          >
            <AlertTriangle className={cn(
              "h-4 w-4",
              !collapsed && "mr-2"
            )} />
            {!collapsed && 'Backlog'}
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
            {isProviderMarketplaceOrg && (
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
            </>
            )}
            
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
            {!isPlatformAdminOrg && (
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
            )}

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
