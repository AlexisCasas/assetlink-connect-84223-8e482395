import { useState, type FormEvent } from 'react';
import { CalendarClock } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  updateDelegatedInternalWorkOrderPlanning,
  type DelegatedWorkOrder,
  type InternalPlanningPriority,
} from '@/lib/delegatedWorkOrders';

const priorities: { value: InternalPlanningPriority; label: string }[] = [
  { value: 'low', label: 'Baja' },
  { value: 'medium', label: 'Media' },
  { value: 'high', label: 'Alta' },
  { value: 'urgent', label: 'Urgente' },
];

/** HTML datetime-local uses the user's local timezone, but RPC uses UTC.
 * Keep the original DB timestamp unchanged when the input is not edited. */
function toLocalDateTime(value: string | null): string {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000)
    .toISOString().slice(0, 16);
}

function toRpcDateTime(input: string, previous: string | null): string | null {
  if (input === toLocalDateTime(previous)) return previous;
  if (input === '') return null;
  const date = new Date(input);
  if (!Number.isFinite(date.getTime())) throw new Error('La fecha ingresada no es válida.');
  return date.toISOString();
}

export function DelegatedWorkOrderPlanningForm({
  clientOrganizationId,
  workOrder,
  onSaved,
}: {
  clientOrganizationId: string;
  workOrder: DelegatedWorkOrder;
  onSaved: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [priority, setPriority] = useState<InternalPlanningPriority>(
    (['low', 'medium', 'high', 'urgent'].includes(workOrder.priority)
      ? workOrder.priority : 'medium') as InternalPlanningPriority,
  );
  const [scheduledAt, setScheduledAt] = useState(toLocalDateTime(workOrder.scheduledAt));
  const [dueAt, setDueAt] = useState(toLocalDateTime(workOrder.dueAt));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const reset = () => {
    setPriority(workOrder.priority as InternalPlanningPriority);
    setScheduledAt(toLocalDateTime(workOrder.scheduledAt));
    setDueAt(toLocalDateTime(workOrder.dueAt));
    setError(null);
    setSaved(false);
  };

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving) return;
    setError(null);
    setSaved(false);
    setSaving(true);
    try {
      const nextScheduledAt = toRpcDateTime(scheduledAt, workOrder.scheduledAt);
      const nextDueAt = toRpcDateTime(dueAt, workOrder.dueAt);
      await updateDelegatedInternalWorkOrderPlanning(clientOrganizationId, workOrder, {
        priority,
        scheduledAt: nextScheduledAt,
        dueAt: nextDueAt,
      });
      setEditing(false);
      setSaved(true);
      onSaved();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo guardar la planificación.');
    } finally {
      setSaving(false);
    }
  }

  if (!editing) {
    return (
      <div className="space-y-2 rounded-md border bg-muted/20 p-4" data-testid="delegated-planning-permitted">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="flex items-center gap-2 text-sm font-semibold">
              <CalendarClock className="h-4 w-4" /> Coordinación de planificación
            </p>
            <p className="text-xs text-muted-foreground">
              Puedes ajustar prioridad y fechas; no el estado, técnicos ni la ejecución.
            </p>
          </div>
          <Button type="button" size="sm" variant="outline" onClick={() => {
            reset();
            setEditing(true);
          }}>
            Editar planificación
          </Button>
        </div>
        {saved && <p role="status" className="text-sm text-green-700">Planificación guardada correctamente.</p>}
      </div>
    );
  }

  return (
    <form onSubmit={(e) => void submit(e)} className="space-y-4 rounded-md border bg-muted/20 p-4" data-testid="delegated-planning-form">
      <div>
        <p className="font-semibold">Planificar orden interna</p>
        <p className="text-xs text-muted-foreground">Solo se guardarán prioridad, fecha programada y fecha límite.</p>
      </div>
      <div className="space-y-2">
        <Label htmlFor="fm-wo-priority">Prioridad</Label>
        <Select value={priority} onValueChange={(v) => setPriority(v as InternalPlanningPriority)} disabled={saving}>
          <SelectTrigger id="fm-wo-priority"><SelectValue placeholder="Seleccionar prioridad" /></SelectTrigger>
          <SelectContent>
            {priorities.map(({ value, label }) => <SelectItem key={value} value={value}>{label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor="fm-wo-scheduled">Fecha programada</Label>
          <Input id="fm-wo-scheduled" type="datetime-local" value={scheduledAt}
            disabled={saving} onChange={(e) => setScheduledAt(e.target.value)} />
        </div>
        <div className="space-y-2">
          <Label htmlFor="fm-wo-due">Fecha límite</Label>
          <Input id="fm-wo-due" type="datetime-local" value={dueAt}
            disabled={saving} onChange={(e) => setDueAt(e.target.value)} />
        </div>
      </div>
      <p className="text-xs text-muted-foreground">
        Las fechas vacías se guardan sin programación. Si otra persona modificó la orden,
        el sistema rechazará tu cambio y deberás actualizarla.
      </p>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={saving}>{saving ? 'Guardando…' : 'Guardar planificación'}</Button>
        <Button type="button" variant="outline" disabled={saving} onClick={() => {reset(); setEditing(false);}}>
          Cancelar
        </Button>
      </div>
    </form>
  );
}
