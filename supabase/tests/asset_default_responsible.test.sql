-- Responsable predeterminado por activo (20260926120000_asset_default_responsible.sql).
-- Se ejecuta con: supabase test db --local
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(88);

-- -------------------------------------------------------------------------
-- Fixture
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'owner-a@test.local', '{"name":"Olga Owner"}'),
  ('10000000-0000-0000-0000-000000000002', 'viewer-a@test.local', '{"name":"Vera Viewer"}'),
  ('10000000-0000-0000-0000-000000000003', 'tech-a@test.local', '{"name":"Tito Tecnico"}'),
  ('10000000-0000-0000-0000-000000000004', 'owner-b@test.local', '{"name":"Bruno B"}'),
  ('10000000-0000-0000-0000-000000000005', 'manager-a@test.local', '{"name":"Raul Manager"}'),
  ('10000000-0000-0000-0000-000000000006', 'admin-a@test.local', '{"name":"Ana Admin"}'),
  ('10000000-0000-0000-0000-000000000007', 'requester-a@test.local', '{"name":"Rita Requester"}'),
  ('10000000-0000-0000-0000-000000000008', 'manager2-a@test.local', '{"name":"Mario Luego Inactivo"}'),
  ('10000000-0000-0000-0000-000000000009', 'platform@test.local', '{"name":"Plataforma"}'),
  ('10000000-0000-0000-0000-000000000010', 'inactive-a@test.local', '{"name":"Ines Inactiva"}'),
  ('10000000-0000-0000-0000-000000000011', 'manager3-a@test.local', '{"name":"Nora Aviso"}'),
  ('10000000-0000-0000-0000-000000000012', 'manager4-a@test.local', '{"name":"Pablo Preventivo"}'),
  ('10000000-0000-0000-0000-000000000013', 'manager5-a@test.local', '{"name":"Borrado Luego"}'),
  ('10000000-0000-0000-0000-000000000014', 'owner-c@test.local', '{"name":"Carla C"}');

INSERT INTO public.organizations (id, name, organization_type)
VALUES
  ('20000000-0000-0000-0000-000000000001', 'Cliente A', 'client_company'),
  ('20000000-0000-0000-0000-000000000002', 'Cliente B', 'client_company'),
  ('20000000-0000-0000-0000-000000000003', 'Plataforma', 'platform_admin'),
  ('20000000-0000-0000-0000-000000000004', 'Cliente C (se borra)', 'client_company');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active)
