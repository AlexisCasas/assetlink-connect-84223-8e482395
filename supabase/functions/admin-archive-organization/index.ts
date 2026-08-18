import {
  assertPlatformAdmin,
  createServiceClient,
  getAuthenticatedUser,
  isForbidden,
  isUuid,
  requirePost,
} from '../_shared/adminAuth.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const jsonResponse = (body: unknown, status = 200) => new Response(
  JSON.stringify(body),
  { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
);

const errorResponse = (message: string, status = 400) => jsonResponse({ error: message }, status);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    requirePost(req);
    const caller = await getAuthenticatedUser(req);
    await assertPlatformAdmin(caller.id);

    const { organization_id: organizationId } = await req.json();
    if (!isUuid(organizationId)) return errorResponse('organization_id must be a UUID');

    const service = createServiceClient();
    const { data: organization, error: organizationError } = await service
      .from('organizations')
      .select('id, organization_type, status')
      .eq('id', organizationId)
      .maybeSingle();

    if (organizationError || !organization) return errorResponse('Organization not found', 404);
    if (organization.organization_type === 'platform_admin') {
      return errorResponse('Platform administrator organizations cannot be archived', 403);
    }
    if (organization.status === 'archived') {
      return jsonResponse({ success: true, organization_id: organization.id, status: 'archived' });
    }

    const { data: archivedOrganization, error: archiveError } = await service
      .from('organizations')
      .update({ status: 'archived' })
      .eq('id', organization.id)
      .select('id, status')
      .single();

    if (archiveError || !archivedOrganization) throw archiveError ?? new Error('Unable to archive organization');
    return jsonResponse({
      success: true,
      organization_id: archivedOrganization.id,
      status: archivedOrganization.status,
    });
  } catch (error) {
    if (isForbidden(error)) return errorResponse('Forbidden', 403);
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('admin-archive-organization failed');
    return errorResponse('Internal server error', 500);
  }
});
