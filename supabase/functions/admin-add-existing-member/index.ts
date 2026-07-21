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
    const userId = input.user_id;
    const role = input.role;

    if (!isUuid(organizationId) || !isUuid(userId)) return errorResponse('organization_id and user_id must be UUIDs');
    if (!allowedRoles.has(role)) return errorResponse('Invalid organization member role');

    const service = createServiceClient();
    const { data: organization, error: organizationError } = await service
      .from('organizations')
      .select('id, organization_type, status')
      .eq('id', organizationId)
      .maybeSingle();
    if (organizationError || !organization) return errorResponse('Organization not found', 404);
    if (organization.organization_type === 'platform_admin') return errorResponse('Platform administrator memberships are not managed by this function', 403);
    if (organization.status !== 'active') return errorResponse('Organization is not active', 409);

    try {
      await assertPlatformAdmin(caller.id);
    } catch (error) {
      if (!isForbidden(error)) throw error;
      await assertOrganizationAdmin(caller.id, organizationId);
    }

    const { data: existingUser, error: userError } = await service.auth.admin.getUserById(userId);
    if (userError || !existingUser.user) return errorResponse('user_id does not identify an existing user');

    const { data: membership, error } = await service
      .from('organization_members')
      .upsert(
        { organization_id: organizationId, user_id: userId, role, is_active: true, invited_by: caller.id },
        { onConflict: 'organization_id,user_id' },
      )
      .select('id, organization_id, user_id, role, is_active, joined_at')
      .single();
    if (error || !membership) throw new Error('Unable to add organization member');

    await service.from('activity_logs').insert({
      organization_id: organizationId,
      actor_user_id: caller.id,
      entity_type: 'organization_member',
      entity_id: membership.id,
      action: 'organization_member.added',
      metadata: { user_id: userId, role },
    });

    return jsonResponse({ membership }, 201);
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('admin-add-existing-member failed', error);
    return errorResponse('Internal server error', 500);
  }
});
