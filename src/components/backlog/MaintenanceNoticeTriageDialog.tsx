import { useEffect, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useToast } from '@/hooks/use-toast';
import { useOrganizationPlanners } from '@/hooks/useOrganizationPlanners';
import type { MaintenanceNotice, MaintenanceNoticePriority, TriageMaintenanceNoticeInput } from '@/types/maintenanceNotice';
import { MAINTENANCE_NOTICE_PRIORITY_LABELS } from '@/types/maintenanceNotice';
import { RESPONSIBLE_UNAVAILABLE_LABEL } from '@/lib/assetLabels';

interface MaintenanceNoticeTriageDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  notice: MaintenanceNotice | null;
  organizationId: string | null | undefined;
  onTriage: (input: TriageMaintenanceNoticeInput) => Promise<void>;
  /** responsible_member_id is client-owned: a delegated Facility Manager sees
   * it read-only and never loads the client roster. */
  canChooseResponsible?: boolean;
}

const PRIORITIES: MaintenanceNoticePriority[] = ['low', 'medium', 'high', 'urgent'];
const NO_RESPONSIBLE = '__none__';

/** Revisar un aviso: confirmar o corregir la prioridad reportada, dejar
 * notas y asignar un responsable de seguimiento. Revisar NO planifica nada
 * — el aviso sigue siendo un aviso hasta que alguien decida convertirlo. */
export function MaintenanceNoticeTriageDialog({
  open,
  onOpenChange,
  notice,
  organizationId,
  onTriage,
  canChooseResponsible = true,
}: MaintenanceNoticeTriageDialogProps) {
  const { toast } = useToast();
  const { planners, loading: loadingPlanners } = useOrganizationPlanners(open && canChooseResponsible ? organizationId : null);
  const [priority, setPriority] = useState<MaintenanceNoticePriority>('medium');
  const [triageNotes, setTriageNotes] = useState('');
  const [responsibleMemberId, setResponsibleMemberId] = useState<string>(NO_RESPONSIBLE);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!notice) return;
    setPriority(notice.priority);
    setTriageNotes(notice.triageNotes ?? '');
    setResponsibleMemberId(notice.responsibleMemberId ?? NO_RESPONSIBLE);
  }, [notice]);

  if (!notice) return null;

  const originalResponsible = notice.responsibleMemberId ?? NO_RESPONSIBLE;
  // The current responsible may no longer be an active owner/admin/manager
  // (e.g. inherited from the asset and deactivated later): it stays visible
  // and can be kept, but it cannot be re-selected once changed.
  const showUnavailableResponsible = !!notice.responsibleMemberId && !loadingPlanners
    && !planners.some((planner) => planner.memberId === notice.responsibleMemberId);

  const handleSubmit = async () => {
    setSaving(true);
    try {
      await onTriage({
        noticeId: notice.id,
        priority,
        triageNotes: triageNotes.trim() || undefined,
        // undefined = conservar (sin revalidar), null = desasignar, UUID = asignar.
        // A delegated FM never sends a responsible change (the backend
        // rejects it): "keep" is expressed by omitting it.
        responsibleMemberId: !canChooseResponsible || responsibleMemberId === originalResponsible
          ? undefined
          : responsibleMemberId === NO_RESPONSIBLE ? null : responsibleMemberId,
      });
      toast({ title: 'Aviso revisado', description: `${notice.noticeNumber} quedó marcado como revisado.` });
      onOpenChange(false);
    } catch (error) {
      toast({
        title: 'No se pudo revisar el aviso',
        description: error instanceof Error ? error.message : 'Intenta nuevamente.',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Revisar {notice.noticeNumber}</DialogTitle>
          <DialogDescription>{notice.title}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Prioridad</Label>
            <Select value={priority} onValueChange={(value) => setPriority(value as MaintenanceNoticePriority)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {PRIORITIES.map((value) => (
                  <SelectItem key={value} value={value}>{MAINTENANCE_NOTICE_PRIORITY_LABELS[value]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>Responsable de seguimiento</Label>
            {!canChooseResponsible ? (
              <p className="rounded-md border bg-muted/40 p-2 text-sm text-muted-foreground" data-testid="notice-responsible-readonly">
                {notice.responsibleName ?? 'Sin responsable asignado'} — lo asigna el cliente.
              </p>
            ) : (
            <Select value={responsibleMemberId} onValueChange={setResponsibleMemberId} disabled={loadingPlanners}>
              <SelectTrigger><SelectValue placeholder="Sin responsable" /></SelectTrigger>
              <SelectContent>
                <SelectItem value={NO_RESPONSIBLE}>Sin responsable</SelectItem>
                {showUnavailableResponsible && (
                  <SelectItem value={notice.responsibleMemberId!} disabled>
                    {notice.responsibleName ? `${notice.responsibleName} — ` : ''}{RESPONSIBLE_UNAVAILABLE_LABEL}
                  </SelectItem>
                )}
                {planners.map((planner) => (
                  <SelectItem key={planner.memberId} value={planner.memberId}>
                    {planner.name} — {planner.email}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="triage-notes">Notas de revisión</Label>
            <Textarea
              id="triage-notes"
              value={triageNotes}
              onChange={(event) => setTriageNotes(event.target.value)}
              placeholder="Qué se verificó, qué falta por confirmar"
              rows={4}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
          <Button onClick={handleSubmit} disabled={saving}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Guardar revisión
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
