-- Fase 1 · Punto 6B — Invitación productiva de usuarios.
-- Se ejecuta con: supabase test db --local
--
-- Toda fila de organization_invitations/organization_members ya no admite
-- INSERT/UPDATE directo desde `authenticated` (organization_access_hardening).
-- Por eso cada ajuste de fixture a mitad de prueba (simular una fila vencida,
-- registrar un nuevo auth.users, etc.) se hace explícitamente como
-- `postgres` (RESET ROLE), nunca mientras el rol activo es `authenticated`.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(84);

-- -------------------------------------------------------------------------
-- Fixture inicial (como postgres)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email, email_confirmed_at) VALUES
  ('c1000000-0000-0000-0000-000000000001', 'owner-a@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000002', 'admin-a@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000003', 'manager-a@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000004', 'owner-b@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000005', 'platform@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000006', 'invitee@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000007', 'unconfirmed@invite.test', NULL),
  ('c1000000-0000-0000-0000-000000000008', 'existing-member@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000009', 'wrong-account@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000010', 'lone-owner@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000011', 'reactivate@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000012', 'newdup@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000013', 'expired-accept@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000014', 'suspended-org@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000015', 'pending-list@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000016', 'exowner@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000017', 'exowner2@invite.test', now()),
  ('c1000000-0000-0000-0000-000000000018', 'exadmin@invite.test', now());

