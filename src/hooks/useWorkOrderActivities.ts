import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { WorkOrderActivity, WorkOrderActivityInput, WorkOrderActivityTechnician } from '@/types/workOrderActivity';

interface RawTechnician {
  member_id: string;
  name: string;
  email: string;
  is_primary: boolean;
}

const toTechnicians = (value: unknown): WorkOrderActivityTechnician[] => {
  if (!Array.isArray(value)) return [];
  return (value as RawTechnician[]).map((technician) => ({
    memberId: technician.member_id,
    name: technician.name,
    email: technician.email,
    isPrimary: technician.is_primary,
  }));
};

/**
 * Loads/saves the activities of a single work order via
 * get_work_order_activities / upsert_work_order_activity /
 * delete_work_order_activity (all SECURITY DEFINER, tenant-scoped to the
 * OT's own operating organization — see docs/WORK_ORDER_ACTIVITIES.md).
 * Every mutation refreshes the full list from the RPC afterwards instead of
 * patching local state, so technician names always come from the server's
 * own resolution, never guessed client-side.
 */
export function useWorkOrderActivities(workOrderId: string | null | undefined) {
  const [activities, setActivities] = useState<WorkOrderActivity[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!workOrderId) {
      setActivities([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_work_order_activities', {
        p_work_order_id: workOrderId,
      });
      if (rpcError) throw rpcError;
      setActivities((data ?? []).map((row) => ({
        id: row.id,
        workOrderId: row.work_order_id,
        description: row.description,
        estimatedHours: row.estimated_hours,
        dueAt: row.due_at,
        status: row.status as WorkOrderActivity['status'],
        sequence: row.sequence,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        technicians: toTechnicians(row.technicians),
      })));
    } catch (err) {
      setActivities([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar las actividades.');
    } finally {
      setLoading(false);
    }
  }, [workOrderId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const saveActivity = useCallback(async (input: WorkOrderActivityInput, activityId?: string, sequence?: number): Promise<boolean> => {
    if (!workOrderId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_work_order_activity', {
        p_work_order_id: workOrderId,
        p_activity_id: activityId ?? null,
        p_description: input.description,
        p_estimated_hours: input.estimatedHours,
        p_due_at: input.dueAt,
        p_status: input.status,
        p_sequence: sequence ?? null,
        p_technician_member_ids: input.memberIds,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar la actividad.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [workOrderId, refresh]);

  const deleteActivity = useCallback(async (activityId: string): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('delete_work_order_activity', {
        p_activity_id: activityId,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo eliminar la actividad.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  // Simple sequence swap between an activity and its immediate neighbor —
  // no dedicated "reorder" RPC, just two upsert_work_order_activity calls
  // reusing the same write path (a transient duplicate sequence between the
  // two calls is harmless: there is no UNIQUE constraint on it).
  const moveActivity = useCallback(async (activity: WorkOrderActivity, direction: 'up' | 'down'): Promise<boolean> => {
    if (!workOrderId) return false;
    const sorted = [...activities].sort((a, b) => a.sequence - b.sequence);
    const index = sorted.findIndex((item) => item.id === activity.id);
    const swapIndex = direction === 'up' ? index - 1 : index + 1;
    if (index === -1 || swapIndex < 0 || swapIndex >= sorted.length) return false;
    const neighbor = sorted[swapIndex];

    setSaving(true);
    setError(null);
    try {
      const { error: firstError } = await supabase.rpc('upsert_work_order_activity', {
        p_work_order_id: workOrderId,
        p_activity_id: activity.id,
        p_description: activity.description,
        p_estimated_hours: activity.estimatedHours,
        p_due_at: activity.dueAt,
        p_status: activity.status,
        p_sequence: neighbor.sequence,
        p_technician_member_ids: activity.technicians.map((technician) => technician.memberId),
      });
      if (firstError) throw firstError;

      const { error: secondError } = await supabase.rpc('upsert_work_order_activity', {
        p_work_order_id: workOrderId,
        p_activity_id: neighbor.id,
        p_description: neighbor.description,
        p_estimated_hours: neighbor.estimatedHours,
        p_due_at: neighbor.dueAt,
        p_status: neighbor.status,
        p_sequence: activity.sequence,
        p_technician_member_ids: neighbor.technicians.map((technician) => technician.memberId),
      });
      if (secondError) throw secondError;

      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo reordenar la actividad.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [activities, workOrderId, refresh]);

  return { activities, loading, saving, error, refresh, saveActivity, deleteActivity, moveActivity };
}
