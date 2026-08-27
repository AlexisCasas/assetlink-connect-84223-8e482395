import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import type { Database } from '@/integrations/supabase/types';

export type WorkOrder = Database['public']['Tables']['work_orders']['Row'];

export function useWorkOrders() {
  const { currentOrganization } = useAuth();
  const [workOrders, setWorkOrders] = useState<WorkOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const refetch = useCallback(async () => {
    if (!currentOrganization) {
      setWorkOrders([]);
      setError(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    // Same best-effort, idempotent due-notification generation as
    // useOrganizationNotifications.ts — no external scheduler in this
    // phase, see docs/OPERATIONAL_NOTIFICATIONS.md. Never blocks the
    // actual work orders load.
    try {
      await supabase.rpc('generate_operational_due_notifications');
    } catch (dueNotificationsError) {
      console.error('Error generating due-date notifications:', dueNotificationsError);
    }

    const baseQuery = supabase
      .from('work_orders')
      .select('*')
      .order('created_at', { ascending: false });

    const { data, error: queryError } =
      currentOrganization.organizationType === 'client_company'
        ? await baseQuery.eq('client_organization_id', currentOrganization.id)
        : currentOrganization.organizationType === 'provider_company' ||
            currentOrganization.organizationType === 'facility_manager'
          ? await baseQuery.eq('provider_organization_id', currentOrganization.id)
          : currentOrganization.organizationType === 'platform_admin'
            ? await baseQuery
            : { data: [], error: null };

    if (queryError) {
      setWorkOrders([]);
      setError(new Error(queryError.message));
    } else {
      setWorkOrders(data ?? []);
    }

    setLoading(false);
  }, [currentOrganization]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { workOrders, loading, error, refetch };
}