INSERT INTO public.organizations (id, name, organization_type, status) VALUES
  ('c2000000-0000-0000-0000-00000000000a', 'Tenant A', 'client_company', 'active'),
  ('c2000000-0000-0000-0000-00000000000b', 'Tenant B', 'client_company', 'active'),
  ('c2000000-0000-0000-0000-00000000000c', 'Tenant Solo Owner', 'client_company', 'active'),
  ('c2000000-0000-0000-0000-00000000000d', 'Tenant Archivado', 'client_company', 'suspended'),
  ('c2000000-0000-0000-0000-00000000000f', 'Plataforma', 'platform_admin', 'active');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000001', 'owner', true),
  ('c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000002', 'admin', true),
  ('c3000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000003', 'manager', true),
  ('c3000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000008', 'viewer', true),
  ('c3000000-0000-0000-0000-000000000005', 'c2000000-0000-0000-0000-00000000000b', 'c1000000-0000-0000-0000-000000000004', 'owner', true),
  ('c3000000-0000-0000-0000-000000000006', 'c2000000-0000-0000-0000-00000000000f', 'c1000000-0000-0000-0000-000000000005', 'owner', true),
  ('c3000000-0000-0000-0000-000000000007', 'c2000000-0000-0000-0000-00000000000c', 'c1000000-0000-0000-0000-000000000010', 'owner', true),
  ('c3000000-0000-0000-0000-000000000008', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000011', 'viewer', false),
  ('c3000000-0000-0000-0000-000000000009', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000016', 'owner', false),
  ('c3000000-0000-0000-0000-000000000010', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000017', 'owner', false),
  ('c3000000-0000-0000-0000-000000000011', 'c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000018', 'admin', false);

-- Invitaciones fijadas por fixture (no via RPC) para los escenarios 4d-4g y 6.
INSERT INTO public.organization_invitations (id, organization_id, email, role, invited_by, expires_at) VALUES
  ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-00000000000a', 'unconfirmed@invite.test', 'viewer', 'c1000000-0000-0000-0000-000000000001', now() + interval '7 days'),
  ('c4000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-00000000000a', 'expired-accept@invite.test', 'viewer', 'c1000000-0000-0000-0000-000000000001', now() - interval '1 hour'),
  ('c4000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-00000000000d', 'suspended-org@invite.test', 'viewer', 'c1000000-0000-0000-0000-000000000001', now() + interval '7 days'),
  ('c4000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-00000000000a', 'reactivate@invite.test', 'manager', 'c1000000-0000-0000-0000-000000000001', now() + interval '7 days'),
  ('c4000000-0000-0000-0000-000000000005', 'c2000000-0000-0000-0000-00000000000a', 'pending-list@invite.test', 'viewer', 'c1000000-0000-0000-0000-000000000001', now() + interval '7 days');

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;

-- organization_invitations' only SELECT policy is owner/admin/platform
-- admin (by design — see docs/USER_INVITATIONS.md): the invitee itself,
-- and any manager/lower role, cannot see the row directly. This
-- SECURITY DEFINER helper resolves an invitation id by email regardless of
-- who is currently impersonated, purely for wiring up these tests — never
-- a stand-in for get_my_organization_invitation, which the app actually
-- uses and which IS covered on its own below.
CREATE FUNCTION pg_temp.invitation_id_by_email(p_email text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id FROM public.organization_invitations WHERE email = p_email ORDER BY created_at DESC LIMIT 1;
$$;

-- Post-condition checks below sometimes run while impersonating the
-- invitee/an inactive member — someone with NO SELECT visibility into
-- organization_invitations (owner/admin/platform admin only) or, for an
-- inactive member, not even into their own organization_members row
-- (is_organization_member requires an ACTIVE membership). These two
-- SECURITY DEFINER helpers read the real state regardless, purely so the
-- test can assert on it — never a stand-in for what the app itself reads.
CREATE FUNCTION pg_temp.invitation_status(p_id uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT status::text FROM public.organization_invitations WHERE id = p_id;
$$;

CREATE FUNCTION pg_temp.member_state(p_org uuid, p_user uuid) RETURNS TABLE(is_active boolean, role public.organization_member_role)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT is_active, role FROM public.organization_members WHERE organization_id = p_org AND user_id = p_user;
$$;

SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 1. Invitar: owner / admin / manager / cross-tenant / duplicados
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001'); -- owner A
SELECT lives_ok(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'INVITEE@invite.test', 'admin', 'Invitado Uno') $$,
  'owner invites admin (email normalized to lowercase, name trimmed)');
SELECT is((SELECT email FROM public.organization_invitations WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND invited_name = 'Invitado Uno'),
  'invitee@invite.test', 'stored email is lowercased');
SELECT ok((SELECT expires_at - created_at = interval '7 days' FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'expires_at defaults to +7 days');
SELECT is((SELECT send_count FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'), 0, 'send_count starts at 0');

SELECT lives_ok($$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'newdup@invite.test', 'viewer') $$, 'first invitation to newdup@invite.test succeeds');
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'newdup@invite.test', 'admin') $$,
  'Ya existe una invitación pendiente', 'a second pending invitation to the same email is rejected');

SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'existing-member@invite.test', 'admin') $$,
  'ya pertenece a un miembro activo', 'cannot invite an email that already is an active member');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002'); -- admin A
SELECT lives_ok($$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'by-admin@invite.test', 'manager') $$,
  'admin invites manager');
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'rogue-owner@invite.test', 'owner') $$,
  'No autorizado', 'admin CANNOT invite an owner (role hierarchy)');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003'); -- manager A
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'by-manager@invite.test', 'viewer') $$,
  'No autorizado', 'manager cannot invite at all');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000004'); -- owner B
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'cross-tenant@invite.test', 'viewer') $$,
  'No autorizado', 'owner of Tenant B cannot invite into Tenant A (cross-tenant rejected)');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005'); -- platform admin
SELECT lives_ok($$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'by-platform@invite.test', 'owner') $$,
  'platform admin can invite an owner into a non-platform_admin org');
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000f', 'x@invite.test', 'viewer') $$,
  'no admite invitaciones', 'cannot invite into a platform_admin organization');
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000d', 'x@invite.test', 'viewer') $$,
  'no está activa', 'cannot invite into a non-active (suspended) organization');

