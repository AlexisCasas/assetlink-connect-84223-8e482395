-- Fase 1 · Punto 9A — permisos delegados Cliente -> Facility Manager
-- (20260927194923_facility_manager_delegated_permissions.sql).
-- Se ejecuta con: supabase test db --local
--
-- Cada intento se ejecuta como `authenticated` (o `anon`) con un auth.uid()
-- sintético; el estado se verifica después como postgres. Los errores
-- funcionales se verifican por SQLSTATE, nunca por texto:
--   42501 no autenticado/no autorizado · 22023 parámetro inválido ·
--   P0002 relación inexistente · 55000 transición/estado no permitido ·
--   23514 invariante de trigger.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(328);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('c1000000-0000-0000-0000-000000000001', 'owner-client-a@fm.test'),
  ('c1000000-0000-0000-0000-000000000002', 'admin-client-a@fm.test'),
  ('c1000000-0000-0000-0000-000000000003', 'manager-client-a@fm.test'),
  ('c1000000-0000-0000-0000-000000000004', 'owner-client-b@fm.test'),
  ('c1000000-0000-0000-0000-000000000005', 'owner-fm-a@fm.test'),
  ('c1000000-0000-0000-0000-000000000006', 'manager-fm-a@fm.test'),
  ('c1000000-0000-0000-0000-000000000007', 'technician-fm-a@fm.test'),
  ('c1000000-0000-0000-0000-000000000008', 'owner-fm-b@fm.test'),
  ('c1000000-0000-0000-0000-000000000009', 'platform@fm.test'),
  ('c1000000-0000-0000-0000-00000000000a', 'outsider@fm.test'),
  ('c1000000-0000-0000-0000-00000000000b', 'admin-fm-a@fm.test'),
  ('c1000000-0000-0000-0000-00000000000c', 'technician2-fm-a@fm.test'),
  ('c1000000-0000-0000-0000-00000000000d', 'inactive-fm-a@fm.test'),
  ('c1000000-0000-0000-0000-00000000000e', 'owner-client-c@fm.test');

-- Metadata con un nombre y una clave "sensible": get_facility_management_members
-- debe devolver solo el nombre, nunca metadata cruda.
UPDATE auth.users SET raw_user_meta_data = '{"name": "Carlos Tecnico", "internal_note": "do-not-leak"}'::jsonb
WHERE id = 'c1000000-0000-0000-0000-000000000007';

INSERT INTO public.organizations (id, name, organization_type) VALUES
  ('c2000000-0000-0000-0000-0000000000a1', 'Client A', 'client_company'),
  ('c2000000-0000-0000-0000-0000000000b1', 'Client B', 'client_company'),
  ('c2000000-0000-0000-0000-0000000000c1', 'Client C', 'client_company'),
  ('c2000000-0000-0000-0000-0000000000f1', 'FM Alpha', 'facility_manager'),
  ('c2000000-0000-0000-0000-0000000000f2', 'FM Beta', 'facility_manager'),
  ('c2000000-0000-0000-0000-0000000000d1', 'Provider Control', 'provider_company'),
  ('c2000000-0000-0000-0000-0000000000ee', 'Plataforma FM Test', 'platform_admin');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-000000000001', 'owner', true),
  ('c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-000000000002', 'admin', true),
  ('c3000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-000000000003', 'manager', true),
  ('c3000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-0000000000b1', 'c1000000-0000-0000-0000-000000000004', 'owner', true),
  ('c3000000-0000-0000-0000-000000000005', 'c2000000-0000-0000-0000-0000000000f1', 'c1000000-0000-0000-0000-000000000005', 'owner', true),
  ('c3000000-0000-0000-0000-000000000006', 'c2000000-0000-0000-0000-0000000000f1', 'c1000000-0000-0000-0000-000000000006', 'manager', true),
  ('c3000000-0000-0000-0000-000000000007', 'c2000000-0000-0000-0000-0000000000f1', 'c1000000-0000-0000-0000-000000000007', 'technician', true),
  ('c3000000-0000-0000-0000-000000000008', 'c2000000-0000-0000-0000-0000000000f2', 'c1000000-0000-0000-0000-000000000008', 'owner', true),
  ('c3000000-0000-0000-0000-000000000009', 'c2000000-0000-0000-0000-0000000000ee', 'c1000000-0000-0000-0000-000000000009', 'owner', true),
  ('c3000000-0000-0000-0000-00000000000b', 'c2000000-0000-0000-0000-0000000000f1', 'c1000000-0000-0000-0000-00000000000b', 'admin', true),
  ('c3000000-0000-0000-0000-00000000000c', 'c2000000-0000-0000-0000-0000000000f1', 'c1000000-0000-0000-0000-00000000000c', 'technician', true),
  ('c3000000-0000-0000-0000-00000000000d', 'c2000000-0000-0000-0000-0000000000f1', 'c1000000-0000-0000-0000-00000000000d', 'viewer', false),
  ('c3000000-0000-0000-0000-00000000000e', 'c2000000-0000-0000-0000-0000000000c1', 'c1000000-0000-0000-0000-00000000000e', 'owner', true);

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;

-- =========================================================================
-- 1. ESTRUCTURA
-- =========================================================================
SELECT has_type('public', 'facility_management_permission', 'enum facility_management_permission exists');
SELECT enum_has_labels('public', 'facility_management_permission', ARRAY[
  'assets.view', 'assets.manage', 'criticality.view', 'criticality.manage',
  'inspections.view', 'inspections.manage', 'preventive_maintenance.view', 'preventive_maintenance.manage',
  'maintenance_notices.view', 'maintenance_notices.report', 'maintenance_notices.manage',
  'requests.view', 'requests.create', 'requests.manage', 'providers.manage',
  'quotes.view', 'quotes.manage', 'quotes.approve', 'work_orders.view', 'work_orders.manage', 'reports.view'
], 'enum has exactly the 21 delegable capabilities, in order');
SELECT has_table('public', 'facility_management_permissions', 'table facility_management_permissions exists');
SELECT columns_are('public', 'facility_management_permissions', ARRAY['relationship_id', 'permission', 'granted_by', 'granted_at'],
  'permissions table does not duplicate client/FM ids');
SELECT col_is_pk('public', 'facility_management_permissions', ARRAY['relationship_id', 'permission'], 'PK is (relationship_id, permission)');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint c
  WHERE c.conrelid = 'public.facility_management_permissions'::regclass AND c.contype = 'f'
    AND c.confrelid = 'public.organization_relationships'::regclass AND c.confdeltype = 'c'
), 'relationship_id FK -> organization_relationships ON DELETE CASCADE');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint c
  WHERE c.conrelid = 'public.facility_management_permissions'::regclass AND c.contype = 'f'
    AND c.confrelid = 'auth.users'::regclass AND c.confdeltype = 'n'
), 'granted_by FK -> auth.users ON DELETE SET NULL');
SELECT has_index('public', 'facility_management_permissions', 'idx_facility_management_permissions_permission_relationship',
  ARRAY['permission', 'relationship_id'], 'index on (permission, relationship_id)');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.facility_management_permissions'::regclass), 'RLS enabled on facility_management_permissions');

SELECT ok(has_table_privilege('authenticated', 'public.facility_management_permissions', 'SELECT'), 'authenticated: SELECT on permissions');
SELECT ok(NOT has_table_privilege('authenticated', 'public.facility_management_permissions', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
  'authenticated: no write privileges on permissions');
SELECT ok(NOT has_table_privilege('anon', 'public.facility_management_permissions', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
  'anon: no privileges on permissions');
SELECT ok(has_table_privilege('service_role', 'public.facility_management_permissions', 'SELECT')
  AND has_table_privilege('service_role', 'public.facility_management_permissions', 'INSERT')
  AND has_table_privilege('service_role', 'public.facility_management_permissions', 'UPDATE')
  AND has_table_privilege('service_role', 'public.facility_management_permissions', 'DELETE'),
  'service_role: explicit DML on permissions');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
  WHERE c.oid IN ('public.facility_management_permissions'::regclass, 'public.organization_relationships'::regclass) AND a.grantee = 0
), 'PUBLIC has no privileges on permissions or relationships');
SELECT policies_are('public', 'facility_management_permissions', ARRAY['relationship members can view facility management permissions'],
  'permissions table only has its SELECT policy');
