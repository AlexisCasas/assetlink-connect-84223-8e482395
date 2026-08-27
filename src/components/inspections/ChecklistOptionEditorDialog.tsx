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
import { Switch } from '@/components/ui/switch';
import type { ChecklistOptionInput, ChecklistResponseOption } from '@/types/checklist';

interface ChecklistOptionEditorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  templateId: string | null;
  templateName: string;
  option: ChecklistResponseOption | null;
  nextSequence: number;
  saving: boolean;
  onSave: (input: ChecklistOptionInput, optionId: string | undefined) => Promise<boolean>;
}

/** value is a stable machine-readable key (e.g. complies/non_complies/
 * not_applicable) — submit_inspection_run computes "not_applicable" result
 * by matching this exact value, so it must stay consistent per template. */
export function ChecklistOptionEditorDialog({ open, onOpenChange, templateId, templateName, option, nextSequence, saving, onSave }: ChecklistOptionEditorDialogProps) {
  const [label, setLabel] = useState('');
  const [value, setValue] = useState('');
  const [score, setScore] = useState('');
  const [isFailure, setIsFailure] = useState(false);
  const [sequence, setSequence] = useState('1');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setLabel(option?.label ?? '');
    setValue(option?.value ?? '');
    setScore(option?.score != null ? String(option.score) : '');
    setIsFailure(option?.isFailure ?? false);
    setSequence(String(option?.sequence ?? nextSequence));
    setFormError(null);
  }, [open, option, nextSequence]);

  const handleSubmit = async () => {
    if (!templateId) return;
    if (!label.trim()) {
      setFormError('La etiqueta de la opción es obligatoria.');
      return;
    }
    if (!value.trim()) {
      setFormError('El valor (código) de la opción es obligatorio.');
      return;
    }
    const sequenceNumber = Number(sequence);
    if (!Number.isInteger(sequenceNumber) || sequenceNumber <= 0) {
      setFormError('El orden debe ser un número entero mayor a 0.');
      return;
    }
    const scoreNumber = score.trim() === '' ? null : Number(score);
    if (scoreNumber !== null && Number.isNaN(scoreNumber)) {
      setFormError('La puntuación debe ser un número.');
      return;
    }
    setFormError(null);

    const input: ChecklistOptionInput = {
      templateId,
      label: label.trim(),
      value: value.trim(),
      score: scoreNumber,
      isFailure,
      sequence: sequenceNumber,
    };
    const ok = await onSave(input, option?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{option ? 'Editar opción de respuesta' : 'Nueva opción de respuesta'}</DialogTitle>
          <DialogDescription>Ej. Cumple / No cumple / No aplica — define su valor, puntuación y si marca no conformidad.</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">Plantilla: {templateName}</p>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="option-label">Etiqueta *</Label>
              <Input id="option-label" value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Ej. Cumple" disabled={saving} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="option-value">Valor (código) *</Label>
              <Input id="option-value" value={value} onChange={(e) => setValue(e.target.value)} placeholder="Ej. complies" disabled={saving} />
            </div>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="option-score">Puntuación (opcional)</Label>
              <Input id="option-score" type="number" step={0.01} value={score} onChange={(e) => setScore(e.target.value)} disabled={saving} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="option-sequence">Orden *</Label>
              <Input id="option-sequence" type="number" min={1} step={1} value={sequence} onChange={(e) => setSequence(e.target.value)} disabled={saving} />
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Switch id="option-failure" checked={isFailure} onCheckedChange={setIsFailure} disabled={saving} />
            <Label htmlFor="option-failure">Marca no conformidad (ej. "No cumple")</Label>
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving || !templateId}>
              {saving ? 'Guardando…' : 'Guardar opción'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
