import { createClient } from 'npm:@supabase/supabase-js@2';
import { createServiceClient } from './adminAuth.ts';

const environment = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required Edge Function secret: ${name}`);
  return value;
};

/** Dedicated anon-key client (no stored session) for triggering the
 * existing-user magic link. Mirrors what a normal signed-out browser would
 * call — deliberately NOT the service-role client, so this stays on the
 * exact same GoTrue path (rate limits, templates) a real user hitting
 * "forgot access" would use. */
const createAnonClient = () => createClient(
  environment('SUPABASE_URL'),
  environment('SUPABASE_ANON_KEY'),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

export type InvitationRecipientKind = 'new_user' | 'existing_user';

/** Resolves whether `email` already has a Supabase Auth account, via the
 * service-only get_auth_user_state_by_email RPC — never
 * auth.admin.listUsers({ perPage: 1000 }), which silently truncates past
 * 1000 users, and never exposed to owner/admin (would let a tenant admin
 * enumerate accounts across the whole platform). */
export const resolveInvitationRecipientKind = async (email: string): Promise<InvitationRecipientKind> => {
  const service = createServiceClient();
  const { data, error } = await service.rpc('get_auth_user_state_by_email', { p_email: email });
  if (error) throw new Error('Unable to resolve recipient account state');
  const row = Array.isArray(data) ? data[0] : data;
  // Only a CONFIRMED account goes the magic-link route. An account that
  // exists but is still unconfirmed is exactly what the first
  // inviteUserByEmail leaves behind until the person clicks: magic link
  // with shouldCreateUser:false is rejected for it ("Signups not allowed"),
  // while inviteUserByEmail re-sends to the same auth.users row (verified
  // locally: same user id, no duplicate). Confirmed accounts are the
  // opposite — inviteUserByEmail returns email_exists for them.
  return row?.exists_flag && row?.email_confirmed ? 'existing_user' : 'new_user';
};

/** Sends the actual invitation email/magic link. Throws on delivery
 * failure — the caller must NOT call mark_invitation_sent in that case, so
 * the invitation row stays untouched (send_count/last_sent_at unchanged)
 * and remains retryable, per the "no falso positivo de envío" requirement. */
export const sendInvitationEmail = async (params: {
  email: string;
  invitedName: string | null;
  redirectTo: string;
  recipientKind: InvitationRecipientKind;
}): Promise<void> => {
  const { email, invitedName, redirectTo, recipientKind } = params;

  if (recipientKind === 'new_user') {
    const service = createServiceClient();
    const { error } = await service.auth.admin.inviteUserByEmail(email, {
      redirectTo,
      // Only a display name — never a role or any authorization-relevant
      // claim. The RPC always resolves the role from the invitation row.
      data: invitedName ? { name: invitedName } : undefined,
    });
    if (error) throw new Error(`No se pudo enviar el correo de invitación: ${error.message}`);
    return;
  }

  const anon = createAnonClient();
  const { error } = await anon.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false, emailRedirectTo: redirectTo },
  });
  if (error) throw new Error(`No se pudo enviar el enlace de acceso: ${error.message}`);
};
