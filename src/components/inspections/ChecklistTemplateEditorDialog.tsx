import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import type { ChecklistTemplate, ChecklistTemplateInput } from '@/types/checklist';

interface ChecklistTemplateEditorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  template: ChecklistTemplate | null;
  saving: boolean;
  onSave: (input: ChecklistTemplateInput, templateId: string | undefined) => Promise<boolean>;
}

/** Category is deliberately free text (inspeccion/auditoria/preventivo/
 * itse/seguridad/gerencial are just examples) — never a fixed dropdown, so
 * ITSE stays "one template among others" instead of a hardcoded option. */
export function ChecklistTemplateEditorDialog({ open, onOpenChange, template, saving, onSave }: ChecklistTemplateEditorDialogProps) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName(template?.name ?? '');
    setDescription(template?.description ?? '');
    setCategory(template?.category ?? '');
    setFormError(null);
  }, [open, template]);

  const handleSubmit = async () => {
    if (!name.trim()) {
      setFormError('El nombre de la plantilla es obligatorio.');
      return;
    }
    setFormError(null);

    const input: ChecklistTemplateInput = {
      name: name.trim(),
      description: description.trim() || null,
      category: category.trim() || null,
    };
    const ok = await onSave(input, template?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{template ? 'Editar plantilla' : 'Nueva plantilla de checklist'}</DialogTitle>
          <DialogDescription>
            ITSE, inspección de techos, auditoría interna, etc. son todas plantillas como esta — define nombre, categoría y descripción.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label htmlFor="template-name">Nombre *</Label>
            <Input id="template-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Ej. Inspección de luces de emergencia" disabled={saving} />
          </div>

          <div className="space-y-1">
            <Label htmlFor="template-category">Categoría</Label>
            <Input id="template-category" value={category} onChange={(e) => setCategory(e.target.value)} placeholder="Ej. inspeccion, auditoria, preventivo, itse, seguridad, gerencial" disabled={saving} />
          </div>

          <div className="space-y-1">
            <Label htmlFor="template-description">Descripción</Label>
            <Textarea id="template-description" value={description} onChange={(e) => setDescription(e.target.value)} disabled={saving} />
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving}>
              {saving ? 'Guardando…' : 'Guardar plantilla'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
