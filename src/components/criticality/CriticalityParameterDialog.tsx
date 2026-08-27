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
import { Textarea } from '@/components/ui/textarea';
import type { CriticalityParameter, CriticalityParameterInput } from '@/types/criticalityMatrix';

interface CriticalityParameterDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  parameter: CriticalityParameter | null;
  nextSequence: number;
  saving: boolean;
  onSave: (input: CriticalityParameterInput, parameterId: string | undefined) => Promise<boolean>;
}

export function CriticalityParameterDialog({ open, onOpenChange, parameter, nextSequence, saving, onSave }: CriticalityParameterDialogProps) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [weight, setWeight] = useState('0');
  const [sequence, setSequence] = useState('1');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setName(parameter?.name ?? '');
    setDescription(parameter?.description ?? '');
    setWeight(parameter ? String(parameter.weight) : '0');
    setSequence(String(parameter?.sequence ?? nextSequence));
    setFormError(null);
  }, [open, parameter, nextSequence]);

  const handleSubmit = async () => {
    if (!name.trim()) {
      setFormError('El nombre del parámetro es obligatorio.');
      return;
    }
    const weightNumber = Number(weight);
    if (Number.isNaN(weightNumber) || weightNumber < 0) {
      setFormError('El peso debe ser un número mayor o igual a 0.');
      return;
    }
    const sequenceNumber = Number(sequence);
    if (!Number.isInteger(sequenceNumber) || sequenceNumber <= 0) {
      setFormError('El orden debe ser un número entero mayor a 0.');
      return;
    }
    setFormError(null);

    const input: CriticalityParameterInput = {
      name: name.trim(),
      description: description.trim() || null,
      weight: weightNumber,
      sequence: sequenceNumber,
    };
    const ok = await onSave(input, parameter?.id);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{parameter ? 'Editar parámetro' : 'Nuevo parámetro'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label htmlFor="param-name">Nombre *</Label>
            <Input id="param-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Ej. Sin equipo de respaldo" disabled={saving} />
          </div>

          <div className="space-y-1">
            <Label htmlFor="param-description">Descripción</Label>
            <Textarea id="param-description" value={description} onChange={(e) => setDescription(e.target.value)} disabled={saving} />
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="param-weight">Peso (%) *</Label>
              <Input id="param-weight" type="number" min={0} step={0.01} value={weight} onChange={(e) => setWeight(e.target.value)} disabled={saving} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="param-sequence">Orden *</Label>
              <Input id="param-sequence" type="number" min={1} step={1} value={sequence} onChange={(e) => setSequence(e.target.value)} disabled={saving} />
            </div>
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving}>
              {saving ? 'Guardando…' : 'Guardar parámetro'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
