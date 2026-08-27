/** ok = stock covers the planned quantity; no_stock = zero stock with a
 * positive planned quantity; insufficient_stock = stock covers some but not
 * all of it. Purely informational — never blocks saving. */
export type WorkOrderMaterialWarningStatus = 'ok' | 'no_stock' | 'insufficient_stock';

export interface WorkOrderMaterial {
  id: string;
  materialId: string;
  materialCode: string;
  materialName: string;
  materialUnit: string;
  warehouseId: string;
  warehouseName: string;
  plannedQuantity: number;
  usedQuantity: number;
  /** Material stock at the moment this line was created (or the material
   * was swapped) — a planning-time marker, not live. */
  stockSnapshot: number;
  /** Live materials.stock, resolved by get_work_order_materials. */
  currentStock: number;
  warningStatus: WorkOrderMaterialWarningStatus;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface WorkOrderMaterialInput {
  materialId: string;
  plannedQuantity: number;
  usedQuantity: number;
  notes: string | null;
}