VALUES
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner', true),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'viewer', true),
  ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'technician', true),
  ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000004', 'owner', true),
  ('30000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'manager', true),
  ('30000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000006', 'admin', true),
  ('30000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000007', 'requester', true),
  ('30000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000008', 'manager', true),
  ('30000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000009', 'owner', true),
  ('30000000-0000-0000-0000-000000000010', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000010', 'manager', false),
  ('30000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000011', 'manager', true),
  ('30000000-0000-0000-0000-000000000012', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000012', 'manager', true),
  ('30000000-0000-0000-0000-000000000013', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000013', 'manager', true),
  ('30000000-0000-0000-0000-000000000014', '20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000014', 'owner', true);

INSERT INTO public.assets (id, organization_id, code, name, node_type)
VALUES
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'A-1', 'Grupo electrógeno', 'equipment'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'A-2', 'Tablero general', 'equipment'),
  ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'A-3', 'Bomba', 'equipment'),
  ('40000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', 'A-4', 'Sin responsable', 'equipment'),
  ('40000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', 'A-5', 'Chiller', 'equipment'),
  ('40000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000001', 'A-6', 'Auditado', 'equipment'),
  ('40000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000001', 'A-7', 'Miembro borrado', 'equipment'),
  ('40000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000002', 'B-1', 'Equipo B', 'equipment'),
  ('40000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000004', 'C-1', 'Equipo C', 'equipment');

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;

CREATE FUNCTION pg_temp.responsible_of(p_asset uuid) RETURNS uuid LANGUAGE sql AS $$
  SELECT a.default_responsible_member_id FROM public.assets a WHERE a.id = p_asset;
$$;

CREATE FUNCTION pg_temp.notice(p_asset uuid, p_title text) RETURNS public.maintenance_notices LANGUAGE sql AS $$
  SELECT * FROM public.create_maintenance_notice('20000000-0000-0000-0000-000000000001', p_asset, p_title, 'Descripción del aviso');
$$;

SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');

-- -------------------------------------------------------------------------
-- 1. Estructura
-- -------------------------------------------------------------------------
SELECT has_column('public', 'assets', 'default_responsible_member_id', 'assets.default_responsible_member_id exists');
SELECT col_is_null('public', 'assets', 'default_responsible_member_id', 'default_responsible_member_id is nullable');
SELECT fk_ok('public', 'assets', 'default_responsible_member_id', 'public', 'organization_members', 'id', 'FK to organization_members(id)');
SELECT is(
  (SELECT c.confdeltype::text FROM pg_constraint c
    WHERE c.conrelid = 'public.assets'::regclass AND c.contype = 'f'
      AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'public.assets'::regclass AND attname = 'default_responsible_member_id')]),
  'n',
  'FK is ON DELETE SET NULL'
);
SELECT has_index('public', 'assets', 'idx_assets_default_responsible_member_id', 'index on default_responsible_member_id');
SELECT has_trigger('public', 'assets', 'trg_assets_check_default_responsible', 'integrity trigger exists');
SELECT has_trigger('public', 'assets', 'trg_assets_log_default_responsible_change', 'audit trigger exists');
SELECT ok(NOT (
  has_function_privilege('authenticated', 'public.is_eligible_follow_up_responsible(uuid, uuid)', 'EXECUTE')
  OR has_function_privilege('anon', 'public.is_eligible_follow_up_responsible(uuid, uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.member_display_name(uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.check_asset_default_responsible()', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.log_asset_default_responsible_change()', 'EXECUTE')
), 'internal helpers and trigger functions are not executable by authenticated/anon');
SELECT hasnt_function('public', 'triage_maintenance_notice', ARRAY['uuid', 'text', 'text', 'uuid'], 'old 4-argument triage overload no longer exists');
SELECT has_function('public', 'triage_maintenance_notice', ARRAY['uuid', 'text', 'text', 'uuid', 'boolean'], 'new triage signature exists');
SELECT ok(has_function_privilege('authenticated', 'public.triage_maintenance_notice(uuid, text, text, uuid, boolean)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.triage_maintenance_notice(uuid, text, text, uuid, boolean)', 'EXECUTE'),
  'triage: authenticated can execute, anon cannot');

-- -------------------------------------------------------------------------
-- 2. Valor por defecto y asignaciones válidas
-- -------------------------------------------------------------------------
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000001'), NULL::uuid, 'new asset has no default responsible');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.assets WHERE default_responsible_member_id IS NOT NULL), 'no asset gets a responsible by default (no backfill)');
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000001' WHERE id = '40000000-0000-0000-0000-000000000001' $$, 'owner is a valid default responsible');
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000006' WHERE id = '40000000-0000-0000-0000-000000000001' $$, 'admin is a valid default responsible');
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000001' $$, 'manager is a valid default responsible');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000001'), '30000000-0000-0000-0000-000000000005'::uuid, 'assignment is stored');
SELECT lives_ok($$
  INSERT INTO public.assets (organization_id, name, node_type, default_responsible_member_id)
  VALUES ('20000000-0000-0000-0000-000000000001', 'Creado con responsable', 'equipment', '30000000-0000-0000-0000-000000000005')
$$, 'INSERT with an eligible responsible is accepted');

-- -------------------------------------------------------------------------
-- 3. Asignaciones rechazadas (mensaje genérico)
-- -------------------------------------------------------------------------
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000004' WHERE id = '40000000-0000-0000-0000-000000000001' $$,
  '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'member of another tenant is rejected');
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000099' WHERE id = '40000000-0000-0000-0000-000000000001' $$,
  '.*(must be an active owner/admin/manager|violates foreign key).*', 'non-existent member id is rejected');
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000010' WHERE id = '40000000-0000-0000-0000-000000000001' $$,
  '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'inactive member is rejected on assignment');
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000003' WHERE id = '40000000-0000-0000-0000-000000000001' $$,
  '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'technician is rejected');
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000002' WHERE id = '40000000-0000-0000-0000-000000000001' $$,
  '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'viewer is rejected');
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000007' WHERE id = '40000000-0000-0000-0000-000000000001' $$,
  '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'requester is rejected');
SELECT throws_matching($$
  INSERT INTO public.assets (organization_id, name, node_type, default_responsible_member_id)
  VALUES ('20000000-0000-0000-0000-000000000001', 'Cross tenant insert', 'equipment', '30000000-0000-0000-0000-000000000004')
$$, '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'INSERT with a cross-tenant responsible is rejected');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000001'), '30000000-0000-0000-0000-000000000005'::uuid, 'rejected writes leave the previous value intact');
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = NULL WHERE id = '40000000-0000-0000-0000-000000000001' $$, 'clearing the responsible is allowed');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000001'), NULL::uuid, 'responsible cleared');

