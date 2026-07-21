import {
  assertOrganizationAdmin,
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

const allowedRoles = new Set(['owner', 'admin', 'manager', 'requester', 'quote_manager', 'technician', 'operator', 'viewer']);

Deno.serve(async (req) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    requirePost(req);
    const caller = await getAuthenticatedUser(req);
    const input = await req.json();
    const organizationId = input.organization_id;
    const email = normalizeEmail(input.email);
    const role = input.role;

    if (!isUuid(organizationId)) return errorResponse('organization_id must be a UUID');
    if (!email) return errorResponse('email must be valid');
    if (!allowedRoles.has(role)) return errorResponse('Invalid organization member role');

    const service = createServiceClient();
    const { data: organization, error: organizationError } = await service
      .from('organizations')
      .select('id, organization_type, status')
      .eq('id', organizationId)
      .maybeSingle();
    if (organizationError || !organization) return errorResponse('Organization not found', 404);
    if (organization.organization_type === 'platform_admin') return errorResponse('Platform administrator invitations are not supported by this function', 403);
    if (organization.status !== 'active') return errorResponse('Organization is not active', 409);

    try {
      await assertPlatformAdmin(caller.id);
    } catch (error) {
      if (!isForbidden(error)) throw error;
      await assertOrganizationAdmin(caller.id, organizationId);
    }

    const { data: invitation, error } = await service
      .from('organization_invitations')
      .insert({ organization_id: organizationId, email, role, invited_by: caller.id })
      .select('id, organization_id, email, role, status, created_at')
      .single();
    if (error || !invitation) {
      if (error?.code === '23505') return errorResponse('A pending invitation already exists for this email', 409);
      throw new Error('Unable to create organization invitation');
    }

    await service.from('activity_logs').insert({
      organization_id: organizationId,
      actor_user_id: caller.id,
      entity_type: 'organization_invitation',
      entity_id: invitation.id,
      action: 'organization_member.invited',
      metadata: { email, role },
    });

    return jsonResponse({ invitation }, 201);
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('admin-invite-organization-member failed', error);
    return errorResponse('Internal server error', 500);
  }
});
