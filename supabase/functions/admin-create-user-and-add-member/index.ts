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

const roles = new Set([
  'owner',
  'admin',
  'manager',
  'requester',
  'quote_manager',
  'technician',
  'operator',
  'viewer',
]);

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    requirePost(req);

    const caller = await getAuthenticatedUser(req);
    await assertPlatformAdmin(caller.id);

    const input = await req.json();
    const email = normalizeEmail(input.email);
    const temporaryPassword = input.temporary_password;

    if (!isUuid(input.organization_id) || !email || !roles.has(input.role)) {
      return errorResponse('organization_id, valid email and valid role are required');
    }

    if (
      temporaryPassword !== undefined &&
      (typeof temporaryPassword !== 'string' || temporaryPassword.length < 8)
    ) {
      return errorResponse('temporary_password must contain at least 8 characters');
    }

    const service = createServiceClient();
    const { data: organization } = await service
      .from('organizations')
      .select('organization_type')
      .eq('id', input.organization_id)
      .maybeSingle();

    if (!organization) return errorResponse('Organization not found', 404);
    if (organization.organization_type === 'platform_admin') {
      return errorResponse(
        'Platform administrator memberships are not managed by this function',
        403,
      );
    }

    const { data: users } = await service.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    let user = users.users.find(
      (candidate) => candidate.email?.toLowerCase() === email,
    );

    const userMetadata = {
      name: typeof input.name === 'string' ? input.name.trim() : '',
    };

    if (!user) {
      const { data, error } = await service.auth.admin.createUser({
        email,
        ...(temporaryPassword === undefined ? {} : { password: temporaryPassword }),
        email_confirm: true,
        user_metadata: userMetadata,
      });

      if (error || !data.user) {
        throw error ?? new Error('Unable to create user');
      }

      user = data.user;
    } else if (temporaryPassword !== undefined) {
      const { data, error } = await service.auth.admin.updateUserById(user.id, {
        password: temporaryPassword,
        user_metadata: userMetadata,
      });

      if (error) throw error;
      user = data.user ?? user;
    }

    const { data: membership, error } = await service
      .from('organization_members')
      .upsert(
        {
          organization_id: input.organization_id,
          user_id: user.id,
          role: input.role,
          is_active: true,
          invited_by: caller.id,
        },
        { onConflict: 'organization_id,user_id' },
      )
      .select('id, organization_id, user_id, role, is_active, joined_at, updated_at')
      .single();

    if (error) throw error;

    return jsonResponse({ user_id: user.id, email: user.email, membership }, 201);
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') {
      return errorResponse('Unauthorized', 401);
    }

    console.error('admin-create-user-and-add-member failed');
    return errorResponse('Internal server error', 500);
  }
});