-- -------------------------------------------------------------------------
-- 4. Miembro que pasa a inactivo después de asignado
-- -------------------------------------------------------------------------
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000008' WHERE id = '40000000-0000-0000-0000-000000000001' $$, 'assign an active manager');
UPDATE public.organization_members SET is_active = false WHERE id = '30000000-0000-0000-0000-000000000008';
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000001'), '30000000-0000-0000-0000-000000000008'::uuid, 'deactivating the member keeps the historical reference');
SELECT lives_ok($$ UPDATE public.assets SET name = 'Grupo electrógeno principal' WHERE id = '40000000-0000-0000-0000-000000000001' $$, 'editing another field works with an inactive historical responsible');
SELECT lives_ok($$
  UPDATE public.assets SET name = 'Grupo electrógeno', default_responsible_member_id = '30000000-0000-0000-0000-000000000008'
  WHERE id = '40000000-0000-0000-0000-000000000001'
$$, 'a full-form save resending the same inactive responsible still works');
SELECT lives_ok($$ UPDATE public.assets SET criticality = 'high' WHERE id = '40000000-0000-0000-0000-000000000001' $$, 'server-side style updates (criticality) are not blocked');
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000010' WHERE id = '40000000-0000-0000-0000-000000000001' $$,
  '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'changing TO another inactive member is still rejected');

-- -------------------------------------------------------------------------
-- 5. Avisos heredan el responsable elegible
-- -------------------------------------------------------------------------
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000002';
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000007');
CREATE TEMP TABLE n1 AS SELECT * FROM pg_temp.notice('40000000-0000-0000-0000-000000000002', 'Aviso heredado');
SELECT is((SELECT responsible_member_id FROM n1), '30000000-0000-0000-0000-000000000005'::uuid, 'new notice inherits the eligible default responsible (reported by a requester)');
SELECT is((SELECT status FROM n1), 'open', 'inherited notice stays open');
SELECT ok((SELECT triaged_at IS NULL AND triaged_by_user_id IS NULL AND triage_notes IS NULL FROM n1), 'inherited notice has no triage data');
SELECT is(
  (SELECT count(*) FROM public.organization_notifications onf
    WHERE onf.recipient_member_id = '30000000-0000-0000-0000-000000000005'
      AND onf.type = 'maintenance_notice_created' AND onf.entity_type = 'maintenance_notice'
      AND onf.entity_id = (SELECT id FROM n1)),
  1::bigint,
  'the inherited responsible is notified exactly once (role + responsible deduplicated)'
);
SELECT is(
  (SELECT count(*) FROM public.organization_notifications onf
    WHERE onf.type = 'maintenance_notice_created' AND onf.entity_id = (SELECT id FROM n1)),
  (SELECT count(*) FROM public.organization_members om
    WHERE om.organization_id = '20000000-0000-0000-0000-000000000001' AND om.is_active AND om.role IN ('owner', 'admin', 'manager')),
  'no extra notification type or duplicate: one per active owner/admin/manager'
);

CREATE TEMP TABLE n_inactive AS SELECT * FROM pg_temp.notice('40000000-0000-0000-0000-000000000001', 'Aviso con responsable inactivo');
SELECT is((SELECT responsible_member_id FROM n_inactive), NULL::uuid, 'new notice ignores an inactive default responsible');

SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000006' WHERE id = '40000000-0000-0000-0000-000000000003';
UPDATE public.organization_members SET role = 'viewer' WHERE id = '30000000-0000-0000-0000-000000000006';
CREATE TEMP TABLE n_role AS SELECT * FROM pg_temp.notice('40000000-0000-0000-0000-000000000003', 'Aviso con responsable degradado');
SELECT is((SELECT responsible_member_id FROM n_role), NULL::uuid, 'new notice ignores a responsible whose role is no longer eligible');
UPDATE public.organization_members SET role = 'admin' WHERE id = '30000000-0000-0000-0000-000000000006';

CREATE TEMP TABLE n_none AS SELECT * FROM pg_temp.notice('40000000-0000-0000-0000-000000000004', 'Aviso sin responsable');
SELECT is((SELECT responsible_member_id FROM n_none), NULL::uuid, 'notice for an asset without default responsible has none');
SELECT is((SELECT status FROM n_none), 'open', 'notice without responsible stays open');

