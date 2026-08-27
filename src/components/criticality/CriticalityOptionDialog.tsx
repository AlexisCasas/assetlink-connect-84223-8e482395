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
import type { CriticalityOption, CriticalityOptionInput } from '@/types/criticalityMatrix';

interface CriticalityOptionDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  parameterId: string | null;
  parameterName: string;
  option: CriticalityOption | null;
  nextSequence: number;
  saving: boolean;
  onSave: (input: CriticalityOptionInput, optionId: string | undefined) => Promise<boolean>;
}

export function CriticalityOptionDialog({ open, onOpenChange, parameterId, parameterName, option, nextSequence, saving, onSave }: CriticalityOptionDialogProps) {
  const [label, setLabel] = useState('');
  const [score, setScore] = useState('0');
  const [sequence, setSequence] = useState('1');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setLabel(option?.label ?? '');
    setScore(option ? String(option.score) : '0');
    setSequence(String(option?.sequence ?? nextSequence));
    setFormError(null);
  }, [open, option, nextSequence]);

  const handleSubmit = async () => {
    if (!parameterId) return;
    if (!label.trim()) {
      setFormError('La etiqueta de la opción es obligatoria.');
      return;
    }
    const scoreNumber = Number(score);
    if (Number.isNaN(scoreNumber) || scoreNumber < 0) {
      setFormError('La puntuación debe ser un número mayor o igual a 0.');
      return;
    }
    const sequenceNumber = Number(sequence);
    if (!Number.isInteger(sequenceNumber) || sequenceNumber <= 0) {
      setFormError('El orden debe ser un número entero mayor a 0.');
      return;
    }
    setFormError(null);

    const input: CriticalityOptionInput = {
      parameterId,
      label: label.trim(),
      score: scoreNumber,
      sequence: sequenceNumber,
    };
    const ok = await onSave(input, option?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{option ? 'Editar opción' : 'Nueva opción'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <p className="text-sm text-muted-foreground">Parámetro: {parameterName}</p>

          <div className="space-y-1">
            <Label htmlFor="option-label">Etiqueta *</Label>
            <Input id="option-label" value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Ej. Sí, No, Alto, Bajo…" disabled={saving} />
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="option-score">Puntuación *</Label>
              <Input id="option-score" type="number" min={0} step={0.01} value={score} onChange={(e) => setScore(e.target.value)} disabled={saving} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="option-sequence">Orden *</Label>
              <Input id="option-sequence" type="number" min={1} step={1} value={sequence} onChange={(e) => setSequence(e.target.value)} disabled={saving} />
            </div>
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving || !parameterId}>
              {saving ? 'Guardando…' : 'Guardar opción'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
