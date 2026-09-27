import { errorResponse, handleCors } from '../_shared/adminAuth.ts';

// Retired (Fase 1 · Punto 6B): this function only ever inserted a "dead"
// pending row with no email, no expiry management and no resend/cancel/
// accept path. The productive flow is send-organization-invitation
// (create_organization_invitation / resend_organization_invitation /
// accept_organization_invitation RPCs). Kept deployed and responding 410 so
// any stale client that still calls this function gets a clear signal
// instead of a broken silent insert.
Deno.serve((req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  return errorResponse('This function was retired. Use send-organization-invitation instead.', 410);
});
