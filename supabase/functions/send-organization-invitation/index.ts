import {
  createCallerClient,
  createServiceClient,
  errorResponse,
  handleCors,
  isUuid,
  jsonResponse,
  requirePost,
} from '../_shared/adminAuth.ts';
import { buildInvitationAcceptUrl } from '../_shared/publicAppUrl.ts';
import { resolveInvitationRecipientKind, sendInvitationEmail } from '../_shared/invitationEmail.ts';

const roles = new Set(['owner', 'admin', 'manager', 'requester', 'quote_manager', 'technician', 'operator', 'viewer']);

/** Full organization_invitations row as the RPCs return it. Never sent back
 * to the client as-is — see toInvitationDto. */
interface InvitationRow {
  id: string;
  organization_id: string;
  email: string;
  role: string;
  invited_name: string | null;
  status: string;
  expires_at: string;
  last_sent_at: string | null;
  send_count: number;
}

/** Explicit allow-list of what the caller receives. Deliberately omits
 * token_hash, invited_by, accepted_by, revoked_by, last_send_attempt_at and
 * anything else the row may grow in the future — adding a column to the
 * table never silently adds it to this response. */
interface InvitationDto {
  id: string;
  organization_id: string;
  email: string;
  invited_name: string | null;
  role: string;
  status: string;
  effective_status: string;
  expires_at: string;
  last_sent_at: string | null;
  send_count: number;
}

const toInvitationDto = (row: InvitationRow): InvitationDto => ({
  id: row.id,
  organization_id: row.organization_id,
  email: row.email,
  invited_name: row.invited_name,
  role: row.role,
  status: row.status,
  effective_status: row.status === 'pending' && new Date(row.expires_at).getTime() <= Date.now() ? 'expired' : row.status,
  expires_at: row.expires_at,
  last_sent_at: row.last_sent_at,
  send_count: row.send_count,
});

/** Runs the RPC as the caller (their own JWT, never service_role) so every
 * authorization/hierarchy rule in create_organization_invitation /
 * resend_organization_invitation applies exactly as it would from a direct
 * PostgREST call — this function never re-implements that logic in
 * TypeScript. */
async function callInvitationRpc(req: Request, name: 'create_organization_invitation' | 'resend_organization_invitation', args: Record<string, unknown>): Promise<InvitationRow> {
  const caller = createCallerClient(req);
  const { data, error } = await caller.rpc(name, args);
  if (error) throw new Error(error.message);
  return data as InvitationRow;
}

/** Returns the row as updated by mark_invitation_sent, so last_sent_at /
 * send_count in the response reflect the confirmed send. */
async function deliverAndMark(invitation: InvitationRow): Promise<InvitationRow> {
  const redirectTo = buildInvitationAcceptUrl(invitation.id);
  const recipientKind = await resolveInvitationRecipientKind(invitation.email);
  await sendInvitationEmail({
    email: invitation.email,
    invitedName: invitation.invited_name,
    redirectTo,
    recipientKind,
  });

  // service_role only (see get_auth_user_state_by_email/mark_invitation_sent
  // grants) — the caller client has no EXECUTE on this RPC by design, so a
  // second, dedicated service client is required here.
  const service = createServiceClient();
  const { data, error } = await service.rpc('mark_invitation_sent', { p_invitation_id: invitation.id });
  if (error) throw new Error(`Invitación creada pero no se pudo registrar el envío: ${error.message}`);
  return data as InvitationRow;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    requirePost(req);
    const input = await req.json();
    const action = input.action;

    if (action === 'create') {
      const organizationId = input.organization_id;
      const email = typeof input.email === 'string' ? input.email : '';
      const role = input.role;
      const invitedName = typeof input.invited_name === 'string' && input.invited_name.trim() ? input.invited_name.trim() : null;

      if (!isUuid(organizationId)) return errorResponse('organization_id must be a UUID');
      if (!roles.has(role)) return errorResponse('Invalid organization member role');

      let invitation: InvitationRow;
      try {
        invitation = await callInvitationRpc(req, 'create_organization_invitation', {
          p_organization_id: organizationId,
          p_email: email,
          p_role: role,
          p_invited_name: invitedName,
        });
      } catch (error) {
        return errorResponse(error instanceof Error ? error.message : 'No se pudo crear la invitación', 400);
      }

      let sent: InvitationRow;
      try {
        sent = await deliverAndMark(invitation);
      } catch (error) {
        // The invitation row already exists and stays exactly as created —
        // never a second row, never a fake "sent" state (send_count 0,
        // last_sent_at NULL). last_send_attempt_at keeps the reserved
        // attempt, so a retry via resend is allowed once the 1-minute
        // cooldown has passed — never immediately (no retry storms).
        return jsonResponse({
          error: error instanceof Error ? error.message : 'No se pudo enviar el correo',
          invitation_id: invitation.id,
        }, 502);
      }

      return jsonResponse({ invitation: toInvitationDto(sent) }, 201);
    }

    if (action === 'resend') {
      const invitationId = input.invitation_id;
      if (!isUuid(invitationId)) return errorResponse('invitation_id must be a UUID');

      let invitation: InvitationRow;
      try {
        invitation = await callInvitationRpc(req, 'resend_organization_invitation', { p_invitation_id: invitationId });
      } catch (error) {
        return errorResponse(error instanceof Error ? error.message : 'No se pudo preparar el reenvío', 400);
      }

      let sent: InvitationRow;
      try {
        sent = await deliverAndMark(invitation);
      } catch (error) {
        return jsonResponse({
          error: error instanceof Error ? error.message : 'No se pudo enviar el correo',
          invitation_id: invitation.id,
        }, 502);
      }

      return jsonResponse({ invitation: toInvitationDto(sent) });
    }

    return errorResponse('Invalid action');
  } catch (error) {
    if (error instanceof Error && error.message === 'Unauthorized') return errorResponse('Unauthorized', 401);
    if (error instanceof Error && error.message === 'Method not allowed') return errorResponse(error.message, 405);
    console.error('send-organization-invitation failed', error);
    return errorResponse('Internal server error', 500);
  }
});
