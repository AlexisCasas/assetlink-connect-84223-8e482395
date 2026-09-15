import { useMemo, useState } from 'react';
import { Bell, CheckCheck } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { useOrganizationNotifications } from '@/hooks/useOrganizationNotifications';
import {
  NOTIFICATION_TYPE_LABELS,
  NOTIFICATION_PRIORITY_LABELS,
  NOTIFICATION_PRIORITY_COLORS,
  isOperationalNotificationType,
  notificationEntityReference,
} from '@/lib/notificationLabels';
import { handleNotificationNavigation } from '@/lib/entityNavigation';
import { toast } from 'sonner';
import { ExternalLink } from 'lucide-react';

type FilterMode = 'all' | 'operational';

export const NotificationList = () => {
  const {
    notifications,
    unreadCount,
    loading,
    markAsRead,
    markAllAsRead,
  } = useOrganizationNotifications(100);
  const [filterMode, setFilterMode] = useState<FilterMode>('all');

  const visibleNotifications = useMemo(
    () => filterMode === 'operational'
      ? notifications.filter((notification) => isOperationalNotificationType(notification.type))
      : notifications,
    [notifications, filterMode],
  );

  const handleMarkAsRead = async (notificationId: string) => {
    if (await markAsRead(notificationId)) {
      toast.success('Notificacion marcada como leida');
    } else {
      toast.error('No se pudo marcar la notificacion');
    }
  };

  // Shared with NotificationBell — the only navigation resolver either of
  // them calls. A card click and the "Ver detalle" button both use this
  // exact function; "Marcar como leída" stays a separate, non-navigating
  // action (stopPropagation'd so it never triggers the card's own click).
  const handleOpen = async (notification: typeof notifications[number]) => {
    const navigated = await handleNotificationNavigation(notification, markAsRead);
    if (!navigated) {
      toast.error('No se pudo abrir el registro relacionado con esta notificación.');
    }
  };

  const handleMarkAllAsRead = async () => {
    if (await markAllAsRead()) {
      toast.success('Todas las notificaciones fueron marcadas como leidas');
    } else {
      toast.error('No se pudieron actualizar las notificaciones');
    }
  };

  if (loading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <p className="text-muted-foreground">Cargando notificaciones...</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Bell className="h-8 w-8" />
          <div>
            <h2 className="text-3xl font-bold">Notificaciones</h2>
            {unreadCount > 0 && (
              <p className="text-sm text-muted-foreground">{unreadCount} sin leer</p>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1 rounded-lg border bg-muted/30 p-1">
            <Button
              size="sm"
              variant={filterMode === 'all' ? 'default' : 'ghost'}
              className="h-7 px-3 text-xs"
              onClick={() => setFilterMode('all')}
            >
              Todas
            </Button>
            <Button
              size="sm"
              variant={filterMode === 'operational' ? 'default' : 'ghost'}
              className="h-7 px-3 text-xs"
              onClick={() => setFilterMode('operational')}
            >
              Operativas
            </Button>
          </div>
          {unreadCount > 0 && (
            <Button onClick={() => void handleMarkAllAsRead()} variant="outline" size="sm">
              <CheckCheck className="mr-2 h-4 w-4" />
              Marcar todas como leidas
            </Button>
          )}
        </div>
      </div>

      {visibleNotifications.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-12">
            <Bell className="mb-4 h-12 w-12 text-muted-foreground" />
            <p className="text-lg font-medium text-muted-foreground">
              {filterMode === 'operational' ? 'No hay notificaciones operativas.' : 'No hay notificaciones para la organizacion activa'}
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {visibleNotifications.map((notification) => {
            const reference = notificationEntityReference(notification.entity_type, notification.metadata);
            return (
              <Card
                key={notification.id}
                role="button"
                tabIndex={0}
                onClick={() => void handleOpen(notification)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    void handleOpen(notification);
                  }
                }}
                className={`cursor-pointer transition-colors hover:bg-muted/50 ${!notification.is_read ? 'border-primary/50 bg-muted/30' : ''}`}
              >
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <CardTitle className="flex flex-wrap items-center gap-2 text-lg">
                        {notification.title}
                        {!notification.is_read && <Badge className="text-xs">Nueva</Badge>}
                        <Badge variant="outline" className={NOTIFICATION_PRIORITY_COLORS[notification.priority] ?? ''}>
                          {NOTIFICATION_PRIORITY_LABELS[notification.priority] ?? notification.priority}
                        </Badge>
                      </CardTitle>
                      <p className="mt-1 text-xs text-muted-foreground">
                        {NOTIFICATION_TYPE_LABELS[notification.type] ?? notification.type}
                        {reference ? ` · ${reference}` : ''}
                      </p>
                      <p className="mt-1 text-sm text-muted-foreground">
                        {new Date(notification.created_at).toLocaleString('es-ES', {
                          year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit',
                        })}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={(event) => { event.stopPropagation(); void handleOpen(notification); }}
                      >
                        <ExternalLink className="mr-1 h-3.5 w-3.5" />
                        Ver detalle
                      </Button>
                      {!notification.is_read && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={(event) => { event.stopPropagation(); void handleMarkAsRead(notification.id); }}
                        >
                          Marcar como leida
                        </Button>
                      )}
                    </div>
                  </div>
                </CardHeader>
                <CardContent><p className="text-sm">{notification.message}</p></CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
};
