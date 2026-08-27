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
import { Switch } from '@/components/ui/switch';
import type { ChecklistItemInput, ChecklistTemplateItem } from '@/types/checklist';

interface ChecklistItemEditorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  templateId: string | null;
  templateName: string;
  item: ChecklistTemplateItem | null;
  nextSequence: number;
  saving: boolean;
  onSave: (input: ChecklistItemInput, itemId: string | undefined) => Promise<boolean>;
}

export function ChecklistItemEditorDialog({ open, onOpenChange, templateId, templateName, item, nextSequence, saving, onSave }: ChecklistItemEditorDialogProps) {
  const [question, setQuestion] = useState('');
  const [section, setSection] = useState('');
  const [helpText, setHelpText] = useState('');
  const [sequence, setSequence] = useState('1');
  const [isRequired, setIsRequired] = useState(true);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setQuestion(item?.question ?? '');
    setSection(item?.section ?? '');
    setHelpText(item?.helpText ?? '');
    setSequence(String(item?.sequence ?? nextSequence));
    setIsRequired(item?.isRequired ?? true);
    setFormError(null);
  }, [open, item, nextSequence]);

  const handleSubmit = async () => {
    if (!templateId) return;
    if (!question.trim()) {
      setFormError('La pregunta del ítem es obligatoria.');
      return;
    }
    const sequenceNumber = Number(sequence);
    if (!Number.isInteger(sequenceNumber) || sequenceNumber <= 0) {
      setFormError('El orden debe ser un número entero mayor a 0.');
      return;
    }
    setFormError(null);

    const input: ChecklistItemInput = {
      templateId,
      question: question.trim(),
      section: section.trim() || null,
      helpText: helpText.trim() || null,
      sequence: sequenceNumber,
      isRequired,
    };
    const ok = await onSave(input, item?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{item ? 'Editar ítem' : 'Nuevo ítem'}</DialogTitle>
          <DialogDescription>Pregunta que aparecerá en el checklist, con orden y si es obligatoria.</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">Plantilla: {templateName}</p>

          <div className="space-y-1">
            <Label htmlFor="item-question">Pregunta *</Label>
            <Input id="item-question" value={question} onChange={(e) => setQuestion(e.target.value)} placeholder="Ej. Enciende correctamente" disabled={saving} />
          </div>

          <div className="space-y-1">
            <Label htmlFor="item-section">Sección</Label>
            <Input id="item-section" value={section} onChange={(e) => setSection(e.target.value)} placeholder="Opcional — agrupa ítems relacionados" disabled={saving} />
          </div>

          <div className="space-y-1">
            <Label htmlFor="item-help">Texto de ayuda</Label>
            <Textarea id="item-help" value={helpText} onChange={(e) => setHelpText(e.target.value)} disabled={saving} />
          </div>

          <div className="flex items-center justify-between">
            <div className="space-y-1">
              <Label htmlFor="item-sequence">Orden *</Label>
              <Input id="item-sequence" type="number" min={1} step={1} className="w-24" value={sequence} onChange={(e) => setSequence(e.target.value)} disabled={saving} />
            </div>
            <div className="flex items-center gap-2">
              <Label htmlFor="item-required">Obligatorio</Label>
              <Switch id="item-required" checked={isRequired} onCheckedChange={setIsRequired} disabled={saving} />
            </div>
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving || !templateId}>
              {saving ? 'Guardando…' : 'Guardar ítem'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