-- -------------------------------------------------------------------------
-- 6. Triage
-- -------------------------------------------------------------------------
SELECT lives_ok($$ SELECT public.triage_maintenance_notice((SELECT id FROM n1), NULL, NULL, '30000000-0000-0000-0000-000000000001') $$, 'triage changes the inherited responsible');
SELECT is((SELECT responsible_member_id FROM public.maintenance_notices WHERE id = (SELECT id FROM n1)), '30000000-0000-0000-0000-000000000001'::uuid, 'responsible changed by triage');
SELECT is((SELECT status FROM public.maintenance_notices WHERE id = (SELECT id FROM n1)), 'triaged', 'triage marks the notice as triaged');
SELECT lives_ok($$ SELECT public.triage_maintenance_notice((SELECT id FROM n1), 'high', NULL, NULL, false) $$, 'triage without responsible arguments');
SELECT is((SELECT responsible_member_id FROM public.maintenance_notices WHERE id = (SELECT id FROM n1)), '30000000-0000-0000-0000-000000000001'::uuid, 'no responsible argument keeps the current one');
SELECT lives_ok($$ SELECT public.triage_maintenance_notice((SELECT id FROM n1), NULL, NULL, NULL, true) $$, 'triage can unassign');
SELECT is((SELECT responsible_member_id FROM public.maintenance_notices WHERE id = (SELECT id FROM n1)), NULL::uuid, '"Sin asignar" really clears the responsible');
SELECT throws_matching($$ SELECT public.triage_maintenance_notice((SELECT id FROM n1), NULL, NULL, '30000000-0000-0000-0000-000000000001', true) $$,
  '.*no ambas cosas.*', 'assigning and clearing at the same time is rejected');
SELECT throws_matching($$ SELECT public.triage_maintenance_notice((SELECT id FROM n1), NULL, NULL, '30000000-0000-0000-0000-000000000003') $$,
  '.*rol de seguimiento.*', 'triage still rejects a new non-eligible responsible');
SELECT throws_matching($$ SELECT public.triage_maintenance_notice((SELECT id FROM n1), NULL, NULL, '30000000-0000-0000-0000-000000000004') $$,
  '.*rol de seguimiento.*', 'triage rejects a responsible of another tenant');

-- Aviso cuyo responsable heredado queda inactivo después.
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000011' WHERE id = '40000000-0000-0000-0000-000000000005';
CREATE TEMP TABLE n_later AS SELECT * FROM pg_temp.notice('40000000-0000-0000-0000-000000000005', 'Aviso cuyo responsable se desactiva');
UPDATE public.organization_members SET is_active = false WHERE id = '30000000-0000-0000-0000-000000000011';
SELECT lives_ok($$ SELECT public.triage_maintenance_notice((SELECT id FROM n_later), 'urgent', 'Revisado', '30000000-0000-0000-0000-000000000011') $$,
  'triage re-sending the unchanged inactive responsible is accepted');
SELECT is(
  (SELECT jsonb_build_array(responsible_member_id, priority, triage_notes) FROM public.maintenance_notices WHERE id = (SELECT id FROM n_later)),
  '["30000000-0000-0000-0000-000000000011", "urgent", "Revisado"]'::jsonb,
  'inactive responsible is kept while priority and notes change'
);
SELECT lives_ok($$ SELECT public.triage_maintenance_notice((SELECT id FROM n_later), 'low') $$, 'triage omitting the responsible also keeps the inactive one');
SELECT is((SELECT responsible_member_id FROM public.maintenance_notices WHERE id = (SELECT id FROM n_later)), '30000000-0000-0000-0000-000000000011'::uuid, 'inactive responsible preserved');

-- Cambiar el responsable del activo no toca avisos existentes.
CREATE TEMP TABLE n_sync AS SELECT * FROM pg_temp.notice('40000000-0000-0000-0000-000000000002', 'Aviso previo al cambio');
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000001' WHERE id = '40000000-0000-0000-0000-000000000002';
SELECT is((SELECT responsible_member_id FROM public.maintenance_notices WHERE id = (SELECT id FROM n_sync)), '30000000-0000-0000-0000-000000000005'::uuid,
  'changing the asset responsible does not modify existing notices');

