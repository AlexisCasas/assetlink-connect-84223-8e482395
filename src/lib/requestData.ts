import { supabase } from '@/integrations/supabase/client';
import type { DelegatedRequestAccess, Request, RequestDetailData } from '@/types/request';

/**
 * Lectura de Solicitudes compartida por RequestList y DraftList, con dos
 * transportes:
 *   - directo (miembros del cliente): tablas con RLS, sin cambios;
 *   - delegado (Facility Manager, 9C.4): RPCs SECURITY DEFINER que devuelven
 *     la solicitud minimizada. La RLS de requests nunca se abre al FM.
 */

/** Fila de public.requests -> Request. El mapeo completo (antes duplicado,
 * e incompleto en DraftList). */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapRequestRow(req: any): Request {
  return {
    id: req.id,
    organizationId: req.organization_id,
    requestNumber: req.request_number,
    title: req.title,
    description: req.description,
    asset: req.asset,
    assetId: req.asset_id ?? undefined,
    // Legacy rows predate request_type and always behave as external.
    requestType: (req.request_type === 'internal' ? 'internal' : 'external'),
    internalResponsibleMemberId: req.internal_responsible_member_id ?? undefined,
    location: req.location,
    serviceType: req.service_type,
    observations: req.observations,
    images: req.image_urls || [],
    documents: req.document_urls || [],
    deadline: req.deadline,
    startTime: req.start_time,
    selectedProviders: [],
    status: req.status,
    createdAt: req.created_at,
    createdBy: req.created_by,
    createdByUserId: req.created_by_user_id,
    createdByName: req.created_by_name,
    createdByEmail: req.created_by_email,
    priority: req.priority,
    clientName: req.client_name,
    clientBranch: req.client_branch,
    isPublic: req.is_public,
    notifiedAt: req.notified_at,
    city: req.city,
    store: req.store,
    branch: req.branch,
    branchId: req.branch_id,
    requiresVisit: req.requires_visit,
    visitDate: req.visit_date,
    visitScheduleMode: req.visit_schedule_mode ?? undefined,
    visitContactMemberId: req.visit_contact_member_id ?? undefined,
    minQuotes: req.min_quotes ?? 3,
    coordinationContactMemberId: req.coordination_contact_member_id ?? undefined,
    coordinationContactName: req.coordination_contact_name ?? undefined,
    coordinationContactEmail: req.coordination_contact_email ?? undefined,
    serviceAddress: req.service_address ?? undefined,
    convocationMode: req.is_public ? 'public' : 'private',
  };
}

/** Filas de request_details (tabla o RPC delegada) -> detalle del formulario. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapRequestDetailRows(rows: any[]): RequestDetailData[] {
  return rows.map((d) => ({
    equipment: d.equipment || '',
    subEquipment: d.sub_equipment || '',
    area: d.area || '',
    subArea: d.sub_area || '',
    activities: d.activities || '',
    relevantMaterials: d.relevant_materials || '',
    quantity: d.quantity,
    unitMeasure: d.unit_measure || '',
    observation: d.observation || '',
    responsibleUser: d.responsible_user || '',
    delegateType: d.delegate_type || '',
  }));
}

/** Directo: detalle + invitaciones activas, para abrir el formulario. */
export async function loadDirectRequestForEdit(request: Request): Promise<Request> {
  const { data: detailsData } = await supabase.from('request_details').select('*').eq('request_id', request.id);
  let selectedProviderOrganizationIds: string[] = [];
  if (request.requestType !== 'internal') {
    const { data: accessData } = await supabase
      .from('request_provider_access')
      .select('provider_organization_id')
      .eq('request_id', request.id)
      .eq('access_type', 'invited')
      .eq('status', 'active');
    selectedProviderOrganizationIds = (accessData || []).map((access) => access.provider_organization_id);
  }
  return { ...request, details: mapRequestDetailRows(detailsData || []), selectedProviderOrganizationIds };
}

// ---------------------------------------------------------------------------
// Transporte delegado (Facility Manager)
// ---------------------------------------------------------------------------

interface DelegatedRequestPayload {
  id: string;
  organization_id: string;
  request_number: string;
  title: string | null;
  description: string;
  asset: string;
  asset_id: string | null;
  location: string;
  service_type: Request['serviceType'];
  observations: string | null;
  deadline: string;
  start_time: string | null;
  status: Request['status'];
  created_at: string;
  priority: number;
  client_name: string | null;
  client_branch: string | null;
  is_public: boolean | null;
  city: string | null;
  store: string | null;
  branch: string | null;
  branch_id: string | null;
  requires_visit: boolean | null;
  visit_date: string | null;
  visit_schedule_mode: Request['visitScheduleMode'] | null;
  min_quotes: number;
  request_type: string;
  service_address: string | null;
  created_by_name: string | null;
  coordination_contact_name: string | null;
  has_client_coordination_contact: boolean;
  has_client_visit_contact: boolean;
  internal_responsible_name: string | null;
  has_client_attachments: boolean;
  is_own: boolean;
  can_edit: boolean;
  can_delete_draft: boolean;
  can_annul: boolean;
}

