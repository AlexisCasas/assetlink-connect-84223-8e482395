-- Fase 1 · Punto 7 — Cloudflare R2 Foundation: authorize_asset_file_access.
-- Se ejecuta con: supabase test db --local
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(36);

-- -------------------------------------------------------------------------
-- Fixture
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('e1000000-0000-0000-0000-000000000001', 'owner-a@r2.test'),
  ('e1000000-0000-0000-0000-000000000002', 'admin-a@r2.test'),
  ('e1000000-0000-0000-0000-000000000003', 'manager-a@r2.test'),
  ('e1000000-0000-0000-0000-000000000004', 'technician-a@r2.test'),
  ('e1000000-0000-0000-0000-000000000005', 'viewer-a@r2.test'),
  ('e1000000-0000-0000-0000-000000000006', 'owner-b@r2.test'),
  ('e1000000-0000-0000-0000-000000000007', 'platform@r2.test'),
  ('e1000000-0000-0000-0000-000000000008', 'inactive-a@r2.test');

INSERT INTO public.organizations (id, name, organization_type, status) VALUES
  ('e2000000-0000-0000-0000-00000000000a', 'Tenant A', 'client_company', 'active'),
  ('e2000000-0000-0000-0000-00000000000b', 'Tenant B', 'client_company', 'active'),
  ('e2000000-0000-0000-0000-00000000000c', 'Tenant Suspendido', 'client_company', 'suspended'),
  ('e2000000-0000-0000-0000-00000000000f', 'Plataforma', 'platform_admin', 'active');

INSERT INTO public.organization_members (organization_id, user_id, role, is_active) VALUES
  ('e2000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000001', 'owner', true),
  ('e2000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000002', 'admin', true),
  ('e2000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000003', 'manager', true),
  ('e2000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000004', 'technician', true),
  ('e2000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000005', 'viewer', true),
  ('e2000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000008', 'manager', false),
  ('e2000000-0000-0000-0000-00000000000b', 'e1000000-0000-0000-0000-000000000006', 'owner', true),
  ('e2000000-0000-0000-0000-00000000000c', 'e1000000-0000-0000-0000-000000000001', 'owner', true),
  ('e2000000-0000-0000-0000-00000000000f', 'e1000000-0000-0000-0000-000000000007', 'owner', true);

INSERT INTO public.assets (id, organization_id, name, node_type, status) VALUES
  ('e3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-00000000000a', 'Activo A', 'equipment', 'active'),
  ('e3000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-00000000000a', 'Activo A archivado', 'equipment', 'archived'),
  ('e3000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-00000000000b', 'Activo B', 'equipment', 'active'),
  ('e3000000-0000-0000-0000-000000000004', 'e2000000-0000-0000-0000-00000000000c', 'Activo suspendido', 'equipment', 'active');

-- Punto 10: rama delegada de Facility Manager (matriz 9C.1 de assets.*).
INSERT INTO auth.users (id, email) VALUES
  ('e1000000-0000-0000-0000-000000000011', 'fm-manager@r2.test'),
  ('e1000000-0000-0000-0000-000000000012', 'fm-technician@r2.test'),
  ('e1000000-0000-0000-0000-000000000013', 'fm-manager-unassigned@r2.test');
INSERT INTO public.organizations (id, name, organization_type, status) VALUES
  ('e2000000-0000-0000-0000-0000000000fa', 'FM R2', 'facility_manager', 'active');
INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('e4000000-0000-0000-0000-000000000011', 'e2000000-0000-0000-0000-0000000000fa', 'e1000000-0000-0000-0000-000000000011', 'manager', true),
  ('e4000000-0000-0000-0000-000000000012', 'e2000000-0000-0000-0000-0000000000fa', 'e1000000-0000-0000-0000-000000000012', 'technician', true),
  ('e4000000-0000-0000-0000-000000000013', 'e2000000-0000-0000-0000-0000000000fa', 'e1000000-0000-0000-0000-000000000013', 'manager', true);
INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status) VALUES
  ('e5000000-0000-0000-0000-0000000000aa', 'e2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-0000000000fa', 'facility_management', 'pending');
INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES
  ('e5000000-0000-0000-0000-0000000000aa', 'assets.view'), ('e5000000-0000-0000-0000-0000000000aa', 'assets.manage');
INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES
  ('e5000000-0000-0000-0000-0000000000aa', 'e4000000-0000-0000-0000-000000000011'),
  ('e5000000-0000-0000-0000-0000000000aa', 'e4000000-0000-0000-0000-000000000012');
UPDATE public.organization_relationships SET status = 'active' WHERE id = 'e5000000-0000-0000-0000-0000000000aa';

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;

SET LOCAL ROLE authenticated;

