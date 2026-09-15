import { useState } from 'react';
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
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { RequestAssetPicker } from '@/components/requests/RequestAssetPicker';
import { useToast } from '@/hooks/use-toast';
import type {
  CreateMaintenanceNoticeInput,
  MaintenanceNoticePriority,
} from '@/types/maintenanceNotice';
import { MAINTENANCE_NOTICE_PRIORITY_LABELS } from '@/types/maintenanceNotice';

interface MaintenanceNoticeDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreate: (input: CreateMaintenanceNoticeInput) => Promise<unknown>;
  /** Activo fijo cuando el aviso nace desde la ficha de un activo o desde
   * una no conformidad de inspección: ahí no se elige, ya se sabe cuál es. */
  fixedAsset?: { id: string; label: string };
  /** Trazabilidad cuando el aviso nace de una inspección. El backend
   * revalida que esa respuesta exista y esté marcada como no conformidad. */
  source?: { type: 'inspection_run'; runId: string; itemId: string };
  defaultTitle?: string;
  defaultDescription?: string;
}

const PRIORITIES: MaintenanceNoticePriority[] = ['low', 'medium', 'high', 'urgent'];

/** Crear un aviso de avería. Nunca crea una solicitud ni una OT: reportar y
 * planificar son decisiones separadas, y la segunda ocurre en el backlog. */
export function MaintenanceNoticeDialog({
  open,
  onOpenChange,
  onCreate,
  fixedAsset,
  source,
  defaultTitle = '',
  defaultDescription = '',
}: MaintenanceNoticeDialogProps) {
  const { toast } = useToast();
  const [assetId, setAssetId] = useState(fixedAsset?.id ?? '');
  const [title, setTitle] = useState(defaultTitle);
  const [description, setDescription] = useState(defaultDescription);
  const [priority, setPriority] = useState<MaintenanceNoticePriority>('medium');
  const [saving, setSaving] = useState(false);

  const reset = () => {
    setAssetId(fixedAsset?.id ?? '');
    setTitle(defaultTitle);
    setDescription(defaultDescription);
    setPriority('medium');
  };

  const handleSubmit = async () => {
    const effectiveAssetId = fixedAsset?.id ?? assetId;
    if (!effectiveAssetId) {
      toast({ title: 'Falta el activo', description: 'Un aviso siempre se reporta sobre un activo.', variant: 'destructive' });
      return;
    }
    if (!title.trim()) {
      toast({ title: 'Falta el título', description: 'Describe brevemente la avería.', variant: 'destructive' });
      return;
    }
    if (!description.trim()) {
      toast({ title: 'Falta la descripción', description: 'Explica qué está fallando.', variant: 'destructive' });
      return;
    }

    setSaving(true);
    try {
      await onCreate({
        assetId: effectiveAssetId,
        title: title.trim(),
        description: description.trim(),
        priority,
        source,
      });
      toast({ title: 'Aviso creado', description: 'El aviso quedó en el backlog de mantenimiento, sin revisar.' });
      reset();
      onOpenChange(false);
    } catch (error) {
      toast({
        title: 'No se pudo crear el aviso',
        description: error instanceof Error ? error.message : 'Intenta nuevamente.',
        variant: 'destructive',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) reset(); onOpenChange(next); }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Nuevo aviso de avería</DialogTitle>
          <DialogDescription>
            Reportar una avería no crea una solicitud ni una orden de trabajo. El aviso queda en el
            backlog para que se revise y se decida si corresponde intervenir.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {fixedAsset ? (
            <div className="space-y-2">
              <Label>Activo</Label>
              <p className="rounded-md border bg-muted/30 p-2 text-sm">{fixedAsset.label}</p>
            </div>
          ) : (
            <RequestAssetPicker
              assetId={assetId}
              onChange={(id) => setAssetId(id)}
              label="Activo *"
            />
          )}

          {source && (
            <p className="rounded-md border border-dashed p-2 text-xs text-muted-foreground">
              Este aviso quedará vinculado a la no conformidad de la inspección que lo originó.
            </p>
          )}

          <div className="space-y-2">
            <Label htmlFor="notice-title">Título *</Label>
            <Input
              id="notice-title"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="Ej: Fuga de refrigerante en el chiller"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="notice-description">Descripción *</Label>
            <Textarea
              id="notice-description"
              value={description}
              onChange={(event) => setDescription(event.target.value)}
              placeholder="Qué falla, desde cuándo, qué se observó"
              rows={4}
            />
          </div>

          <div className="space-y-2">
            <Label>Prioridad reportada</Label>
            <Select value={priority} onValueChange={(value) => setPriority(value as MaintenanceNoticePriority)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {PRIORITIES.map((value) => (
                  <SelectItem key={value} value={value}>{MAINTENANCE_NOTICE_PRIORITY_LABELS[value]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              Es la prioridad de quien reporta. Al revisar el aviso puede ajustarse.
            </p>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancelar</Button>
          <Button onClick={handleSubmit} disabled={saving}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Crear aviso
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
