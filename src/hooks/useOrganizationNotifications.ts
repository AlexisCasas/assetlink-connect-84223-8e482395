import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';

export type OrganizationNotification = Database['public']['Tables']['organization_notifications']['Row'];

export function useOrganizationNotifications(limit = 10) {
  const { currentOrganization } = useAuth();
  const [notifications, setNotifications] = useState<OrganizationNotification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(false);

  const loadNotifications = useCallback(async () => {
    if (!currentOrganization) {
      setNotifications([]);
      setUnreadCount(0);
      return;
    }

    setLoading(true);
    const [notificationsResult, unreadResult] = await Promise.all([
      supabase
        .from('organization_notifications')
        .select('*')
        .eq('organization_id', currentOrganization.id)
        .order('created_at', { ascending: false })
        .limit(limit),
      supabase
        .from('organization_notifications')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', currentOrganization.id)
        .eq('is_read', false),
    ]);

    if (notificationsResult.error) {
      console.error('Error loading organization notifications:', notificationsResult.error);
      setNotifications([]);
    } else {
      setNotifications(notificationsResult.data ?? []);
    }

    if (unreadResult.error) {
      console.error('Error loading unread organization notifications:', unreadResult.error);
      setUnreadCount(0);
    } else {
      setUnreadCount(unreadResult.count ?? 0);
    }

    setLoading(false);
  }, [currentOrganization, limit]);

  useEffect(() => {
    void loadNotifications();
  }, [loadNotifications]);

  const markAsRead = useCallback(async (notificationId: string) => {
    if (!currentOrganization) return false;

    const { error } = await supabase
      .from('organization_notifications')
      .update({ is_read: true, read_at: new Date().toISOString() })
      .eq('id', notificationId)
      .eq('organization_id', currentOrganization.id);

    if (error) {
      console.error('Error marking organization notification as read:', error);
      return false;
    }

    setNotifications((current) => current.map((notification) => (
      notification.id === notificationId
        ? { ...notification, is_read: true, read_at: new Date().toISOString() }
        : notification
    )));
    setUnreadCount((current) => Math.max(0, current - 1));
    return true;
  }, [currentOrganization]);

  const markAllAsRead = useCallback(async () => {
    if (!currentOrganization || unreadCount === 0) return false;

    const { error } = await supabase
      .from('organization_notifications')
      .update({ is_read: true, read_at: new Date().toISOString() })
      .eq('organization_id', currentOrganization.id)
      .eq('is_read', false);

    if (error) {
      console.error('Error marking organization notifications as read:', error);
      return false;
    }

    const readAt = new Date().toISOString();
    setNotifications((current) => current.map((notification) => ({
      ...notification,
      is_read: true,
      read_at: notification.read_at ?? readAt,
    })));
    setUnreadCount(0);
    return true;
  }, [currentOrganization, unreadCount]);

  return {
    notifications,
    unreadCount,
    loading,
    loadNotifications,
    markAsRead,
    markAllAsRead,
  };
}
