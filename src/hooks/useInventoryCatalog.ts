import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { InventoryCatalog, MaterialInput, WarehouseInput } from '@/types/inventory';

interface RawWarehouse {
  id: string;
  name: string;
  branch_id: string | null;
  is_active: boolean;
}

interface RawMaterial {
  id: string;
  warehouse_id: string;
  warehouse_name: string;
  code: string;
  name: string;
  unit: string;
  stock: number;
  is_active: boolean;
}

interface RawCatalog {
  warehouses: RawWarehouse[];
  materials: RawMaterial[];
}

const EMPTY_CATALOG: InventoryCatalog = { warehouses: [], materials: [] };

const isDuplicateCodeError = (message: string) => message.toLowerCase().includes('duplicate key value');

/**
 * Loads the active warehouses + active materials of one organization via
 * get_inventory_catalog (SECURITY DEFINER, tenant-scoped) and exposes
 * saveWarehouse/saveMaterial writing through upsert_warehouse/upsert_material.
 * Every mutation refreshes the full catalog from the server afterwards.
 */
export function useInventoryCatalog(organizationId: string | null | undefined) {
  const [catalog, setCatalog] = useState<InventoryCatalog>(EMPTY_CATALOG);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!organizationId) {
      setCatalog(EMPTY_CATALOG);
      setError(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc('get_inventory_catalog', {
        p_organization_id: organizationId,
      });
      if (rpcError) throw rpcError;
      const raw = (data ?? EMPTY_CATALOG) as unknown as RawCatalog;
      setCatalog({
        warehouses: (raw.warehouses ?? []).map((row) => ({
          id: row.id,
          name: row.name,
          branchId: row.branch_id,
          isActive: row.is_active,
        })),
        materials: (raw.materials ?? []).map((row) => ({
          id: row.id,
          warehouseId: row.warehouse_id,
          warehouseName: row.warehouse_name,
          code: row.code,
          name: row.name,
          unit: row.unit,
          stock: row.stock,
          isActive: row.is_active,
        })),
      });
    } catch (err) {
      setCatalog(EMPTY_CATALOG);
      setError(err instanceof Error ? err.message : 'No se pudo cargar el inventario.');
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => { void refresh(); }, [refresh]);

  const saveWarehouse = useCallback(async (input: WarehouseInput, warehouseId?: string): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_warehouse', {
        p_organization_id: organizationId,
        p_name: input.name,
        p_warehouse_id: warehouseId ?? null,
        p_branch_id: input.branchId,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar el almacén.');
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

  const saveMaterial = useCallback(async (input: MaterialInput, materialId?: string): Promise<boolean> => {
    if (!organizationId) return false;
    setSaving(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('upsert_material', {
        p_organization_id: organizationId,
        p_warehouse_id: input.warehouseId,
        p_code: input.code,
        p_name: input.name,
        p_unit: input.unit,
        p_material_id: materialId ?? null,
        p_stock: input.stock,
      });
      if (rpcError) throw rpcError;
      await refresh();
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : 'No se pudo guardar el material.';
      setError(isDuplicateCodeError(message) ? 'Ya existe un material con ese código en esta organización.' : message);
      return false;
    } finally {
      setSaving(false);
    }
  }, [organizationId, refresh]);

  return { catalog, loading, saving, error, refresh, saveWarehouse, saveMaterial };
}
