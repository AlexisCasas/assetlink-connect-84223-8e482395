-- Organization access hardening (20260926203242_organization_access_hardening.sql).
-- Se ejecuta con: supabase test db --local
--
-- Cada intento de escalamiento se ejecuta como el rol `authenticated` (o
-- `anon`) con un auth.uid() sintético — nunca como postgres — y el estado
-- se verifica después como postgres para demostrar que nada cambió.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(103);

-- -------------------------------------------------------------------------
-- Fixture (todo sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email)
VALUES
  ('a1000000-0000-0000-0000-000000000001', 'owner-a@hardening.test'),
  ('a1000000-0000-0000-0000-000000000002', 'admin-a@hardening.test'),
  ('a1000000-0000-0000-0000-000000000003', 'viewer-a@hardening.test'),
  ('a1000000-0000-0000-0000-000000000004', 'owner-b@hardening.test'),
  ('a1000000-0000-0000-0000-000000000005', 'platform@hardening.test'),
  ('a1000000-0000-0000-0000-000000000006', 'outsider@hardening.test');

INSERT INTO public.organizations (id, name, legal_name, tax_id, organization_type)
VALUES
  ('a2000000-0000-0000-0000-00000000000a', 'Tenant A', 'Tenant A SAC', '20000000001', 'client_company'),
  ('a2000000-0000-0000-0000-00000000000b', 'Tenant B', 'Tenant B SAC', '20000000002', 'client_company'),
  ('a2000000-0000-0000-0000-00000000000f', 'Plataforma', NULL, NULL, 'platform_admin');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active)
VALUES
  ('a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000001', 'owner', true),
  ('a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000002', 'admin', true),
  ('a3000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000003', 'viewer', true),
  ('a3000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-00000000000b', 'a1000000-0000-0000-0000-000000000004', 'owner', true),
  ('a3000000-0000-0000-0000-000000000005', 'a2000000-0000-0000-0000-00000000000f', 'a1000000-0000-0000-0000-000000000005', 'owner', true);

INSERT INTO public.organization_invitations (id, organization_id, email, role, invited_by, expires_at)
VALUES ('a4000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-00000000000a', 'invitee@hardening.test', 'viewer',
        'a1000000-0000-0000-0000-000000000001', now() + interval '7 days');

INSERT INTO public.activity_logs (id, organization_id, actor_user_id, entity_type, entity_id, action)
VALUES ('a5000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000001',
        'organization', 'a2000000-0000-0000-0000-00000000000a', 'fixture.created');

INSERT INTO public.audit_logs (id, organization_id, actor_user_id, table_name, record_id, action)
VALUES ('a6000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000001',
        'organizations', 'a2000000-0000-0000-0000-00000000000a', 'fixture');

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;

-- Exactly the statement OrganizationProfile.tsx issues through PostgREST
-- (.from('organizations').update({ name, legal_name, tax_id }).eq('id', …)),
-- returning how many rows RLS let through.
CREATE FUNCTION pg_temp.update_profile(p_org uuid, p_name text, p_legal text, p_tax text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE v_rows integer;
BEGIN
  UPDATE public.organizations SET name = p_name, legal_name = p_legal, tax_id = p_tax WHERE id = p_org;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END $$;

-- -------------------------------------------------------------------------
-- 1. Estructura: privilegios y policies
-- -------------------------------------------------------------------------
SELECT ok(NOT has_table_privilege('authenticated', 'public.organizations', 'INSERT'), 'authenticated: no INSERT on organizations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organizations', 'DELETE'), 'authenticated: no DELETE on organizations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organizations', 'TRUNCATE'), 'authenticated: no TRUNCATE on organizations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organizations', 'UPDATE'), 'authenticated: no table-wide UPDATE on organizations');
SELECT ok(has_column_privilege('authenticated', 'public.organizations', 'name', 'UPDATE'), 'authenticated: UPDATE(name) on organizations');
SELECT ok(has_column_privilege('authenticated', 'public.organizations', 'legal_name', 'UPDATE'), 'authenticated: UPDATE(legal_name) on organizations');
SELECT ok(has_column_privilege('authenticated', 'public.organizations', 'tax_id', 'UPDATE'), 'authenticated: UPDATE(tax_id) on organizations');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organizations', 'organization_type', 'UPDATE'), 'authenticated: no UPDATE(organization_type)');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organizations', 'status', 'UPDATE'), 'authenticated: no UPDATE(status)');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organizations', 'settings', 'UPDATE'), 'authenticated: no UPDATE(settings)');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organizations', 'created_by', 'UPDATE'), 'authenticated: no UPDATE(created_by)');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organizations', 'id', 'UPDATE'), 'authenticated: no UPDATE(id)');

