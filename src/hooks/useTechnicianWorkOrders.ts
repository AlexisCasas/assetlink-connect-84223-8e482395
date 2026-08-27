import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { TechnicianWorkOrder, TechnicianWorkOrderActivity, TechnicianWorkOrderMaterial } from '@/types/technicianWorkOrder';

interface RawActivity {
  id: string;
  description: string;
  estimated_hours: number | null;
  status: string;
  sequence: number;
  due_at: string | null;
  actual_hours_total: number;
  reports_count: number;
}

interface RawMaterial {
  id: string;
  material_code: string;
  material_name: string;
  material_unit: string;
  planned_quantity: number;
  used_quantity: number;
  current_stock: number;
  warning_status: string;
}

const toActivities = (value: unknown): TechnicianWorkOrderActivity[] => {
  if (!Array.isArray(value)) return [];
  return (value as RawActivity[]).map((row) => ({
    id: row.id,
    description: row.description,
    estimatedHours: row.estimated_hours,
    status: row.status,
    sequence: row.sequence,
    dueAt: row.due_at,
    actualHoursTotal: row.actual_hours_total,
    reportsCount: row.reports_count,
  }));
};

const toMaterials = (value: unknown): TechnicianWorkOrderMaterial[] => {
  if (!Array.isArray(value)) return [];
  return (value as RawMaterial[]).map((row) => ({
    id: row.id,
    materialCode: row.material_code,
    materialName: row.material_name,
    materialUnit: row.material_unit,
    plannedQuantity: row.planned_quantity,
    usedQuantity: row.used_quantity,
    currentStock: row.current_stock,
    warningStatus: row.warning_status as TechnicianWorkOrderMaterial['warningStatus'],
  }));
};

/**
 * "Mis órdenes de trabajo": loads only the caller's own assigned work via
 * get_my_technician_work_orders (SECURITY DEFINER, resolves purely from
 * auth.uid() — no organization_id parameter, see
 * docs/TECHNICIAN_WORK_VIEW.md). Status changes go through
 * technician_update_work_order_progress, the only RPC a technician can use
 * to touch a work order — it never lets them edit planner, assignment,
 * dates, priority, or materials.
 */
export function useTechnicianWorkOrders() {
  const [workOrders, setWorkOrders] = useState<TechnicianWorkOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_my_technician_work_orders');
      if (rpcError) throw rpcError;
      setWorkOrders((data ?? []).map((row) => ({
        id: row.id,
        workOrderNumber: row.work_order_number,
        workOrderType: row.work_order_type,
        title: row.title,
        status: row.status,
        priority: row.priority,
        scheduledAt: row.scheduled_at,
        dueAt: row.due_at,
        assetId: row.asset_id,
        assetName: row.asset_name,
        assetPath: row.asset_path,
        location: row.location,
        organizationId: row.organization_id,
        requestId: row.request_id,
        activities: toActivities(row.activities),
        materials: toMaterials(row.materials),
      })));
    } catch (err) {
      setWorkOrders([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar tus órdenes de trabajo.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const updateProgress = useCallback(async (workOrderId: string, status?: string, notes?: string): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('technician_update_work_order_progress', {
        p_work_order_id: workOrderId,
        p_status: status ?? null,
        p_notes: notes ?? null,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo actualizar la orden de trabajo.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  return { workOrders, loading, saving, error, refresh, updateProgress };
}