SELECT is((SELECT count(*) FROM pg_policy WHERE polrelid = 'public.facility_management_permissions'::regclass AND polcmd <> 'r'), 0::bigint,
  'no INSERT/UPDATE/DELETE policies on permissions');

SELECT ok(has_table_privilege('authenticated', 'public.organization_relationships', 'SELECT'), 'authenticated keeps SELECT on relationships');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organization_relationships', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
  'authenticated: no write privileges on relationships');
SELECT ok(NOT has_table_privilege('anon', 'public.organization_relationships', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
  'anon: no privileges on relationships');
SELECT ok(has_table_privilege('service_role', 'public.organization_relationships', 'SELECT')
  AND has_table_privilege('service_role', 'public.organization_relationships', 'INSERT')
  AND has_table_privilege('service_role', 'public.organization_relationships', 'UPDATE')
  AND has_table_privilege('service_role', 'public.organization_relationships', 'DELETE'),
  'service_role: explicit DML on relationships');
SELECT policies_are('public', 'organization_relationships', ARRAY['members can view organization relationships'],
  'relationships only keep the historical SELECT policy (3 write policies dropped)');

-- =========================================================================
-- 2. CONSISTENCIA (triggers, como postgres)
-- =========================================================================
SELECT lives_ok($$
  INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status)
  VALUES ('c4000000-0000-0000-0000-0000000000b2', 'c2000000-0000-0000-0000-0000000000b1', 'c2000000-0000-0000-0000-0000000000f2', 'facility_management', 'pending')
$$, 'client -> FM facility_management relationship is valid');
SELECT throws_ok($$
  INSERT INTO public.organization_relationships (source_organization_id, target_organization_id, relationship_type, status)
  VALUES ('c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-0000000000f1', 'facility_management', 'pending')
$$, '23514', NULL, 'provider -> FM facility_management is rejected');
SELECT throws_ok($$
  INSERT INTO public.organization_relationships (source_organization_id, target_organization_id, relationship_type, status)
  VALUES ('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000d1', 'facility_management', 'pending')
$$, '23514', NULL, 'client -> provider with facility_management is rejected');
SELECT throws_ok($$
  INSERT INTO public.organization_relationships (source_organization_id, target_organization_id, relationship_type, status)
  VALUES ('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1', 'facility_management', 'active')
$$, '55000', NULL, 'a facility_management relationship cannot be born active');
SELECT lives_ok($$
  INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status)
  VALUES ('c4000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000d1', 'provider', 'active')
$$, 'provider relationships keep their semantics (can be born active)');
SELECT throws_ok($$
  INSERT INTO public.facility_management_permissions (relationship_id, permission)
  VALUES ('c4000000-0000-0000-0000-0000000000d1', 'assets.view')
$$, '23514', NULL, 'a permission on a provider relationship is rejected');
SELECT throws_ok($$
  UPDATE public.organization_relationships SET target_organization_id = 'c2000000-0000-0000-0000-0000000000f1'
  WHERE id = 'c4000000-0000-0000-0000-0000000000b2'
$$, '23514', NULL, 'a facility_management relationship cannot be re-pointed to another FM');
SELECT throws_ok($$
  UPDATE public.organization_relationships SET relationship_type = 'facility_management'
  WHERE id = 'c4000000-0000-0000-0000-0000000000d1'
$$, '23514', NULL, 'a provider relationship cannot be turned into facility_management towards a provider');
SELECT lives_ok($$
  UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'c4000000-0000-0000-0000-0000000000d1'
$$, 'provider relationships keep free status changes');

-- =========================================================================
-- 3. CREACIÓN
-- =========================================================================
SET LOCAL ROLE authenticated;

SELECT pg_temp.as_user(NULL);
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1') $$,
  '42501', NULL, 'unauthenticated caller cannot create a relationship');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1') AS rel_a \gset
SELECT isnt(:'rel_a'::uuid, NULL::uuid, 'owner Client A creates Client A -> FM Alpha');
SELECT is(public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1'), :'rel_a'::uuid,
  'repeated call returns the same id (idempotent)');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000d1') $$,
  '22023', NULL, 'target must be a facility_manager organization');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000a1') $$,
  '22023', NULL, 'client and FM must be different organizations');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000b1', 'c2000000-0000-0000-0000-0000000000f1') $$,
  '42501', NULL, 'owner Client A cannot create a relationship for Client B (cross-tenant)');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002');
SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f2') AS rel_ab \gset
SELECT isnt(:'rel_ab'::uuid, NULL::uuid, 'admin Client A creates Client A -> FM Beta');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1') $$,
  '42501', NULL, 'manager Client A cannot create a relationship');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000004');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1') $$,
  '42501', NULL, 'owner Client B cannot create a relationship for Client A');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1') $$,
  '42501', NULL, 'FM owner cannot create the relationship by itself');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000a');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1') $$,
  '42501', NULL, 'outsider cannot create a relationship');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000b1', 'c2000000-0000-0000-0000-0000000000f1') AS rel_ba \gset
SELECT isnt(:'rel_ba'::uuid, NULL::uuid, 'platform_admin creates Client B -> FM Alpha without any membership in them');
SELECT throws_ok($$ SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-0000000000f1') $$,
  '22023', NULL, 'even platform_admin cannot use a non-client as source');

RESET ROLE;
SELECT is((SELECT status FROM public.organization_relationships WHERE id = :'rel_a'), 'pending'::public.organization_relationship_status,
  'a created relationship starts pending');
SELECT is((SELECT created_by FROM public.organization_relationships WHERE id = :'rel_a'), 'c1000000-0000-0000-0000-000000000001'::uuid,
  'created_by = auth.uid() of the creator');
SELECT is((SELECT count(*) FROM public.organization_relationships
  WHERE source_organization_id = 'c2000000-0000-0000-0000-0000000000a1' AND relationship_type = 'facility_management'), 2::bigint,
  'repeated creation did not duplicate rows (Client A has exactly 2 FM relationships)');

-- =========================================================================
-- 4. PERMISOS
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.view', 'assets.view', 'requests.view']::public.facility_management_permission[]) $$, :'rel_a'),
  'owner Client A configures permissions (with a duplicate in the array)');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 2::bigint,
  'duplicates in the array do not duplicate rows');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, NULL) $$, :'rel_a'), 'NULL is accepted');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 0::bigint, 'NULL empties the permission set');
SELECT throws_ok($$ SELECT public.set_facility_management_permissions('c4000000-0000-0000-0000-0000000000d1', ARRAY['assets.view']::public.facility_management_permission[]) $$,
  '22023', NULL, 'permissions cannot be configured on a provider relationship via RPC');
SELECT throws_ok($$ SELECT public.set_facility_management_permissions('c4000000-0000-0000-0000-00000000ffff', ARRAY['assets.view']::public.facility_management_permission[]) $$,
  'P0002', NULL, 'unknown relationship is reported as not found');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['work_orders.view', 'assets.view', 'requests.view']::public.facility_management_permission[]) $$, :'rel_a'),
  'admin Client A configures permissions');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003');
SELECT throws_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.manage']::public.facility_management_permission[]) $$, :'rel_a'),
  '42501', NULL, 'manager Client A cannot configure permissions');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.manage']::public.facility_management_permission[]) $$, :'rel_a'),
  '42501', NULL, 'FM owner cannot grant permissions to itself');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000004');
SELECT throws_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.manage']::public.facility_management_permission[]) $$, :'rel_a'),
  '42501', NULL, 'owner of another client cannot configure Client A permissions');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES (%L, 'assets.manage') $$, :'rel_a'),
  '42501', NULL, 'direct INSERT into facility_management_permissions as authenticated -> 42501');