-- -------------------------------------------------------------------------
-- 2. Reenvío: rate limit, jerarquía, estados no reenviables
-- -------------------------------------------------------------------------
-- Todo este archivo corre en UNA transacción: now() es constante. Para
-- simular que pasó el cooldown se retroceden los timestamps como postgres.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001'); -- owner A
SELECT ok((SELECT last_send_attempt_at = now() FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'create reserves the first send attempt (last_send_attempt_at = now())');
SELECT ok((SELECT send_count = 0 AND last_sent_at IS NULL FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'create does NOT count a send (send_count 0, last_sent_at NULL) until it is confirmed');
SELECT throws_matching(
  $$ SELECT public.resend_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test')) $$,
  'Espera un minuto', 'resend within 60s of the reserved create attempt is rejected (even with no confirmed send yet)');

-- Fallo de entrega simulado: el correo inicial falló, así que nadie llamó a
-- mark_invitation_sent. Nada de lo "enviado" cambia y el intento se conserva
-- (el cooldown NO se libera por fallar).
SELECT ok((SELECT send_count = 0 AND last_sent_at IS NULL AND last_send_attempt_at IS NOT NULL FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'after a simulated delivery failure: send_count/last_sent_at untouched, attempt kept');

RESET ROLE;
UPDATE public.organization_invitations SET last_send_attempt_at = now() - interval '2 minutes' WHERE email = 'invitee@invite.test';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(
  $$ SELECT public.resend_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test')) $$,
  'resend after the 60s cooldown is allowed');
SELECT ok((SELECT last_send_attempt_at = now() FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'resend reserves a new attempt (last_send_attempt_at = now()) inside the same transaction');
SELECT ok((SELECT send_count = 0 AND last_sent_at IS NULL FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'resend itself never counts a send');

RESET ROLE;
SET LOCAL ROLE service_role;
SELECT lives_ok(
  $$ SELECT public.mark_invitation_sent(pg_temp.invitation_id_by_email('invitee@invite.test')) $$,
  'service_role can call mark_invitation_sent (records the confirmed send)');
SELECT ok((SELECT send_count = 1 AND last_sent_at = now() FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'mark_invitation_sent is the only thing that increments send_count and sets last_sent_at');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT throws_matching(
  $$ SELECT public.resend_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test')) $$,
  'Espera un minuto', '1-minute resend rate limit is enforced right after a recorded send');

-- El cooldown compara contra el MÁS reciente de intento/envío: aunque el
-- envío confirmado sea viejo, un intento reciente sigue bloqueando.
RESET ROLE;
UPDATE public.organization_invitations SET last_sent_at = now() - interval '10 minutes' WHERE email = 'invitee@invite.test';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT throws_matching(
  $$ SELECT public.resend_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test')) $$,
  'Espera un minuto', 'an old confirmed send does not bypass a recent reserved attempt');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003'); -- manager A
SELECT throws_matching(
  $$ SELECT public.resend_organization_invitation(pg_temp.invitation_id_by_email('newdup@invite.test')) $$,
  'No autorizado', 'manager cannot resend');

-- Invitación efectivamente vencida (ajuste de fixture como postgres).
RESET ROLE;
UPDATE public.organization_invitations
SET expires_at = now() - interval '1 day', last_send_attempt_at = now() - interval '8 days'
WHERE email = 'newdup@invite.test';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT is((SELECT CASE WHEN status = 'pending' AND expires_at <= now() THEN 'expired' ELSE status::text END FROM public.organization_invitations WHERE email = 'newdup@invite.test'),
  'expired', 'effective status is expired before resend (still physically pending)');
SELECT lives_ok($$ SELECT public.resend_organization_invitation(pg_temp.invitation_id_by_email('newdup@invite.test')) $$,
  'resending an effectively-expired invitation succeeds');
SELECT ok((SELECT expires_at > now() + interval '6 days' FROM public.organization_invitations WHERE email = 'newdup@invite.test'),
  'resend renewed expires_at to +7 days');
SELECT is((SELECT status FROM public.organization_invitations WHERE email = 'newdup@invite.test'), 'pending', 'resend flipped status back to pending');

-- -------------------------------------------------------------------------
-- 3. Revocación
-- -------------------------------------------------------------------------
SELECT lives_ok($$ SELECT public.revoke_organization_invitation(pg_temp.invitation_id_by_email('newdup@invite.test')) $$,
  'owner revokes a pending invitation');
SELECT is((SELECT status FROM public.organization_invitations WHERE email = 'newdup@invite.test'), 'revoked', 'status is revoked');
SELECT ok((SELECT revoked_at IS NOT NULL AND revoked_by = 'c1000000-0000-0000-0000-000000000001' FROM public.organization_invitations WHERE email = 'newdup@invite.test'),
  'revoked_at/revoked_by recorded');
SELECT throws_matching(
  $$ SELECT public.revoke_organization_invitation(pg_temp.invitation_id_by_email('newdup@invite.test')) $$,
  'pendientes o vencidas', 'cannot revoke an already-revoked invitation');

-- -------------------------------------------------------------------------
-- 4. Aceptación
-- -------------------------------------------------------------------------
-- 4a. Happy path: role comes from the invitation, never from the caller.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006'); -- invitee
SELECT results_eq(
  $$ SELECT status, organization_id FROM public.accept_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test')) $$,
  $$ VALUES ('accepted'::text, 'c2000000-0000-0000-0000-00000000000a'::uuid) $$,
  'invitee accepts successfully');
SELECT is((SELECT role FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND user_id = 'c1000000-0000-0000-0000-000000000006'),
  'admin', 'membership role matches the invitation role (admin), never a client-supplied value');
SELECT is((SELECT status FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'), 'accepted', 'invitation marked accepted');
SELECT ok((SELECT accepted_by = 'c1000000-0000-0000-0000-000000000006' AND accepted_at IS NOT NULL FROM public.organization_invitations WHERE invited_name = 'Invitado Uno'),
  'accepted_by/accepted_at recorded');

-- 4b. Double acceptance is idempotent — no duplicate membership, no error.
SELECT results_eq(
  $$ SELECT status FROM public.accept_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test')) $$,
  $$ VALUES ('already_accepted'::text) $$,
  'accepting twice by the same user is idempotent');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND user_id = 'c1000000-0000-0000-0000-000000000006'),
  1::bigint, 'still exactly one membership row after double acceptance');

-- 4c. Wrong account.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009'); -- wrong-account
SELECT throws_matching(
  $$ SELECT public.accept_organization_invitation(pg_temp.invitation_id_by_email('by-admin@invite.test')) $$,
  'no corresponde a la cuenta', 'a different logged-in account cannot accept someone else''s invitation');

-- 4d. Unconfirmed email.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007'); -- unconfirmed
SELECT throws_matching(
  $$ SELECT public.accept_organization_invitation('c4000000-0000-0000-0000-000000000001') $$,
  'confirmar tu correo', 'a user with an unconfirmed email cannot accept');

-- 4e. Revoked cannot be accepted (newdup@invite.test was revoked above).
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000012'); -- newdup@invite.test
SELECT throws_matching(
  $$ SELECT public.accept_organization_invitation(pg_temp.invitation_id_by_email('newdup@invite.test')) $$,
  'fue cancelada', 'a revoked invitation cannot be accepted, even by the right email');

-- 4f. Expired invitation cannot be accepted (and gets normalized on the attempt).
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000013'); -- expired-accept
SELECT throws_matching(
  $$ SELECT public.accept_organization_invitation('c4000000-0000-0000-0000-000000000002') $$,
  'venció', 'an effectively-expired invitation cannot be accepted');
-- The row itself stays physically 'pending' — a RAISE EXCEPTION rolls back
-- any write from the same call (see the migration's comment on this exact
-- branch) — but every reader computes the same effective status from
-- status+expires_at, so this is what actually matters.
SELECT is(pg_temp.invitation_status('c4000000-0000-0000-0000-000000000002'), 'pending',
  'the row stays physically pending (normalization cannot survive the same call''s exception)');

-- 4g. Inactive (suspended) organization.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000014'); -- suspended-org
SELECT throws_matching(
  $$ SELECT public.accept_organization_invitation('c4000000-0000-0000-0000-000000000003') $$,
  'no está disponible', 'cannot accept into a suspended organization');

-- 4h. Reactivation: a previously-deactivated member accepting a fresh
-- invitation gets is_active flipped back true, with the invitation's role.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000011'); -- reactivate
SELECT is((SELECT is_active FROM pg_temp.member_state('c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000011')),
  false, 'baseline: member starts inactive');
SELECT results_eq(
  $$ SELECT status FROM public.accept_organization_invitation('c4000000-0000-0000-0000-000000000004') $$,
  $$ VALUES ('accepted'::text) $$,
  'accepting reactivates the existing membership row');
SELECT is((SELECT (is_active, role) FROM pg_temp.member_state('c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000011')),
  (true, 'manager'::public.organization_member_role), 'reactivated membership is active with the invitation''s role');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND user_id = 'c1000000-0000-0000-0000-000000000011'),
  1::bigint, 'still exactly one membership row (no duplicate)');

-- -------------------------------------------------------------------------
-- 4i. Membership owner INACTIVA: invitar equivale a reescribir su rol al
--     aceptar, así que un admin no puede hacerlo (ni crear ni reenviar);
--     un owner sí.
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002'); -- admin A (still admin here)
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'exowner@invite.test', 'viewer') $$,
  'No autorizado para invitar a este usuario', 'admin cannot invite an INACTIVE owner with another role (would rewrite an owner membership)');
SELECT is((SELECT (is_active, role) FROM pg_temp.member_state('c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000016')),
  (false, 'owner'::public.organization_member_role), 'inactive owner membership untouched after the blocked attempt');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001'); -- owner A
SELECT lives_ok(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'exowner@invite.test', 'viewer') $$,
  'owner CAN invite an inactive owner with another role');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000016'); -- ex-owner
