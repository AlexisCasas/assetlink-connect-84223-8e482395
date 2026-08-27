import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { WorkOrderMaterial, WorkOrderMaterialInput } from '@/types/workOrderMaterial';

/**
 * Loads/saves the materials planned/used on a single work order via
 * get_work_order_materials / upsert_work_order_material /
 * delete_work_order_material (all SECURITY DEFINER, tenant-scoped to the
 * OT's own operating organization — see docs/MINIMAL_INVENTORY_MATERIALS.md).
 * Every mutation refreshes the full list from the server afterwards, so
 * current_stock/warning_status always come from the server's own
 * computation, never re-derived client-side.
 */
export function useWorkOrderMaterials(workOrderId: string | null | undefined) {
  const [materials, setMaterials] = useState<WorkOrderMaterial[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!workOrderId) {
      setMaterials([]);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_work_order_materials', {
        p_work_order_id: workOrderId,
      });
      if (rpcError) throw rpcError;
      setMaterials((data ?? []).map((row) => ({
        id: row.id,
        materialId: row.material_id,
        materialCode: row.material_code,
        materialName: row.material_name,
        materialUnit: row.material_unit,
        warehouseId: row.warehouse_id,
        warehouseName: row.warehouse_name,
        plannedQuantity: row.planned_quantity,
        usedQuantity: row.used_quantity,
        stockSnapshot: row.stock_snapshot,
        currentStock: row.current_stock,
        warningStatus: row.warning_status as WorkOrderMaterial['warningStatus'],
        notes: row.notes,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      })));
    } catch (err) {
      setMaterials([]);
      setError(err instanceof Error ? err.message : 'No se pudieron cargar los materiales.');
    } finally {
      setLoading(false);
    }
  }, [workOrderId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const saveMaterial = useCallback(async (input: WorkOrderMaterialInput, workOrderMaterialId?: string): Promise<boolean> => {
    if (!workOrderId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_work_order_material', {
        p_work_order_id: workOrderId,
        p_material_id: input.materialId,
        p_work_order_material_id: workOrderMaterialId ?? null,
        p_planned_quantity: input.plannedQuantity,
        p_used_quantity: input.usedQuantity,
        p_notes: input.notes,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar el material.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [workOrderId, refresh]);

  const deleteMaterial = useCallback(async (workOrderMaterialId: string): Promise<boolean> => {
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('delete_work_order_material', {
        p_work_order_material_id: workOrderMaterialId,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo eliminar el material.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [refresh]);

  return { materials, loading, saving, error, refresh, saveMaterial, deleteMaterial };
}
