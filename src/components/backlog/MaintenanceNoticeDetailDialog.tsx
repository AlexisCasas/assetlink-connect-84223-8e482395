import { useState } from 'react';
import { format } from 'date-fns';
import { es } from 'date-fns/locale';
import { Loader2 } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
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
import { Separator } from '@/components/ui/separator';
import { Textarea } from '@/components/ui/textarea';
import { useToast } from '@/hooks/use-toast';
import { ASSET_CRITICALITY_LABELS } from '@/lib/assetLabels';
import type { MaintenanceNotice } from '@/types/maintenanceNotice';
import {
  MAINTENANCE_NOTICE_PRIORITY_COLORS,
  MAINTENANCE_NOTICE_PRIORITY_LABELS,
  MAINTENANCE_NOTICE_SOURCE_LABELS,
  MAINTENANCE_NOTICE_STATUS_COLORS,
  MAINTENANCE_NOTICE_STATUS_LABELS,
} from '@/types/maintenanceNotice';

interface MaintenanceNoticeDetailDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  notice: MaintenanceNotice | null;
  /** owner/admin/manager. Un técnico o solicitante ve el detalle completo
   * pero sin acciones de gestión — el backend lo rechaza igual. */
  canManage: boolean;
  /** Convert into a Request (delegated since 9C.4 with requests.create). */
  canConvertToRequest?: boolean;
  /** Opens the generated request (delegated mode, requests.view). */
  onViewRequest?: (requestId: string) => void;
  /** Live asset criticality is shown only with criticality.view. */
  showCriticality?: boolean;
  onTriage: () => void;
  onPlan: () => void;
  onDismiss: (noticeId: string, reason: string) => Promise<void>;
}

const formatMoment = (value: string | null) =>
  value ? format(new Date(value), "d 'de' MMMM yyyy, HH:mm", { locale: es }) : '—';

const Field = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div className="space-y-1">
    <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
    <div className="text-sm">{children}</div>
  </div>
);