-- -------------------------------------------------------------------------
-- 1. write/delete: owner, admin, manager permitidos; technician, viewer no
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'owner can write');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'delete'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'owner can delete');

SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000002');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'admin can write');

SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000003');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'manager can write');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'delete'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'manager can delete');

SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000004');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write') $$,
  'Not authorized', 'technician cannot write');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'delete') $$,
  'Not authorized', 'technician cannot delete');

SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000005');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write') $$,
  'Not authorized', 'viewer cannot write');

-- Inactive manager (is_active=false): jerarquía exige membership activa.
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000008');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write') $$,
  'Not authorized', 'inactive manager cannot write');

-- -------------------------------------------------------------------------
-- 2. read: cualquier miembro activo, incluidos technician y viewer
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000004');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'technician can read');
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000005');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'viewer can read');
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000008');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read') $$,
  'Not authorized', 'an inactive member cannot even read');

-- -------------------------------------------------------------------------
-- 3. Cross-tenant
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000006'); -- owner of Tenant B
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read') $$,
  'Not authorized', 'owner of another tenant cannot read this asset''s files');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write') $$,
  'Not authorized', 'owner of another tenant cannot write this asset''s files');

-- -------------------------------------------------------------------------
-- 4. Archivado: read permitido, write/delete rechazado
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000001');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000002', 'read'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'reading files of an archived asset is allowed');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000002', 'write') $$,
  'archived asset', 'writing to an archived asset is rejected, even for the owner');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000002', 'delete') $$,
  'archived asset', 'deleting from an archived asset is rejected, even for the owner');

-- -------------------------------------------------------------------------
-- 5. Organización inactiva (suspendida) — rechazado incluso para su owner
-- -------------------------------------------------------------------------
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000004', 'read') $$,
  'not available', 'a suspended organization''s asset rejects read, even for its own owner');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000004', 'write') $$,
  'not available', 'a suspended organization''s asset rejects write, even for its own owner');

-- -------------------------------------------------------------------------
-- 6. Activo inexistente / operación inválida
-- -------------------------------------------------------------------------
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access(gen_random_uuid(), 'read') $$,
  'Asset not found', 'a non-existent asset is rejected');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'admin') $$,
  'Invalid operation', 'an invalid operation string is rejected');

-- -------------------------------------------------------------------------
-- 7. Platform admin conserva acceso completo, sin ser miembro del tenant
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000007');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'platform admin can read any tenant''s asset files');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000003', 'write'), 'e2000000-0000-0000-0000-00000000000b'::uuid,
  'platform admin can write files for a different tenant''s asset');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'delete'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'platform admin can delete');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000002', 'write') $$,
  'archived asset', 'platform admin still cannot write to an archived asset');

-- -------------------------------------------------------------------------
-- 7b. Facility Manager delegado (Punto 10): se agrega, no reemplaza lo anterior
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000011');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'FM manager (assets.view + assets.manage, assigned) can write');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000003', 'read') $$,
  'Not authorized', 'FM manager cannot read another client''s asset files');
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000012');
SELECT is(public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read'), 'e2000000-0000-0000-0000-00000000000a'::uuid,
  'FM technician (assets.view, assigned) can read');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'write') $$,
  'Not authorized', 'FM technician cannot write');
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000013');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read') $$,
  'Not authorized', 'FM manager NOT assigned to the relationship cannot even read');
SELECT pg_temp.as_user('e1000000-0000-0000-0000-000000000011');
SELECT throws_matching(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000002', 'write') $$,
  'archived asset', 'FM manager cannot write to an archived asset');

RESET ROLE;

-- -------------------------------------------------------------------------
-- 8. anon y grants
-- -------------------------------------------------------------------------
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ SELECT public.authorize_asset_file_access('e3000000-0000-0000-0000-000000000001', 'read') $$,
  '42501', NULL, 'anon cannot call authorize_asset_file_access at all');
RESET ROLE;

SELECT ok(NOT has_function_privilege('anon', 'public.authorize_asset_file_access(uuid, text)', 'EXECUTE'),
  'anon has no EXECUTE grant on authorize_asset_file_access');
SELECT ok(has_function_privilege('authenticated', 'public.authorize_asset_file_access(uuid, text)', 'EXECUTE'),
  'authenticated has EXECUTE on authorize_asset_file_access');
SELECT is((SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'public.authorize_asset_file_access(uuid, text)'::regprocedure),
  true, 'authorize_asset_file_access is SECURITY DEFINER');
SELECT is((SELECT array_to_string(p.proconfig, ',') FROM pg_proc p WHERE p.oid = 'public.authorize_asset_file_access(uuid, text)'::regprocedure),
  'search_path=""', 'authorize_asset_file_access pins an empty search_path (Punto 10: schema-qualified references)');

SELECT * FROM finish();
ROLLBACK;
