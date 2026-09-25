import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import {
  THRESHOLDS_CHANGE_NOTICE,
  THRESHOLD_FIELD_LABELS,
  formatThresholdTriplet,
  parseThresholdInput,
  thresholdRanges,
  validateThresholdValues,
} from '@/lib/criticalityThresholds';
import type { CriticalityThresholdValues, CriticalityThresholds } from '@/types/criticalityMatrix';

interface CriticalityThresholdsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  thresholds: CriticalityThresholds;
  saving: boolean;
  /** Returns null on success, or the server's error message. */
  onSave: (values: CriticalityThresholdValues) => Promise<string | null>;
}

const FIELDS: Array<keyof CriticalityThresholdValues> = ['mediumMin', 'highMin', 'criticalMin'];

type FormState = Record<keyof CriticalityThresholdValues, string>;

const toForm = (values: CriticalityThresholdValues): FormState => ({
  mediumMin: String(values.mediumMin),
  highMin: String(values.highMin),
  criticalMin: String(values.criticalMin),
});

export function CriticalityThresholdsDialog({ open, onOpenChange, thresholds, saving, onSave }: CriticalityThresholdsDialogProps) {
  const [form, setForm] = useState<FormState>(toForm(thresholds));
  const [serverError, setServerError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setForm(toForm(thresholds));
    setServerError(null);
  }, [open, thresholds]);

  const parsed = FIELDS.reduce<Partial<CriticalityThresholdValues>>((acc, field) => {
    const value = parseThresholdInput(form[field]);
    if (value !== null) acc[field] = value;
    return acc;
  }, {});
  const fieldErrors = FIELDS.filter((field) => parsed[field] === undefined).map(
    (field) => `"${THRESHOLD_FIELD_LABELS[field]}" debe ser un número mayor o igual a 0 con como máximo 2 decimales.`,
  );
  const complete = fieldErrors.length === 0 ? (parsed as CriticalityThresholdValues) : null;
  const errors = complete ? [...fieldErrors, ...validateThresholdValues(complete)] : fieldErrors;
  const canSave = !!complete && errors.length === 0;

  const handleSave = async () => {
    if (!complete || !canSave) return;
    setServerError(null);
    const error = await onSave(complete);
    if (error) {
      setServerError(error);
    } else {
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(next) => !saving && onOpenChange(next)}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Umbrales de clasificación</DialogTitle>
          <DialogDescription>
            Cada valor es el score mínimo (inclusive) de su categoría. Deben ser números ≥ 0, con hasta 2 decimales y estrictamente ascendentes.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-3 sm:grid-cols-3">
          {FIELDS.map((field) => (
            <div key={field} className="space-y-1">
              <Label htmlFor={`threshold-${field}`}>{THRESHOLD_FIELD_LABELS[field]}</Label>
              <Input
                id={`threshold-${field}`}
                inputMode="decimal"
                value={form[field]}
                onChange={(event) => setForm((current) => ({ ...current, [field]: event.target.value }))}
                disabled={saving}
              />
            </div>
          ))}
        </div>

        {complete && errors.length === 0 && (
          <div className="flex flex-wrap gap-1.5">
            {thresholdRanges(complete).map((item) => (
              <Badge key={item.criticality} variant="outline" className="text-xs font-normal">
                {item.label}: {item.range}
              </Badge>
            ))}
          </div>
        )}

        {complete && complete.mediumMin === 0 && errors.length === 0 && (
          <p className="rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-sm">
            Con "Media desde" = 0 ninguna evaluación puede resultar Baja (el score nunca es negativo).
          </p>
        )}

        {errors.length > 0 && (
          <div className="space-y-1 text-sm text-destructive">
            {errors.map((message) => <p key={message}>{message}</p>)}
          </div>
        )}
        {serverError && <p className="text-sm text-destructive">{serverError}</p>}

        <p className="text-xs text-muted-foreground">{THRESHOLDS_CHANGE_NOTICE}</p>

        <DialogFooter className="gap-2 sm:justify-between">
          <Button
            variant="ghost"
            onClick={() => setForm(toForm(thresholds.defaults))}
            disabled={saving}
            title={`Valores por defecto: ${formatThresholdTriplet(thresholds.defaults)}`}
          >
            Restablecer valores por defecto
          </Button>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSave()} disabled={saving || !canSave}>
              {saving ? 'Guardando…' : 'Guardar umbrales'}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