SELECT throws_ok($$ DELETE FROM public.facility_management_permissions $$,
  '42501', NULL, 'direct DELETE from facility_management_permissions as authenticated -> 42501');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT throws_ok(format($$ UPDATE public.facility_management_permissions SET permission = 'assets.manage' WHERE relationship_id = %L $$, :'rel_a'),
  '42501', NULL, 'direct UPDATE of facility_management_permissions (even by the client owner) -> 42501');
SELECT throws_ok($$ INSERT INTO public.organization_relationships (source_organization_id, target_organization_id, relationship_type) VALUES ('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000d1', 'subcontracting') $$,
  '42501', NULL, 'direct INSERT into organization_relationships as authenticated -> 42501');
SELECT throws_ok(format($$ UPDATE public.organization_relationships SET status = 'active' WHERE id = %L $$, :'rel_a'),
  '42501', NULL, 'direct UPDATE of organization_relationships as authenticated -> 42501');
SELECT throws_ok(format($$ DELETE FROM public.organization_relationships WHERE id = %L $$, :'rel_a'),
  '42501', NULL, 'direct DELETE from organization_relationships as authenticated -> 42501');

RESET ROLE;
SELECT is((SELECT array_agg(permission ORDER BY permission) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'),
  ARRAY['assets.view', 'requests.view', 'work_orders.view']::public.facility_management_permission[],
  'the set was replaced atomically with exactly the requested permissions');
SELECT is((SELECT DISTINCT granted_by FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'),
  'c1000000-0000-0000-0000-000000000002'::uuid, 'granted_by = auth.uid() of the last configurer');

-- Lectura RLS de la tabla de permisos.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 3::bigint,
  'an active FM member (technician) can read the permissions delegated to its FM');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 3::bigint,
  'an active client member (manager) can read them too');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.facility_management_permissions), 0::bigint, 'owner Client B reads no Client A permissions');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000008');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 0::bigint, 'FM Beta owner reads no FM Alpha permissions');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000a');
SELECT is((SELECT count(*) FROM public.facility_management_permissions), 0::bigint, 'outsider reads no permissions');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 3::bigint, 'platform_admin reads all permissions');

-- =========================================================================
-- 5. HELPER has_facility_management_permission
-- =========================================================================
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false,
  'pending relationship => false (even with the permission granted)');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_a'), 'owner Client A activates the relationship (pending -> active)');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false,
  'active + permission + active FM member but NOT assigned => false');

-- El FM (su owner) decide qué personas atienden a Client A.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006', 'c3000000-0000-0000-0000-000000000007']::uuid[]) $$, :'rel_a'),
  'FM Alpha owner assigns its manager and technician to Client A');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), true,
  'active + permission + active ASSIGNED FM member (manager) => true');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.manage'), false,
  'active but permission not granted => false');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000b1', 'assets.view'), false,
  'another client (pending relationship, no permissions) => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'work_orders.view'), true,
  'assigned technician => true: the helper does not evaluate the internal role (each module will)');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000008');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'FM Beta member => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000a');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'outsider => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false,
  'the client owner itself has no delegated permission (it is not an FM member)');
SELECT pg_temp.as_user(NULL);
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'unauthenticated => false');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'suspended') $$, :'rel_a'), 'active -> suspended');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'suspended relationship => false');

-- La creación repetida sobre una relación suspendida no la reactiva.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT is(public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1'), :'rel_a'::uuid,
  'repeated creation on a suspended relationship returns the same id');
RESET ROLE;
SELECT is((SELECT status FROM public.organization_relationships WHERE id = :'rel_a'), 'suspended'::public.organization_relationship_status,
  'repeated creation does not silently reactivate a suspended relationship');
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_a'), 2::bigint,
  'suspended keeps the assigned members');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 3::bigint,
  'suspended keeps the permissions');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_a'), 'suspended -> active');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), true, 'reactivated relationship => true again');

RESET ROLE;
UPDATE public.organizations SET status = 'suspended' WHERE id = 'c2000000-0000-0000-0000-0000000000f1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'FM organization suspended => false');
RESET ROLE;
UPDATE public.organizations SET status = 'active' WHERE id = 'c2000000-0000-0000-0000-0000000000f1';
UPDATE public.organizations SET status = 'suspended' WHERE id = 'c2000000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'client organization suspended => false');
RESET ROLE;
UPDATE public.organizations SET status = 'active' WHERE id = 'c2000000-0000-0000-0000-0000000000a1';
UPDATE public.organization_members SET is_active = false WHERE id = 'c3000000-0000-0000-0000-000000000006';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'inactive FM membership => false');
RESET ROLE;
UPDATE public.organization_members SET is_active = true WHERE id = 'c3000000-0000-0000-0000-000000000006';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), true, 'everything restored => true (the assignment survived the membership deactivation and is effective again)');

-- =========================================================================
-- 6. LECTURA (RPCs)
-- =========================================================================
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT is((SELECT array_agg(facility_manager_organization_name) FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1')),
  ARRAY['FM Alpha', 'FM Beta'], 'owner Client A gets its relationships ordered by FM name');
SELECT is((SELECT permissions FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1') WHERE relationship_id = :'rel_a'),
  ARRAY['assets.view', 'requests.view', 'work_orders.view']::public.facility_management_permission[],
  'returned permissions are exactly the granted ones');
SELECT is((SELECT relationship_status FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1') WHERE relationship_id = :'rel_ab'),
  'pending'::public.organization_relationship_status, 'returned status is the real one');
SELECT is((SELECT permissions FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1') WHERE relationship_id = :'rel_ab'),
  '{}'::public.facility_management_permission[], 'a relationship without permissions returns an empty array');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1')), 2::bigint,
  'admin Client A gets its relationships');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'manager Client A cannot list delegations');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000004');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'Client B owner cannot query Client A delegations');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'FM owner cannot use the client-side listing');

-- Client B -> FM Beta (fixture) activo con permisos, por su propio owner.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.set_facility_management_permissions('c4000000-0000-0000-0000-0000000000b2', ARRAY['requests.view']::public.facility_management_permission[]) $$,
  'owner Client B configures its own FM Beta relationship');
SELECT lives_ok($$ SELECT public.set_facility_management_relationship_status('c4000000-0000-0000-0000-0000000000b2', 'active') $$,
  'owner Client B activates its own FM Beta relationship');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is((SELECT array_agg(relationship_id) FROM public.get_my_facility_management_clients()), ARRAY[:'rel_a'::uuid],
  'FM Alpha member only gets its ACTIVE administered clients (Client B is still pending)');
SELECT is((SELECT membership_role FROM public.get_my_facility_management_clients()), 'manager'::public.organization_member_role,
  'membership_role is the caller''s internal FM role');
SELECT is((SELECT permissions FROM public.get_my_facility_management_clients()),
  ARRAY['assets.view', 'requests.view', 'work_orders.view']::public.facility_management_permission[], 'FM sees exactly the granted permissions');
SELECT is((SELECT client_organization_name FROM public.get_my_facility_management_clients()), 'Client A', 'client name is resolved server-side');
SELECT is((SELECT count(*) FROM public.organization_relationships WHERE target_organization_id = 'c2000000-0000-0000-0000-0000000000f2'), 0::bigint,
  'FM Alpha never sees FM Beta relationships (direct SELECT under RLS)');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000008');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()), 0::bigint,
  'FM Beta owner is not assigned to Client B yet => Client B is not an operational client');
SELECT lives_ok($$ SELECT public.set_facility_management_members('c4000000-0000-0000-0000-0000000000b2', ARRAY['c3000000-0000-0000-0000-000000000008']::uuid[]) $$,
  'FM Beta owner assigns itself to Client B');
SELECT is((SELECT array_agg(relationship_id) FROM public.get_my_facility_management_clients()), ARRAY['c4000000-0000-0000-0000-0000000000b2'::uuid],
  'FM Beta owner only gets Client B (never FM Alpha relationships, never its pending Client A delegation)');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000a');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()), 0::bigint, 'outsider gets no clients');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()), 0::bigint, 'a client owner gets no FM clients');
