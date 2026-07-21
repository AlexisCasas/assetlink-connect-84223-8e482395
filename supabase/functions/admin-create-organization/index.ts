import {
  assertPlatformAdmin,
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

    if (ownerUserId) {
      const { error } = await service.from('organization_members').insert({
        organization_id: organization.id,
        user_id: ownerUserId,
        role: 'owner',
        invited_by: caller.id,
      });
      if (error) throw new Error('Organization was created but its owner could not be assigned');
    } else if (ownerEmail) {
      const { error } = await service.from('organization_invitations').insert({
        organization_id: organization.id,
        email: ownerEmail,
        role: 'owner',
        invited_by: caller.id,
      });
      if (error) throw new Error('Organization was created but its owner invitation could not be registered');
    }

    await service.from('activity_logs').insert({
      organization_id: organization.id,
      actor_user_id: caller.id,
      entity_type: 'organization',
      entity_id: organization.id,
      action: 'organization.created',
      metadata: { owner_user_id: ownerUserId ?? null, owner_email: ownerEmail },
    });

    return jsonResponse({ organization }, 201);
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('admin-create-organization failed', error);
    return errorResponse('Internal server error', 500);
  }
});