SELECT ok(NOT has_table_privilege('authenticated', 'public.organization_members', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated: no writes on organization_members');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organization_invitations', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated: no writes on organization_invitations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.activity_logs', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated: no writes on activity_logs');
SELECT ok(NOT has_table_privilege('authenticated', 'public.audit_logs', 'INSERT,UPDATE,DELETE,TRUNCATE'), 'authenticated: no writes on audit_logs');

SELECT ok(has_table_privilege('authenticated', 'public.organizations', 'SELECT'), 'authenticated keeps SELECT on organizations');
SELECT ok(has_table_privilege('authenticated', 'public.organization_members', 'SELECT'), 'authenticated keeps SELECT on organization_members');
SELECT ok(has_table_privilege('authenticated', 'public.organization_invitations', 'SELECT'), 'authenticated keeps SELECT on organization_invitations');
SELECT ok(has_table_privilege('authenticated', 'public.activity_logs', 'SELECT'), 'authenticated keeps SELECT on activity_logs');
SELECT ok(has_table_privilege('authenticated', 'public.audit_logs', 'SELECT'), 'authenticated keeps SELECT on audit_logs');

SELECT ok(NOT has_table_privilege('anon', 'public.organizations', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: no privileges on organizations');
SELECT ok(NOT has_table_privilege('anon', 'public.organization_members', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: no privileges on organization_members');
SELECT ok(NOT has_table_privilege('anon', 'public.organization_invitations', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: no privileges on organization_invitations');
SELECT ok(NOT has_table_privilege('anon', 'public.activity_logs', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: no privileges on activity_logs');
SELECT ok(NOT has_table_privilege('anon', 'public.audit_logs', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: no privileges on audit_logs');

SELECT ok(has_table_privilege('service_role', 'public.organization_members', 'SELECT') AND has_table_privilege('service_role', 'public.organization_members', 'INSERT')
  AND has_table_privilege('service_role', 'public.organization_members', 'UPDATE') AND has_table_privilege('service_role', 'public.organization_members', 'DELETE'),
  'service_role keeps full access to organization_members');
SELECT ok(has_table_privilege('service_role', 'public.organizations', 'INSERT') AND has_table_privilege('service_role', 'public.organizations', 'UPDATE'),
  'service_role keeps INSERT/UPDATE on organizations');
SELECT ok(has_table_privilege('service_role', 'public.organization_invitations', 'INSERT') AND has_table_privilege('service_role', 'public.activity_logs', 'INSERT'),
  'service_role keeps INSERT on organization_invitations and activity_logs');

SELECT policies_are('public', 'organization_members', ARRAY['members can view organization memberships'],
  'organization_members only keeps its SELECT policy');
SELECT policies_are('public', 'activity_logs', ARRAY['members can view activity logs'],
  'activity_logs only keeps its SELECT policy');
SELECT policies_are('public', 'organization_invitations', ARRAY['organization administrators can view invitations'],
  'organization_invitations only has its SELECT policy');
SELECT policies_are('public', 'audit_logs', ARRAY['administrators can view audit logs'],
  'audit_logs only has its SELECT policy');
SELECT policies_are('public', 'organizations', ARRAY['members can view organizations', 'organization administrators can update organizations'],
  'organizations keeps SELECT + owner/admin profile UPDATE policies');
SELECT ok((SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'public.set_request_audience'::regproc),
  'set_request_audience (only SQL writer of audit_logs) is SECURITY DEFINER');

-- -------------------------------------------------------------------------
-- 2. Intentos de escalamiento como admin del Tenant A (rol authenticated)
-- -------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000002');

SELECT is(public.is_platform_admin(), false, 'baseline: tenant admin is not a platform admin');

SELECT throws_ok($$ UPDATE public.organization_members SET role = 'owner' WHERE user_id = 'a1000000-0000-0000-0000-000000000002' $$,
  '42501', NULL, 'admin cannot self-promote to owner with a direct UPDATE');
SELECT throws_ok($$ UPDATE public.organization_members SET is_active = false WHERE user_id = 'a1000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'admin cannot deactivate the owner directly');
SELECT throws_ok($$ UPDATE public.organization_members SET role = 'viewer' WHERE user_id = 'a1000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'admin cannot demote the owner directly');
SELECT throws_ok($$ INSERT INTO public.organization_members (organization_id, user_id, role) VALUES ('a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000006', 'owner') $$,
  '42501', NULL, 'admin cannot insert an arbitrary membership');
SELECT throws_ok($$ DELETE FROM public.organization_members WHERE user_id = 'a1000000-0000-0000-0000-000000000003' $$,
  '42501', NULL, 'admin cannot DELETE a membership');
SELECT throws_ok($$ TRUNCATE public.organization_members $$,
  '42501', NULL, 'admin cannot TRUNCATE organization_members');

SELECT throws_ok($$ UPDATE public.organizations SET organization_type = 'provider_company' WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  '42501', NULL, 'admin cannot change organizations.organization_type');
SELECT throws_ok($$ UPDATE public.organizations SET organization_type = 'platform_admin' WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  '42501', NULL, 'admin cannot turn the organization into platform_admin');
-- Checked right here, before the status/settings attempts below: a
-- successful status='suspended' would itself make is_platform_admin()
-- false and mask a successful platform_admin flip.
SELECT is(public.is_platform_admin(), false, 'is_platform_admin() stays false right after the platform_admin attempt');
SELECT throws_ok($$ UPDATE public.organizations SET status = 'suspended' WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  '42501', NULL, 'admin cannot change organizations.status');
SELECT throws_ok($$ UPDATE public.organizations SET settings = '{"x":1}'::jsonb WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  '42501', NULL, 'admin cannot change organizations.settings');
SELECT throws_ok($$ UPDATE public.organizations SET name = 'X', organization_type = 'platform_admin' WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  '42501', NULL, 'mixing an allowed column with organization_type is still rejected');
SELECT throws_ok($$ INSERT INTO public.organizations (name, organization_type) VALUES ('Rogue', 'platform_admin') $$,
  '42501', NULL, 'admin cannot INSERT organizations');
SELECT throws_ok($$ DELETE FROM public.organizations WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  '42501', NULL, 'admin cannot DELETE organizations');

SELECT throws_ok($$ INSERT INTO public.organization_invitations (organization_id, email, role, invited_by) VALUES ('a2000000-0000-0000-0000-00000000000a', 'rogue@hardening.test', 'owner', 'a1000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'admin cannot INSERT invitations directly');
SELECT throws_ok($$ UPDATE public.organization_invitations SET role = 'owner' WHERE id = 'a4000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'admin cannot UPDATE invitations directly');
SELECT throws_ok($$ DELETE FROM public.organization_invitations WHERE id = 'a4000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'admin cannot DELETE invitations directly');

SELECT throws_ok($$ INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, action) VALUES ('a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000002', 'x', 'forged') $$,
  '42501', NULL, 'authenticated cannot INSERT audit_logs');
SELECT throws_ok($$ UPDATE public.audit_logs SET action = 'tampered' $$,
  '42501', NULL, 'authenticated cannot UPDATE audit_logs');
SELECT throws_ok($$ DELETE FROM public.audit_logs $$,
  '42501', NULL, 'authenticated cannot DELETE audit_logs');
SELECT throws_ok($$ INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, action) VALUES ('a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000002', 'x', 'forged') $$,
  '42501', NULL, 'authenticated cannot INSERT activity_logs (even with its own actor id)');
SELECT throws_ok($$ UPDATE public.activity_logs SET action = 'tampered' $$,
  '42501', NULL, 'authenticated cannot UPDATE activity_logs');
SELECT throws_ok($$ DELETE FROM public.activity_logs $$,
  '42501', NULL, 'authenticated cannot DELETE activity_logs');

SELECT is(public.is_platform_admin(), false, 'tenant admin is still NOT a platform admin after every escalation attempt');

-- -------------------------------------------------------------------------
-- 3. Lecturas existentes (RLS sin cambios)
-- -------------------------------------------------------------------------
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a'), 3::bigint,
  'admin A reads the memberships of Tenant A');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'a2000000-0000-0000-0000-00000000000b'), 0::bigint,
  'admin A cannot read Tenant B memberships');
SELECT is((SELECT count(*) FROM public.organization_invitations), 1::bigint, 'admin A reads Tenant A invitations');
SELECT is((SELECT count(*) FROM public.activity_logs), 1::bigint, 'admin A reads Tenant A activity logs');
SELECT is((SELECT count(*) FROM public.audit_logs), 1::bigint, 'admin A reads Tenant A audit logs');
SELECT is((SELECT count(*) FROM public.organizations), 1::bigint, 'admin A only sees its own organization');

SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a'), 3::bigint,
  'viewer A still reads Tenant A memberships (is_organization_member)');
SELECT is((SELECT count(*) FROM public.organization_invitations), 0::bigint, 'viewer A cannot read invitations (owner/admin only)');
SELECT is((SELECT count(*) FROM public.audit_logs), 0::bigint, 'viewer A cannot read audit logs (owner/admin only)');

-- -------------------------------------------------------------------------
-- 4. OrganizationProfile: la escritura legítima sigue funcionando
-- -------------------------------------------------------------------------
SELECT is(pg_temp.update_profile('a2000000-0000-0000-0000-00000000000a', 'Hackeado', 'Hackeado SAC', '1'), 0,
  'viewer A cannot update the profile (RLS filters the row)');

SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000002');
SELECT is(pg_temp.update_profile('a2000000-0000-0000-0000-00000000000a', 'Tenant A (admin)', 'Tenant A Admin SAC', '20000000011'), 1,
  'admin A updates name/legal_name/tax_id (OrganizationProfile query)');
SELECT results_eq(
  $$ SELECT name, legal_name, tax_id FROM public.organizations WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  $$ VALUES ('Tenant A (admin)'::text, 'Tenant A Admin SAC'::text, '20000000011'::text) $$,
  'admin profile update persisted');

SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000001');
SELECT is(pg_temp.update_profile('a2000000-0000-0000-0000-00000000000a', 'Tenant A (owner)', NULL, NULL), 1,
  'owner A updates the profile, including clearing legal_name/tax_id to NULL');

SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000004');
SELECT is(pg_temp.update_profile('a2000000-0000-0000-0000-00000000000a', 'Cross-tenant', 'X', 'X'), 0,
  'owner of Tenant B cannot update Tenant A profile');

-- -------------------------------------------------------------------------
-- 5. Platform admin: conserva lecturas administrativas, sin escrituras directas
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000005');
SELECT is(public.is_platform_admin(), true, 'platform owner is a platform admin');
SELECT is((SELECT count(*) FROM public.organizations WHERE id IN ('a2000000-0000-0000-0000-00000000000a', 'a2000000-0000-0000-0000-00000000000b', 'a2000000-0000-0000-0000-00000000000f')), 3::bigint,
  'platform admin reads every organization');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a'), 3::bigint,
  'platform admin reads Tenant A memberships');
SELECT is((SELECT count(*) FROM public.organization_invitations WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a'), 1::bigint,
  'platform admin reads Tenant A invitations');
SELECT is((SELECT count(*) FROM public.activity_logs WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a'), 1::bigint,
  'platform admin reads Tenant A activity logs');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a'), 1::bigint,
  'platform admin reads Tenant A audit logs');
SELECT throws_ok($$ UPDATE public.organization_members SET role = 'viewer' WHERE user_id = 'a1000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'platform admin cannot write memberships directly either (Edge Functions only)');
SELECT throws_ok($$ UPDATE public.organizations SET status = 'archived' WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  '42501', NULL, 'platform admin cannot change status directly (admin-archive-organization only)');
RESET ROLE;

-- -------------------------------------------------------------------------
-- 6. anon: ningún acceso directo
-- -------------------------------------------------------------------------
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT 1 FROM public.organizations $$, '42501', NULL, 'anon cannot SELECT organizations');
SELECT throws_ok($$ SELECT 1 FROM public.organization_members $$, '42501', NULL, 'anon cannot SELECT organization_members');
SELECT throws_ok($$ SELECT 1 FROM public.organization_invitations $$, '42501', NULL, 'anon cannot SELECT organization_invitations');
SELECT throws_ok($$ SELECT 1 FROM public.activity_logs $$, '42501', NULL, 'anon cannot SELECT activity_logs');
SELECT throws_ok($$ SELECT 1 FROM public.audit_logs $$, '42501', NULL, 'anon cannot SELECT audit_logs');
SELECT throws_ok($$ INSERT INTO public.organization_members (organization_id, user_id, role) VALUES ('a2000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000006', 'owner') $$,
  '42501', NULL, 'anon cannot INSERT organization_members');
RESET ROLE;

-- -------------------------------------------------------------------------
-- 7. service_role (Edge Functions) sigue pudiendo escribir
-- -------------------------------------------------------------------------
SET LOCAL ROLE service_role;
SELECT lives_ok($$ INSERT INTO public.organizations (id, name, organization_type) VALUES ('a2000000-0000-0000-0000-00000000000c', 'Tenant C', 'client_company') $$,
  'service_role creates organizations (admin-create-organization)');
SELECT lives_ok($$ INSERT INTO public.organization_members (organization_id, user_id, role) VALUES ('a2000000-0000-0000-0000-00000000000c', 'a1000000-0000-0000-0000-000000000006', 'owner') $$,
  'service_role adds memberships (admin-add-existing-member / create-user)');
SELECT lives_ok($$ UPDATE public.organization_members SET role = 'admin' WHERE organization_id = 'a2000000-0000-0000-0000-00000000000c' $$,
  'service_role updates memberships (admin-update-organization-member)');
SELECT lives_ok($$ INSERT INTO public.organization_invitations (organization_id, email, role, invited_by) VALUES ('a2000000-0000-0000-0000-00000000000c', 'new@hardening.test', 'viewer', 'a1000000-0000-0000-0000-000000000005') $$,
  'service_role inserts invitations (admin-invite-organization-member)');
SELECT lives_ok($$ INSERT INTO public.activity_logs (organization_id, actor_user_id, entity_type, action) VALUES ('a2000000-0000-0000-0000-00000000000c', 'a1000000-0000-0000-0000-000000000005', 'organization', 'organization.created') $$,
  'service_role inserts activity_logs');
SELECT lives_ok($$ UPDATE public.organizations SET status = 'archived' WHERE id = 'a2000000-0000-0000-0000-00000000000c' $$,
  'service_role archives organizations (admin-archive-organization)');
SELECT is((SELECT count(*) FROM public.organization_members WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a'), 3::bigint,
  'service_role lists memberships (admin-list-organization-members)');
RESET ROLE;

-- -------------------------------------------------------------------------
-- 8. Estado final (como postgres): ningún intento dejó huella
-- -------------------------------------------------------------------------
SELECT results_eq(
  $$ SELECT user_id::text, role::text, is_active FROM public.organization_members WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a' ORDER BY user_id $$,
  $$ VALUES ('a1000000-0000-0000-0000-000000000001', 'owner', true),
            ('a1000000-0000-0000-0000-000000000002', 'admin', true),
            ('a1000000-0000-0000-0000-000000000003', 'viewer', true) $$,
  'Tenant A memberships are exactly the fixture (no promotion, no deactivation, no insert, no delete)');
SELECT results_eq(
  $$ SELECT organization_type::text, status, settings FROM public.organizations WHERE id = 'a2000000-0000-0000-0000-00000000000a' $$,
  $$ VALUES ('client_company', 'active', '{}'::jsonb) $$,
  'Tenant A type/status/settings unchanged');
SELECT is((SELECT name FROM public.organizations WHERE id = 'a2000000-0000-0000-0000-00000000000b'), 'Tenant B', 'Tenant B name unchanged');
SELECT results_eq(
  $$ SELECT role::text, status::text FROM public.organization_invitations WHERE organization_id = 'a2000000-0000-0000-0000-00000000000a' $$,
  $$ VALUES ('viewer', 'pending') $$,
  'Tenant A invitations unchanged');
SELECT is((SELECT count(*) FROM public.activity_logs WHERE action IN ('forged', 'tampered')), 0::bigint, 'no forged/tampered activity_logs');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE action IN ('forged', 'tampered')), 0::bigint, 'no forged/tampered audit_logs');
SELECT is((SELECT count(*) FROM public.organizations WHERE name = 'Rogue'), 0::bigint, 'no rogue organization inserted');

SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT is(public.is_platform_admin(), false, 'final check: tenant admin is still not a platform admin');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