SELECT pg_temp.as_user(NULL);
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()), 0::bigint, 'unauthenticated gets no clients');

-- =========================================================================
-- 7. STATUS (máquina de estados)
-- =========================================================================
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT audit_before FROM (SELECT count(*) AS audit_before FROM public.audit_logs WHERE record_id = :'rel_a'::uuid AND action = 'facility_management.status_changed') s \gset
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_a'), 'same status is an idempotent no-op');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE record_id = :'rel_a'::uuid AND action = 'facility_management.status_changed'), :audit_before::bigint,
  'a no-op status change writes no audit row');
SELECT throws_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'pending') $$, :'rel_a'),
  '55000', NULL, 'active -> pending is an invalid transition');
SELECT throws_ok($$ SELECT public.set_facility_management_relationship_status('c4000000-0000-0000-0000-0000000000d1', 'active') $$,
  '22023', NULL, 'the FM status RPC refuses provider relationships');
SELECT throws_ok($$ SELECT public.set_facility_management_relationship_status('c4000000-0000-0000-0000-00000000ffff', 'active') $$,
  'P0002', NULL, 'unknown relationship is reported as not found');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003');
SELECT throws_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'suspended') $$, :'rel_a'),
  '42501', NULL, 'manager Client A cannot change the status');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'ended') $$, :'rel_ab'),
  '42501', NULL, 'an FM owner cannot change a relationship status (not even one pointing to another FM)');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_ba'),
  '42501', NULL, 'FM Alpha owner cannot activate its own pending delegation');

-- Activación bloqueada con organizaciones suspendidas (platform_admin).
RESET ROLE;
UPDATE public.organizations SET status = 'suspended' WHERE id = 'c2000000-0000-0000-0000-0000000000f1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT throws_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_ba'),
  '55000', NULL, 'activation is rejected while the FM is suspended');
RESET ROLE;
UPDATE public.organizations SET status = 'active' WHERE id = 'c2000000-0000-0000-0000-0000000000f1';
UPDATE public.organizations SET status = 'suspended' WHERE id = 'c2000000-0000-0000-0000-0000000000b1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT throws_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_ba'),
  '55000', NULL, 'activation is rejected while the client is suspended');
RESET ROLE;
UPDATE public.organizations SET status = 'active' WHERE id = 'c2000000-0000-0000-0000-0000000000b1';

-- ended borra permisos; ended -> pending no los restaura.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'ended') $$, :'rel_a'), 'active -> ended');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'ended relationship => false');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()), 0::bigint, 'an ended relationship disappears from the FM listing');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 0::bigint, 'ended deletes every permission');
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_a'), 0::bigint, 'ended deletes every assigned member');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT throws_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_a'),
  '55000', NULL, 'ended -> active is an invalid transition');
SELECT throws_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.view']::public.facility_management_permission[]) $$, :'rel_a'),
  '55000', NULL, 'permissions cannot be configured on an ended relationship');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006']::uuid[]) $$, :'rel_a'),
  '55000', NULL, 'members cannot be assigned to an ended relationship');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
-- Desde 9B la RPC legacy de homologación ya no administra facility_management.
SELECT throws_ok($$ SELECT public.set_provider_relationship_status('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000f1', 'active') $$,
  '22023', NULL, 'the legacy homologation RPC no longer manages facility_management relationships');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'pending') $$, :'rel_a'), 'ended -> pending');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 0::bigint, 'ended -> pending does not restore permissions');
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_a'), 0::bigint, 'ended -> pending does not restore assigned members');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['reports.view']::public.facility_management_permission[]) $$, :'rel_a'),
  'a pending (reopened) relationship can be configured again');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'suspended') $$, :'rel_a'), 'pending -> suspended');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['reports.view', 'quotes.view']::public.facility_management_permission[]) $$, :'rel_a'),
  'a suspended relationship can be configured');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'ended') $$, :'rel_a'), 'suspended -> ended');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'pending') $$, :'rel_a'), 'ended -> pending (again)');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'ended') $$, :'rel_a'), 'pending -> ended');

-- Un ended escrito directamente (fuera de las RPCs) también limpia permisos.
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.view', 'quotes.approve']::public.facility_management_permission[]) $$, :'rel_ba'),
  'platform_admin configures Client B -> FM Alpha without any membership in them');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_ba'),
  'platform_admin activates Client B -> FM Alpha');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006']::uuid[]) $$, :'rel_ba'),
  'platform_admin assigns FM Alpha manager to Client B without any membership in them');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000b1', 'quotes.approve'), true,
  'FM Alpha now holds quotes.approve on Client B');
RESET ROLE;
SELECT throws_ok(format($$ UPDATE public.organization_relationships SET status = 'pending' WHERE id = %L $$, :'rel_ba'),
  '55000', NULL, 'the trigger enforces the state machine even for direct writes (active -> pending)');
SELECT lives_ok(format($$ UPDATE public.organization_relationships SET status = 'ended' WHERE id = %L $$, :'rel_ba'),
  'a direct (service-level) active -> ended is allowed');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_ba'), 0::bigint,
  'a direct ended also deletes the permissions (trigger)');
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ba'), 0::bigint,
  'a direct ended also deletes the assigned members (trigger)');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES (%L, 'assets.view') $$, :'rel_ba'),
  '55000', NULL, 'even a direct insert cannot attach permissions to an ended relationship');

-- =========================================================================
-- 8. PLATFORM ADMIN — nunca necesita membresía en cliente/FM
-- =========================================================================
SELECT ok(NOT EXISTS (
  SELECT 1 FROM public.organization_members
  WHERE user_id = 'c1000000-0000-0000-0000-000000000009'
    AND organization_id IN ('c2000000-0000-0000-0000-0000000000a1', 'c2000000-0000-0000-0000-0000000000b1',
                            'c2000000-0000-0000-0000-0000000000f1', 'c2000000-0000-0000-0000-0000000000f2')
), 'platform_admin has no membership in any client/FM used above');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT is((SELECT count(*) FROM public.get_facility_management_relationships('c2000000-0000-0000-0000-0000000000a1')), 2::bigint,
  'platform_admin lists Client A delegations');
RESET ROLE;

-- =========================================================================
-- 9. AUDITORÍA
-- =========================================================================
SELECT is((SELECT count(*) FROM public.audit_logs WHERE record_id = :'rel_a'::uuid AND action = 'facility_management.relationship_created'), 1::bigint,
  'creation audited exactly once (repeated calls are not re-audited)');
SELECT is((SELECT actor_user_id FROM public.audit_logs WHERE record_id = :'rel_ba'::uuid AND action = 'facility_management.relationship_created'),
  'c1000000-0000-0000-0000-000000000009'::uuid, 'actor_user_id = auth.uid() (platform_admin)');
SELECT ok(EXISTS (
  SELECT 1 FROM public.audit_logs
  WHERE record_id = :'rel_a'::uuid AND action = 'facility_management.permissions_replaced'
    AND old_data -> 'permissions' = '["assets.view", "requests.view"]'::jsonb
    AND new_data -> 'permissions' = '[]'::jsonb
), 'permission replacement audits previous and new permissions');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE record_id = :'rel_a'::uuid AND action = 'facility_management.permissions_replaced'), 5::bigint,
  'every permission replacement on Client A -> FM Alpha is audited');
SELECT ok(EXISTS (
  SELECT 1 FROM public.audit_logs
  WHERE record_id = :'rel_a'::uuid AND action = 'facility_management.status_changed'
    AND old_data ->> 'status' = 'active' AND new_data ->> 'status' = 'ended'
    AND new_data -> 'removed_permissions' = '["assets.view", "requests.view", "work_orders.view"]'::jsonb
), 'status change audits old/new status and the permissions removed by ended');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE record_id = :'rel_a'::uuid AND action = 'facility_management.status_changed'), 9::bigint,
  'every real status change on Client A -> FM Alpha is audited');