SELECT results_eq(
  $$ SELECT status FROM public.accept_organization_invitation(pg_temp.invitation_id_by_email('exowner@invite.test')) $$,
  $$ VALUES ('accepted'::text) $$,
  'the ex-owner accepts the owner-issued invitation');
SELECT is((SELECT (is_active, role) FROM pg_temp.member_state('c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000016')),
  (true, 'viewer'::public.organization_member_role), 'reactivated with the invitation role (owner-authorized)');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001'); -- owner A
SELECT lives_ok(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'exowner2@invite.test', 'viewer') $$,
  'owner invites a second inactive owner');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002'); -- admin A
SELECT throws_matching(
  $$ SELECT public.resend_organization_invitation(pg_temp.invitation_id_by_email('exowner2@invite.test')) $$,
  'No autorizado para reenviar', 'admin cannot resend an owner-issued invitation that targets an inactive owner');

-- -------------------------------------------------------------------------
-- 4j. Admin (activo o inactivo) intentando usar invitaciones sobre sí mismo
-- -------------------------------------------------------------------------
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'admin-a@invite.test', 'viewer') $$,
  'ya pertenece a un miembro activo', 'an ACTIVE admin cannot invite its own email');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000018'); -- inactive admin
SELECT throws_matching(
  $$ SELECT public.create_organization_invitation('c2000000-0000-0000-0000-00000000000a', 'exadmin@invite.test', 'admin') $$,
  'No autorizado', 'an INACTIVE admin cannot invite (itself or anyone)');
