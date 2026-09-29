import { useEffect, useMemo, useState } from 'react';
import { OrderForm } from '@/components/requests/OrderForm';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { useAuth } from '@/contexts/AuthContext';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import { persistRequest } from '@/lib/requestPersistence';
import { fetchDelegatedRequest } from '@/lib/requestData';
import { useDirectRequestScope, type RequestScope } from '@/hooks/useRequestScope';
import type { PreventiveOccurrence, PreventivePlan } from '@/types/preventiveMaintenance';
import type { Request } from '@/types/request';

interface Props {
  plan: PreventivePlan;
  /** request_creation_id: always in direct mode; delegated (9C.4) only with
   * the planner capability (preventive manage + requests create). */
  occurrence: PreventiveOccurrence & { request_creation_id: string };
  onClose: () => void;
  onLink: (occurrenceId: string, requestId: string) => Promise<boolean>;
  /** Direct (default, historic) or delegated (Facility Manager, 9C.4). */
  requestScope?: RequestScope;
}

const text = (value: unknown) => typeof value === 'string' ? value : '';

export function PreventiveRequestDialog({ plan, occurrence, onClose, onLink, requestScope }: Props) {
  const { user, currentMembership } = useAuth();
  const { toast } = useToast();
  const directScope = useDirectRequestScope();
  const scope = requestScope ?? directScope;
  const isDelegated = scope.mode === 'facility_manager';
  const organizationId = scope.organizationId;
  const [checkingExisting, setCheckingExisting] = useState(true);
  const [existingRequest, setExistingRequest] = useState<{ id: string; request_number: string; status: string } | null>(null);

  useEffect(() => {
    let cancelled = false;
    if (!organizationId) {
      setCheckingExisting(false);
      return () => { cancelled = true; };
    }

    setCheckingExisting(true);
    setExistingRequest(null);
    // Delegated: the requests RLS is never opened to the FM; the minimized
    // detail RPC answers null for "does not exist / not visible".
    const lookup: Promise<{ data: { id: string; request_number: string; status: string } | null; error: { message: string } | null }> = isDelegated
      ? fetchDelegatedRequest(organizationId, occurrence.request_creation_id).then(
        (detail) => ({ data: detail ? { id: detail.request.id, request_number: detail.request.requestNumber, status: detail.request.status } : null, error: null }),
        (cause) => ({ data: null, error: { message: cause instanceof Error ? cause.message : 'Error' } }),
      )
      : Promise.resolve(supabase
        .from('requests')
        .select('id, request_number, status')
        .eq('id', occurrence.request_creation_id)
        .eq('organization_id', organizationId)
        .maybeSingle());
    void lookup.then(({ data, error }) => {
      if (cancelled) return;
      if (error) {
        toast({ title: 'No se pudo verificar la solicitud reservada', description: error.message, variant: 'destructive' });
      }
      setExistingRequest(data);
      setCheckingExisting(false);
    });

    return () => { cancelled = true; };
  }, [organizationId, isDelegated, occurrence.request_creation_id, toast]);

  const prefill = useMemo<Request>(() => {
    const snapshot = occurrence.scope_snapshot ?? {};
    const asset = (snapshot.asset ?? {}) as Record<string, unknown>;
    const card = (snapshot.card ?? {}) as Record<string, unknown>;
    const tasks = Array.isArray(card.tasks) ? card.tasks as Record<string, unknown>[] : [];
    const materials = Array.isArray(card.materials) ? card.materials as Record<string, unknown>[] : [];
    const branchId = text(asset.branch_id);
    const branchName = text(asset.branch_name);
    const dueDate = occurrence.due_at ? new Date(occurrence.due_at).toISOString().slice(0, 10) : '';
    return {
      id: occurrence.request_creation_id,
      organizationId: organizationId ?? undefined,
      requestNumber: `MP-${occurrence.request_creation_id.slice(0, 8).toUpperCase()}`,
      title: `Mantenimiento preventivo — ${plan.card_name}`,
      description: [
        text(card.description) || `Ejecución de ficha ${plan.card_code} — ${plan.card_name}.`,
        `Plan preventivo · ciclo #${occurrence.sequence}.`,
      ].join('\n\n'),
      asset: text(asset.path) || plan.asset_path || plan.asset_name,
      assetId: plan.asset_id,
      location: branchName,
      serviceType: 'preventivo',
      requestType: plan.default_request_type,
      deadline: dueDate,
      selectedProviders: [],
      status: 'draft',
      createdAt: new Date().toISOString(),
      createdBy: user?.email || '',
      priority: plan.priority === 'urgent' ? 1 : plan.priority === 'high' ? 2 : plan.priority === 'medium' ? 3 : 4,
      branchId: branchId || undefined,
      branch: branchName,
      store: branchName,
      city: '',
      // Delegated: the FM is never a client member.
      coordinationContactMemberId: isDelegated ? undefined : currentMembership?.id,
      coordinationContactName: isDelegated ? undefined : (user?.name || undefined),
      coordinationContactEmail: isDelegated ? undefined : (user?.email || undefined),
      details: [{
        equipment: plan.asset_name,
        activities: tasks.map((task) => text(task.title)).filter(Boolean).join('\n'),
        relevantMaterials: materials.map((material) => {
          const label = text(material.name) || text(material.description);
          return `${String(material.quantity ?? '')} ${text(material.unit)} · ${label}`.trim();
        }).filter(Boolean).join('\n'),
        observation: [
          text(card.procedure_notes) && `Procedimiento: ${text(card.procedure_notes)}`,
          text(card.safety_notes) && `Seguridad: ${text(card.safety_notes)}`,
        ].filter(Boolean).join('\n'),
      }],
    };
  }, [currentMembership?.id, organizationId, isDelegated, occurrence, plan, user?.email, user?.name]);

  const save = async (request: Request, isDraft: boolean) => {
    if (!organizationId) return;
    try {
      await persistRequest({
        request: { ...request, id: occurrence.request_creation_id, assetId: plan.asset_id, serviceType: 'preventivo' },
        isDraft,
        organizationId,
        actor: { id: user?.id, email: user?.email, name: user?.name },
        mode: isDelegated ? 'delegated' : 'direct',
      });
    } catch (cause) {
      toast({
        title: 'No se pudo guardar la solicitud',
        description: cause instanceof Error ? cause.message : 'La ocurrencia sigue abierta.',
        variant: 'destructive',
      });
      return;
    }

    setExistingRequest({
      id: occurrence.request_creation_id,
      request_number: request.requestNumber,
      status: isDraft ? 'draft' : 'sent',
    });
    const linked = await onLink(occurrence.id, occurrence.request_creation_id);
    if (!linked) {
      toast({
        title: 'Solicitud guardada, vínculo pendiente',
        description: 'La solicitud conserva el identificador de esta ocurrencia. Corrige el problema y vuelve a guardar; no se creará otra.',
        variant: 'destructive',
      });
      return;
    }
    toast({ title: 'Mantenimiento planificado', description: 'La solicitud quedó vinculada a la ocurrencia preventiva.' });
    onClose();
  };

  const retryLink = async () => {
    const linked = await onLink(occurrence.id, occurrence.request_creation_id);
    if (!linked) {
      toast({
        title: 'El vínculo continúa pendiente',
        description: 'La solicitud existente se conserva sin crear ni sobrescribir otra.',
        variant: 'destructive',
      });
      return;
    }
    toast({ title: 'Mantenimiento planificado', description: 'La solicitud existente quedó vinculada a la ocurrencia preventiva.' });
    onClose();
  };

  if (checkingExisting) {
    return <Dialog open onOpenChange={(open) => !open && onClose()}><DialogContent><DialogHeader><DialogTitle>Verificando solicitud reservada</DialogTitle></DialogHeader><p className="text-sm text-muted-foreground">Comprobando si este ciclo ya tiene una solicitud persistida…</p></DialogContent></Dialog>;
  }

  if (existingRequest) {
    return (
      <Dialog open onOpenChange={(open) => !open && onClose()}>
        <DialogContent>
          <DialogHeader><DialogTitle>Solicitud ya guardada</DialogTitle></DialogHeader>
          <p className="text-sm text-muted-foreground">
            {existingRequest.request_number} ({existingRequest.status}) usa el identificador reservado de este ciclo. Se reintentará solamente el vínculo; sus datos no se volverán a persistir.
          </p>
          <DialogFooter><Button variant="outline" onClick={onClose}>Cancelar</Button><Button onClick={() => void retryLink()}>Reintentar vínculo</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    );
  }

  return <OrderForm onClose={onClose} onSave={save} editingRequest={prefill} lockAsset lockServiceType scope={scope} />;
}
