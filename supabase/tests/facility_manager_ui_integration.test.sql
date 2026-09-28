-- Fase 1 · Punto 9B — backend complementario de la UI de Facility Managers
-- (20260927205942_facility_manager_ui_integration.sql).
-- Se ejecuta con: supabase test db --local
--
-- Solo prueba el delta de 9B: get_facility_manager_directory y el cierre de
-- la ruta legacy de homologación para facility_manager. Las garantías de 9A
-- viven en facility_manager_delegated_permissions.test.sql.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(75);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('d1000000-0000-0000-0000-000000000001', 'owner-client-a@fm-ui.test'),
  ('d1000000-0000-0000-0000-000000000002', 'admin-client-a@fm-ui.test'),
  ('d1000000-0000-0000-0000-000000000003', 'manager-client-a@fm-ui.test'),
  ('d1000000-0000-0000-0000-000000000004', 'owner-client-b@fm-ui.test'),
  ('d1000000-0000-0000-0000-000000000005', 'owner-fm-uno@fm-ui.test'),
  ('d1000000-0000-0000-0000-000000000006', 'platform@fm-ui.test'),
  ('d1000000-0000-0000-0000-000000000007', 'outsider@fm-ui.test');

INSERT INTO public.organizations (id, name, organization_type, status) VALUES
  ('d2000000-0000-0000-0000-0000000000a1', 'UI Client A', 'client_company', 'active'),
  ('d2000000-0000-0000-0000-0000000000b1', 'UI Client B', 'client_company', 'active'),
  ('d2000000-0000-0000-0000-0000000000f1', 'UI FM Uno', 'facility_manager', 'active'),
  ('d2000000-0000-0000-0000-0000000000f2', 'UI FM Dos', 'facility_manager', 'active'),
  ('d2000000-0000-0000-0000-0000000000f3', 'UI FM Suspendido', 'facility_manager', 'suspended'),
  ('d2000000-0000-0000-0000-0000000000d1', 'UI Proveedor', 'provider_company', 'active'),
  ('d2000000-0000-0000-0000-0000000000e1', 'UI Subcontratista', 'subcontractor_company', 'active'),
  ('d2000000-0000-0000-0000-0000000000ee', 'UI Plataforma', 'platform_admin', 'active');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-0000000000a1', 'd1000000-0000-0000-0000-000000000001', 'owner', true),
  ('d3000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-0000000000a1', 'd1000000-0000-0000-0000-000000000002', 'admin', true),
  ('d3000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-0000000000a1', 'd1000000-0000-0000-0000-000000000003', 'manager', true),
  ('d3000000-0000-0000-0000-000000000004', 'd2000000-0000-0000-0000-0000000000b1', 'd1000000-0000-0000-0000-000000000004', 'owner', true),
  ('d3000000-0000-0000-0000-000000000005', 'd2000000-0000-0000-0000-0000000000f1', 'd1000000-0000-0000-0000-000000000005', 'owner', true),
  ('d3000000-0000-0000-0000-000000000006', 'd2000000-0000-0000-0000-0000000000ee', 'd1000000-0000-0000-0000-000000000006', 'owner', true);

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;

-- Solo las organizaciones de este fixture (la base local puede tener otras).
CREATE FUNCTION pg_temp.fixture_ids() RETURNS uuid[] LANGUAGE sql AS $$
  SELECT ARRAY[
    'd2000000-0000-0000-0000-0000000000f1', 'd2000000-0000-0000-0000-0000000000f2', 'd2000000-0000-0000-0000-0000000000f3',
    'd2000000-0000-0000-0000-0000000000d1', 'd2000000-0000-0000-0000-0000000000e1',
    'd2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000b1', 'd2000000-0000-0000-0000-0000000000ee'
  ]::uuid[];
$$;

-- =========================================================================
-- 1. get_facility_manager_directory
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1') $$, 'client owner can read the FM directory');
SELECT is((SELECT array_agg(facility_manager_organization_name ORDER BY facility_manager_organization_name)
  FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = ANY (pg_temp.fixture_ids())),
  ARRAY['UI FM Dos', 'UI FM Uno'], 'only ACTIVE facility_manager organizations are listed (suspended FM excluded)');