SELECT throws_matching(
  $$ SELECT public.update_organization_member('c3000000-0000-0000-0000-000000000011', NULL, true) $$,
  'Not authorized', 'an INACTIVE admin cannot reactivate its own membership directly');
SELECT is((SELECT (is_active, role) FROM pg_temp.member_state('c2000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-000000000018')),
  (false, 'admin'::public.organization_member_role), 'inactive admin membership untouched');

-- -------------------------------------------------------------------------
-- 5. Último owner / auto-modificación (update_organization_member)
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002'); -- admin A
SELECT throws_matching(
  $$ SELECT public.update_organization_member((SELECT id FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND user_id = 'c1000000-0000-0000-0000-000000000001'), 'viewer'::public.organization_member_role, NULL) $$,
  'No autorizado', 'admin cannot demote the owner (cannot manage an owner-role membership)');
SELECT throws_matching(
  $$ SELECT public.update_organization_member((SELECT id FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND user_id = 'c1000000-0000-0000-0000-000000000002'), 'owner'::public.organization_member_role, NULL) $$,
  'No autorizado', 'admin cannot promote itself (or anyone) to owner');
SELECT throws_matching(
  $$ SELECT public.update_organization_member((SELECT id FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND user_id = 'c1000000-0000-0000-0000-000000000002'), NULL, false) $$,
  'No puedes modificar tu propia membresía', 'admin cannot deactivate itself');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000010'); -- lone owner of Tenant Solo Owner
