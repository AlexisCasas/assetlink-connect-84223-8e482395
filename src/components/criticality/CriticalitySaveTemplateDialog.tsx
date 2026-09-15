import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';

interface CriticalitySaveTemplateDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  saving: boolean;
  onSave: (name: string, description: string | null, category: string | null) => Promise<boolean>;
}

/** Freezes the organization's ACTIVE matrix as a private (scope=organization)
 * template. Evaluations are never copied — only the configuration. */
export function CriticalitySaveTemplateDialog({ open, onOpenChange, saving, onSave }: CriticalitySaveTemplateDialogProps) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState('');
  const [touched, setTouched] = useState(false);

  useEffect(() => {
    if (open) {
      setName('');
      setDescription('');
      setCategory('');
      setTouched(false);
    }
  }, [open]);

  const handleSave = async () => {
    setTouched(true);
    if (name.trim() === '') return;
    if (await onSave(name.trim(), description.trim() || null, category.trim() || null)) {
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Guardar matriz como plantilla</DialogTitle>
          <DialogDescription>
            Copia la configuración activa (parámetros, pesos y opciones) como plantilla reutilizable de tu organización.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1">
            <Label htmlFor="template-name">Nombre *</Label>
            <Input
              id="template-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Ej: Matriz HVAC 2026"
              disabled={saving}
            />
            {touched && name.trim() === '' && (
              <p className="text-xs text-destructive">El nombre es obligatorio.</p>
            )}
          </div>
          <div className="space-y-1">
            <Label htmlFor="template-description">Descripción</Label>
            <Textarea
              id="template-description"
              value={description}
              onChange={(event) => setDescription(event.target.value)}
              rows={3}
              disabled={saving}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="template-category">Categoría</Label>
            <Input
              id="template-category"
              value={category}
              onChange={(event) => setCategory(event.target.value)}
              placeholder="Ej: HVAC, Refrigeración"
              disabled={saving}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
          <Button onClick={() => void handleSave()} disabled={saving}>
            {saving ? 'Guardando…' : 'Guardar plantilla'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
