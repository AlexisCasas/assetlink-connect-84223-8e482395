import { supabase } from '@/integrations/supabase/client';
import type { Request } from '@/types/request';

/**
 * La ÚNICA implementación de "guardar una solicitud" del producto.
 *
 * Vivía dentro de RequestList.handleSaveRequest. Se extrajo tal cual —
 * mismos pasos, mismo orden, mismas garantías — cuando el Backlog de
 * mantenimiento necesitó crear solicitudes al convertir un aviso: dos
 * implementaciones del mismo flujo terminarían divergiendo justo en lo que
 * es delicado (la atomicidad de abajo), así que RequestList y
 * MaintenanceNoticePlanningDialog llaman ambos a esta función.
 *
 * Lo que NO hace, a propósito: toasts, cerrar diálogos, recargar listas.
 * Eso es responsabilidad de quien la llama, porque es distinto en cada
 * pantalla. Aquí solo se persiste, y los errores se propagan.
 */

export interface RequestActor {
  id?: string | null;
  email?: string | null;
  name?: string | null;
}

export interface PersistRequestParams {
  request: Request;
  /** true = guardar como borrador; false = enviar. */
  isDraft: boolean;
  /** Organización activa. La solicitud siempre se escribe acotada a ella. */
  organizationId: string;
  actor: RequestActor;
}

export async function persistRequest({
  request,
  isDraft,
  organizationId,
  actor,
}: PersistRequestParams): Promise<void> {
  if (request.organizationId && request.organizationId !== organizationId) {
    throw new Error('La solicitud no pertenece a la organización activa.');
  }

  const { data: existing } = await supabase
    .from('requests')
    .select('id, status')
    .eq('id', request.id)
    .eq('organization_id', organizationId)
    .maybeSingle();

  const isExternal = (request.requestType ?? 'external') === 'external';
  // Atomicity guard (external only): a request must never reach 'sent'
  // with is_public already flipped before its audience (is_public +
  // request_provider_access) is confirmed synced by set_request_audience.
  // So for any transition into 'sent', the row is first written/kept as
  // 'draft' — invisible to every provider regardless of is_public,
  // exactly like today — and only promoted to 'sent' in a dedicated
  // final step, after set_request_audience has already succeeded. If
  // that RPC throws (network blip, a relationship revoked between page
  // load and submit, etc.), the promotion step never runs and the
  // request simply stays a normal, still-editable draft — it can never
  // be observed as request_type=external + status=sent + is_public=false
  // + 0 rows in request_provider_access. `is_public` itself is never
  // written by this insert/update anymore — set_request_audience is now
  // its only writer, for the same reason.
  const wantsToSend = !isDraft;
  const initialStatus = existing
    ? (existing.status === 'draft' ? 'draft' : existing.status)
    : 'draft';

  if (existing) {
    const { error: requestError } = await supabase
      .from('requests')
      .update({
        title: request.title || null,
        description: request.description,
        service_type: request.serviceType,
        deadline: request.deadline,
        branch_id: request.branchId || null,
        city: request.city,
        store: request.store,
        branch: request.branch,
        location: request.location,
        requires_visit: request.requiresVisit,
        visit_date: request.visitDate || null,
        visit_schedule_mode: request.requiresVisit ? (request.visitScheduleMode ?? null) : null,
        visit_contact_member_id: request.requiresVisit ? (request.visitContactMemberId || null) : null,
        asset: request.asset,
        asset_id: request.assetId || null,
        request_type: request.requestType ?? 'external',
        internal_responsible_member_id: request.internalResponsibleMemberId || null,
        status: initialStatus,
        min_quotes: request.minQuotes ?? 3,
        coordination_contact_member_id: request.coordinationContactMemberId || null,
        coordination_contact_name: request.coordinationContactName || null,
        coordination_contact_email: request.coordinationContactEmail || null,
        service_address: request.serviceAddress || null,
      })
      .eq('id', request.id)
      .eq('organization_id', organizationId);
    if (requestError) throw requestError;

    await supabase.from('request_details').delete().eq('request_id', request.id);
  } else {
    const { error: insertError } = await supabase.from('requests').insert({
      id: request.id,
      organization_id: organizationId,
      request_number: request.requestNumber,
      title: request.title || null,
      description: request.description,
      service_type: request.serviceType,
      deadline: request.deadline,
      branch_id: request.branchId || null,
      city: request.city,
      store: request.store,
      branch: request.branch,
      location: request.location,
      requires_visit: request.requiresVisit,
      visit_date: request.visitDate || null,
      visit_schedule_mode: request.requiresVisit ? (request.visitScheduleMode ?? null) : null,
      visit_contact_member_id: request.requiresVisit ? (request.visitContactMemberId || null) : null,
      asset: request.asset,
      asset_id: request.assetId || null,
      request_type: request.requestType ?? 'external',
      internal_responsible_member_id: request.internalResponsibleMemberId || null,
      status: initialStatus,
      created_by: actor.email || '',
      created_by_user_id: actor.id || null,
      created_by_name: actor.name || null,
      created_by_email: actor.email || null,
      client_name: request.clientName,
      client_branch: request.clientBranch,
      priority: request.priority,
      min_quotes: request.minQuotes ?? 3,
      coordination_contact_member_id: request.coordinationContactMemberId || null,
      coordination_contact_name: request.coordinationContactName || null,
      coordination_contact_email: request.coordinationContactEmail || null,
      service_address: request.serviceAddress || null,
    });
    if (insertError) throw insertError;
  }

  if (request.details && request.details.length > 0) {
    const detailsToInsert = request.details.map((d) => ({
      request_id: request.id,
      equipment: d.equipment || null,
      sub_equipment: d.subEquipment || null,
      area: d.area || null,
      sub_area: d.subArea || null,
      activities: d.activities || null,
      relevant_materials: d.relevantMaterials || null,
      quantity: d.quantity || null,
      unit_measure: d.unitMeasure || null,
      observation: d.observation || null,
      responsible_user: d.responsibleUser || null,
      delegate_type: d.delegateType || null,
    }));
    const { error: detailsError } = await supabase.from('request_details').insert(detailsToInsert);
    if (detailsError) throw detailsError;
  }

  // Audience (público/privado + invitaciones) se sincroniza en una sola
  // transacción server-side, después de que la fila de requests ya
  // existe — nunca se puede terminar con is_public actualizado pero sin
  // sus invitaciones (o viceversa). No aplica a solicitudes internas.
  if (isExternal) {
    const { error: audienceError } = await supabase.rpc('set_request_audience', {
      p_request_id: request.id,
      p_is_public: request.isPublic ?? true,
      p_provider_organization_ids: request.convocationMode === 'private'
        ? (request.selectedProviderOrganizationIds || [])
        : [],
    });
    if (audienceError) throw audienceError;
  }

  // Promoción final a 'sent': solo ocurre aquí, después de que
  // request_details ya se guardó y (para external) set_request_audience
  // ya confirmó éxito. Si cualquiera de esos pasos falló, esta línea
  // nunca se ejecuta y la solicitud queda como 'draft' — nunca a medio
  // camino entre borrador y enviada.
  if (wantsToSend && initialStatus === 'draft') {
    const { error: promoteError } = await supabase
      .from('requests')
      .update({ status: 'sent' })
      .eq('id', request.id)
      .eq('organization_id', organizationId);
    if (promoteError) throw promoteError;
  }
}