export function MaintenanceNoticeDetailDialog({
  open,
  onOpenChange,
  notice,
  canManage,
  canConvertToRequest = true,
  onViewRequest,
  showCriticality = true,
  onTriage,
  onPlan,
  onDismiss,
}: MaintenanceNoticeDetailDialogProps) {
  const { toast } = useToast();
  const [dismissing, setDismissing] = useState(false);
  const [showDismissForm, setShowDismissForm] = useState(false);
  const [reason, setReason] = useState('');

  if (!notice) return null;

  const isPending = notice.status === 'open' || notice.status === 'triaged';

  const handleDismiss = async () => {
    if (!reason.trim()) {
      toast({ title: 'Falta el motivo', description: 'Explica por qué se descarta el aviso.', variant: 'destructive' });
      return;
    }
    setDismissing(true);
    try {
      await onDismiss(notice.id, reason.trim());
      toast({ title: 'Aviso descartado', description: `${notice.noticeNumber} queda archivado con su motivo.` });
      setShowDismissForm(false);
      setReason('');
      onOpenChange(false);
    } catch (error) {
      toast({
        title: 'No se pudo descartar el aviso',
        description: error instanceof Error ? error.message : 'Intenta nuevamente.',
        variant: 'destructive',
      });
    } finally {
      setDismissing(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) { setShowDismissForm(false); setReason(''); } onOpenChange(next); }}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex flex-wrap items-center gap-2">
            {notice.noticeNumber}
            <Badge variant="outline" className={MAINTENANCE_NOTICE_STATUS_COLORS[notice.status]}>
              {MAINTENANCE_NOTICE_STATUS_LABELS[notice.status]}
            </Badge>
            <Badge variant="outline" className={MAINTENANCE_NOTICE_PRIORITY_COLORS[notice.priority]}>
              {MAINTENANCE_NOTICE_PRIORITY_LABELS[notice.priority]}
            </Badge>
          </DialogTitle>
          <DialogDescription>{notice.title}</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <Field label="Descripción">
            <p className="whitespace-pre-wrap">{notice.description}</p>
          </Field>

          <Separator />

          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Activo (al momento del aviso)">
              <p>{notice.assetNameSnapshot ?? '—'}{notice.assetCodeSnapshot ? ` (${notice.assetCodeSnapshot})` : ''}</p>
              {notice.assetPathSnapshot && (
                <p className="text-xs text-muted-foreground">{notice.assetPathSnapshot}</p>
              )}
            </Field>
            <Field label="Sede (al momento del aviso)">{notice.branchNameSnapshot ?? '—'}</Field>
            {showCriticality && (
            <Field label="Criticidad actual del activo">
              {notice.assetCurrentCriticality ? ASSET_CRITICALITY_LABELS[notice.assetCurrentCriticality] : 'Sin evaluar'}
            </Field>
            )}
            <Field label="Origen">
              {MAINTENANCE_NOTICE_SOURCE_LABELS[notice.sourceType]}
              {notice.sourceType === 'inspection_run' && notice.sourceMetadata.itemQuestion && (
                <p className="text-xs text-muted-foreground">
                  {notice.sourceMetadata.templateName ? `${notice.sourceMetadata.templateName}: ` : ''}
                  {notice.sourceMetadata.itemQuestion}
                  {notice.sourceMetadata.responseLabel ? ` → ${notice.sourceMetadata.responseLabel}` : ''}
                </p>
              )}
            </Field>
            <Field label="Reportado por">
              {notice.reportedByName ?? '—'}
              <p className="text-xs text-muted-foreground">{formatMoment(notice.reportedAt)}</p>
            </Field>
            <Field label="Responsable de seguimiento">{notice.responsibleName ?? 'Sin asignar'}</Field>
          </div>

          {notice.triagedAt && (
            <>
              <Separator />
              <Field label="Revisión">
                <p className="whitespace-pre-wrap">{notice.triageNotes || 'Sin notas.'}</p>
                <p className="text-xs text-muted-foreground">
                  {notice.triagedByName ?? '—'} · {formatMoment(notice.triagedAt)}
                </p>
              </Field>
            </>
          )}

          {notice.status === 'converted' && (
            <>
              <Separator />
              <Field label="Convertido en solicitud">
                <p>{notice.convertedRequestNumber ?? 'Solicitud vinculada'}</p>
                <p className="text-xs text-muted-foreground">
                  {notice.convertedByName ?? '—'} · {formatMoment(notice.convertedAt)}
                </p>
                {onViewRequest && notice.convertedRequestId && (
                  <Button variant="link" className="h-auto p-0" onClick={() => onViewRequest(notice.convertedRequestId!)}>
                    Ver solicitud
                  </Button>
                )}
              </Field>
            </>
          )}

          {notice.status === 'dismissed' && (
            <>
              <Separator />
              <Field label="Descartado">
                <p className="whitespace-pre-wrap">{notice.dismissalReason}</p>
                <p className="text-xs text-muted-foreground">
                  {notice.dismissedByName ?? '—'} · {formatMoment(notice.dismissedAt)}
                </p>
              </Field>
            </>
          )}

          {showDismissForm && (
            <>
              <Separator />
              <div className="space-y-2">
                <Label htmlFor="dismiss-reason">Motivo del descarte *</Label>
                <Textarea
                  id="dismiss-reason"
                  value={reason}
                  onChange={(event) => setReason(event.target.value)}
                  placeholder="Ej: se resolvió en sitio, no requiere intervención"
                  rows={3}
                />
                <p className="text-xs text-muted-foreground">
                  El aviso no se elimina: queda archivado con su motivo y su historial.
                </p>
              </div>
            </>
          )}
        </div>

        <DialogFooter className="flex-wrap gap-2">
          {canManage && isPending && !showDismissForm && (
            <>
              <Button variant="outline" onClick={() => setShowDismissForm(true)}>Descartar</Button>
              <Button variant="outline" onClick={onTriage}>Revisar</Button>
              {canConvertToRequest && <Button onClick={onPlan}>Convertir en solicitud</Button>}
            </>
          )}
          {showDismissForm && (
            <>
              <Button variant="outline" onClick={() => { setShowDismissForm(false); setReason(''); }} disabled={dismissing}>
                Cancelar
              </Button>
              <Button variant="destructive" onClick={handleDismiss} disabled={dismissing}>
                {dismissing && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Confirmar descarte
              </Button>
            </>
          )}
          {!showDismissForm && !(canManage && isPending) && (
            <Button variant="outline" onClick={() => onOpenChange(false)}>Cerrar</Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
