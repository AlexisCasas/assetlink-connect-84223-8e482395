import { useEffect, useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import type { TechnicianWorkOrder } from '@/types/technicianWorkOrder';

interface TechnicianWorkLogDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  workOrder: TechnicianWorkOrder | null;
  saving: boolean;
  onSubmit: (note: string, status?: string) => Promise<boolean>;
}

/** Only the transition a technician is allowed to make from the OT's
 * current status — mirrors technician_update_work_order_progress exactly.
 * Empty when there is nothing left to advance to (e.g. already completed). */
const nextStatusFor = (status: string): { value: string; label: string } | null => {
  if (status === 'pending' || status === 'assigned') return { value: 'in_progress', label: 'Marcar "En ejecución"' };
  if (status === 'in_progress') return { value: 'completed', label: 'Marcar "Finalizada"' };
  return null;
};

export function TechnicianWorkLogDialog({ open, onOpenChange, workOrder, saving, onSubmit }: TechnicianWorkLogDialogProps) {
  const [note, setNote] = useState('');
  const [changeStatus, setChangeStatus] = useState('none');
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setNote('');
    setChangeStatus('none');
    setFormError(null);
  }, [open]);

  if (!workOrder) return null;
  const nextStatus = nextStatusFor(workOrder.status);

  const handleSubmit = async () => {
    const trimmedNote = note.trim();
    const status = changeStatus === 'none' ? undefined : changeStatus;
    if (!trimmedNote && !status) {
      setFormError('Escribe una nota o selecciona un cambio de estado.');
      return;
    }
    setFormError(null);
    const ok = await onSubmit(trimmedNote, status);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Registrar trabajo</DialogTitle>
          <DialogDescription>{workOrder.workOrderNumber} — {workOrder.title || 'Orden sin título'}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label htmlFor="work-log-note">Nota</Label>
            <Textarea
              id="work-log-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Ej. Cambié el rodamiento, falta prueba final."
              disabled={saving}
              rows={3}
            />
          </div>

          {nextStatus && (
            <div className="space-y-1">
              <Label>Cambiar estado (opcional)</Label>
              <Select value={changeStatus} onValueChange={setChangeStatus} disabled={saving}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent className="bg-popover">
                  <SelectItem value="none">No cambiar estado</SelectItem>
                  <SelectItem value={nextStatus.value}>{nextStatus.label}</SelectItem>
                </SelectContent>
              </Select>
            </div>
          )}

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving}>
              {saving ? 'Guardando…' : 'Guardar'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
