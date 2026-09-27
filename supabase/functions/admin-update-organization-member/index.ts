import { createCallerClient, errorResponse, handleCors, jsonResponse, requirePost } from '../_shared/adminAuth.ts';

const roles = new Set(['owner', 'admin', 'manager', 'requester', 'quote_manager', 'technician', 'operator', 'viewer']);

// Every authorization rule (role hierarchy, last-owner protection, self-
// modification, platform_admin org gating) now lives exclusively in the
// update_organization_member RPC (20260926205830_production_user_invitations.sql),
// enforced against auth.uid() in Postgres. This function is a thin relay
// using the CALLER's own JWT — never service_role — so it can never bypass
// that authorization by construction.
Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    requirePost(req);
    const input = await req.json();
    if (typeof input.membership_id !== 'string') return errorResponse('membership_id is required');
    if (input.role !== undefined && !roles.has(input.role)) return errorResponse('Invalid organization member role');
    if (input.is_active !== undefined && typeof input.is_active !== 'boolean') return errorResponse('is_active must be boolean');

    const caller = createCallerClient(req);
    const { data, error } = await caller.rpc('update_organization_member', {
      p_membership_id: input.membership_id,
      p_role: input.role ?? null,
      p_is_active: input.is_active ?? null,
    });
    if (error) return errorResponse(error.message, 400);
    return jsonResponse({ membership: data });
  } catch (error) {
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('admin-update-organization-member failed', error);
    return errorResponse('Internal server error', 500);
  }
});