SELECT is((SELECT count(*) FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id IN ('d2000000-0000-0000-0000-0000000000d1', 'd2000000-0000-0000-0000-0000000000e1')), 0::bigint,
  'provider_company and subcontractor_company are excluded');
SELECT ok((SELECT relationship_id IS NULL AND relationship_status IS NULL FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = 'd2000000-0000-0000-0000-0000000000f2'), 'an unlinked FM comes with relationship_id/status NULL');
SELECT is((SELECT array_agg(facility_manager_organization_name) FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = ANY (pg_temp.fixture_ids())),
  ARRAY['UI FM Dos', 'UI FM Uno'], 'the directory is ordered by name');

SELECT public.create_facility_management_relationship('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000f1') AS rel_a1 \gset
SELECT is((SELECT relationship_id FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = 'd2000000-0000-0000-0000-0000000000f1'), :'rel_a1'::uuid, 'an existing relationship is returned');
SELECT is((SELECT relationship_status FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = 'd2000000-0000-0000-0000-0000000000f1'), 'pending'::public.organization_relationship_status,
  'with its real status (pending after creation)');
SELECT lives_ok(format($$ SELECT public.set_facility_management_relationship_status(%L, 'active') $$, :'rel_a1'), 'client owner activates it via the 9A RPC');
SELECT is((SELECT relationship_status FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = 'd2000000-0000-0000-0000-0000000000f1'), 'active'::public.organization_relationship_status,
  'the directory reflects the status change');

SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000b1')
  WHERE relationship_id IS NOT NULL AND facility_manager_organization_id = ANY (pg_temp.fixture_ids())), 0::bigint,
  'another client never sees Client A''s relationships in its own directory');
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'another client cannot query Client A''s directory');

SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = ANY (pg_temp.fixture_ids())), 2::bigint, 'client admin can read the FM directory');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000003');
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'client manager cannot read the FM directory');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000005');
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'an FM owner cannot read a client''s directory');
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000f1') $$,
  '22023', NULL, 'an FM cannot use the directory as if it were a client (its own org is not a client_company)');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000007');
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'outsider cannot read the FM directory');
SELECT pg_temp.as_user(NULL);
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'unauthenticated caller cannot read the FM directory');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000006');
SELECT is((SELECT count(*) FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE facility_manager_organization_id = ANY (pg_temp.fixture_ids())), 2::bigint, 'platform_admin can read any client''s FM directory');
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000d1') $$,
  '22023', NULL, 'even platform_admin must pass a client_company');
RESET ROLE;

SELECT is(pg_get_function_result('public.get_facility_manager_directory(uuid)'::regprocedure),
  'TABLE(facility_manager_organization_id uuid, facility_manager_organization_name text, relationship_id uuid, relationship_status organization_relationship_status)',
  'the directory exposes only FM id/name and relationship id/status (no members, emails or metadata)');

-- =========================================================================
-- 2. Legacy: get_provider_relationship_directory
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.get_provider_relationship_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE organization_type = 'facility_manager'), 0::bigint, 'the legacy provider directory no longer returns facility_manager');
SELECT is((SELECT relationship_type FROM public.get_provider_relationship_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE organization_id = 'd2000000-0000-0000-0000-0000000000d1'), 'provider'::public.organization_relationship_type,
  'it still returns provider_company (as provider)');
SELECT is((SELECT relationship_type FROM public.get_provider_relationship_directory('d2000000-0000-0000-0000-0000000000a1')
  WHERE organization_id = 'd2000000-0000-0000-0000-0000000000e1'), 'subcontracting'::public.organization_relationship_type,
  'it still returns subcontractor_company (as subcontracting)');
RESET ROLE;
SELECT is(pg_get_function_result('public.get_provider_relationship_directory(uuid)'::regprocedure),
  'TABLE(organization_id uuid, organization_name text, organization_type organization_type, relationship_id uuid, relationship_type organization_relationship_type, relationship_status organization_relationship_status, specialties text[])',
  'the legacy directory keeps its return contract');

-- =========================================================================
-- 3. Legacy: set_provider_relationship_status
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000f2', 'pending') $$,
  '22023', NULL, 'the legacy setter rejects a facility_manager target');
SELECT throws_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000f1', 'suspended') $$,
  '22023', NULL, 'the legacy setter rejects a facility_manager that already has a relationship');
