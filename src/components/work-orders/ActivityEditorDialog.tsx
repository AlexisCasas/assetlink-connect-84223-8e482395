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
import { Checkbox } from '@/components/ui/checkbox';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useOrganizationTechnicians } from '@/hooks/useOrganizationTechnicians';
import { toDatetimeLocalValue, fromDatetimeLocalValue } from '@/lib/dateTime';
import { WORK_ORDER_ACTIVITY_STATUS_LABELS } from '@/components/requests/StatusBadge';
import type { WorkOrderActivity, WorkOrderActivityInput, WorkOrderActivityStatus } from '@/types/workOrderActivity';

interface ActivityEditorDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  organizationId: string;
  /** null creates a new activity. */
  activity: WorkOrderActivity | null;
  nextSequence: number;
  saving: boolean;
  onSave: (input: WorkOrderActivityInput, activityId: string | undefined, sequence: number) => Promise<boolean>;
}

export function ActivityEditorDialog({ open, onOpenChange, organizationId, activity, nextSequence, saving, onSave }: ActivityEditorDialogProps) {
  const { technicians, loading: loadingTechnicians } = useOrganizationTechnicians(organizationId);

  const [description, setDescription] = useState('');
  const [estimatedHours, setEstimatedHours] = useState('');
  const [dueAt, setDueAt] = useState('');
  const [status, setStatus] = useState<WorkOrderActivityStatus>('pending');
  const [sequence, setSequence] = useState(1);
  const [selectedMemberIds, setSelectedMemberIds] = useState<string[]>([]);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setDescription(activity?.description ?? '');
    setEstimatedHours(activity?.estimatedHours != null ? String(activity.estimatedHours) : '');
    setDueAt(toDatetimeLocalValue(activity?.dueAt ?? null));
    setStatus(activity?.status ?? 'pending');
    setSequence(activity?.sequence ?? nextSequence);
    setSelectedMemberIds(activity?.technicians.map((technician) => technician.memberId) ?? []);
    setFormError(null);
  }, [open, activity, nextSequence]);

  const toggleMember = (memberId: string) => {
    setSelectedMemberIds((current) => (
      current.includes(memberId) ? current.filter((id) => id !== memberId) : [...current, memberId]
    ));
  };

  const handleSubmit = async () => {
    if (!description.trim()) {
      setFormError('La descripción es obligatoria.');
      return;
    }
    const hours = estimatedHours.trim() === '' ? null : Number(estimatedHours);
    if (hours !== null && (Number.isNaN(hours) || hours < 0)) {
      setFormError('Las horas estimadas deben ser un número mayor o igual a 0.');
      return;
    }
    setFormError(null);

    const input: WorkOrderActivityInput = {
      description: description.trim(),
      estimatedHours: hours,
      dueAt: fromDatetimeLocalValue(dueAt),
      status,
      memberIds: selectedMemberIds,
    };
    const ok = await onSave(input, activity?.id, sequence);
    if (ok) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{activity ? 'Editar actividad' : 'Nueva actividad'}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-1">
            <Label htmlFor="activity-description">Descripción *</Label>
            <Textarea
              id="activity-description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Ej. Cambiar rodamiento"
              disabled={saving}
              rows={2}
            />
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="activity-hours">Horas estimadas</Label>
              <Input
                id="activity-hours"
                type="number"
                min={0}
                step={0.25}
                value={estimatedHours}
                onChange={(e) => setEstimatedHours(e.target.value)}
                disabled={saving}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="activity-sequence">Orden / secuencia</Label>
              <Input
                id="activity-sequence"
                type="number"
                min={1}
                step={1}
                value={sequence}
                onChange={(e) => setSequence(Math.max(1, parseInt(e.target.value, 10) || 1))}
                disabled={saving}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="activity-due-at">Fecha límite (opcional)</Label>
              <Input
                id="activity-due-at"
                type="datetime-local"
                value={dueAt}
                onChange={(e) => setDueAt(e.target.value)}
                disabled={saving}
              />
            </div>
            <div className="space-y-1">
              <Label>Estado</Label>
              <Select value={status} onValueChange={(value) => setStatus(value as WorkOrderActivityStatus)} disabled={saving}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent className="bg-popover">
                  {Object.entries(WORK_ORDER_ACTIVITY_STATUS_LABELS).map(([value, label]) => (
                    <SelectItem key={value} value={value}>{label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="space-y-1">
            <Label>Técnico(s)</Label>
            {loadingTechnicians ? (
              <p className="text-xs text-muted-foreground">Cargando técnicos…</p>
            ) : technicians.length === 0 ? (
              <p className="text-xs text-muted-foreground">Esta organización todavía no tiene técnicos activos.</p>
            ) : (
              <div className="max-h-40 space-y-2 overflow-y-auto rounded-md border p-2">
                {technicians.map((technician) => (
                  <label key={technician.memberId} className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={selectedMemberIds.includes(technician.memberId)}
                      onCheckedChange={() => toggleMember(technician.memberId)}
                      disabled={saving}
                    />
                    {technician.name} ({technician.email})
                  </label>
                ))}
              </div>
            )}
            {selectedMemberIds.length > 1 && (
              <p className="text-xs text-muted-foreground">
                {technicians.find((technician) => technician.memberId === selectedMemberIds[0])?.name} queda como técnico principal.
              </p>
            )}
          </div>

          {formError && <p className="text-sm text-destructive">{formError}</p>}

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
            <Button onClick={() => void handleSubmit()} disabled={saving}>
              {saving ? 'Guardando…' : 'Guardar actividad'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