SELECT is((SELECT count(*) FROM public.audit_logs a
  JOIN public.organization_relationships rel ON rel.id = a.record_id
  WHERE a.action LIKE 'facility_management.%' AND a.organization_id IS DISTINCT FROM rel.source_organization_id), 0::bigint,
  'every facility_management audit row belongs to the CLIENT (source) organization');
SELECT ok((SELECT count(*) FROM public.audit_logs WHERE action LIKE 'facility_management.%') > 0, 'facility_management audit rows exist');

-- =========================================================================
-- 10. SEGURIDAD de funciones
-- =========================================================================
SELECT is((SELECT count(*) FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN ('has_facility_management_permission', 'create_facility_management_relationship', 'set_facility_management_permissions',
                      'set_facility_management_relationship_status', 'get_facility_management_relationships', 'get_my_facility_management_clients',
                      'set_facility_management_members', 'get_facility_management_members', 'get_my_facility_management_portfolio')
    AND pg_get_function_arguments(p.oid) ILIKE '%user%'), 0::bigint,
  'no RPC accepts a user_id input parameter');
SELECT is((SELECT pronargs FROM pg_proc WHERE oid = 'public.has_facility_management_permission(uuid, public.facility_management_permission)'::regprocedure), 2::smallint,
  'has_facility_management_permission takes only (client, permission)');
SELECT ok((SELECT prosrc FROM pg_proc WHERE oid = 'public.has_facility_management_permission(uuid, public.facility_management_permission)'::regprocedure) LIKE '%auth.uid()%',
  'has_facility_management_permission resolves the caller from auth.uid()');
SELECT is((SELECT pronargs FROM pg_proc WHERE oid = 'public.get_my_facility_management_clients()'::regprocedure), 0::smallint,
  'get_my_facility_management_clients takes no organization/user parameter');
SELECT is((SELECT count(*) FROM pg_proc p
  WHERE p.oid IN (
    'public.has_facility_management_permission(uuid, public.facility_management_permission)'::regprocedure,
    'public.create_facility_management_relationship(uuid, uuid)'::regprocedure,
    'public.set_facility_management_permissions(uuid, public.facility_management_permission[])'::regprocedure,
    'public.set_facility_management_relationship_status(uuid, public.organization_relationship_status)'::regprocedure,
    'public.get_facility_management_relationships(uuid)'::regprocedure,
    'public.get_my_facility_management_clients()'::regprocedure,
    'public.set_facility_management_members(uuid, uuid[])'::regprocedure,
    'public.get_facility_management_members(uuid)'::regprocedure,
    'public.get_my_facility_management_portfolio()'::regprocedure)
    AND p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')), 9::bigint,
  'the 9 RPCs are SECURITY DEFINER with a pinned search_path');
SELECT is((SELECT count(*) FROM pg_proc p
  WHERE p.oid IN (
    'public.check_facility_management_relationship()'::regprocedure,
    'public.clear_ended_facility_management_delegation()'::regprocedure,
    'public.check_facility_management_permission_relationship()'::regprocedure,
    'public.check_facility_management_relationship_member()'::regprocedure)
    AND NOT p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')), 4::bigint,
  'the 4 trigger functions pin search_path and are not SECURITY DEFINER');

SELECT ok(has_function_privilege('authenticated', 'public.has_facility_management_permission(uuid, public.facility_management_permission)', 'EXECUTE'), 'authenticated EXECUTE has_facility_management_permission');
SELECT ok(has_function_privilege('authenticated', 'public.create_facility_management_relationship(uuid, uuid)', 'EXECUTE'), 'authenticated EXECUTE create_facility_management_relationship');
SELECT ok(has_function_privilege('authenticated', 'public.set_facility_management_permissions(uuid, public.facility_management_permission[])', 'EXECUTE'), 'authenticated EXECUTE set_facility_management_permissions');
SELECT ok(has_function_privilege('authenticated', 'public.set_facility_management_relationship_status(uuid, public.organization_relationship_status)', 'EXECUTE'), 'authenticated EXECUTE set_facility_management_relationship_status');
SELECT ok(has_function_privilege('authenticated', 'public.get_facility_management_relationships(uuid)', 'EXECUTE'), 'authenticated EXECUTE get_facility_management_relationships');
SELECT ok(has_function_privilege('authenticated', 'public.get_my_facility_management_clients()', 'EXECUTE'), 'authenticated EXECUTE get_my_facility_management_clients');
SELECT ok(has_function_privilege('authenticated', 'public.set_facility_management_members(uuid, uuid[])', 'EXECUTE'), 'authenticated EXECUTE set_facility_management_members');
SELECT ok(has_function_privilege('authenticated', 'public.get_facility_management_members(uuid)', 'EXECUTE'), 'authenticated EXECUTE get_facility_management_members');
SELECT ok(has_function_privilege('authenticated', 'public.get_my_facility_management_portfolio()', 'EXECUTE'), 'authenticated EXECUTE get_my_facility_management_portfolio');
SELECT is((SELECT pronargs FROM pg_proc WHERE oid = 'public.get_my_facility_management_portfolio()'::regprocedure), 0::smallint,
  'get_my_facility_management_portfolio takes no organization/user parameter');

SELECT ok(NOT has_function_privilege('anon', 'public.has_facility_management_permission(uuid, public.facility_management_permission)', 'EXECUTE'), 'anon: no EXECUTE has_facility_management_permission');
SELECT ok(NOT has_function_privilege('anon', 'public.create_facility_management_relationship(uuid, uuid)', 'EXECUTE'), 'anon: no EXECUTE create_facility_management_relationship');
SELECT ok(NOT has_function_privilege('anon', 'public.set_facility_management_permissions(uuid, public.facility_management_permission[])', 'EXECUTE'), 'anon: no EXECUTE set_facility_management_permissions');
SELECT ok(NOT has_function_privilege('anon', 'public.set_facility_management_relationship_status(uuid, public.organization_relationship_status)', 'EXECUTE'), 'anon: no EXECUTE set_facility_management_relationship_status');
SELECT ok(NOT has_function_privilege('anon', 'public.get_facility_management_relationships(uuid)', 'EXECUTE'), 'anon: no EXECUTE get_facility_management_relationships');
SELECT ok(NOT has_function_privilege('anon', 'public.get_my_facility_management_clients()', 'EXECUTE'), 'anon: no EXECUTE get_my_facility_management_clients');
SELECT ok(NOT has_function_privilege('anon', 'public.set_facility_management_members(uuid, uuid[])', 'EXECUTE'), 'anon: no EXECUTE set_facility_management_members');
SELECT ok(NOT has_function_privilege('anon', 'public.get_facility_management_members(uuid)', 'EXECUTE'), 'anon: no EXECUTE get_facility_management_members');
SELECT ok(NOT has_function_privilege('anon', 'public.get_my_facility_management_portfolio()', 'EXECUTE'), 'anon: no EXECUTE get_my_facility_management_portfolio');

SELECT ok(NOT has_function_privilege('authenticated', 'public.check_facility_management_relationship()', 'EXECUTE'), 'authenticated: no EXECUTE on the relationship consistency trigger function');
SELECT ok(NOT has_function_privilege('authenticated', 'public.clear_ended_facility_management_delegation()', 'EXECUTE'), 'authenticated: no EXECUTE on the ended-cleanup trigger function');
SELECT ok(NOT has_function_privilege('authenticated', 'public.check_facility_management_permission_relationship()', 'EXECUTE'), 'authenticated: no EXECUTE on the permission consistency trigger function');

SELECT is((SELECT count(*) FROM pg_proc p, aclexplode(p.proacl) a
  WHERE a.grantee = 0 AND p.oid IN (
    'public.has_facility_management_permission(uuid, public.facility_management_permission)'::regprocedure,
    'public.create_facility_management_relationship(uuid, uuid)'::regprocedure,
    'public.set_facility_management_permissions(uuid, public.facility_management_permission[])'::regprocedure,
    'public.set_facility_management_relationship_status(uuid, public.organization_relationship_status)'::regprocedure,
    'public.get_facility_management_relationships(uuid)'::regprocedure,
    'public.get_my_facility_management_clients()'::regprocedure,
    'public.check_facility_management_relationship()'::regprocedure,
    'public.clear_ended_facility_management_delegation()'::regprocedure,
    'public.check_facility_management_permission_relationship()'::regprocedure,
    'public.check_facility_management_relationship_member()'::regprocedure,
    'public.set_facility_management_members(uuid, uuid[])'::regprocedure,
    'public.get_facility_management_members(uuid)'::regprocedure,
    'public.get_my_facility_management_portfolio()'::regprocedure)), 0::bigint,
  'PUBLIC has no EXECUTE on any function of this migration');
SELECT ok((SELECT proacl IS NOT NULL FROM pg_proc WHERE oid = 'public.check_facility_management_relationship()'::regprocedure),
  'trigger functions carry an explicit ACL (not the implicit PUBLIC default)');

SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT * FROM public.facility_management_permissions $$, '42501', NULL, 'anon cannot read facility_management_permissions');
SELECT throws_ok($$ SELECT * FROM public.organization_relationships $$, '42501', NULL, 'anon cannot read organization_relationships');
SELECT throws_ok($$ SELECT public.get_my_facility_management_clients() $$, '42501', NULL, 'anon cannot call get_my_facility_management_clients');
RESET ROLE;

-- =========================================================================
-- 11. TERCERA CAPA — miembros concretos del FM asignados a la relación
-- =========================================================================
-- 11.1 Estructura
SELECT has_table('public', 'facility_management_relationship_members', 'table facility_management_relationship_members exists');
SELECT columns_are('public', 'facility_management_relationship_members', ARRAY['relationship_id', 'organization_member_id', 'assigned_by', 'assigned_at'],
  'assignments do not duplicate client/FM/user_id/role');
SELECT col_is_pk('public', 'facility_management_relationship_members', ARRAY['relationship_id', 'organization_member_id'],
  'PK is (relationship_id, organization_member_id)');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint c
  WHERE c.conrelid = 'public.facility_management_relationship_members'::regclass AND c.contype = 'f'
    AND c.confrelid = 'public.organization_relationships'::regclass AND c.confdeltype = 'c'
), 'relationship_id FK -> organization_relationships ON DELETE CASCADE');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint c
  WHERE c.conrelid = 'public.facility_management_relationship_members'::regclass AND c.contype = 'f'
    AND c.confrelid = 'public.organization_members'::regclass AND c.confdeltype = 'c'
), 'organization_member_id FK -> organization_members ON DELETE CASCADE');
SELECT ok(EXISTS (
  SELECT 1 FROM pg_constraint c
  WHERE c.conrelid = 'public.facility_management_relationship_members'::regclass AND c.contype = 'f'
    AND c.confrelid = 'auth.users'::regclass AND c.confdeltype = 'n'
), 'assigned_by FK -> auth.users ON DELETE SET NULL');
SELECT has_index('public', 'facility_management_relationship_members', 'idx_facility_management_relationship_members_member_relationship',
  ARRAY['organization_member_id', 'relationship_id'], 'index on (organization_member_id, relationship_id)');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.facility_management_relationship_members'::regclass), 'RLS enabled on assignments');
