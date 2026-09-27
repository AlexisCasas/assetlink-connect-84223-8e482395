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

// LEGACY / staging-only tool (Fase 1 · Punto 6B). The productive flow is
// send-organization-invitation → accept_organization_invitation: it always
// requires the invited person's own consent and email confirmation before
// any membership is created. This function activates a membership
// immediately with no acceptance step, so docs/ADMIN_ORGANIZATION_USER_MANAGEMENT.md
// documents it as staging/demo-only, and AdminConsole hides the "Crear
// usuario + contraseña temporal" panel in production builds
// (VITE_APP_ENV === 'production').
//
// It must NEVER overwrite an existing user's password again — that was a
// real account-takeover primitive (any platform admin could silently take
// over any tenant's account by "creating" a user with that email and a
// password only the admin knows). For an email that already has an Auth
// account, temporary_password is now silently ignored; only user_metadata
// (display name) may still be touched, and only the membership is
// upserted.
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

    // Never auth.admin.listUsers({ perPage: 1000 }): silently truncates past
    // 1000 users. This SECURITY DEFINER RPC is service_role-only.
    const { data: stateRows, error: stateError } = await service.rpc('get_auth_user_state_by_email', { p_email: email });
    if (stateError) throw stateError;
    const state = Array.isArray(stateRows) ? stateRows[0] : stateRows;

    const userMetadata = {
      name: typeof input.name === 'string' ? input.name.trim() : '',
    };

    let userId: string;
    if (!state?.exists_flag) {
      const { data, error } = await service.auth.admin.createUser({
        email,
        ...(temporaryPassword === undefined ? {} : { password: temporaryPassword }),
        email_confirm: true,
        user_metadata: userMetadata,
      });
      if (error || !data.user) throw error ?? new Error('Unable to create user');
      userId = data.user.id;
    } else {
      // Existing account: password is never touched here, regardless of
      // temporary_password. Only the display name may be refreshed.
      userId = state.user_id as string;
      if (userMetadata.name) {
        const { error } = await service.auth.admin.updateUserById(userId, { user_metadata: userMetadata });
        if (error) throw error;
      }
    }

    const { data: membership, error } = await service
      .from('organization_members')
      .upsert(
        {
          organization_id: input.organization_id,
          user_id: userId,
          role: input.role,
          is_active: true,
          invited_by: caller.id,
        },
        { onConflict: 'organization_id,user_id' },
      )
      .select('id, organization_id, user_id, role, is_active, joined_at, updated_at')
      .single();

    if (error) throw error;

    await service.from('activity_logs').insert({
      organization_id: input.organization_id,
      actor_user_id: caller.id,
      entity_type: 'organization_member',
      entity_id: membership.id,
      action: 'organization_member.added',
      metadata: { user_id: userId, role: input.role, legacy_tool: true },
    });

    return jsonResponse({ user_id: userId, email, membership }, 201);
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') {
      return errorResponse('Unauthorized', 401);
    }

    console.error('admin-create-user-and-add-member failed', error);
    return errorResponse('Internal server error', 500);
  }
});
