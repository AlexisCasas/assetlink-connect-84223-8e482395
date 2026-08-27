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
import { supabase } from '@/integrations/supabase/client';
import type { InventoryWarehouse, WarehouseInput } from '@/types/inventory';

interface WarehouseEditorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  organizationId: string;
  warehouse: InventoryWarehouse | null;
  saving: boolean;
  onSave: (input: WarehouseInput, warehouseId: string | undefined) => Promise<boolean>;
}

interface BranchOption {
  id: string;
  name: string;
}

export function WarehouseEditorDialog({ open, onOpenChange, organizationId, warehouse, saving, onSave }: WarehouseEditorDialogProps) {
  const [name, setName] = useState('');
  const [branchId, setBranchId] = useState<string>('none');
  const [branches, setBranches] = useState<BranchOption[]>([]);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName(warehouse?.name ?? '');
    setBranchId(warehouse?.branchId ?? 'none');
    setFormError(null);
  }, [open, warehouse]);

  useEffect(() => {
    if (!open || !organizationId) return;
    void (async () => {
      const { data } = await supabase
        .from('client_branches')
        .select('id, name')
        .eq('organization_id', organizationId)
        .eq('is_active', true)
        .order('name');
      setBranches(data ?? []);
    })();
  }, [open, organizationId]);

  const handleSubmit = async () => {
    if (!name.trim()) {
      setFormError('El nombre es obligatorio.');
      return;
    }
    setFormError(null);
    const ok = await onSave({ name: name.trim(), branchId: branchId === 'none' ? null : branchId }, warehouse?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{warehouse ? 'Editar almacén' : 'Nuevo almacén'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label htmlFor="warehouse-name">Nombre *</Label>
            <Input
              id="warehouse-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ej. Almacén Central"
              disabled={saving}
            />
          </div>

          <div className="space-y-1">
            <Label>Sede (opcional)</Label>
            <Select value={branchId} onValueChange={setBranchId} disabled={saving}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent className="bg-popover">
                <SelectItem value="none">Sin sede</SelectItem>
                {branches.map((branch) => (
                  <SelectItem key={branch.id} value={branch.id}>{branch.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving}>
              {saving ? 'Guardando…' : 'Guardar almacén'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
