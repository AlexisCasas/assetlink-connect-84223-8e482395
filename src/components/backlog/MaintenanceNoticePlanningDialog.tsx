import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { OrderForm } from '@/components/requests/OrderForm';
import { useToast } from '@/hooks/use-toast';
import { persistRequest } from '@/lib/requestPersistence';
import { generateUuid } from '@/lib/uuid';
import type { Request } from '@/types/request';
import type { MaintenanceNotice } from '@/types/maintenanceNotice';

interface MaintenanceNoticePlanningDialogProps {
  notice: MaintenanceNotice;
  onClose: () => void;
  onConvert: (noticeId: string, requestId: string) => Promise<void>;
}

/**
 * Convertir un aviso en solicitud.
 *
 * Deliberadamente NO reimplementa el formulario ni el guardado: monta el
 * mismo OrderForm que usa el módulo de Solicitudes y guarda con
 * persistRequest (la única implementación del flujo, extraída de
 * RequestList). Recién cuando la solicitud quedó guardada de verdad se
 * llama a convert_maintenance_notice para vincularla al aviso.
 *
 * Ese orden importa: si la vinculación falla (corte de red), la solicitud ya
 * existe y el aviso sigue pendiente, así que reintentar la conversión con
 * esa misma solicitud es un no-op exitoso en el backend — nunca hace falta
 * crear una segunda solicitud duplicada.
 */
export function MaintenanceNoticePlanningDialog({ notice, onClose, onConvert }: MaintenanceNoticePlanningDialogProps) {
  const { user, currentOrganization, currentMembership } = useAuth();
  const { toast } = useToast();

  // Prefill: lo que el aviso ya sabe (activo, sede, qué falla) no se le
  // vuelve a pedir a quien planifica. status 'draft' es intencional — el
  // formulario bloquea el tipo de solicitud solo para solicitudes que ya
  // salieron de borrador, y esta todavía no existe.
  const prefill = useMemo<Request>(() => ({
    id: generateUuid(),
    organizationId: currentOrganization?.id,
    requestNumber: '',
    title: notice.title,
    description: [
      notice.description,
      '',
      `Origen: aviso ${notice.noticeNumber}.`,
    ].join('\n'),
    asset: notice.assetPathSnapshot || notice.assetNameSnapshot || '',
    assetId: notice.assetId,
    location: notice.branchNameSnapshot || '',
    serviceType: 'correctivo',
    deadline: '',
    selectedProviders: [],
    status: 'draft',
    createdAt: new Date().toISOString(),
    createdBy: user?.email || '',
    priority: 2,
    branchId: notice.branchIdSnapshot || undefined,
    coordinationContactMemberId: currentMembership?.id,
    coordinationContactName: user?.name || undefined,
    coordinationContactEmail: user?.email || undefined,
  }), [notice, currentOrganization?.id, currentMembership?.id, user?.email, user?.name]);

  const handleSave = async (request: Request, isDraft: boolean) => {
    if (!currentOrganization) {
      toast({ title: 'Organización requerida', description: 'Selecciona una organización activa.', variant: 'destructive' });
      return;
    }

    try {
      await persistRequest({
        request,
        isDraft,
        organizationId: currentOrganization.id,
        actor: { id: user?.id, email: user?.email, name: user?.name },
      });
    } catch (error) {
      toast({
        title: 'No se pudo guardar la solicitud',
        description: error instanceof Error ? error.message : 'El aviso sigue pendiente.',
        variant: 'destructive',
      });
      return;
    }

    try {
      await onConvert(notice.id, request.id);
    } catch (error) {
      // La solicitud SÍ quedó guardada: decirlo explícitamente evita que se
      // cree otra por creer que no pasó nada.
      toast({
        title: 'La solicitud se guardó, pero no quedó vinculada al aviso',
        description: error instanceof Error ? error.message : 'Vuelve a intentar la conversión desde el aviso.',
        variant: 'destructive',
      });
      onClose();
      return;
    }

    toast({
      title: 'Aviso convertido',
      description: `${notice.noticeNumber} quedó vinculado a la solicitud creada.`,
    });
    onClose();
  };

  return <OrderForm onClose={onClose} onSave={handleSave} editingRequest={prefill} />;
}