SELECT throws_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000f3', 'pending') $$,
  '22023', NULL, 'the legacy setter rejects a suspended facility_manager with the same stable code');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.organization_relationships
  WHERE source_organization_id = 'd2000000-0000-0000-0000-0000000000a1'
    AND target_organization_id IN ('d2000000-0000-0000-0000-0000000000f2', 'd2000000-0000-0000-0000-0000000000f3')), 0::bigint,
  'no facility_management relationship was created by the legacy setter');
SELECT is((SELECT status FROM public.organization_relationships WHERE id = :'rel_a1'), 'active'::public.organization_relationship_status,
  'the existing FM relationship was not changed by the legacy setter');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000d1', 'pending') $$,
  'provider: "Agregar como pendiente" still works');
SELECT lives_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000d1', 'active') $$,
  'provider: "Homologar" still works');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000d1', 'suspended') $$,
  'provider: "Suspender" still works (client admin)');
SELECT lives_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000d1', 'ended') $$,
  'provider: historical free transitions are kept (suspended -> ended)');
SELECT lives_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000d1', 'active') $$,
  'provider: historical free transitions are kept (ended -> active, no FM state machine)');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000e1', 'active') $$,
  'subcontractor: a new relationship can still be created directly active');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000003');
SELECT throws_ok($$ SELECT public.set_provider_relationship_status('d2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-0000000000d1', 'suspended') $$,
  'P0001', NULL, 'the legacy setter keeps rejecting a client manager');
RESET ROLE;
SELECT is((SELECT relationship_type::text || ':' || status::text FROM public.organization_relationships
  WHERE source_organization_id = 'd2000000-0000-0000-0000-0000000000a1' AND target_organization_id = 'd2000000-0000-0000-0000-0000000000d1'),
  'provider:active', 'provider relationship keeps type provider and its last status');
SELECT is((SELECT created_by FROM public.organization_relationships
  WHERE source_organization_id = 'd2000000-0000-0000-0000-0000000000a1' AND target_organization_id = 'd2000000-0000-0000-0000-0000000000d1'),
  'd1000000-0000-0000-0000-000000000001'::uuid, 'the upsert still preserves the original created_by');
SELECT is((SELECT relationship_type::text || ':' || status::text FROM public.organization_relationships
  WHERE source_organization_id = 'd2000000-0000-0000-0000-0000000000a1' AND target_organization_id = 'd2000000-0000-0000-0000-0000000000e1'),
  'subcontracting:active', 'subcontractor relationship keeps type subcontracting');

-- =========================================================================
-- 5. Facility Manager NO es provider-facing (decisión funcional MVP)
-- =========================================================================
INSERT INTO auth.users (id, email) VALUES
  ('d1000000-0000-0000-0000-000000000008', 'owner-provider@fm-ui.test'),
  ('d1000000-0000-0000-0000-000000000009', 'owner-subcontractor@fm-ui.test');
INSERT INTO public.organizations (id, name, organization_type, status) VALUES
  ('d2000000-0000-0000-0000-0000000000d2', 'UI Proveedor Suspendido', 'provider_company', 'suspended');
INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('d3000000-0000-0000-0000-000000000008', 'd2000000-0000-0000-0000-0000000000d1', 'd1000000-0000-0000-0000-000000000008', 'owner', true),
  ('d3000000-0000-0000-0000-000000000009', 'd2000000-0000-0000-0000-0000000000e1', 'd1000000-0000-0000-0000-000000000009', 'owner', true);
INSERT INTO public.requests (id, request_number, description, asset, location, service_type, deadline, status, created_by, organization_id, request_type, is_public) VALUES
  ('d5000000-0000-0000-0000-000000000001', 'UI-REQ-PUB', 'x', 'Activo', 'Planta', 'correctivo', now() + interval '7 days', 'sent', 'x@x.test', 'd2000000-0000-0000-0000-0000000000a1', 'external', true),
  ('d5000000-0000-0000-0000-000000000002', 'UI-REQ-PRIV', 'x', 'Activo', 'Planta', 'correctivo', now() + interval '7 days', 'sent', 'x@x.test', 'd2000000-0000-0000-0000-0000000000a1', 'external', false);

