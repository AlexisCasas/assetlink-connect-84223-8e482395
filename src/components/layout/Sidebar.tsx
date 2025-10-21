import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { useAuth, UserRole } from '@/contexts/AuthContext';
import { 
  LayoutDashboard,
  Package,
  FileText,
  ChevronLeft,
  ChevronRight,
  LogOut,
  AlertCircle
} from 'lucide-react';

interface SidebarProps {
  className?: string;
  onViewChange?: (view: 'dashboard' | 'assets' | 'requests' | 'drafts') => void;
  currentView?: string;
  userRole?: UserRole;
}

export function Sidebar({ className, onViewChange, currentView = 'dashboard', userRole }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const { user, logout } = useAuth();

  return (
    <div className={cn(
      "flex flex-col bg-card border-r border-border transition-all duration-300",
      collapsed ? "w-16" : "w-64",
      className
    )}>
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-border">
        {!collapsed && (
          <div className="flex items-center space-x-2">
            <Package className="h-8 w-8 text-primary" />
            <span className="text-xl font-bold text-foreground">One Facility</span>
          </div>
        )}
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setCollapsed(!collapsed)}
          className="h-8 w-8 p-0"
        >
          {collapsed ? (
            <ChevronRight className="h-4 w-4" />
          ) : (
            <ChevronLeft className="h-4 w-4" />
          )}
        </Button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-4 space-y-2">
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
          </>
        )}

        {userRole === 'proveedor' && (
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
            {!collapsed && 'Nuevas solicitudes'}
          </Button>
        )}

        {userRole === 'team_member' && (
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
      </nav>

      {/* User Profile */}
      <div className="p-4 border-t border-border space-y-2">
        <div className={cn(
          "flex items-center space-x-3",
          collapsed && "justify-center"
        )}>
          <div className="h-8 w-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-medium">
            {user?.name?.[0]?.toUpperCase() || 'U'}
          </div>
          {!collapsed && (
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground">{user?.name || user?.email}</p>
              <p className="text-xs text-muted-foreground capitalize">{user?.role}</p>
            </div>
          )}
        </div>
        {!collapsed && (
          <Button
            variant="outline"
            size="sm"
            className="w-full"
            onClick={logout}
          >
            <LogOut className="h-4 w-4 mr-2" />
            Cerrar Sesión
          </Button>
        )}
      </div>
    </div>
  );
}
