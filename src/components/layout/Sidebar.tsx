import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { useAuth, UserRole } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
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
  MessageSquare
} from 'lucide-react';

interface SidebarProps {
  className?: string;
  onViewChange?: (view: 'dashboard' | 'assets' | 'requests' | 'drafts' | 'public-requests' | 'profile' | 'notifications' | 'contact') => void;
  currentView?: string;
  userRole?: UserRole;
}

export function Sidebar({ className, onViewChange, currentView = 'dashboard', userRole }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const [unreadContactCount, setUnreadContactCount] = useState(0);
  const { user, logout } = useAuth();

  useEffect(() => {
    if (user?.email) {
      loadUnreadCount();
      loadUnreadContactCount();
    }
  }, [user]);

  const loadUnreadCount = async () => {
    try {
      const { count } = await supabase
        .from('notifications')
        .select('*', { count: 'exact', head: true })
        .eq('user_email', user?.email)
        .eq('read', false);

      setUnreadCount(count || 0);
    } catch (error) {
      console.error('Error loading unread count:', error);
    }
  };

  const loadUnreadContactCount = async () => {
    try {
      const { data: participations } = await supabase
        .from('request_chat_participants')
        .select('request_id, last_read_at')
        .eq('user_email', user?.email);

      if (!participations || participations.length === 0) {
        setUnreadContactCount(0);
        return;
      }

      let totalUnread = 0;
      for (const chat of participations) {
        const { count } = await supabase
          .from('chat_messages')
          .select('*', { count: 'exact', head: true })
          .eq('request_id', chat.request_id)
          .neq('sender_email', user?.email)
          .gt('created_at', chat.last_read_at || '1970-01-01');
        
        totalUnread += count || 0;
      }
      
      setUnreadContactCount(totalUnread);
    } catch (error) {
      console.error('Error loading unread contact count:', error);
    }
  };

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
              {!collapsed && 'Mi Perfil'}
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
          variant={currentView === 'contact' ? "default" : "ghost"}
          className={cn(
            "w-full justify-start",
            collapsed && "justify-center px-2"
          )}
          onClick={() => onViewChange?.('contact')}
        >
          <MessageSquare className={cn(
            "h-4 w-4",
            !collapsed && "mr-2"
          )} />
          {!collapsed && (
            <>
              <span>Contacto</span>
              {unreadContactCount > 0 && (
                <Badge variant="destructive" className="ml-auto">
                  {unreadContactCount}
                </Badge>
              )}
            </>
          )}
          {collapsed && unreadContactCount > 0 && (
            <Badge variant="destructive" className="absolute top-1 right-1 h-2 w-2 p-0" />
          )}
        </Button>
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