-- -------------------------------------------------------------------------
-- 7. Preventivo
-- -------------------------------------------------------------------------
SELECT lives_ok($$
  SELECT public.save_maintenance_card(
    '20000000-0000-0000-0000-000000000001', 'CARD-R', 'Ficha responsable', NULL, NULL, NULL, NULL, NULL,
    '[{"title":"Inspeccionar","estimated_hours":1,"is_required":true}]'::jsonb, '[]'::jsonb, NULL
  )
$$, 'card for preventive plans');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-R'), 'calendar', 'medium', 'internal',
    '30000000-0000-0000-0000-000000000012', 7, 'monthly', NULL, NULL,
    '2030-01-15 10:00:00+00', NULL, NULL, NULL, NULL, NULL
  )
$$, 'preventive plan with its own responsible');
CREATE TEMP TABLE plan_r AS SELECT id FROM public.preventive_maintenance_plans WHERE asset_id = '40000000-0000-0000-0000-000000000002';
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000002';
SELECT is((SELECT responsible_member_id FROM public.preventive_maintenance_plans WHERE id = (SELECT id FROM plan_r)), '30000000-0000-0000-0000-000000000012'::uuid,
  'changing the asset responsible does not modify existing preventive plans');

UPDATE public.organization_members SET is_active = false WHERE id = '30000000-0000-0000-0000-000000000012';
SELECT lives_ok($$ SELECT public.set_preventive_maintenance_plan_active((SELECT id FROM plan_r), false, 'Pausa temporal') $$,
  'plan whose responsible became inactive can be deactivated');
SELECT lives_ok($$ SELECT public.set_preventive_maintenance_plan_active((SELECT id FROM plan_r), true) $$,
  'plan whose responsible became inactive can be reactivated');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-R'), 'calendar', 'high', 'internal',
    '30000000-0000-0000-0000-000000000012', 10, 'monthly', NULL, NULL,
    '2030-01-15 10:00:00+00', NULL, NULL, NULL, NULL, (SELECT id FROM plan_r)
  )
$$, 'plan whose responsible became inactive can edit other fields');
SELECT is(
  (SELECT jsonb_build_array(priority, planning_lead_days, responsible_member_id) FROM public.preventive_maintenance_plans WHERE id = (SELECT id FROM plan_r)),
  '["high", 10, "30000000-0000-0000-0000-000000000012"]'::jsonb,
  'other fields changed, historical responsible preserved'
);
SELECT throws_matching($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-R'), 'calendar', 'high', 'internal',
    '30000000-0000-0000-0000-000000000003', 10, 'monthly', NULL, NULL,
    '2030-01-15 10:00:00+00', NULL, NULL, NULL, NULL, (SELECT id FROM plan_r)
  )
$$, '.*responsible_member_id must be an active owner/admin/manager.*', 'changing the plan responsible still validates it');
SELECT throws_matching($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-R'), 'calendar', 'medium', 'internal',
    '30000000-0000-0000-0000-000000000012', 7, 'monthly', NULL, NULL,
    '2030-02-15 10:00:00+00', NULL, NULL, NULL, NULL, NULL
  )
$$, '.*responsible_member_id must be an active owner/admin/manager.*', 'a NEW plan still rejects an inactive responsible');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-R'), 'calendar', 'medium', 'internal',
    NULL, 7, 'monthly', NULL, NULL,
    '2030-02-15 10:00:00+00', NULL, NULL, NULL, NULL, NULL
  )
$$, 'a new plan can be saved deliberately "Sin asignar" (no backend default applied)');
SELECT is(
  (SELECT responsible_member_id FROM public.preventive_maintenance_plans WHERE asset_id = '40000000-0000-0000-0000-000000000003'),
  NULL::uuid,
  'backend does not fill the plan responsible from the asset'
);

