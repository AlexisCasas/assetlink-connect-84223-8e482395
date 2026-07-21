import { Bell, CheckCheck } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { useOrganizationNotifications } from '@/hooks/useOrganizationNotifications';
import { toast } from 'sonner';

export const NotificationList = () => {
  const {
    notifications,
    unreadCount,
    loading,
    markAsRead,
    markAllAsRead,
  } = useOrganizationNotifications(100);

  const handleMarkAsRead = async (notificationId: string) => {
    if (await markAsRead(notificationId)) {
      toast.success('Notificacion marcada como leida');
    } else {
      toast.error('No se pudo marcar la notificacion');
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
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Bell className="h-8 w-8" />
          <div>
            <h2 className="text-3xl font-bold">Notificaciones</h2>
            {unreadCount > 0 && (
              <p className="text-sm text-muted-foreground">{unreadCount} sin leer</p>
            )}
          </div>
        </div>
        {unreadCount > 0 && (
          <Button onClick={() => void handleMarkAllAsRead()} variant="outline" size="sm">
            <CheckCheck className="mr-2 h-4 w-4" />
            Marcar todas como leidas
          </Button>
        )}
      </div>

      {notifications.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-12">
            <Bell className="mb-4 h-12 w-12 text-muted-foreground" />
            <p className="text-lg font-medium text-muted-foreground">
              No hay notificaciones para la organizacion activa
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {notifications.map((notification) => (
            <Card key={notification.id} className={!notification.is_read ? 'border-primary/50 bg-muted/30' : ''}>
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <CardTitle className="flex items-center gap-2 text-lg">
                      {notification.title}
                      {!notification.is_read && <Badge className="text-xs">Nueva</Badge>}
                    </CardTitle>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {new Date(notification.created_at).toLocaleString('es-ES', {
                        year: 'numeric', month: 'long', day: 'numeric', hour: '2-digit', minute: '2-digit',
                      })}
                    </p>
                  </div>
                  {!notification.is_read && (
                    <Button variant="ghost" size="sm" onClick={() => void handleMarkAsRead(notification.id)}>
                      Marcar como leida
                    </Button>
                  )}
                </div>
              </CardHeader>
              <CardContent><p className="text-sm">{notification.message}</p></CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
};
