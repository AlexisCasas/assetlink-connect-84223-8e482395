import {
  assertPlatformAdmin,
  createCallerClient,
  createServiceClient,
  errorResponse,
  getAuthenticatedUser,
  handleCors,
  isForbidden,
  isUuid,
  jsonResponse,
  normalizeEmail,
  requirePost,
} from '../_shared/adminAuth.ts';
import { buildInvitationAcceptUrl } from '../_shared/publicAppUrl.ts';
import { resolveInvitationRecipientKind, sendInvitationEmail } from '../_shared/invitationEmail.ts';

const organizationTypes = new Set([
  'client_company', 'provider_company', 'facility_manager',
  'subcontractor_company', 'platform_admin',
]);

Deno.serve(async (req) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    requirePost(req);
    const caller = await getAuthenticatedUser(req);
    await assertPlatformAdmin(caller.id);

    const input = await req.json();
    const name = typeof input.name === 'string' ? input.name.trim() : '';
    const legalName = typeof input.legal_name === 'string' ? input.legal_name.trim() : null;
    const taxId = typeof input.tax_id === 'string' ? input.tax_id.trim() : null;
    const organizationType = input.organization_type;
    const ownerUserId = input.owner_user_id;
    const ownerEmail = normalizeEmail(input.owner_email);

    if (!name || name.length > 200) return errorResponse('name is required and must be at most 200 characters');
    if (legalName && legalName.length > 200) return errorResponse('legal_name must be at most 200 characters');
    if (taxId && taxId.length > 64) return errorResponse('tax_id must be at most 64 characters');
    if (!organizationTypes.has(organizationType)) return errorResponse('Invalid organization_type');
    if (ownerUserId !== undefined && !isUuid(ownerUserId)) return errorResponse('owner_user_id must be a UUID');
    if (input.owner_email !== undefined && !ownerEmail) return errorResponse('owner_email must be valid');

    const service = createServiceClient();
    if (ownerUserId) {
      const { data: owner, error } = await service.auth.admin.getUserById(ownerUserId);
      if (error || !owner.user) return errorResponse('owner_user_id does not identify an existing user');
    }

    const { data: organization, error: organizationError } = await service
      .from('organizations')
      .insert({
        name,
        legal_name: legalName || null,
        organization_type: organizationType,
        tax_id: taxId || null,
        created_by: caller.id,
      })
      .select('id, name, organization_type')
      .single();
    if (organizationError || !organization) throw new Error('Unable to create organization');

    let ownerInvitation: { status: 'sent' | 'delivery_failed'; invitation_id?: string; error?: string } | null = null;

    if (ownerUserId) {
      const { error } = await service.from('organization_members').insert({
        organization_id: organization.id,
        user_id: ownerUserId,
        role: 'owner',
        invited_by: caller.id,
      });
      if (error) throw new Error('Organization was created but its owner could not be assigned');
    } else if (ownerEmail) {
      // Fase 1 · Punto 6B: no más invitaciones "muertas" insertadas
      // directamente. Se crea vía la misma RPC/flujo productivo que
      // send-organization-invitation, con el JWT del propio caller (ya
      // verificado platform admin arriba) — nunca service_role para la
      // creación en sí, para que can_manage_organization_role la autorice
      // por la misma vía que cualquier otra invitación.
      //
      // Fallo parcial: si la invitación o el correo fallan, la organización
      // YA fue creada y se devuelve igual (nunca se crea una organización
      // duplicada por reintentar). El admin puede volver a invitar al owner
      // para esta misma organización desde la vista de Usuarios.
      try {
        const callerClient = createCallerClient(req);
        const { data: invitation, error: invitationError } = await callerClient.rpc('create_organization_invitation', {
          p_organization_id: organization.id,
          p_email: ownerEmail,
          p_role: 'owner',
          p_invited_name: null,
        });
        if (invitationError || !invitation) throw new Error(invitationError?.message ?? 'No se pudo crear la invitación del owner');

        const redirectTo = buildInvitationAcceptUrl(invitation.id);
        const recipientKind = await resolveInvitationRecipientKind(ownerEmail);
        await sendInvitationEmail({ email: ownerEmail, invitedName: null, redirectTo, recipientKind });

        const { error: markError } = await service.rpc('mark_invitation_sent', { p_invitation_id: invitation.id });
        if (markError) throw new Error(markError.message);

        ownerInvitation = { status: 'sent', invitation_id: invitation.id };
      } catch (error) {
        ownerInvitation = {
          status: 'delivery_failed',
          error: error instanceof Error ? error.message : 'No se pudo invitar al owner',
        };
      }
    }

    await service.from('activity_logs').insert({
      organization_id: organization.id,
      actor_user_id: caller.id,
      entity_type: 'organization',
      entity_id: organization.id,
      action: 'organization.created',
      metadata: { owner_user_id: ownerUserId ?? null, owner_email: ownerEmail },
    });

    return jsonResponse({ organization, owner_invitation: ownerInvitation }, 201);
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('admin-create-organization failed', error);
    return errorResponse('Internal server error', 500);
  }
});