-- -------------------------------------------------------------------------
-- 8. Auditoría
-- -------------------------------------------------------------------------
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000006';
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000006';
UPDATE public.assets SET name = 'Auditado renombrado' WHERE id = '40000000-0000-0000-0000-000000000006';
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000001' WHERE id = '40000000-0000-0000-0000-000000000006';
UPDATE public.assets SET default_responsible_member_id = NULL WHERE id = '40000000-0000-0000-0000-000000000006';
SELECT is(
  (SELECT count(*) FROM public.asset_events WHERE asset_id = '40000000-0000-0000-0000-000000000006' AND event_type = 'asset_default_responsible_changed'),
  3::bigint,
  'one audit event per real change; none for same value or other fields'
);
SELECT is(
  (SELECT payload FROM public.asset_events WHERE asset_id = '40000000-0000-0000-0000-000000000006' AND event_type = 'asset_default_responsible_changed'
    AND payload->>'new_member_id' = '30000000-0000-0000-0000-000000000001'),
  jsonb_build_object(
    'previous_member_id', '30000000-0000-0000-0000-000000000005',
    'new_member_id', '30000000-0000-0000-0000-000000000001',
    'previous_name', 'Raul Manager',
    'new_name', 'Olga Owner'
  ),
  'audit payload carries previous/new ids and names'
);
SELECT is(
  (SELECT description FROM public.asset_events WHERE asset_id = '40000000-0000-0000-0000-000000000006' AND event_type = 'asset_default_responsible_changed'
    AND payload->>'new_member_id' = '30000000-0000-0000-0000-000000000001'),
  'Responsable predeterminado: Raul Manager → Olga Owner',
  'audit description'
);
SELECT is(
  (SELECT description FROM public.asset_events WHERE asset_id = '40000000-0000-0000-0000-000000000006' AND event_type = 'asset_default_responsible_changed'
    AND payload->>'new_member_id' IS NULL),
  'Responsable predeterminado: Olga Owner → Sin responsable',
  'clearing is audited too'
);
SELECT is(
  (SELECT created_by_user_id FROM public.asset_events WHERE asset_id = '40000000-0000-0000-0000-000000000006' AND event_type = 'asset_default_responsible_changed' LIMIT 1),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'audit records the actor'
);
SELECT is(
  (SELECT count(*) FROM public.get_asset_integrated_history('40000000-0000-0000-0000-000000000006') h
    WHERE h.event_label = 'Responsable predeterminado actualizado' AND h.title = 'Responsable predeterminado actualizado'),
  3::bigint,
  'integrated history shows the Spanish label'
);
SELECT is(
  (SELECT count(*) FROM public.get_asset_integrated_history('40000000-0000-0000-0000-000000000006') h WHERE h.event_label ILIKE '%asset default%'),
  0::bigint,
  'no raw event type leaks into the history labels'
);

-- Borrar la membresía: ON DELETE SET NULL + auditoría best-effort.
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000013' WHERE id = '40000000-0000-0000-0000-000000000007';
SELECT lives_ok($$ DELETE FROM public.organization_members WHERE id = '30000000-0000-0000-0000-000000000013' $$,
  'deleting an assigned membership never fails (FK SET NULL, best-effort names)');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000007'), NULL::uuid, 'deleted membership sets the asset responsible to NULL');
SELECT is(
  (SELECT description FROM public.asset_events WHERE asset_id = '40000000-0000-0000-0000-000000000007' AND event_type = 'asset_default_responsible_changed'
    AND payload->>'new_member_id' IS NULL),
  'Responsable predeterminado: Miembro no disponible → Sin responsable',
  'unresolvable name is audited as "Miembro no disponible"'
);

-- Borrar una organización entera con activos asignados sigue funcionando.
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000014' WHERE id = '40000000-0000-0000-0000-000000000009';
SELECT lives_ok($$ DELETE FROM public.organizations WHERE id = '20000000-0000-0000-0000-000000000004' $$,
  'deleting an organization with assigned assets cascades without audit errors');

-- -------------------------------------------------------------------------
-- 9. RLS / aislamiento con el rol authenticated
-- -------------------------------------------------------------------------
GRANT SELECT ON n_none TO authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000004' WHERE id = '40000000-0000-0000-0000-000000000004';
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000004'), NULL::uuid, 'Client B cannot write Client A assets (RLS)');
SELECT throws_matching($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000004' WHERE id = '40000000-0000-0000-0000-000000000004' $$,
  '^default_responsible_member_id must be an active owner/admin/manager of this organization$', 'Client A owner cannot assign a Client B member (real UUID)');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000002');
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000004';
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000004'), NULL::uuid, 'viewer cannot assign a responsible (RLS)');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000003');
UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000004';
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000004'), NULL::uuid, 'technician cannot assign a responsible (RLS)');
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = '30000000-0000-0000-0000-000000000005' WHERE id = '40000000-0000-0000-0000-000000000004' $$,
  'owner assigns through RLS as authenticated');
SELECT is(pg_temp.responsible_of('40000000-0000-0000-0000-000000000004'), '30000000-0000-0000-0000-000000000005'::uuid, 'assignment through RLS stored');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.assets WHERE id = '40000000-0000-0000-0000-000000000004'), 0::bigint, 'Client B cannot even read Client A assets');
SELECT throws_matching($$ SELECT public.triage_maintenance_notice((SELECT id FROM n_none), NULL, NULL, NULL, true) $$,
  '.*(Not authorized|El aviso no existe|permission denied).*', 'Client B cannot triage Client A notices');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
