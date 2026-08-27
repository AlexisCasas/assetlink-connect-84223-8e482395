import { useState } from 'react';
import { Boxes, Package, Plus, Pencil, Warehouse as WarehouseIcon } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { usePermissions } from '@/hooks/usePermissions';
import { useInventoryCatalog } from '@/hooks/useInventoryCatalog';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useToast } from '@/hooks/use-toast';
import { WarehouseEditorDialog } from './WarehouseEditorDialog';
import { MaterialEditorDialog } from './MaterialEditorDialog';
import type { InventoryMaterial, InventoryWarehouse, MaterialInput, WarehouseInput } from '@/types/inventory';

export function InventoryView() {
  const { currentOrganization } = useAuth();
  const { canPlanWork } = usePermissions();
  const { catalog, loading, saving, error, saveWarehouse, saveMaterial } = useInventoryCatalog(currentOrganization?.id);
  const { toast } = useToast();

  const [warehouseEditorOpen, setWarehouseEditorOpen] = useState(false);
  const [editingWarehouse, setEditingWarehouse] = useState<InventoryWarehouse | null>(null);
  const [materialEditorOpen, setMaterialEditorOpen] = useState(false);
  const [editingMaterial, setEditingMaterial] = useState<InventoryMaterial | null>(null);
  const [materialDefaultWarehouseId, setMaterialDefaultWarehouseId] = useState<string | undefined>(undefined);

  if (!currentOrganization) {
    return <EmptyState message="Sin organización asignada" />;
  }

  const openCreateWarehouse = () => { setEditingWarehouse(null); setWarehouseEditorOpen(true); };
  const openEditWarehouse = (warehouse: InventoryWarehouse) => { setEditingWarehouse(warehouse); setWarehouseEditorOpen(true); };
  const openCreateMaterial = (warehouseId?: string) => { setEditingMaterial(null); setMaterialDefaultWarehouseId(warehouseId); setMaterialEditorOpen(true); };
  const openEditMaterial = (material: InventoryMaterial) => { setEditingMaterial(material); setMaterialDefaultWarehouseId(undefined); setMaterialEditorOpen(true); };

  const handleSaveWarehouse = async (input: WarehouseInput, warehouseId: string | undefined) => {
    const ok = await saveWarehouse(input, warehouseId);
    toast(ok
      ? { title: warehouseId ? 'Almacén actualizado' : 'Almacén creado' }
      : { title: 'No se pudo guardar el almacén', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
    return ok;
  };

  const handleSaveMaterial = async (input: MaterialInput, materialId: string | undefined) => {
    const ok = await saveMaterial(input, materialId);
    toast(ok
      ? { title: materialId ? 'Material actualizado' : 'Material creado' }
      : { title: 'No se pudo guardar el material', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
    return ok;
  };

  const materialsByWarehouse = new Map<string, InventoryMaterial[]>();
  catalog.materials.forEach((material) => {
    const list = materialsByWarehouse.get(material.warehouseId) ?? [];
    list.push(material);
    materialsByWarehouse.set(material.warehouseId, list);
  });

  return (
    <div className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Inventario</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Almacenes y materiales con stock simple — sin kardex, sin valorización, sin descuento automático.
          </p>
        </div>
        {canPlanWork && (
          <Button onClick={openCreateWarehouse} disabled={loading}>
            <Plus className="mr-2 h-4 w-4" /> Nuevo almacén
          </Button>
        )}
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando inventario…</p>
      ) : catalog.warehouses.length === 0 ? (
        <Card>
          <CardContent className="flex min-h-40 flex-col items-center justify-center gap-2 text-center">
            <WarehouseIcon className="h-8 w-8 text-muted-foreground" />
            <p className="font-medium">Aún no hay almacenes registrados.</p>
            {canPlanWork && <p className="text-sm text-muted-foreground">Crea un almacén para empezar a registrar materiales.</p>}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {catalog.warehouses.map((warehouse) => (
            <Card key={warehouse.id}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0">
                <CardTitle className="flex items-center gap-2 text-base">
                  <WarehouseIcon className="h-4 w-4 text-muted-foreground" /> {warehouse.name}
                </CardTitle>
                <div className="flex items-center gap-2">
                  {canPlanWork && (
                    <>
                      <Button variant="outline" size="sm" onClick={() => openCreateMaterial(warehouse.id)}>
                        <Plus className="mr-1 h-3.5 w-3.5" /> Material
                      </Button>
                      <Button variant="ghost" size="icon" onClick={() => openEditWarehouse(warehouse)} title="Editar almacén">
                        <Pencil className="h-4 w-4" />
                      </Button>
                    </>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                {(materialsByWarehouse.get(warehouse.id) ?? []).length === 0 ? (
                  <p className="text-sm text-muted-foreground">Este almacén todavía no tiene materiales.</p>
                ) : (
                  <div className="space-y-2">
                    {(materialsByWarehouse.get(warehouse.id) ?? []).map((material) => (
                      <div key={material.id} className="flex items-center justify-between rounded-md border p-2.5">
                        <div className="flex min-w-0 items-center gap-2">
                          <Package className="h-4 w-4 shrink-0 text-muted-foreground" />
                          <div className="min-w-0">
                            <p className="truncate text-sm font-medium">{material.code} — {material.name}</p>
                            <p className="text-xs text-muted-foreground">Unidad: {material.unit}</p>
                          </div>
                        </div>
                        <div className="flex shrink-0 items-center gap-2">
                          <Badge variant={material.stock === 0 ? 'destructive' : 'secondary'}>
                            Stock: {material.stock}
                          </Badge>
                          {canPlanWork && (
                            <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEditMaterial(material)} title="Editar material">
                              <Pencil className="h-3.5 w-3.5" />
                            </Button>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {canPlanWork && (
        <>
          <WarehouseEditorDialog
            open={warehouseEditorOpen}
            onOpenChange={setWarehouseEditorOpen}
            organizationId={currentOrganization.id}
            warehouse={editingWarehouse}
            saving={saving}
            onSave={handleSaveWarehouse}
          />
          <MaterialEditorDialog
            open={materialEditorOpen}
            onOpenChange={setMaterialEditorOpen}
            warehouses={catalog.warehouses}
            defaultWarehouseId={materialDefaultWarehouseId}
            material={editingMaterial}
            saving={saving}
            onSave={handleSaveMaterial}
          />
        </>
      )}
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="p-6">
      <Card><CardContent className="flex min-h-56 flex-col items-center justify-center gap-3 text-center">
        <Boxes className="h-10 w-10 text-muted-foreground" />
        <p className="font-medium">{message}</p>
      </CardContent></Card>
    </div>
  );
}