SELECT throws_matching(
  $$ SELECT public.update_organization_member((SELECT id FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000c'), NULL, false) $$,
  'último propietario activo', 'the last active owner cannot deactivate itself');
SELECT throws_matching(
  $$ SELECT public.update_organization_member((SELECT id FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000c'), 'admin'::public.organization_member_role, NULL) $$,
  'último propietario activo', 'the last active owner cannot demote itself');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001'); -- owner A
SELECT lives_ok(
  $$ SELECT public.update_organization_member((SELECT id FROM public.organization_members WHERE organization_id = 'c2000000-0000-0000-0000-00000000000a' AND user_id = 'c1000000-0000-0000-0000-000000000002'), 'viewer'::public.organization_member_role, NULL) $$,
  'owner CAN demote an admin');

-- -------------------------------------------------------------------------
-- 6. Lecturas propias: get_my_organization_invitation / get_my_pending_invitations
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006'); -- invitee (owns the accepted 'Invitado Uno' invitation)
SELECT is((SELECT count(*) FROM public.get_my_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test'))),
  1::bigint, 'the invitation owner can read their own invitation');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009'); -- wrong-account
SELECT is((SELECT count(*) FROM public.get_my_organization_invitation(pg_temp.invitation_id_by_email('invitee@invite.test'))),
  0::bigint, 'get_my_organization_invitation returns nothing (not an error) for a non-matching account — privacy');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000015'); -- pending-list
SELECT is((SELECT count(*) FROM public.get_my_pending_invitations()), 1::bigint, 'get_my_pending_invitations lists exactly the caller''s own pending invitation');

-- -------------------------------------------------------------------------
-- 7. list_organization_access: aislamiento por tenant
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001'); -- owner A
SELECT ok((SELECT count(*) FROM public.list_organization_access('c2000000-0000-0000-0000-00000000000a')) > 0,
  'owner A can list Tenant A access');
SELECT throws_matching(
  $$ SELECT public.list_organization_access('c2000000-0000-0000-0000-00000000000b') $$,
  'Not authorized', 'owner A cannot list Tenant B access (cross-tenant rejected)');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.list_organization_access('c2000000-0000-0000-0000-00000000000a') WHERE effective_status = 'accepted'),
  'accepted invitations never appear in the invitations list (already reflected as a member)');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003'); -- manager A (not owner/admin)
SELECT throws_matching(
  $$ SELECT public.list_organization_access('c2000000-0000-0000-0000-00000000000a') $$,
  'Not authorized', 'a manager cannot list organization access');

-- -------------------------------------------------------------------------
-- 8. Funciones solo-service_role: inaccesibles para authenticated/anon
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.mark_invitation_sent(gen_random_uuid()) $$, '42501', NULL,
  'authenticated cannot call mark_invitation_sent');
SELECT throws_ok($$ SELECT public.get_auth_user_state_by_email('someone@invite.test') $$, '42501', NULL,
  'authenticated cannot call get_auth_user_state_by_email (no user enumeration)');

RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT public.mark_invitation_sent(gen_random_uuid()) $$, '42501', NULL,
  'anon cannot call mark_invitation_sent');
SELECT throws_ok($$ SELECT public.create_organization_invitation(gen_random_uuid(), 'x@invite.test', 'viewer') $$, '42501', NULL,
  'anon cannot call create_organization_invitation');
RESET ROLE;

-- -------------------------------------------------------------------------
-- 9. Auditoría: activity_logs registra las acciones clave, nunca secretos
-- -------------------------------------------------------------------------
SELECT ok((SELECT count(*) FROM public.activity_logs WHERE action = 'organization_invitation.created') >= 1, 'invitation creation is audited');
SELECT ok((SELECT count(*) FROM public.activity_logs WHERE action = 'organization_invitation.accepted') >= 1, 'invitation acceptance is audited');
SELECT ok((SELECT count(*) FROM public.activity_logs WHERE action = 'organization_invitation.revoked') >= 1, 'invitation revocation is audited');
SELECT ok((SELECT count(*) FROM public.activity_logs WHERE action IN ('organization_invitation.sent', 'organization_invitation.resent')) >= 1, 'a confirmed send is audited');
SELECT ok((SELECT count(*) FROM public.activity_logs WHERE action = 'organization_member.reactivated') >= 1, 'membership reactivation is audited');
SELECT is((SELECT count(*) FROM public.activity_logs WHERE metadata::text ILIKE '%token%' OR metadata::text ILIKE '%password%'), 0::bigint,
  'no activity_logs row ever contains a token or password');

SELECT * FROM finish();
ROLLBACK;
