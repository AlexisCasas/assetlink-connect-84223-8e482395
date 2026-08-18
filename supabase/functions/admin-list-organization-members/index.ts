import { assertOrganizationAdmin, assertPlatformAdmin, createServiceClient, errorResponse, getAuthenticatedUser, handleCors, isForbidden, isUuid, jsonResponse, requirePost } from '../_shared/adminAuth.ts';

Deno.serve(async (req) => {
  const cors = handleCors(req); if (cors) return cors;
  try {
    requirePost(req); const caller = await getAuthenticatedUser(req); const { organization_id } = await req.json();
    if (!isUuid(organization_id)) return errorResponse('organization_id must be a UUID');
    try { await assertPlatformAdmin(caller.id); } catch (error) { if (!isForbidden(error)) throw error; await assertOrganizationAdmin(caller.id, organization_id); }
    const service = createServiceClient();
    const { data: memberships, error } = await service.from('organization_members').select('id, organization_id, user_id, role, is_active, joined_at, updated_at').eq('organization_id', organization_id).order('joined_at');
    if (error) throw error;
    const members = await Promise.all((memberships ?? []).map(async (membership) => {
      const { data } = await service.auth.admin.getUserById(membership.user_id);
      return { ...membership, email: data.user?.email ?? null, name: typeof data.user?.user_metadata?.name === 'string' ? data.user.user_metadata.name : null };
    }));
    return jsonResponse({ members });
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('admin-list-organization-members failed', error); return errorResponse('Internal server error', 500);
  }
});
