import { useEffect, useMemo, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Check, ChevronsUpDown, Package } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useInventoryCatalog } from '@/hooks/useInventoryCatalog';
import { WorkOrderMaterialWarningBadge } from '@/components/requests/StatusBadge';
import type { WorkOrderMaterial, WorkOrderMaterialInput, WorkOrderMaterialWarningStatus } from '@/types/workOrderMaterial';

interface WorkOrderMaterialEditorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The OT's operating organization — same catalog scope used everywhere
   * else (technicians, planners). */
  organizationId: string;
  /** null creates a new material line. */
  material: WorkOrderMaterial | null;
  saving: boolean;
  onSave: (input: WorkOrderMaterialInput, workOrderMaterialId: string | undefined) => Promise<boolean>;
}

/** Same rule as get_work_order_materials' warning_status, mirrored
 * client-side only for an immediate preview before saving — the saved
 * value always comes back from the server afterwards. */
const previewWarning = (stock: number, planned: number): WorkOrderMaterialWarningStatus => {
  if (stock === 0 && planned > 0) return 'no_stock';
  if (stock < planned) return 'insufficient_stock';
  return 'ok';
};

export function WorkOrderMaterialEditorDialog({ open, onOpenChange, organizationId, material, saving, onSave }: WorkOrderMaterialEditorDialogProps) {
  const { catalog, loading: loadingCatalog } = useInventoryCatalog(organizationId);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [materialId, setMaterialId] = useState('');
  const [plannedQuantity, setPlannedQuantity] = useState('0');
  const [usedQuantity, setUsedQuantity] = useState('0');
  const [notes, setNotes] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setMaterialId(material?.materialId ?? '');
    setPlannedQuantity(material ? String(material.plannedQuantity) : '0');
    setUsedQuantity(material ? String(material.usedQuantity) : '0');
    setNotes(material?.notes ?? '');
    setFormError(null);
  }, [open, material]);

  const activeMaterials = useMemo(() => catalog.materials.filter((item) => item.isActive), [catalog.materials]);
  const selectedCatalogMaterial = activeMaterials.find((item) => item.id === materialId)
    // Editing a line whose material was later deactivated: fall back to the
    // values already loaded on the OT line so the form still shows something.
    ?? (material && material.materialId === materialId
      ? { id: material.materialId, code: material.materialCode, name: material.materialName, unit: material.materialUnit, warehouseName: material.warehouseName, stock: material.currentStock, warehouseId: material.warehouseId, isActive: false }
      : undefined);

  const plannedNumber = Number(plannedQuantity) || 0;
  const livePreview = selectedCatalogMaterial ? previewWarning(selectedCatalogMaterial.stock, plannedNumber) : null;

  const handleSubmit = async () => {
    if (!materialId) {
      setFormError('Selecciona un material.');
      return;
    }
    const planned = Number(plannedQuantity);
    const used = Number(usedQuantity);
    if (Number.isNaN(planned) || planned < 0) {
      setFormError('La cantidad planificada debe ser un número mayor o igual a 0.');
      return;
    }
    if (Number.isNaN(used) || used < 0) {
      setFormError('La cantidad utilizada debe ser un número mayor o igual a 0.');
      return;
    }
    setFormError(null);

    const input: WorkOrderMaterialInput = {
      materialId,
      plannedQuantity: planned,
      usedQuantity: used,
      notes: notes.trim() || null,
    };
    const ok = await onSave(input, material?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{material ? 'Editar material' : 'Agregar material'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label>Material *</Label>
            <Popover open={pickerOpen} onOpenChange={setPickerOpen}>
              <PopoverTrigger asChild>
                <Button
                  type="button"
                  variant="outline"
                  role="combobox"
                  aria-expanded={pickerOpen}
                  disabled={loadingCatalog || saving}
                  className="w-full justify-between font-normal"
                >
                  {selectedCatalogMaterial ? (
                    <span className="flex items-center gap-2 truncate">
                      <Package className="h-4 w-4 shrink-0 text-muted-foreground" />
                      <span className="truncate">{selectedCatalogMaterial.code} — {selectedCatalogMaterial.name}</span>
                    </span>
                  ) : (
                    <span className="text-muted-foreground">
                      {loadingCatalog ? 'Cargando materiales…' : 'Buscar material…'}
                    </span>
                  )}
                  <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
                <Command>
                  <CommandInput placeholder="Buscar por código o nombre…" />
                  <CommandList>
                    <CommandEmpty>No se encontraron materiales.</CommandEmpty>
                    <CommandGroup>
                      {activeMaterials.map((item) => (
                        <CommandItem
                          key={item.id}
                          value={[item.code, item.name].join(' ')}
                          onSelect={() => { setMaterialId(item.id); setPickerOpen(false); }}
                        >
                          <Check className={cn('mr-2 h-4 w-4 shrink-0', materialId === item.id ? 'opacity-100' : 'opacity-0')} />
                          <span className="flex min-w-0 flex-col">
                            <span className="truncate">{item.code} — {item.name}</span>
                            <span className="truncate text-xs text-muted-foreground">
                              {item.warehouseName} · Stock {item.stock} {item.unit}
                            </span>
                          </span>
                        </CommandItem>
                      ))}
                    </CommandGroup>
                  </CommandList>
                </Command>
              </PopoverContent>
            </Popover>
            {selectedCatalogMaterial && (
              <div className="flex flex-wrap items-center gap-2 rounded-md bg-muted/30 p-2 text-xs text-muted-foreground">
                <span>{selectedCatalogMaterial.warehouseName}</span>
                <Badge variant="secondary" className="text-xs">Stock actual: {selectedCatalogMaterial.stock} {selectedCatalogMaterial.unit}</Badge>
              </div>
            )}
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="wom-planned">Cantidad planificada</Label>
              <Input
                id="wom-planned"
                type="number"
                min={0}
                step={0.01}
                value={plannedQuantity}
                onChange={(e) => setPlannedQuantity(e.target.value)}
                disabled={saving}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="wom-used">Cantidad utilizada</Label>
              <Input
                id="wom-used"
                type="number"
                min={0}
                step={0.01}
                value={usedQuantity}
                onChange={(e) => setUsedQuantity(e.target.value)}
                disabled={saving}
              />
            </div>
          </div>

          {livePreview && (
            <div className="flex items-center gap-2 text-sm">
              <span className="text-muted-foreground">Advertencia:</span>
              <WorkOrderMaterialWarningBadge status={livePreview} />
            </div>
          )}

          <div className="space-y-1">
            <Label htmlFor="wom-notes">Notas (opcional)</Label>
            <Textarea
              id="wom-notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              disabled={saving}
              rows={2}
            />
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving}>
              {saving ? 'Guardando…' : 'Guardar material'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