-- 5.1 is_provider_facing_organization
SELECT is(public.is_provider_facing_organization('d2000000-0000-0000-0000-0000000000d1'), true, 'active provider_company is provider-facing');
SELECT is(public.is_provider_facing_organization('d2000000-0000-0000-0000-0000000000e1'), true, 'active subcontractor_company is provider-facing');
SELECT is(public.is_provider_facing_organization('d2000000-0000-0000-0000-0000000000f1'), false, 'active facility_manager is NOT provider-facing');
SELECT is(public.is_provider_facing_organization('d2000000-0000-0000-0000-0000000000d2'), false, 'suspended provider_company is not provider-facing');
SELECT is(public.is_provider_facing_organization('d2000000-0000-0000-0000-0000000000a1'), false, 'client_company is not provider-facing');
SELECT is(public.is_provider_facing_organization('d2000000-0000-0000-0000-0000000000ee'), false, 'platform_admin is not provider-facing');

-- 5.2 set_request_audience (provider y subcontractor tienen relación activa
--     desde la sección 3; FM Uno tiene una relación facility_management activa)
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT * FROM public.set_request_audience('d5000000-0000-0000-0000-000000000002', false,
  ARRAY['d2000000-0000-0000-0000-0000000000d1', 'd2000000-0000-0000-0000-0000000000e1']::uuid[]) $$,
  'set_request_audience accepts an active provider and an active subcontractor');
SELECT throws_ok($$ SELECT * FROM public.set_request_audience('d5000000-0000-0000-0000-000000000002', false,
  ARRAY['d2000000-0000-0000-0000-0000000000d1', 'd2000000-0000-0000-0000-0000000000f1']::uuid[]) $$,
  '22023', NULL, 'a facility_manager with an ACTIVE facility_management relationship is still rejected (22023)');
SELECT throws_ok($$ SELECT * FROM public.set_request_audience('d5000000-0000-0000-0000-000000000002', false,
  ARRAY['d2000000-0000-0000-0000-0000000000f2']::uuid[]) $$,
  '22023', NULL, 'a facility_manager without any relationship is rejected (22023)');
RESET ROLE;
SELECT is((SELECT array_agg(provider_organization_id ORDER BY provider_organization_id) FROM public.request_provider_access
  WHERE request_id = 'd5000000-0000-0000-0000-000000000002' AND status = 'active'),
  ARRAY['d2000000-0000-0000-0000-0000000000d1', 'd2000000-0000-0000-0000-0000000000e1']::uuid[],
  'provider and subcontractor were invited; the rejected calls left the audience untouched');
SELECT is((SELECT count(*) FROM public.request_provider_access
  WHERE request_id = 'd5000000-0000-0000-0000-000000000002'
    AND provider_organization_id IN ('d2000000-0000-0000-0000-0000000000f1', 'd2000000-0000-0000-0000-0000000000f2')), 0::bigint,
  'the rejection creates no request_provider_access row for a facility_manager');

-- Fila sintética creada por servicio: un FM "invitado" a la solicitud privada.
INSERT INTO public.request_provider_access (request_id, provider_organization_id, access_type, status)
VALUES ('d5000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-0000000000f1', 'invited', 'active');

-- 5.3 Proveedor / subcontratista: lectura y cotización intactas
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000008');
SELECT is(public.can_user_read_request('d5000000-0000-0000-0000-000000000002'), true, 'invited provider can read the private request');
SELECT is(public.can_user_read_request('d5000000-0000-0000-0000-000000000001'), true, 'provider can read the public request');
SELECT is(public.can_provider_quote_request('d5000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-0000000000d1'), true,
  'invited provider can quote the private request');
SELECT is(public.can_provider_quote_request('d5000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-0000000000d1'), true,
  'provider can quote the public request');
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000009');
SELECT is(public.can_user_read_request('d5000000-0000-0000-0000-000000000002'), true, 'invited subcontractor can read the private request');
SELECT is(public.can_provider_quote_request('d5000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-0000000000e1'), true,
  'invited subcontractor can quote the private request');
SELECT is(public.can_provider_quote_request('d5000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-0000000000e1'), true,
  'subcontractor can quote the public request');

-- 5.4 Facility Manager: sin acceso provider-facing
SELECT pg_temp.as_user('d1000000-0000-0000-0000-000000000005');
SELECT is(public.can_user_read_request('d5000000-0000-0000-0000-000000000002'), false,
  'FM does not read the private request even with a service-created request_provider_access row');
