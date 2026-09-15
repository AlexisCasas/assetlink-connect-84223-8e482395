import { Bell, CheckCheck } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';
import { useOrganizationNotifications } from '@/hooks/useOrganizationNotifications';
import { NOTIFICATION_PRIORITY_COLORS, NOTIFICATION_PRIORITY_LABELS, notificationEntityReference } from '@/lib/notificationLabels';
import { handleNotificationNavigation } from '@/lib/entityNavigation';

interface NotificationBellProps {
  collapsed?: boolean;
}

export function NotificationBell({ collapsed = false }: NotificationBellProps) {
  const {
    notifications,
    unreadCount,
    loadNotifications,
    markAsRead,
    markAllAsRead,
  } = useOrganizationNotifications(8);

  return (
    <DropdownMenu onOpenChange={(open) => open && void loadNotifications()}>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          className={cn('relative w-full justify-start', collapsed && 'justify-center px-2')}
          aria-label="Notificaciones de la organizacion"
        >
          <Bell className={cn('h-4 w-4', !collapsed && 'mr-2')} />
          {!collapsed && <span>Notificaciones</span>}
          {unreadCount > 0 && (
            <Badge
              variant="destructive"
              className={cn(collapsed ? 'absolute right-1 top-1 h-2 w-2 p-0' : 'ml-auto')}
            >
              {!collapsed && unreadCount}
            </Badge>
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-80">
        <div className="flex items-center justify-between px-2 py-1.5">
          <DropdownMenuLabel className="p-0">Notificaciones</DropdownMenuLabel>
          {unreadCount > 0 && (
            <Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={() => void markAllAsRead()}>
              <CheckCheck className="mr-1 h-3.5 w-3.5" />
              Marcar leidas
            </Button>
          )}
        </div>
        <DropdownMenuSeparator />
        {notifications.length === 0 ? (
          <p className="px-2 py-6 text-center text-sm text-muted-foreground">
            No hay notificaciones para esta organizacion.
          </p>
        ) : notifications.map((notification) => {
          const reference = notificationEntityReference(notification.entity_type, notification.metadata);
          return (
            <DropdownMenuItem
              key={notification.id}
              className="flex cursor-pointer flex-col items-start gap-1 whitespace-normal py-2"
              onSelect={() => {
                // The dropdown closes immediately (default Radix behavior);
                // handleNotificationNavigation keeps running afterwards —
                // it only ever touches window.location.hash and Supabase,
                // neither of which depends on this menu still being mounted.
                void handleNotificationNavigation(notification, markAsRead);
              }}
            >
              <div className="flex w-full items-center gap-2">
                <span className={cn('font-medium', !notification.is_read && 'text-primary')}>
                  {notification.title}
                </span>
                <Badge variant="outline" className={cn('text-[10px]', NOTIFICATION_PRIORITY_COLORS[notification.priority])}>
                  {NOTIFICATION_PRIORITY_LABELS[notification.priority] ?? notification.priority}
                </Badge>
                {!notification.is_read && <Badge className="ml-auto text-[10px]">Nueva</Badge>}
              </div>
              <span className="text-xs text-muted-foreground">{notification.message}</span>
              {reference && <span className="text-[11px] text-muted-foreground">{reference}</span>}
              <span className="text-[11px] text-muted-foreground">
                {new Date(notification.created_at).toLocaleString('es-ES', {
                  day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
                })}
              </span>
            </DropdownMenuItem>
          );
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
