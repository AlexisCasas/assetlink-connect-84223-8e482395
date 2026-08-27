import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import type { InventoryMaterial, InventoryWarehouse, MaterialInput } from '@/types/inventory';

interface MaterialEditorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  warehouses: InventoryWarehouse[];
  /** Preselects the warehouse when creating from a warehouse's own row. */
  defaultWarehouseId?: string;
  material: InventoryMaterial | null;
  saving: boolean;
  onSave: (input: MaterialInput, materialId: string | undefined) => Promise<boolean>;
}

export function MaterialEditorDialog({ open, onOpenChange, warehouses, defaultWarehouseId, material, saving, onSave }: MaterialEditorDialogProps) {
  const [warehouseId, setWarehouseId] = useState('');
  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [unit, setUnit] = useState('');
  const [stock, setStock] = useState('0');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setWarehouseId(material?.warehouseId ?? defaultWarehouseId ?? warehouses[0]?.id ?? '');
    setCode(material?.code ?? '');
    setName(material?.name ?? '');
    setUnit(material?.unit ?? '');
    setStock(material ? String(material.stock) : '0');
    setFormError(null);
  }, [open, material, defaultWarehouseId, warehouses]);

  const handleSubmit = async () => {
    if (!warehouseId) {
      setFormError('Selecciona un almacén.');
      return;
    }
    if (!code.trim() || !name.trim() || !unit.trim()) {
      setFormError('Código, nombre y unidad son obligatorios.');
      return;
    }
    const stockNumber = Number(stock);
    if (Number.isNaN(stockNumber) || stockNumber < 0) {
      setFormError('El stock debe ser un número mayor o igual a 0.');
      return;
    }
    setFormError(null);

    const input: MaterialInput = {
      warehouseId,
      code: code.trim(),
      name: name.trim(),
      unit: unit.trim(),
      stock: stockNumber,
    };
    const ok = await onSave(input, material?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{material ? 'Editar material' : 'Nuevo material'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label>Almacén *</Label>
            <Select value={warehouseId} onValueChange={setWarehouseId} disabled={saving}>
              <SelectTrigger><SelectValue placeholder={warehouses.length === 0 ? 'Crea un almacén primero' : 'Selecciona almacén'} /></SelectTrigger>
              <SelectContent className="bg-popover">
                {warehouses.map((warehouse) => (
                  <SelectItem key={warehouse.id} value={warehouse.id}>{warehouse.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="material-code">Código *</Label>
              <Input id="material-code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="Ej. ROD-001" disabled={saving} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="material-unit">Unidad *</Label>
              <Input id="material-unit" value={unit} onChange={(e) => setUnit(e.target.value)} placeholder="Ej. unidad, litro" disabled={saving} />
            </div>
          </div>

          <div className="space-y-1">
            <Label htmlFor="material-name">Nombre *</Label>
            <Input id="material-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Ej. Rodamiento" disabled={saving} />
          </div>

          <div className="space-y-1">
            <Label htmlFor="material-stock">Stock</Label>
            <Input
              id="material-stock"
              type="number"
              min={0}
              step={0.01}
              value={stock}
              onChange={(e) => setStock(e.target.value)}
              disabled={saving}
            />
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving || warehouses.length === 0}>
              {saving ? 'Guardando…' : 'Guardar material'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