SELECT is(public.can_user_read_request('d5000000-0000-0000-0000-000000000001'), false,
  'FM does not read a public request as if it were a provider');
SELECT is(public.can_provider_quote_request('d5000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-0000000000f1'), false,
  'FM cannot quote a public request');
SELECT is(public.can_provider_quote_request('d5000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-0000000000f1'), false,
  'FM cannot quote even with an active request_provider_access row');
SELECT is((SELECT count(*) FROM public.requests WHERE id IN ('d5000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002')), 0::bigint,
  'FM sees neither request through the requests RLS');
SELECT is((SELECT count(*) FROM public.request_provider_access WHERE provider_organization_id = 'd2000000-0000-0000-0000-0000000000f1'), 0::bigint,
  'FM does not even see its own synthetic request_provider_access row (policy depends on the helper)');
RESET ROLE;

SELECT ok(has_function_privilege('authenticated', 'public.is_provider_facing_organization(uuid)', 'EXECUTE')
  AND has_function_privilege('authenticated', 'public.can_user_read_request(uuid)', 'EXECUTE')
  AND has_function_privilege('authenticated', 'public.set_request_audience(uuid, boolean, uuid[])', 'EXECUTE'),
  'the replaced provider-facing functions keep EXECUTE for authenticated');
SELECT ok(NOT has_function_privilege('anon', 'public.is_provider_facing_organization(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.can_user_read_request(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.set_request_audience(uuid, boolean, uuid[])', 'EXECUTE'),
  'the replaced provider-facing functions stay closed to anon');
SELECT is((SELECT count(*) FROM pg_proc p, aclexplode(p.proacl) a
  WHERE a.grantee = 0 AND p.oid IN (
    'public.is_provider_facing_organization(uuid)'::regprocedure,
    'public.can_user_read_request(uuid)'::regprocedure,
    'public.set_request_audience(uuid, boolean, uuid[])'::regprocedure)), 0::bigint,
  'PUBLIC has no EXECUTE on the replaced provider-facing functions');
SELECT ok(pg_get_functiondef('public.can_user_read_request(uuid)'::regprocedure) NOT ILIKE '%facility_manager%'
  AND pg_get_functiondef('public.can_user_read_request(uuid)'::regprocedure) ILIKE '%is_provider_facing_organization%',
  'can_user_read_request no longer hardcodes organization types (delegates to the helper)');

-- =========================================================================
-- 4. Grants
-- =========================================================================
SELECT ok(has_function_privilege('authenticated', 'public.get_facility_manager_directory(uuid)', 'EXECUTE'), 'authenticated EXECUTE get_facility_manager_directory');
SELECT ok(NOT has_function_privilege('anon', 'public.get_facility_manager_directory(uuid)', 'EXECUTE'), 'anon: no EXECUTE get_facility_manager_directory');
SELECT is((SELECT count(*) FROM pg_proc p, aclexplode(p.proacl) a
  WHERE a.grantee = 0 AND p.oid IN (
    'public.get_facility_manager_directory(uuid)'::regprocedure,
    'public.get_provider_relationship_directory(uuid)'::regprocedure,
    'public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status)'::regprocedure)), 0::bigint,
  'PUBLIC has no EXECUTE on the new or replaced functions');
SELECT ok((SELECT p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')
  FROM pg_proc p WHERE p.oid = 'public.get_facility_manager_directory(uuid)'::regprocedure),
  'get_facility_manager_directory is SECURITY DEFINER with a pinned search_path');
SELECT ok(pg_get_function_arguments('public.get_facility_manager_directory(uuid)'::regprocedure) NOT ILIKE '%user%',
  'get_facility_manager_directory takes no user parameter');
SELECT ok(has_function_privilege('authenticated', 'public.get_provider_relationship_directory(uuid)', 'EXECUTE')
  AND has_function_privilege('authenticated', 'public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status)', 'EXECUTE'),
  'the replaced legacy RPCs keep EXECUTE for authenticated');
SELECT ok(NOT has_function_privilege('anon', 'public.get_provider_relationship_directory(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status)', 'EXECUTE'),
  'the replaced legacy RPCs stay closed to anon');
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT * FROM public.get_facility_manager_directory('d2000000-0000-0000-0000-0000000000a1') $$,
  '42501', NULL, 'anon cannot call get_facility_manager_directory');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