export interface DelegatedRequestDetail {
  request: Request;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  detailRows: any[];
  /** Solo cuando el delegado puede editar la solicitud. */
  audience: { isPublic: boolean; providers: { organizationId: string; organizationName: string }[] } | null;
}

function mapDelegatedRequest(payload: DelegatedRequestPayload): Request {
  const access: DelegatedRequestAccess = {
    isOwn: payload.is_own,
    canEdit: payload.can_edit,
    canDeleteDraft: payload.can_delete_draft,
    canAnnul: payload.can_annul,
    hasClientAttachments: payload.has_client_attachments,
    hasClientCoordinationContact: payload.has_client_coordination_contact,
    hasClientVisitContact: payload.has_client_visit_contact,
    internalResponsibleLabel: payload.internal_responsible_name,
  };
  return {
    id: payload.id,
    organizationId: payload.organization_id,
    requestNumber: payload.request_number,
    title: payload.title ?? undefined,
    description: payload.description,
    asset: payload.asset,
    assetId: payload.asset_id ?? undefined,
    requestType: payload.request_type === 'internal' ? 'internal' : 'external',
    location: payload.location,
    serviceType: payload.service_type,
    observations: payload.observations ?? undefined,
    deadline: payload.deadline,
    startTime: payload.start_time ?? undefined,
    selectedProviders: [],
    status: payload.status,
    createdAt: payload.created_at,
    // Nunca el email del creador: solo un nombre seguro.
    createdBy: payload.created_by_name ?? '',
    createdByName: payload.created_by_name ?? undefined,
    priority: payload.priority,
    clientName: payload.client_name ?? undefined,
    clientBranch: payload.client_branch ?? undefined,
    isPublic: payload.is_public ?? undefined,
    city: payload.city ?? undefined,
    store: payload.store ?? undefined,
    branch: payload.branch ?? undefined,
    branchId: payload.branch_id ?? undefined,
    requiresVisit: payload.requires_visit ?? undefined,
    visitDate: payload.visit_date ?? undefined,
    visitScheduleMode: payload.visit_schedule_mode ?? undefined,
    minQuotes: payload.min_quotes ?? 3,
    coordinationContactName: payload.coordination_contact_name ?? undefined,
    serviceAddress: payload.service_address ?? undefined,
    convocationMode: payload.is_public ? 'public' : 'private',
    delegatedAccess: access,
  };
}

export async function fetchDelegatedRequests(clientOrganizationId: string, scope: 'sent' | 'drafts' | 'history'): Promise<Request[]> {
  const { data, error } = await supabase.rpc('get_facility_management_requests', {
    _client_organization_id: clientOrganizationId,
    _scope: scope,
  });
  if (error) throw error;
  return ((data ?? []) as unknown as DelegatedRequestPayload[]).map(mapDelegatedRequest);
}

/** null = no existe o no es visible para el delegado (no se distingue). */
export async function fetchDelegatedRequest(clientOrganizationId: string, requestId: string): Promise<DelegatedRequestDetail | null> {
  const { data, error } = await supabase.rpc('get_facility_management_request', {
    _client_organization_id: clientOrganizationId,
    _request_id: requestId,
  });
  if (error) throw error;
  if (!data) return null;
  const payload = data as unknown as {
    request: DelegatedRequestPayload;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    details: any[];
    audience: { is_public: boolean; providers: { organization_id: string; organization_name: string }[] } | null;
  };
  return {
    request: mapDelegatedRequest(payload.request),
    detailRows: payload.details ?? [],
    audience: payload.audience
      ? {
        isPublic: payload.audience.is_public,
        providers: payload.audience.providers.map((provider) => ({
          organizationId: provider.organization_id,
          organizationName: provider.organization_name,
        })),
      }
      : null,
  };
}

/** Delegado: detalle + audiencia, para abrir el formulario. `knownProviders`
 * conserva el nombre de los invitados aunque su relación ya no esté activa. */
export async function loadDelegatedRequestForEdit(clientOrganizationId: string, requestId: string): Promise<{
  request: Request;
  knownProviders: { organizationId: string; organizationName: string }[];
}> {
  const detail = await fetchDelegatedRequest(clientOrganizationId, requestId);
  if (!detail) throw new Error('La solicitud ya no está disponible.');
  const knownProviders = detail.audience?.providers ?? [];
  return {
    request: {
      ...detail.request,
      details: mapRequestDetailRows(detail.detailRows),
      selectedProviderOrganizationIds: knownProviders.map((provider) => provider.organizationId),
    },
    knownProviders,
  };
}

export async function deleteDelegatedDraft(clientOrganizationId: string, requestId: string): Promise<void> {
  const { error } = await supabase.rpc('delete_facility_management_request_draft', {
    _client_organization_id: clientOrganizationId,
    _request_id: requestId,
  });
  if (error) throw error;
}

export async function annulDelegatedRequest(clientOrganizationId: string, requestId: string): Promise<void> {
  const { error } = await supabase.rpc('annul_facility_management_request', {
    _client_organization_id: clientOrganizationId,
    _request_id: requestId,
  });
  if (error) throw error;
}