SELECT is((SELECT count(*) FROM pg_policy WHERE polrelid = 'public.facility_management_relationship_members'::regclass), 0::bigint,
  'no policies on assignments: the read surface is RPC-only');
SELECT ok(NOT has_table_privilege('authenticated', 'public.facility_management_relationship_members', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
  'authenticated: no privileges at all on assignments (not even SELECT)');
SELECT ok(NOT has_table_privilege('anon', 'public.facility_management_relationship_members', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
  'anon: no privileges on assignments');
SELECT ok(has_table_privilege('service_role', 'public.facility_management_relationship_members', 'SELECT')
  AND has_table_privilege('service_role', 'public.facility_management_relationship_members', 'INSERT')
  AND has_table_privilege('service_role', 'public.facility_management_relationship_members', 'UPDATE')
  AND has_table_privilege('service_role', 'public.facility_management_relationship_members', 'DELETE'),
  'service_role: explicit DML on assignments');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
  WHERE c.oid = 'public.facility_management_relationship_members'::regclass AND a.grantee = 0
), 'PUBLIC has no privileges on assignments');
SELECT ok(NOT has_function_privilege('authenticated', 'public.check_facility_management_relationship_member()', 'EXECUTE'),
  'authenticated: no EXECUTE on the assignment consistency trigger function');

-- 11.2 Client C -> FM Alpha (nueva relación para esta sección)
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000e');
SELECT public.create_facility_management_relationship('c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000f1') AS rel_ca \gset
RESET ROLE;

-- 11.3 Consistencia (trigger, escritura directa como postgres)
SELECT lives_ok(format($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES (%L, 'c3000000-0000-0000-0000-000000000006') $$, :'rel_ca'),
  'an active member of the target FM can be assigned');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES (%L, 'c3000000-0000-0000-0000-000000000008') $$, :'rel_ca'),
  '23514', NULL, 'a member of another FM is rejected');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES (%L, 'c3000000-0000-0000-0000-00000000000e') $$, :'rel_ca'),
  '23514', NULL, 'a member of the client is rejected (client people never join the FM team)');
SELECT throws_ok($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES ('c4000000-0000-0000-0000-0000000000d1', 'c3000000-0000-0000-0000-000000000001') $$,
  '23514', NULL, 'a provider relationship cannot hold assignments');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES (%L, 'c3000000-0000-0000-0000-000000000006') $$, :'rel_ba'),
  '23514', NULL, 'an ended relationship cannot hold assignments');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES (%L, 'c3000000-0000-0000-0000-00000000000d') $$, :'rel_ca'),
  '23514', NULL, 'an inactive membership is rejected at assignment time');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES (%L, 'c3000000-0000-0000-0000-00000000ffff') $$, :'rel_ca'),
  '23514', NULL, 'an unknown membership is rejected');
SELECT throws_ok(format($$ UPDATE public.facility_management_relationship_members SET organization_member_id = 'c3000000-0000-0000-0000-000000000008' WHERE relationship_id = %L $$, :'rel_ca'),
  '23514', NULL, 'an assignment cannot be re-pointed to another FM''s member');
DELETE FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca';

-- 11.4 set_facility_management_members
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006']::uuid[]) $$, :'rel_ca'),
  'FM owner assigns members');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000b');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006', 'c3000000-0000-0000-0000-000000000007', 'c3000000-0000-0000-0000-000000000006']::uuid[]) $$, :'rel_ca'),
  'FM admin assigns members (with a duplicated id)');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca'), 2::bigint,
  'duplicated ids do not duplicate assignments');
SELECT is((SELECT DISTINCT assigned_by FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca'),
  'c1000000-0000-0000-0000-00000000000b'::uuid, 'assigned_by = auth.uid() of the FM admin');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006']::uuid[]) $$, :'rel_ca'),
  '42501', NULL, 'FM manager (even assigned) cannot manage assignments');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000007']::uuid[]) $$, :'rel_ca'),
  '42501', NULL, 'FM technician (even assigned) cannot manage assignments');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000e');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006']::uuid[]) $$, :'rel_ca'),
  '42501', NULL, 'client owner cannot manage the FM roster');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000008']::uuid[]) $$, :'rel_ab'),
  '42501', NULL, 'client admin cannot manage the FM roster');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000008');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000008']::uuid[]) $$, :'rel_ca'),
  '42501', NULL, 'owner of another FM cannot manage this roster');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000a');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, NULL) $$, :'rel_ca'),
  '42501', NULL, 'outsider cannot manage assignments');
SELECT pg_temp.as_user(NULL);
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, NULL) $$, :'rel_ca'),
  '42501', NULL, 'unauthenticated caller cannot manage assignments');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000008']::uuid[]) $$, :'rel_ca'),
  '22023', NULL, 'the RPC rejects members of another FM');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-00000000000d']::uuid[]) $$, :'rel_ca'),
  '22023', NULL, 'the RPC rejects inactive members');
