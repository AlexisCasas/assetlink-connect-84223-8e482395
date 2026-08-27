import { useState } from 'react';
import { ListChecks, Plus, Pencil, Trash2, ArrowUp, ArrowDown, Users } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useToast } from '@/hooks/use-toast';
import { useWorkOrderActivities } from '@/hooks/useWorkOrderActivities';
import { WorkOrderActivityStatusBadge } from '@/components/requests/StatusBadge';
import { ActivityEditorDialog } from './ActivityEditorDialog';
import type { WorkOrderActivity, WorkOrderActivityInput } from '@/types/workOrderActivity';

interface WorkOrderActivitiesSectionProps {
  workOrderId: string;
  /** The OT's operating organization (provider_organization_id) — same
   * organization technicians are scoped to elsewhere in this dialog. */
  organizationId: string;
  canManage: boolean;
}

const formatDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('es-PE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : '—';

export function WorkOrderActivitiesSection({ workOrderId, organizationId, canManage }: WorkOrderActivitiesSectionProps) {
  const { activities, loading, saving, error, saveActivity, deleteActivity, moveActivity } = useWorkOrderActivities(workOrderId);
  const { toast } = useToast();
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingActivity, setEditingActivity] = useState<WorkOrderActivity | null>(null);
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null);

  const sorted = [...activities].sort((a, b) => a.sequence - b.sequence);
  const nextSequence = (sorted[sorted.length - 1]?.sequence ?? 0) + 1;

  const openCreate = () => { setEditingActivity(null); setEditorOpen(true); };
  const openEdit = (activity: WorkOrderActivity) => { setEditingActivity(activity); setEditorOpen(true); };

  const handleSave = async (input: WorkOrderActivityInput, activityId: string | undefined, sequence: number): Promise<boolean> => {
    const ok = await saveActivity(input, activityId, sequence);
    if (ok) {
      toast({ title: activityId ? 'Actividad actualizada' : 'Actividad creada', description: input.description });
    } else {
      toast({ title: 'No se pudo guardar la actividad', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
    }
    return ok;
  };

  const handleConfirmDelete = async () => {
    if (!pendingDeleteId) return;
    const ok = await deleteActivity(pendingDeleteId);
    setPendingDeleteId(null);
    toast(ok
      ? { title: 'Actividad eliminada' }
      : { title: 'No se pudo eliminar la actividad', description: error ?? 'Intenta nuevamente.', variant: 'destructive' });
  };

  const handleMove = async (activity: WorkOrderActivity, direction: 'up' | 'down') => {
    const ok = await moveActivity(activity, direction);
    if (!ok && error) toast({ title: 'No se pudo reordenar', description: error, variant: 'destructive' });
  };

  return (
    <div className="rounded-lg border p-3 space-y-3">
      <div className="flex items-center justify-between">
        <p className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          <ListChecks className="h-3.5 w-3.5" /> Actividades
        </p>
        {canManage && (
          <Button size="sm" variant="outline" onClick={openCreate} disabled={loading}>
            <Plus className="mr-1 h-3.5 w-3.5" /> Agregar actividad
          </Button>
        )}
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Cargando actividades…</p>
      ) : sorted.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aún no hay actividades registradas para esta OT.</p>
      ) : (
        <div className="space-y-2">
          {sorted.map((activity, index) => (
            <div key={activity.id} className="rounded-md border p-2.5">
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-start gap-2 min-w-0">
                  <span className="mt-0.5 shrink-0 rounded bg-muted px-1.5 py-0.5 text-xs font-medium text-muted-foreground">
                    {activity.sequence}
                  </span>
                  <div className="min-w-0 space-y-1">
                    <p className="text-sm font-medium break-words">{activity.description}</p>
                    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                      <span className="flex items-center gap-1">
                        <Users className="h-3 w-3" />
                        {activity.technicians.length > 0
                          ? activity.technicians.map((technician) => technician.name).join(', ')
                          : 'Sin técnico asignado'}
                      </span>
                      {activity.estimatedHours != null && <span>{activity.estimatedHours} h</span>}
                      <span>Límite: {formatDate(activity.dueAt)}</span>
                    </div>
                  </div>
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  <WorkOrderActivityStatusBadge status={activity.status} />
                  {canManage && (
                    <>
                      <Button variant="ghost" size="icon" className="h-7 w-7" disabled={saving || index === 0} onClick={() => void handleMove(activity, 'up')} title="Subir">
                        <ArrowUp className="h-3.5 w-3.5" />
                      </Button>
                      <Button variant="ghost" size="icon" className="h-7 w-7" disabled={saving || index === sorted.length - 1} onClick={() => void handleMove(activity, 'down')} title="Bajar">
                        <ArrowDown className="h-3.5 w-3.5" />
                      </Button>
                      <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openEdit(activity)} title="Editar actividad">
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive hover:text-destructive" onClick={() => setPendingDeleteId(activity.id)} title="Eliminar actividad">
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {canManage && (
        <ActivityEditorDialog
          open={editorOpen}
          onOpenChange={setEditorOpen}
          organizationId={organizationId}
          activity={editingActivity}
          nextSequence={nextSequence}
          saving={saving}
          onSave={handleSave}
        />
      )}

      <AlertDialog open={pendingDeleteId !== null} onOpenChange={(open) => !open && setPendingDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>¿Eliminar esta actividad?</AlertDialogTitle>
            <AlertDialogDescription>Esta acción no se puede deshacer.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={() => void handleConfirmDelete()}>Eliminar</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
