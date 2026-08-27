export interface InventoryWarehouse {
  id: string;
  name: string;
  branchId: string | null;
  isActive: boolean;
}

export interface InventoryMaterial {
  id: string;
  warehouseId: string;
  warehouseName: string;
  code: string;
  name: string;
  unit: string;
  stock: number;
  isActive: boolean;
}

export interface InventoryCatalog {
  warehouses: InventoryWarehouse[];
  materials: InventoryMaterial[];
}

export interface WarehouseInput {
  name: string;
  branchId: string | null;
}

export interface MaterialInput {
  warehouseId: string;
  code: string;
  name: string;
  unit: string;
  stock: number;
}