SELECT throws_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-00000000000e']::uuid[]) $$, :'rel_ca'),
  '22023', NULL, 'the RPC rejects client members');
SELECT throws_ok($$ SELECT public.set_facility_management_members('c4000000-0000-0000-0000-00000000ffff', NULL) $$,
  'P0002', NULL, 'unknown relationship is reported as not found');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT throws_ok($$ SELECT public.set_facility_management_members('c4000000-0000-0000-0000-0000000000d1', NULL) $$,
  '22023', NULL, 'the RPC refuses provider relationships');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000007']::uuid[]) $$, :'rel_ca'),
  'platform_admin can manage assignments');
RESET ROLE;
SELECT is((SELECT array_agg(organization_member_id) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca'),
  ARRAY['c3000000-0000-0000-0000-000000000007'::uuid], 'replacing the set removes the previous assignments');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, NULL) $$, :'rel_ca'), 'NULL is accepted');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca'), 0::bigint, 'NULL empties the assignments');
SELECT ok(EXISTS (
  SELECT 1 FROM public.audit_logs
  WHERE record_id = :'rel_ca'::uuid AND action = 'facility_management.members_replaced'
    AND table_name = 'facility_management_relationship_members'
    AND organization_id = 'c2000000-0000-0000-0000-0000000000c1'
    AND actor_user_id = 'c1000000-0000-0000-0000-00000000000b'
    AND old_data -> 'organization_member_ids' = '["c3000000-0000-0000-0000-000000000006"]'::jsonb
    AND new_data -> 'organization_member_ids' = '["c3000000-0000-0000-0000-000000000006", "c3000000-0000-0000-0000-000000000007"]'::jsonb
), 'assignment replacement is audited with old/new membership ids, actor and organization_id = client');
SELECT is((SELECT count(*) FROM public.audit_logs WHERE record_id = :'rel_ca'::uuid AND action = 'facility_management.members_replaced'), 4::bigint,
  'every successful replacement is audited (rejected calls are not)');

-- 11.5 Puesta en marcha operativa: Client C activo; Client A reabierto.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000e');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.view', 'work_orders.view']::public.facility_management_permission[]) $$, :'rel_ca'),
  'Client C grants permissions to FM Alpha');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_ca'), 'Client C activates FM Alpha');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006']::uuid[]) $$, :'rel_ca'),
  'FM Alpha assigns only its manager to Client C');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'pending') $$, :'rel_a'), 'Client A reopens FM Alpha (ended -> pending)');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.view']::public.facility_management_permission[]) $$, :'rel_a'),
  'Client A grants assets.view again');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_a'), 'Client A reactivates FM Alpha');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000b');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006', 'c3000000-0000-0000-0000-000000000007']::uuid[]) $$, :'rel_a'),
  'FM Alpha admin assigns manager + technician to Client A');

-- 11.6 get_facility_management_members
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.get_facility_management_members(:'rel_a')), 2::bigint, 'client owner sees the assigned team');
SELECT is((SELECT array_agg(membership_role) FROM public.get_facility_management_members(:'rel_a')),
  ARRAY['manager', 'technician']::public.organization_member_role[], 'team is ordered by internal role');
SELECT is((SELECT array_agg(user_id ORDER BY user_id) FROM public.get_facility_management_members(:'rel_a')),
  ARRAY['c1000000-0000-0000-0000-000000000006', 'c1000000-0000-0000-0000-000000000007']::uuid[],
  'only the people assigned from the target FM are returned');
SELECT is((SELECT member_email FROM public.get_facility_management_members(:'rel_a') WHERE organization_member_id = 'c3000000-0000-0000-0000-000000000006'),
  'manager-fm-a@fm.test', 'member_email is returned');
SELECT is((SELECT member_name FROM public.get_facility_management_members(:'rel_a') WHERE organization_member_id = 'c3000000-0000-0000-0000-000000000006'),
  'manager-fm-a', 'member_name falls back to the email prefix (same rule as the other RPCs)');
SELECT is((SELECT member_name FROM public.get_facility_management_members(:'rel_a') WHERE organization_member_id = 'c3000000-0000-0000-0000-000000000007'),
  'Carlos Tecnico', 'member_name uses user_metadata.name when present');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.get_facility_management_members(:'rel_a') m WHERE m::text LIKE '%do-not-leak%'),
  'raw auth metadata is never exposed');
SELECT ok(pg_get_function_result('public.get_facility_management_members(uuid)'::regprocedure) NOT ILIKE '%meta%',
  'the result type has no metadata column');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.get_facility_management_members(:'rel_a')), 2::bigint, 'client admin sees the assigned team');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT is((SELECT count(*) FROM public.get_facility_management_members(:'rel_a')), 2::bigint, 'FM owner sees the assigned team');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000b');
SELECT is((SELECT count(*) FROM public.get_facility_management_members(:'rel_a')), 2::bigint, 'FM admin sees the assigned team');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT is((SELECT count(*) FROM public.get_facility_management_members(:'rel_a')), 2::bigint, 'platform_admin sees the assigned team');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_members('c4000000-0000-0000-0000-0000000000d1') $$,
  '22023', NULL, 'get_facility_management_members refuses provider relationships');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_members('c4000000-0000-0000-0000-00000000ffff') $$,
  'P0002', NULL, 'get_facility_management_members reports unknown relationships');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000004');
SELECT throws_ok(format($$ SELECT * FROM public.get_facility_management_members(%L) $$, :'rel_a'), '42501', NULL, 'another client cannot see the team');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000008');
SELECT throws_ok(format($$ SELECT * FROM public.get_facility_management_members(%L) $$, :'rel_a'), '42501', NULL, 'another FM cannot see the team');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT throws_ok(format($$ SELECT * FROM public.get_facility_management_members(%L) $$, :'rel_a'), '42501', NULL, 'FM manager cannot see the team listing');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007');
SELECT throws_ok(format($$ SELECT * FROM public.get_facility_management_members(%L) $$, :'rel_a'), '42501', NULL, 'FM technician cannot see the team listing');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000003');
SELECT throws_ok(format($$ SELECT * FROM public.get_facility_management_members(%L) $$, :'rel_a'), '42501', NULL, 'client manager cannot see the team listing');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000a');
SELECT throws_ok(format($$ SELECT * FROM public.get_facility_management_members(%L) $$, :'rel_a'), '42501', NULL, 'outsider cannot see the team listing');

-- 11.7 Helper con asignación
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), true, 'assigned active manager => true');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000c1', 'work_orders.view'), true,
  'a person assigned to two relationships => true on the second client too');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), true,
  'assigned technician => true (internal role is not evaluated by the helper)');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000c1', 'work_orders.view'), false,
  'technician assigned only to Client A => false on Client C');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000c');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'unassigned member of the same FM => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'unassigned FM owner => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000b');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'unassigned FM admin => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false,
  'platform_admin is never an operational delegate => false');

RESET ROLE;
UPDATE public.organization_members SET is_active = false WHERE id = 'c3000000-0000-0000-0000-000000000006';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false,
  'membership deactivated after assignment => false immediately');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT is((SELECT membership_is_active FROM public.get_facility_management_members(:'rel_a') WHERE organization_member_id = 'c3000000-0000-0000-0000-000000000006'), false,
  'the assignment row is kept and reported as inactive');
RESET ROLE;
UPDATE public.organization_members SET is_active = true WHERE id = 'c3000000-0000-0000-0000-000000000006';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), true,
  'membership reactivated => the assignment is effective again');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, NULL) $$, :'rel_a'), 'Client A revokes every permission');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'permission removed => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_permissions(%L, ARRAY['assets.view']::public.facility_management_permission[]) $$, :'rel_a'),
  'Client A restores assets.view');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000007']::uuid[]) $$, :'rel_a'),
  'FM owner unassigns its manager from Client A');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'assignment removed => false');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT lives_ok(format($$ SELECT public.set_facility_management_members(%L, ARRAY['c3000000-0000-0000-0000-000000000006', 'c3000000-0000-0000-0000-000000000007']::uuid[]) $$, :'rel_a'),
  'FM owner reassigns its manager');

SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'suspended') $$, :'rel_a'), 'Client A suspends FM Alpha');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), false, 'suspended => false for an assigned member');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_a'), 2::bigint, 'suspended keeps the assignments');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_a'), 1::bigint, 'suspended keeps the permissions');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000001');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_a'), 'Client A reactivates FM Alpha');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000a1', 'assets.view'), true,
  'reactivated => true again (membership still active, assignment kept)');

-- 11.8 get_my_facility_management_clients = clientes OPERATIVOS del usuario
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is((SELECT array_agg(client_organization_name ORDER BY client_organization_name) FROM public.get_my_facility_management_clients()),
  ARRAY['Client A', 'Client C'], 'a person assigned to two relationships sees both clients');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007');
SELECT is((SELECT array_agg(client_organization_name) FROM public.get_my_facility_management_clients()),
  ARRAY['Client A'], 'a person assigned only to Client A does not see Client C');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000c');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()), 0::bigint, 'an unassigned member of the same FM sees no client');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()), 0::bigint, 'an unassigned FM owner sees no operational client');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000e');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'suspended') $$, :'rel_ca'), 'Client C suspends FM Alpha');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is((SELECT array_agg(client_organization_name) FROM public.get_my_facility_management_clients()),
  ARRAY['Client A'], 'suspended relationships are not operational clients');

-- 11.9 Cartera administrativa del FM
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT is((SELECT array_agg(client_organization_name ORDER BY client_organization_name) FROM public.get_my_facility_management_portfolio()),
  ARRAY['Client A', 'Client B', 'Client C'], 'FM owner sees the whole portfolio although it is not assigned anywhere');
SELECT is((SELECT array_agg(relationship_status::text ORDER BY client_organization_name) FROM public.get_my_facility_management_portfolio()),
  ARRAY['active', 'ended', 'suspended'], 'the portfolio includes active, ended and suspended relationships');
SELECT is((SELECT assigned_member_count FROM public.get_my_facility_management_portfolio() WHERE relationship_id = :'rel_a'), 2::bigint,
  'assigned_member_count is correct');
SELECT is((SELECT permissions FROM public.get_my_facility_management_portfolio() WHERE relationship_id = :'rel_ca'),
  ARRAY['assets.view', 'work_orders.view']::public.facility_management_permission[], 'portfolio permissions are the granted ones');
SELECT is((SELECT client_organization_status FROM public.get_my_facility_management_portfolio() WHERE relationship_id = :'rel_a'), 'active',
  'client_organization_status is returned');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000c1', 'assets.view'), false,
  'seeing a client in the portfolio grants no operational access');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000b');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_portfolio()), 3::bigint, 'FM admin sees the portfolio');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000008');
SELECT is((SELECT array_agg(relationship_status::text ORDER BY client_organization_name) FROM public.get_my_facility_management_portfolio()),
  ARRAY['pending', 'active'], 'FM Beta portfolio shows its pending and active relationships, never FM Alpha''s');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_portfolio()), 0::bigint, 'FM manager gets no portfolio');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000007');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_portfolio()), 0::bigint, 'FM technician gets no portfolio');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000009');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_portfolio()), 0::bigint,
  'platform_admin gets no global portfolio (administers by relationship_id instead)');
SELECT pg_temp.as_user('c1000000-0000-0000-0000-00000000000e');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_ca'), 'Client C reactivates FM Alpha');

-- 11.10 Escritor de nivel servicio (fuera de las RPCs 9A) sobre la relación
-- FM de Client C. Desde 9B la RPC legacy set_provider_relationship_status ya
-- no administra facility_management (ver facility_manager_ui_integration.test.sql);
-- los triggers siguen aplicando las mismas garantías a cualquier escritor.
RESET ROLE;
SELECT lives_ok(format($$ UPDATE public.organization_relationships SET status = 'suspended' WHERE id = %L $$, :'rel_ca'),
  'a service-level writer still moves within valid transitions (active -> suspended)');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_ca'), 2::bigint, 'a status change neither grants nor removes permissions');
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca'), 1::bigint, 'a status change neither assigns nor removes members');
SELECT lives_ok(format($$ UPDATE public.organization_relationships SET status = 'ended' WHERE id = %L $$, :'rel_ca'),
  'a service-level writer can end the relationship');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_ca'), 0::bigint, 'ended by any writer clears permissions');
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca'), 0::bigint, 'ended by any writer clears assignments');
SELECT lives_ok(format($$ UPDATE public.organization_relationships SET status = 'pending' WHERE id = %L $$, :'rel_ca'),
  'a service-level writer reopens ended -> pending');
SELECT lives_ok(format($$ UPDATE public.organization_relationships SET status = 'active' WHERE id = %L $$, :'rel_ca'),
  'a service-level writer activates the reopened relationship');
SELECT is((SELECT count(*) FROM public.facility_management_permissions WHERE relationship_id = :'rel_ca'), 0::bigint, 'reopening restores no permissions');
SELECT is((SELECT count(*) FROM public.facility_management_relationship_members WHERE relationship_id = :'rel_ca'), 0::bigint, 'reopening restores no assignments');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_permission('c2000000-0000-0000-0000-0000000000c1', 'work_orders.view'), false,
  'a relationship reopened and activated outside the RPCs grants nothing until reconfigured');
SELECT is((SELECT array_agg(client_organization_name) FROM public.get_my_facility_management_clients()),
  ARRAY['Client A'], 'and it is not an operational client of the former assignee');
-- Regresión del trigger con INSERT ... ON CONFLICT DO UPDATE (status
-- no-pending sobre una fila FM existente): debe aplicar la máquina de
-- estados, no la regla "nace en pending".
RESET ROLE;
SELECT lives_ok($$ INSERT INTO public.organization_relationships (source_organization_id, target_organization_id, relationship_type, status)
  VALUES ('c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000f2', 'facility_management', 'pending') $$,
  'an upsert-style writer creates a pending FM relationship');
SELECT lives_ok($$ INSERT INTO public.organization_relationships (source_organization_id, target_organization_id, relationship_type, status)
  VALUES ('c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-0000000000f2', 'facility_management', 'active')
  ON CONFLICT (source_organization_id, target_organization_id, relationship_type) DO UPDATE SET status = EXCLUDED.status $$,
  'pending -> active through INSERT ... ON CONFLICT DO UPDATE is governed by the state machine, not the born-pending rule');
SET LOCAL ROLE authenticated;

-- 11.11 Escritura/lectura directa
SELECT pg_temp.as_user('c1000000-0000-0000-0000-000000000005');
SELECT throws_ok(format($$ INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES (%L, 'c3000000-0000-0000-0000-00000000000c') $$, :'rel_a'),
  '42501', NULL, 'direct INSERT into assignments as authenticated (even FM owner) -> 42501');
SELECT throws_ok(format($$ UPDATE public.facility_management_relationship_members SET assigned_at = now() WHERE relationship_id = %L $$, :'rel_a'),
  '42501', NULL, 'direct UPDATE of assignments -> 42501');
SELECT throws_ok(format($$ DELETE FROM public.facility_management_relationship_members WHERE relationship_id = %L $$, :'rel_a'),
  '42501', NULL, 'direct DELETE from assignments -> 42501');
SELECT throws_ok($$ SELECT * FROM public.facility_management_relationship_members $$,
  '42501', NULL, 'direct SELECT of assignments -> 42501 (read surface is RPC-only)');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT * FROM public.facility_management_relationship_members $$, '42501', NULL, 'anon cannot read assignments');
SELECT throws_ok($$ SELECT * FROM public.get_my_facility_management_portfolio() $$, '42501', NULL, 'anon cannot call the portfolio RPC');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_members('c4000000-0000-0000-0000-0000000000b2') $$, '42501', NULL, 'anon cannot call get_facility_management_members');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
