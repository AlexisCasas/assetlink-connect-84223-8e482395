-- Fase 1 · Punto 9C.1 — acceso operativo de Facility Manager a Activos +
-- Criticidad (…_facility_manager_assets_criticality_access.sql).
-- Se ejecuta con: supabase test db --local
--
-- Cada intento se ejecuta como `authenticated` con un auth.uid() sintético.
-- Errores: 42501 = RLS/grant/trigger de escritura delegada; P0001 = las RPCs
-- de criticidad y de otros módulos rechazan con RAISE sin código propio.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(188);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('a9100000-0000-0000-0000-000000000001', 'ca-owner@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000002', 'ca-manager@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000003', 'ca-technician@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000004', 'fa-owner@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000005', 'fa-admin@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000006', 'fa-manager@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000007', 'fa-technician@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000008', 'fa-viewer@fm-assets.test'),
  ('a9100000-0000-0000-0000-000000000009', 'fb-owner@fm-assets.test'),
  ('a9100000-0000-0000-0000-00000000000a', 'outsider@fm-assets.test'),
  ('a9100000-0000-0000-0000-00000000000b', 'platform@fm-assets.test'),
  ('a9100000-0000-0000-0000-00000000000c', 'fa-manager-unassigned@fm-assets.test'),
  ('a9100000-0000-0000-0000-00000000000d', 'cb-owner@fm-assets.test'),
  ('a9100000-0000-0000-0000-00000000000e', 'fa-viewer-fb-manager@fm-assets.test');

INSERT INTO public.organizations (id, name, organization_type) VALUES
  ('a9200000-0000-0000-0000-0000000000a1', 'Client A', 'client_company'),
  ('a9200000-0000-0000-0000-0000000000b1', 'Client B', 'client_company'),
  ('a9200000-0000-0000-0000-0000000000c1', 'Client C (manage sin view)', 'client_company'),
  ('a9200000-0000-0000-0000-0000000000d1', 'Client D (solo view)', 'client_company'),
  ('a9200000-0000-0000-0000-0000000000e1', 'Client E (pending)', 'client_company'),
  ('a9200000-0000-0000-0000-0000000000f1', 'Client G (assets manage)', 'client_company'),
  ('a9200000-0000-0000-0000-000000000011', 'Client H (solo criticidad)', 'client_company'),
  ('a9200000-0000-0000-0000-000000000012', 'Client I (assets.view + criticality.manage)', 'client_company'),
  ('a9200000-0000-0000-0000-000000000013', 'Client J (assets manage + criticality.view)', 'client_company'),
  ('a9200000-0000-0000-0000-000000000014', 'Client K (assets manage + criticality.manage)', 'client_company'),
  ('a9200000-0000-0000-0000-0000000000fa', 'FM A', 'facility_manager'),
  ('a9200000-0000-0000-0000-0000000000fb', 'FM B', 'facility_manager'),
  ('a9200000-0000-0000-0000-0000000000ee', 'Plataforma 9C1', 'platform_admin');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('a9300000-0000-0000-0000-000000000001', 'a9200000-0000-0000-0000-0000000000a1', 'a9100000-0000-0000-0000-000000000001', 'owner', true),
  ('a9300000-0000-0000-0000-000000000002', 'a9200000-0000-0000-0000-0000000000a1', 'a9100000-0000-0000-0000-000000000002', 'manager', true),
  ('a9300000-0000-0000-0000-000000000003', 'a9200000-0000-0000-0000-0000000000a1', 'a9100000-0000-0000-0000-000000000003', 'technician', true),
  ('a9300000-0000-0000-0000-000000000004', 'a9200000-0000-0000-0000-0000000000fa', 'a9100000-0000-0000-0000-000000000004', 'owner', true),
  ('a9300000-0000-0000-0000-000000000005', 'a9200000-0000-0000-0000-0000000000fa', 'a9100000-0000-0000-0000-000000000005', 'admin', true),
  ('a9300000-0000-0000-0000-000000000006', 'a9200000-0000-0000-0000-0000000000fa', 'a9100000-0000-0000-0000-000000000006', 'manager', true),
  ('a9300000-0000-0000-0000-000000000007', 'a9200000-0000-0000-0000-0000000000fa', 'a9100000-0000-0000-0000-000000000007', 'technician', true),
  ('a9300000-0000-0000-0000-000000000008', 'a9200000-0000-0000-0000-0000000000fa', 'a9100000-0000-0000-0000-000000000008', 'viewer', true),
  ('a9300000-0000-0000-0000-000000000009', 'a9200000-0000-0000-0000-0000000000fb', 'a9100000-0000-0000-0000-000000000009', 'owner', true),
  ('a9300000-0000-0000-0000-00000000000b', 'a9200000-0000-0000-0000-0000000000ee', 'a9100000-0000-0000-0000-00000000000b', 'owner', true),
  ('a9300000-0000-0000-0000-00000000000c', 'a9200000-0000-0000-0000-0000000000fa', 'a9100000-0000-0000-0000-00000000000c', 'manager', true),
  ('a9300000-0000-0000-0000-00000000000d', 'a9200000-0000-0000-0000-0000000000b1', 'a9100000-0000-0000-0000-00000000000d', 'owner', true),
  ('a9300000-0000-0000-0000-00000000000e', 'a9200000-0000-0000-0000-0000000000fa', 'a9100000-0000-0000-0000-00000000000e', 'viewer', true),
  ('a9300000-0000-0000-0000-00000000000f', 'a9200000-0000-0000-0000-0000000000fb', 'a9100000-0000-0000-0000-00000000000e', 'manager', true);

INSERT INTO public.asset_categories (id, organization_id, name) VALUES
  ('a9500000-0000-0000-0000-0000000000a1', 'a9200000-0000-0000-0000-0000000000a1', 'Cat A'),
  ('a9500000-0000-0000-0000-0000000000b1', 'a9200000-0000-0000-0000-0000000000b1', 'Cat B');
INSERT INTO public.client_branches (id, organization_id, client_email, name, city, site, address, is_active) VALUES
  ('a9600000-0000-0000-0000-0000000000a1', 'a9200000-0000-0000-0000-0000000000a1', 'secret@client-a.test', 'Sede A', 'Lima', 'S1', 'Av. A 1', true),
  ('a9600000-0000-0000-0000-0000000000b1', 'a9200000-0000-0000-0000-0000000000b1', 'secret@client-b.test', 'Sede B', 'Lima', 'S1', 'Av. B 1', true);
INSERT INTO public.assets (id, organization_id, code, name, node_type) VALUES
  ('a9400000-0000-0000-0000-0000000000a1', 'a9200000-0000-0000-0000-0000000000a1', 'A-1', 'Activo A1', 'equipment'),
  ('a9400000-0000-0000-0000-0000000000a2', 'a9200000-0000-0000-0000-0000000000a1', 'A-2', 'Activo A2', 'equipment'),
  ('a9400000-0000-0000-0000-0000000000b1', 'a9200000-0000-0000-0000-0000000000b1', 'B-1', 'Activo B1', 'equipment'),
  ('a9400000-0000-0000-0000-0000000000c1', 'a9200000-0000-0000-0000-0000000000c1', 'C-1', 'Activo C1', 'equipment'),
  ('a9400000-0000-0000-0000-0000000000d1', 'a9200000-0000-0000-0000-0000000000d1', 'D-1', 'Activo D1', 'equipment'),
  ('a9400000-0000-0000-0000-0000000000e1', 'a9200000-0000-0000-0000-0000000000e1', 'E-1', 'Activo E1', 'equipment'),
  ('a9400000-0000-0000-0000-0000000000f1', 'a9200000-0000-0000-0000-0000000000f1', 'G-1', 'Activo G1', 'equipment'),
  ('a9400000-0000-0000-0000-000000000011', 'a9200000-0000-0000-0000-000000000011', 'H-1', 'Activo H1', 'equipment'),
  ('a9400000-0000-0000-0000-000000000012', 'a9200000-0000-0000-0000-000000000012', 'I-1', 'Activo I1', 'equipment'),
  ('a9400000-0000-0000-0000-000000000013', 'a9200000-0000-0000-0000-000000000013', 'J-1', 'Activo J1', 'equipment'),
  ('a9400000-0000-0000-0000-000000000014', 'a9200000-0000-0000-0000-000000000014', 'K-1', 'Activo K1', 'equipment');

-- Relaciones (nacen pending, se configuran y se activan como las RPCs 9A).
INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status) VALUES
  ('a9700000-0000-0000-0000-0000000000aa', 'a9200000-0000-0000-0000-0000000000a1', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-0000000000bb', 'a9200000-0000-0000-0000-0000000000b1', 'a9200000-0000-0000-0000-0000000000fb', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-0000000000ca', 'a9200000-0000-0000-0000-0000000000c1', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-0000000000da', 'a9200000-0000-0000-0000-0000000000d1', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-0000000000ea', 'a9200000-0000-0000-0000-0000000000e1', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-0000000000fa', 'a9200000-0000-0000-0000-0000000000f1', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-00000000001a', 'a9200000-0000-0000-0000-000000000011', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-00000000002a', 'a9200000-0000-0000-0000-000000000012', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-00000000003a', 'a9200000-0000-0000-0000-000000000013', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('a9700000-0000-0000-0000-00000000004a', 'a9200000-0000-0000-0000-000000000014', 'a9200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending');
INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES
  ('a9700000-0000-0000-0000-0000000000aa', 'assets.view'), ('a9700000-0000-0000-0000-0000000000aa', 'assets.manage'),
  ('a9700000-0000-0000-0000-0000000000aa', 'criticality.view'), ('a9700000-0000-0000-0000-0000000000aa', 'criticality.manage'),
  ('a9700000-0000-0000-0000-0000000000bb', 'assets.view'), ('a9700000-0000-0000-0000-0000000000bb', 'criticality.view'),
  ('a9700000-0000-0000-0000-0000000000ca', 'assets.manage'), ('a9700000-0000-0000-0000-0000000000ca', 'criticality.manage'),
  ('a9700000-0000-0000-0000-0000000000da', 'assets.view'), ('a9700000-0000-0000-0000-0000000000da', 'criticality.view'),
  ('a9700000-0000-0000-0000-0000000000ea', 'assets.view'),
  ('a9700000-0000-0000-0000-0000000000fa', 'assets.view'), ('a9700000-0000-0000-0000-0000000000fa', 'assets.manage'),
  ('a9700000-0000-0000-0000-00000000001a', 'criticality.view'), ('a9700000-0000-0000-0000-00000000001a', 'criticality.manage'),
  ('a9700000-0000-0000-0000-00000000002a', 'assets.view'), ('a9700000-0000-0000-0000-00000000002a', 'criticality.manage'),
  ('a9700000-0000-0000-0000-00000000003a', 'assets.view'), ('a9700000-0000-0000-0000-00000000003a', 'assets.manage'), ('a9700000-0000-0000-0000-00000000003a', 'criticality.view'),
  ('a9700000-0000-0000-0000-00000000004a', 'assets.view'), ('a9700000-0000-0000-0000-00000000004a', 'assets.manage'), ('a9700000-0000-0000-0000-00000000004a', 'criticality.manage');
INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id) VALUES
  ('a9700000-0000-0000-0000-0000000000aa', 'a9300000-0000-0000-0000-000000000004'),
  ('a9700000-0000-0000-0000-0000000000aa', 'a9300000-0000-0000-0000-000000000005'),
  ('a9700000-0000-0000-0000-0000000000aa', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-0000000000aa', 'a9300000-0000-0000-0000-000000000007'),
  ('a9700000-0000-0000-0000-0000000000aa', 'a9300000-0000-0000-0000-000000000008'),
  ('a9700000-0000-0000-0000-0000000000aa', 'a9300000-0000-0000-0000-00000000000e'),
  ('a9700000-0000-0000-0000-0000000000bb', 'a9300000-0000-0000-0000-000000000009'),
  ('a9700000-0000-0000-0000-0000000000ca', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-0000000000da', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-0000000000ea', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-0000000000fa', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-00000000001a', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-00000000002a', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-00000000003a', 'a9300000-0000-0000-0000-000000000006'),
  ('a9700000-0000-0000-0000-00000000004a', 'a9300000-0000-0000-0000-000000000006');
UPDATE public.organization_relationships SET status = 'active'
WHERE id IN ('a9700000-0000-0000-0000-0000000000aa', 'a9700000-0000-0000-0000-0000000000bb', 'a9700000-0000-0000-0000-0000000000ca',
             'a9700000-0000-0000-0000-0000000000da', 'a9700000-0000-0000-0000-0000000000fa', 'a9700000-0000-0000-0000-00000000001a',
             'a9700000-0000-0000-0000-00000000002a', 'a9700000-0000-0000-0000-00000000003a', 'a9700000-0000-0000-0000-00000000004a');

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;
CREATE FUNCTION pg_temp.rename_asset(p_id uuid, p_name text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v integer; BEGIN UPDATE public.assets SET name = p_name WHERE id = p_id; GET DIAGNOSTICS v = ROW_COUNT; RETURN v; END $$;
CREATE FUNCTION pg_temp.set_asset_status(p_id uuid, p_status text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v integer; BEGIN UPDATE public.assets SET status = p_status WHERE id = p_id; GET DIAGNOSTICS v = ROW_COUNT; RETURN v; END $$;
-- -1 = rechazado por permisos (sin abortar la transacción de la suite).
CREATE FUNCTION pg_temp.set_criticality(p_id uuid, p_value text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v integer; BEGIN UPDATE public.assets SET criticality = p_value WHERE id = p_id; GET DIAGNOSTICS v = ROW_COUNT; RETURN v;
EXCEPTION WHEN insufficient_privilege THEN RETURN -1; END $$;
CREATE FUNCTION pg_temp.visible_assets(p_org uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.assets WHERE organization_id = p_org;
$$;

-- Matriz mínima (un parámetro de peso 100) configurada por los owners directos.
CREATE TEMP TABLE test_matrix AS
SELECT jsonb_build_object('parameters', jsonb_build_array(jsonb_build_object(
  'code', 'P1', 'name', 'Impacto', 'weight', 100, 'sequence', 1, 'is_active', true,
  'options', jsonb_build_array(
    jsonb_build_object('code', 's25', 'label', 'Bajo', 'score', 25, 'sequence', 1),
    jsonb_build_object('code', 's75', 'label', 'Alto', 'score', 75, 'sequence', 2)
  )
))) AS payload;
GRANT SELECT ON test_matrix TO authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000001');
SELECT public.replace_criticality_configuration('a9200000-0000-0000-0000-0000000000a1', (SELECT payload FROM test_matrix), NULL) IS NOT NULL AS setup_a \gset
SELECT pg_temp.as_user('a9100000-0000-0000-0000-00000000000d');
SELECT public.replace_criticality_configuration('a9200000-0000-0000-0000-0000000000b1', (SELECT payload FROM test_matrix), NULL) IS NOT NULL AS setup_b \gset

-- =========================================================================
-- 1. HELPER has_facility_management_operational_access(_all)
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000004');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), true, 'helper: assigned FM owner with permission => true');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000005');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), true, 'helper: assigned FM admin => true');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), true, 'helper: assigned FM manager => true');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), true, 'helper: technician => true when technician is an allowed role');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager']::public.organization_member_role[]), false, 'helper: technician => false when not an allowed role');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000008');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: assigned viewer => false');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-00000000000c');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: FM manager without assignment => false');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'inspections.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: permission not granted => false');
SELECT is(public.has_facility_management_operational_access_all('a9200000-0000-0000-0000-0000000000a1', ARRAY['assets.view','assets.manage']::public.facility_management_permission[], ARRAY['owner','admin','manager']::public.organization_member_role[]), true, 'helper_all: every permission present in the same relationship => true');
SELECT is(public.has_facility_management_operational_access_all('a9200000-0000-0000-0000-0000000000a1', ARRAY['assets.view','inspections.view']::public.facility_management_permission[], ARRAY['owner','admin','manager']::public.organization_member_role[]), false, 'helper_all: one missing permission => false');
SELECT is(public.has_facility_management_operational_access_all('a9200000-0000-0000-0000-0000000000a1', '{}'::public.facility_management_permission[], ARRAY['owner','admin','manager']::public.organization_member_role[]), false, 'helper_all: empty permission list => false');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000e1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: pending relationship => false');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000b1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: Client B (another FM''s client) is never mixed in');
RESET ROLE;
UPDATE public.organization_members SET is_active = false WHERE id = 'a9300000-0000-0000-0000-000000000006';
SET LOCAL ROLE authenticated;
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: inactive membership => false');
RESET ROLE;
UPDATE public.organization_members SET is_active = true WHERE id = 'a9300000-0000-0000-0000-000000000006';
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'a9700000-0000-0000-0000-0000000000aa';
SET LOCAL ROLE authenticated;
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: suspended relationship => false');
RESET ROLE;
UPDATE public.organization_relationships SET status = 'active' WHERE id = 'a9700000-0000-0000-0000-0000000000aa';
UPDATE public.organizations SET status = 'suspended' WHERE id = 'a9200000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: suspended client => false');
RESET ROLE;
UPDATE public.organizations SET status = 'active' WHERE id = 'a9200000-0000-0000-0000-0000000000a1';
UPDATE public.organizations SET status = 'suspended' WHERE id = 'a9200000-0000-0000-0000-0000000000fa';
SET LOCAL ROLE authenticated;
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: suspended FM => false');
RESET ROLE;
UPDATE public.organizations SET status = 'active' WHERE id = 'a9200000-0000-0000-0000-0000000000fa';
SET LOCAL ROLE authenticated;
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), true, 'helper: everything restored => true again');
-- Usuario viewer asignado en FM A y manager (no asignado) en FM B: nunca se
-- combina la relación de un FM con el rol de otro.
SELECT pg_temp.as_user('a9100000-0000-0000-0000-00000000000e');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager']::public.organization_member_role[]), false, 'helper: FM A viewer + FM B manager never combine into access on Client A');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000b1', 'assets.view', ARRAY['owner','admin','manager']::public.organization_member_role[]), false, 'helper: FM B manager without assignment => false on Client B');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000009');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: FM B owner => false on Client A');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-00000000000a');
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: outsider => false');
SELECT pg_temp.as_user(NULL);
SELECT is(public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner','admin','manager','technician']::public.organization_member_role[]), false, 'helper: unauthenticated => false');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT public.has_facility_management_operational_access('a9200000-0000-0000-0000-0000000000a1', 'assets.view', ARRAY['owner']::public.organization_member_role[]) $$, '42501', NULL, 'helper: anon cannot execute it');
RESET ROLE;

-- =========================================================================
-- 2. ASSETS.VIEW (RLS)
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000004');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 2::bigint, 'assets.view: FM owner sees Client A assets');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000005');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 2::bigint, 'assets.view: FM admin sees Client A assets');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 2::bigint, 'assets.view: FM technician sees Client A assets');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000008');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'assets.view: FM viewer sees nothing');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-00000000000c');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'assets.view: unassigned FM manager sees nothing');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000009');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'assets.view: FM B owner sees nothing of Client A');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 2::bigint, 'assets.view: FM manager sees Client A assets');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000b1'), 0::bigint, 'assets.view: FM manager sees nothing of Client B');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000c1'), 0::bigint, 'assets.view: assets.manage without assets.view gives no read');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000e1'), 0::bigint, 'assets.view: pending relationship gives no read');
SELECT is((SELECT array_agg(DISTINCT organization_id ORDER BY organization_id) FROM public.assets),
  ARRAY['a9200000-0000-0000-0000-000000000012', 'a9200000-0000-0000-0000-000000000013', 'a9200000-0000-0000-0000-000000000014',
        'a9200000-0000-0000-0000-0000000000a1', 'a9200000-0000-0000-0000-0000000000d1', 'a9200000-0000-0000-0000-0000000000f1']::uuid[],
  'assets.view: only the tenants actually delegated with assets.view are returned');
RESET ROLE;
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'a9700000-0000-0000-0000-0000000000aa';
SET LOCAL ROLE authenticated;
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'assets.view: suspended relationship hides the assets');
RESET ROLE;
UPDATE public.organization_relationships SET status = 'active' WHERE id = 'a9700000-0000-0000-0000-0000000000aa';

-- Tablas auxiliares
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT is((SELECT count(*) FROM public.asset_categories WHERE organization_id = 'a9200000-0000-0000-0000-0000000000a1'), 1::bigint, 'categories: FM manager reads Client A categories');
SELECT is((SELECT count(*) FROM public.asset_categories WHERE organization_id = 'a9200000-0000-0000-0000-0000000000b1'), 0::bigint, 'categories: not Client B');
SELECT throws_ok($$ INSERT INTO public.asset_categories (organization_id, name) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'FM cat') $$, '42501', NULL, 'categories: no delegated write');
SELECT is((SELECT count(*) FROM public.get_facility_management_client_branches('a9200000-0000-0000-0000-0000000000a1')), 1::bigint, 'branches: FM manager gets Client A branches through the RPC');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_client_branches('a9200000-0000-0000-0000-0000000000b1') $$, '42501', NULL, 'branches: not Client B');
SELECT is((SELECT count(*) FROM public.client_branches WHERE organization_id = 'a9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'branches: no direct table read (client_email stays private)');
SELECT throws_ok($$ INSERT INTO public.client_branches (organization_id, client_email, name, city, site) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'x@x.test', 'X', 'X', 'X') $$, '42501', NULL, 'branches: no delegated write');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT is((SELECT count(*) FROM public.asset_categories WHERE organization_id = 'a9200000-0000-0000-0000-0000000000a1'), 1::bigint, 'categories: FM technician reads Client A categories');
SELECT is((SELECT count(*) FROM public.get_facility_management_client_branches('a9200000-0000-0000-0000-0000000000a1')), 1::bigint, 'branches: FM technician gets Client A branches');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000008');
SELECT throws_ok($$ SELECT * FROM public.get_facility_management_client_branches('a9200000-0000-0000-0000-0000000000a1') $$, '42501', NULL, 'branches: FM viewer rejected');
RESET ROLE;
SELECT ok(pg_get_function_result('public.get_facility_management_client_branches(uuid)'::regprocedure) NOT ILIKE '%email%', 'branches: the RPC never returns client_email');

-- =========================================================================
-- 3. ASSETS.MANAGE (RLS + límites delegados)
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT lives_ok($$ INSERT INTO public.assets (id, organization_id, name, node_type, branch_id, asset_category_id, parent_asset_id, created_by_user_id)
  VALUES ('a9400000-0000-0000-0000-0000000000a3', 'a9200000-0000-0000-0000-0000000000a1', 'Creado por FM manager', 'component',
          'a9600000-0000-0000-0000-0000000000a1', 'a9500000-0000-0000-0000-0000000000a1', 'a9400000-0000-0000-0000-0000000000a1',
          'a9100000-0000-0000-0000-000000000006') $$,
  'manage: FM manager creates a Client A asset (with branch, category and parent)');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000005');
SELECT lives_ok($$ INSERT INTO public.assets (organization_id, name, node_type, created_by_user_id) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'Creado por FM admin', 'equipment', 'a9100000-0000-0000-0000-000000000005') $$, 'manage: FM admin creates');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000004');
SELECT lives_ok($$ INSERT INTO public.assets (organization_id, name, node_type, created_by_user_id) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'Creado por FM owner', 'equipment', 'a9100000-0000-0000-0000-000000000004') $$, 'manage: FM owner creates');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment') $$, '42501', NULL, 'manage: FM technician cannot create');
SELECT is(pg_temp.rename_asset('a9400000-0000-0000-0000-0000000000a2', 'tech'), 0, 'manage: FM technician cannot update');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000008');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment') $$, '42501', NULL, 'manage: FM viewer cannot create');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT is(pg_temp.rename_asset('a9400000-0000-0000-0000-0000000000a2', 'Renombrado por FM'), 1, 'manage: FM manager updates a Client A asset');
SELECT is(pg_temp.set_asset_status('a9400000-0000-0000-0000-0000000000a2', 'archived'), 1, 'manage: FM manager archives');
SELECT is(pg_temp.set_asset_status('a9400000-0000-0000-0000-0000000000a2', 'active'), 1, 'manage: FM manager restores');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000b1', 'X', 'equipment') $$, '42501', NULL, 'manage: cannot create for Client B');
SELECT is(pg_temp.rename_asset('a9400000-0000-0000-0000-0000000000b1', 'x'), 0, 'manage: cannot update a Client B asset');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000c1', 'X', 'equipment') $$, '42501', NULL, 'manage: assets.manage without assets.view cannot create');
SELECT is(pg_temp.rename_asset('a9400000-0000-0000-0000-0000000000c1', 'x'), 0, 'manage: assets.manage without assets.view cannot update');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000d1', 'X', 'equipment') $$, '42501', NULL, 'manage: assets.view alone cannot create');
SELECT is(pg_temp.rename_asset('a9400000-0000-0000-0000-0000000000d1', 'x'), 0, 'manage: assets.view alone cannot update');
SELECT throws_ok($$ UPDATE public.assets SET organization_id = 'a9200000-0000-0000-0000-0000000000b1' WHERE id = 'a9400000-0000-0000-0000-0000000000a1' $$, '42501', NULL, 'manage: cannot move a Client A asset into Client B');
SELECT throws_ok($$ UPDATE public.assets SET organization_id = 'a9200000-0000-0000-0000-0000000000f1' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$,
  '42501', 'A delegated writer cannot move an asset to another organization', 'manage: cannot move an asset between two clients it manages (trigger)');
SELECT throws_ok($$ DELETE FROM public.assets WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', NULL, 'manage: no DELETE (archiving is an UPDATE)');

-- Responsable predeterminado: CLIENT-ONLY
RESET ROLE;
UPDATE public.assets SET default_responsible_member_id = 'a9300000-0000-0000-0000-000000000002' WHERE id = 'a9400000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ UPDATE public.assets SET default_responsible_member_id = 'a9300000-0000-0000-0000-000000000001' WHERE id = 'a9400000-0000-0000-0000-0000000000a1' $$,
  '42501', 'The default responsible of an asset can only be set by the client organization', 'responsible: FM cannot change it');
SELECT throws_ok($$ UPDATE public.assets SET default_responsible_member_id = NULL WHERE id = 'a9400000-0000-0000-0000-0000000000a1' $$,
  '42501', 'The default responsible of an asset can only be set by the client organization', 'responsible: FM cannot clear it');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type, default_responsible_member_id) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment', 'a9300000-0000-0000-0000-000000000002') $$,
  '42501', 'The default responsible of an asset can only be set by the client organization', 'responsible: FM cannot set it on create');
SELECT is(pg_temp.rename_asset('a9400000-0000-0000-0000-0000000000a1', 'A1 editado por FM'), 1, 'responsible: FM still edits other fields of an asset that has a responsible');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000001');
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = 'a9300000-0000-0000-0000-000000000001' WHERE id = 'a9400000-0000-0000-0000-0000000000a1' $$, 'responsible: direct client owner keeps changing it');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ UPDATE public.assets SET default_responsible_member_id = NULL WHERE id = 'a9400000-0000-0000-0000-0000000000a1' $$, 'responsible: direct client manager keeps changing it');

-- asset_events (auditoría del flujo de Activos)
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT lives_ok($$ INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, created_by_user_id)
  VALUES ('a9200000-0000-0000-0000-0000000000a1', 'a9400000-0000-0000-0000-0000000000a2', 'updated', 'Activo actualizado.', 'a9100000-0000-0000-0000-000000000006') $$,
  'events: FM manager logs the legitimate event of a Client A asset');
SELECT throws_ok($$ INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, created_by_user_id)
  VALUES ('a9200000-0000-0000-0000-0000000000a1', 'a9400000-0000-0000-0000-0000000000a2', 'updated', 'x', 'a9100000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'events: cannot forge another actor');
SELECT throws_ok($$ INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, created_by_user_id)
  VALUES ('a9200000-0000-0000-0000-0000000000a1', 'a9400000-0000-0000-0000-0000000000a2', 'asset_default_responsible_changed', 'x', 'a9100000-0000-0000-0000-000000000006') $$,
  '42501', NULL, 'events: only the asset-flow event types');
SELECT throws_ok($$ INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, created_by_user_id)
  VALUES ('a9200000-0000-0000-0000-0000000000b1', 'a9400000-0000-0000-0000-0000000000b1', 'updated', 'x', 'a9100000-0000-0000-0000-000000000006') $$,
  'P0001', 'organization_id must match the organization_id of asset_id', 'events: not for Client B (the invoker consistency trigger cannot even see the asset)');
SELECT throws_ok($$ INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, created_by_user_id)
  VALUES ('a9200000-0000-0000-0000-0000000000a1', 'a9400000-0000-0000-0000-0000000000b1', 'updated', 'x', 'a9100000-0000-0000-0000-000000000006') $$,
  'P0001', 'organization_id must match the organization_id of asset_id', 'events: organization_id/asset_id mismatch rejected');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, created_by_user_id)
  VALUES ('a9200000-0000-0000-0000-0000000000a1', 'a9400000-0000-0000-0000-0000000000a2', 'updated', 'x', 'a9100000-0000-0000-0000-000000000007') $$,
  '42501', NULL, 'events: FM technician cannot log');
RESET ROLE;


-- =========================================================================
-- 3b. CRITICALITY NO SE BYPASSEA VÍA assets + ALLOWLIST DE COLUMNAS
--     (llamadas directas a tabla, como haría un PostgREST manual)
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
-- Client G: assets.view + assets.manage, sin criticidad.
SELECT throws_ok($$ UPDATE public.assets SET criticality = 'high' WHERE id = 'a9400000-0000-0000-0000-0000000000f1' $$,
  '42501', 'Changing the criticality of an asset requires the delegated criticality permissions',
  'crit-bypass: assets.view+manage without criticality permissions cannot change assets.criticality');
SELECT is(pg_temp.rename_asset('a9400000-0000-0000-0000-0000000000f1', 'G-1 renombrado'), 1, 'crit-bypass: ...but still edits other allowed columns');
SELECT throws_ok($$ UPDATE public.assets SET criticality = 'high' WHERE id = 'a9400000-0000-0000-0000-000000000013' $$,
  '42501', 'Changing the criticality of an asset requires the delegated criticality permissions', 'crit-bypass: criticality.view without manage => rejected');
SELECT throws_ok($$ UPDATE public.assets SET criticality = 'high' WHERE id = 'a9400000-0000-0000-0000-000000000014' $$,
  '42501', 'Changing the criticality of an asset requires the delegated criticality permissions', 'crit-bypass: criticality.manage without view => rejected');
SELECT is(pg_temp.set_criticality('a9400000-0000-0000-0000-0000000000a2', 'critical'), 1, 'crit-bypass: with assets + criticality view/manage => allowed');
SELECT is(pg_temp.set_criticality('a9400000-0000-0000-0000-0000000000a2', 'critical'), 1, 'crit-bypass: re-sending the same criticality is not a change (edit form sends it)');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type, criticality, created_by_user_id) VALUES ('a9200000-0000-0000-0000-0000000000f1', 'X', 'equipment', 'high', 'a9100000-0000-0000-0000-000000000006') $$,
  '42501', 'Changing the criticality of an asset requires the delegated criticality permissions', 'crit-bypass: INSERT with criticality follows the same rule (no criticality permissions)');
SELECT lives_ok($$ INSERT INTO public.assets (organization_id, name, node_type, criticality, created_by_user_id) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'Con criticidad', 'equipment', 'high', 'a9100000-0000-0000-0000-000000000006') $$,
  'crit-bypass: INSERT with criticality allowed with every criticality permission');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT is(pg_temp.set_criticality('a9400000-0000-0000-0000-0000000000a2', 'low'), 0, 'crit-bypass: FM technician cannot change criticality');

-- Allowlist de columnas en UPDATE delegado
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ UPDATE public.assets SET qr_code = 'x' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', 'A delegated writer cannot modify reserved asset columns: qr_code', 'columns: qr_code is reserved');
SELECT throws_ok($$ UPDATE public.assets SET image_url = 'https://x' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', 'A delegated writer cannot modify reserved asset columns: image_url', 'columns: image_url is reserved');
SELECT throws_ok($$ UPDATE public.assets SET metadata = '{"x":1}' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', 'A delegated writer cannot modify reserved asset columns: metadata', 'columns: metadata is reserved');
SELECT throws_ok($$ UPDATE public.assets SET technical_data = '{"x":1}' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', 'A delegated writer cannot modify reserved asset columns: technical_data', 'columns: technical_data is reserved');
SELECT throws_ok($$ UPDATE public.assets SET created_by_user_id = 'a9100000-0000-0000-0000-000000000006' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', 'A delegated writer cannot modify reserved asset columns: created_by_user_id', 'columns: created_by_user_id is reserved');
SELECT throws_ok($$ UPDATE public.assets SET created_at = now() - interval '1 year' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', 'A delegated writer cannot modify reserved asset columns: created_at', 'columns: created_at is reserved');
SELECT throws_ok($$ UPDATE public.assets SET id = gen_random_uuid() WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, '42501', 'A delegated writer cannot modify reserved asset columns: id', 'columns: id is reserved');
SELECT lives_ok($$ UPDATE public.assets SET name = 'A2 completo', node_type = 'system', status = 'maintenance', code = 'A-2b', description = 'd',
    manufacturer = 'm', model = 'mo', serial_number = 's', barcode = 'b', purchase_date = '2024-01-01', warranty_until = '2027-01-01',
    location_text = 'l', branch_id = 'a9600000-0000-0000-0000-0000000000a1', asset_category_id = 'a9500000-0000-0000-0000-0000000000a1',
    parent_asset_id = 'a9400000-0000-0000-0000-0000000000a1', updated_at = now()
  WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$, 'columns: every functional column of the Assets flow stays writable');

-- INSERT delegado
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment') $$,
  '42501', 'A delegated writer must create assets as itself (created_by_user_id)', 'insert: created_by_user_id is required and must be the caller');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type, created_by_user_id) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment', 'a9100000-0000-0000-0000-000000000001') $$,
  '42501', 'A delegated writer must create assets as itself (created_by_user_id)', 'insert: cannot attribute the asset to someone else');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type, created_by_user_id, qr_code) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment', 'a9100000-0000-0000-0000-000000000006', 'qr') $$,
  '42501', 'A delegated writer cannot preload qr_code or image_url', 'insert: cannot preload qr_code');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type, created_by_user_id, image_url) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment', 'a9100000-0000-0000-0000-000000000006', 'https://x') $$,
  '42501', 'A delegated writer cannot preload qr_code or image_url', 'insert: cannot preload image_url');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type, created_by_user_id, metadata) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment', 'a9100000-0000-0000-0000-000000000006', '{"x":1}') $$,
  '42501', 'A delegated writer cannot set metadata or technical_data', 'insert: cannot set metadata');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type, created_by_user_id, technical_data) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment', 'a9100000-0000-0000-0000-000000000006', '{"x":1}') $$,
  '42501', 'A delegated writer cannot set metadata or technical_data', 'insert: cannot set technical_data');
SELECT lives_ok($$ INSERT INTO public.assets (id, organization_id, name, node_type, created_by_user_id, created_at, updated_at)
  VALUES ('a9400000-0000-0000-0000-0000000000a9', 'a9200000-0000-0000-0000-0000000000a1', 'Fechas forzadas', 'equipment', 'a9100000-0000-0000-0000-000000000006', '2000-01-01', '2000-01-01') $$,
  'insert: forged timestamps are accepted but normalized');
RESET ROLE;
SELECT ok((SELECT created_at = now() AND updated_at = now() FROM public.assets WHERE id = 'a9400000-0000-0000-0000-0000000000a9'), 'insert: created_at/updated_at normalized to now()');
SELECT is((SELECT criticality FROM public.assets WHERE id = 'a9400000-0000-0000-0000-0000000000f1'), NULL::text, 'crit-bypass: the rejected criticality change left Client G untouched');

-- Cliente directo: comportamiento histórico intacto
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000002');
SELECT is(pg_temp.set_criticality('a9400000-0000-0000-0000-0000000000a1', 'low'), 1, 'direct: client manager still changes criticality manually');
SELECT lives_ok($$ UPDATE public.assets SET metadata = '{"direct":true}', technical_data = '{"direct":true}', qr_code = 'QR-A1' WHERE id = 'a9400000-0000-0000-0000-0000000000a1' $$,
  'direct: client manager still writes every column its historic RLS allows');
SELECT lives_ok($$ INSERT INTO public.assets (organization_id, name, node_type, criticality, metadata) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'Directo con criticidad', 'equipment', 'medium', '{"k":1}') $$,
  'direct: client manager still inserts with criticality/metadata and without created_by_user_id');
RESET ROLE;
-- =========================================================================
-- 4. CRITICALITY.VIEW
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT lives_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'crit.view: FM manager reads the Client A matrix');
SELECT lives_ok($$ SELECT public.get_criticality_thresholds('a9200000-0000-0000-0000-0000000000a1') $$, 'crit.view: FM manager reads thresholds');
SELECT lives_ok($$ SELECT * FROM public.get_criticality_templates('a9200000-0000-0000-0000-0000000000a1') $$, 'crit.view: FM manager lists templates');
SELECT lives_ok($$ SELECT * FROM public.get_asset_criticality_assessments('a9400000-0000-0000-0000-0000000000a1') $$, 'crit.view: FM manager reads assessment history');
SELECT lives_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000d1') $$, 'crit.view: criticality.view alone is enough to read');
SELECT throws_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000c1') $$, 'P0001', NULL, 'crit.view: criticality.manage without criticality.view gives no read');
SELECT throws_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000b1') $$, 'P0001', NULL, 'crit.view: not Client B');
SELECT throws_ok($$ SELECT * FROM public.get_asset_criticality_assessments('a9400000-0000-0000-0000-0000000000c1') $$, 'P0001', NULL, 'crit.view: no assessment history without the view permissions');
SELECT is((SELECT count(*) FROM public.criticality_parameters WHERE organization_id = 'a9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'crit.view: criticality tables stay RPC-only (no direct RLS read)');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'crit.view: FM owner reads');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000005');
SELECT lives_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'crit.view: FM admin reads');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'crit.view: FM technician cannot read the matrix');
SELECT throws_ok($$ SELECT * FROM public.get_asset_criticality_assessments('a9400000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'crit.view: FM technician cannot read assessment history');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000008');
SELECT throws_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'crit.view: FM viewer cannot read');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000009');
SELECT throws_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'crit.view: FM B cannot read Client A');

-- =========================================================================
-- 5. CRITICALITY.MANAGE (matriz)
-- =========================================================================
RESET ROLE;
SELECT cp.id AS param_a FROM public.criticality_parameters cp WHERE cp.organization_id = 'a9200000-0000-0000-0000-0000000000a1' AND cp.is_active \gset
SELECT cpo.id AS option_a FROM public.criticality_parameter_options cpo WHERE cpo.parameter_id = :'param_a' AND cpo.code = 's25' \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT (public.create_template_from_current_matrix('a9200000-0000-0000-0000-0000000000a1', 'Plantilla FM')).id AS template_a \gset
SELECT isnt(:'template_a'::uuid, NULL::uuid, 'crit.manage: create template from matrix');
SELECT lives_ok($$ SELECT public.upsert_criticality_parameter('a9200000-0000-0000-0000-0000000000a1', 'Parámetro FM', NULL, 0, 2) $$, 'crit.manage: upsert parameter');
SELECT lives_ok(format($$ SELECT public.upsert_criticality_option(%L, 'Opción FM', 50, 3) $$, :'param_a'), 'crit.manage: upsert option');
SELECT lives_ok(format($$ SELECT public.set_criticality_option_active(%L, false) $$, :'option_a'), 'crit.manage: deactivate option');
SELECT lives_ok(format($$ SELECT public.set_criticality_option_active(%L, true) $$, :'option_a'), 'crit.manage: reactivate option');
SELECT lives_ok(format($$ SELECT public.set_criticality_parameter_active(%L, false) $$, :'param_a'), 'crit.manage: deactivate parameter');
SELECT lives_ok(format($$ SELECT public.set_criticality_parameter_active(%L, true) $$, :'param_a'), 'crit.manage: reactivate parameter');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-0000000000a1', 30, 60, 80) $$, 'crit.manage: thresholds');
SELECT lives_ok($$ SELECT public.clear_active_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'crit.manage: clear matrix');
SELECT lives_ok(format($$ SELECT public.apply_criticality_template('a9200000-0000-0000-0000-0000000000a1', %L) $$, :'template_a'), 'crit.manage: apply template');
SELECT lives_ok($$ SELECT public.replace_criticality_configuration('a9200000-0000-0000-0000-0000000000a1', (SELECT payload FROM test_matrix), '{"medium_min":25,"high_min":50,"critical_min":75}') $$, 'crit.manage: replace/import configuration');
SELECT lives_ok($$ SELECT public.upsert_criticality_parameter('a9200000-0000-0000-0000-000000000011', 'Solo criticidad', NULL, 0, 1) $$, 'crit.manage: criticality.view + criticality.manage without assets.* still manage the matrix');
SELECT throws_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-0000000000c1', 30, 60, 80) $$, 'P0001', NULL, 'crit.manage: criticality.manage without criticality.view cannot mutate');
SELECT throws_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-0000000000d1', 30, 60, 80) $$, 'P0001', NULL, 'crit.manage: criticality.view alone cannot mutate');
SELECT throws_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-0000000000b1', 30, 60, 80) $$, 'P0001', NULL, 'crit.manage: not Client B');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000005');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-0000000000a1', 25, 50, 75) $$, 'crit.manage: FM admin manages');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-0000000000a1', 25, 50, 75) $$, 'crit.manage: FM owner manages');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT throws_ok($$ SELECT public.upsert_criticality_parameter('a9200000-0000-0000-0000-0000000000a1', 'X', NULL, 0, 9) $$, 'P0001', NULL, 'crit.manage: FM technician cannot mutate');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000009');
SELECT throws_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-0000000000a1', 30, 60, 80) $$, 'P0001', NULL, 'crit.manage: FM B cannot mutate Client A');
RESET ROLE;

-- =========================================================================
-- 6. EVALUACIÓN DE CRITICIDAD DE ACTIVOS
-- =========================================================================
SELECT jsonb_build_array(jsonb_build_object('parameter_id', cp.id, 'option_id', cpo.id)) AS answers_a
FROM public.criticality_parameters cp
JOIN public.criticality_parameter_options cpo ON cpo.parameter_id = cp.id AND cpo.is_active AND cpo.code = 's75'
WHERE cp.organization_id = 'a9200000-0000-0000-0000-0000000000a1' AND cp.is_active AND cp.code = 'P1' \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT lives_ok(format($$ SELECT * FROM public.preview_bulk_asset_criticality('a9200000-0000-0000-0000-0000000000a1',
  jsonb_build_array(jsonb_build_object('row_number', 1, 'asset_id', 'a9400000-0000-0000-0000-0000000000a1', 'answers', %L::jsonb))) $$, :'answers_a'),
  'assess: FM manager previews');
SELECT lives_ok(format($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-0000000000a1', %L::jsonb, 'fm eval') $$, :'answers_a'), 'assess: FM manager calculates and saves');
SELECT lives_ok(format($$ SELECT public.bulk_calculate_asset_criticality('a9200000-0000-0000-0000-0000000000a1',
  jsonb_build_array(jsonb_build_object('row_number', 1, 'asset_id', 'a9400000-0000-0000-0000-0000000000a2', 'answers', %L::jsonb))) $$, :'answers_a'),
  'assess: FM manager bulk-calculates');
SELECT ok((SELECT count(*) FROM public.get_asset_criticality_assessments('a9400000-0000-0000-0000-0000000000a1')) >= 1, 'assess: FM manager reads the new assessment in history');
SELECT throws_ok($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-000000000011', '[]'::jsonb, NULL) $$, 'P0001', NULL, 'assess: without assets.view cannot evaluate even with criticality.manage');
SELECT throws_ok($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-0000000000d1', '[]'::jsonb, NULL) $$, 'P0001', NULL, 'assess: without criticality.manage cannot evaluate');
SELECT throws_ok($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-0000000000c1', '[]'::jsonb, NULL) $$, 'P0001', NULL, 'assess: without the view permissions cannot evaluate');
SELECT throws_ok($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-0000000000b1', '[]'::jsonb, NULL) $$, 'P0001', NULL, 'assess: not a Client B asset');
SELECT throws_ok($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-000000000012', '[]'::jsonb, NULL) $$, 'P0001', NULL, 'assess: assets.view + criticality.manage WITHOUT criticality.view cannot evaluate');
SELECT throws_ok($$ SELECT * FROM public.get_asset_criticality_assessments('a9400000-0000-0000-0000-000000000012') $$, 'P0001', NULL, 'assess: ...nor read assessment history');
SELECT throws_ok($$ SELECT public.set_criticality_thresholds('a9200000-0000-0000-0000-000000000012', 30, 60, 80) $$, 'P0001', NULL, 'assess: ...nor manage the matrix');
SELECT throws_ok($$ SELECT public.bulk_calculate_asset_criticality('a9200000-0000-0000-0000-0000000000b1', '[]'::jsonb) $$, 'P0001', NULL, 'assess: no bulk on Client B');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000007');
SELECT throws_ok(format($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-0000000000a1', %L::jsonb, NULL) $$, :'answers_a'), 'P0001', NULL, 'assess: FM technician cannot calculate');
SELECT throws_ok(format($$ SELECT * FROM public.preview_bulk_asset_criticality('a9200000-0000-0000-0000-0000000000a1',
  jsonb_build_array(jsonb_build_object('row_number', 1, 'asset_id', 'a9400000-0000-0000-0000-0000000000a1', 'answers', %L::jsonb))) $$, :'answers_a'),
  'P0001', NULL, 'assess: FM technician cannot preview');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 8::bigint, 'assess: the FM technician still sees the Client A assets');
RESET ROLE;

-- =========================================================================
-- 7. REGRESIÓN DEL ACCESO DIRECTO
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000001');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 8::bigint, 'direct: client owner sees every Client A asset (incl. the ones created by the FM)');
SELECT lives_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'direct: client owner reads the matrix');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'Creado por cliente', 'equipment') $$, 'direct: client manager creates assets');
SELECT lives_ok(format($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-0000000000a1', %L::jsonb, 'direct eval') $$, :'answers_a'), 'direct: client manager evaluates criticality');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000003');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 9::bigint, 'direct: client technician keeps reading assets');
SELECT throws_ok($$ INSERT INTO public.assets (organization_id, name, node_type) VALUES ('a9200000-0000-0000-0000-0000000000a1', 'X', 'equipment') $$, '42501', NULL, 'direct: client technician still cannot create');
SELECT lives_ok($$ SELECT public.get_criticality_matrix('a9200000-0000-0000-0000-0000000000a1') $$, 'direct: client technician keeps reading the matrix (historic rule)');
SELECT lives_ok($$ SELECT * FROM public.get_asset_criticality_assessments('a9400000-0000-0000-0000-0000000000a1') $$, 'direct: client technician keeps reading assessment history (historic rule)');
SELECT throws_ok(format($$ SELECT public.calculate_asset_criticality('a9400000-0000-0000-0000-0000000000a1', %L::jsonb, NULL) $$, :'answers_a'), 'P0001', NULL, 'direct: client technician still cannot evaluate');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-00000000000b');
SELECT is(pg_temp.visible_assets('a9200000-0000-0000-0000-0000000000a1'), 9::bigint, 'direct: platform admin keeps its read access');
RESET ROLE;

-- =========================================================================
-- 8. SIN FUGAS A OTROS MÓDULOS (assets.view no abre nada más)
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ SELECT * FROM public.get_asset_traffic_light('a9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: traffic light (OT/inspections) stays closed');
SELECT throws_ok($$ SELECT * FROM public.get_asset_integrated_history('a9400000-0000-0000-0000-0000000000a2') $$, 'P0001', NULL, 'no leak: integrated asset history stays closed');
SELECT throws_ok($$ SELECT public.get_preventive_maintenance_plans('a9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: preventive maintenance stays closed');
SELECT throws_ok($$ SELECT * FROM public.get_maintenance_notices('a9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: maintenance notices stay closed');
SELECT throws_ok($$ SELECT * FROM public.get_inspection_plans('a9200000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'no leak: inspections stay closed');
SELECT throws_ok($$ SELECT public.authorize_asset_file_access('a9400000-0000-0000-0000-0000000000a1', 'read') $$, 'P0001', NULL, 'no leak: R2 asset files stay closed');
SELECT is((SELECT count(*) FROM public.asset_events WHERE organization_id = 'a9200000-0000-0000-0000-0000000000a1'), 0::bigint, 'no leak: asset_events are not readable by the FM');
RESET ROLE;

-- =========================================================================
-- 9. ESTRUCTURA Y GRANTS
-- =========================================================================
SELECT ok(has_function_privilege('authenticated', 'public.has_facility_management_operational_access(uuid, public.facility_management_permission, public.organization_member_role[])', 'EXECUTE')
  AND has_function_privilege('authenticated', 'public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[])', 'EXECUTE'),
  'grants: authenticated executes the helpers (needed by RLS)');
SELECT ok(NOT has_function_privilege('anon', 'public.has_facility_management_operational_access(uuid, public.facility_management_permission, public.organization_member_role[])', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[])', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.get_facility_management_client_branches(uuid)', 'EXECUTE'),
  'grants: anon executes none of the new public functions');
SELECT ok(has_function_privilege('authenticated', 'public.get_facility_management_client_branches(uuid)', 'EXECUTE'), 'grants: authenticated executes the branches RPC');
SELECT is((SELECT count(*) FROM pg_proc p WHERE p.oid IN (
    'public.can_view_criticality_matrix(uuid)'::regprocedure, 'public.can_manage_criticality_matrix(uuid)'::regprocedure,
    'public.can_view_asset_criticality_assessments(uuid)'::regprocedure, 'public.can_evaluate_asset_criticality(uuid)'::regprocedure,
    'public.enforce_delegated_asset_write_limits()'::regprocedure, 'public.check_asset_consistency()'::regprocedure)
  AND has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0::bigint,
  'grants: internal capability/trigger functions are not executable by authenticated');
SELECT is((SELECT count(*) FROM pg_proc p, aclexplode(p.proacl) a WHERE a.grantee = 0 AND p.oid IN (
    'public.has_facility_management_operational_access(uuid, public.facility_management_permission, public.organization_member_role[])'::regprocedure,
    'public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[])'::regprocedure,
    'public.get_facility_management_client_branches(uuid)'::regprocedure,
    'public.can_view_criticality_matrix(uuid)'::regprocedure, 'public.can_manage_criticality_matrix(uuid)'::regprocedure,
    'public.can_view_asset_criticality_assessments(uuid)'::regprocedure, 'public.can_evaluate_asset_criticality(uuid)'::regprocedure,
    'public.enforce_delegated_asset_write_limits()'::regprocedure, 'public.check_asset_consistency()'::regprocedure)), 0::bigint,
  'grants: PUBLIC executes none of the new/replaced functions');
SELECT ok((SELECT p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%') FROM pg_proc p
  WHERE p.oid = 'public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[])'::regprocedure),
  'helper is SECURITY DEFINER with a pinned search_path');
SELECT ok(pg_get_function_arguments('public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[])'::regprocedure) NOT ILIKE '%user%'
  AND pg_get_function_arguments('public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[])'::regprocedure) NOT ILIKE '%member_id%',
  'helper takes no user/membership id');
SELECT policies_are('public', 'assets', ARRAY[
  'organization members can view assets', 'organization managers can create assets', 'organization managers can update assets',
  'facility managers can view delegated assets', 'facility managers can create delegated assets', 'facility managers can update delegated assets'],
  'assets: direct policies kept, delegated ones added');
SELECT ok(NOT has_table_privilege('authenticated', 'public.assets', 'DELETE')
  AND NOT has_table_privilege('authenticated', 'public.client_branches', 'INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('authenticated', 'public.asset_criticality_assessments', 'INSERT,UPDATE,DELETE'),
  'grants: no new table write privileges');
SELECT has_trigger('public', 'assets', 'trg_assets_enforce_delegated_write_limits', 'the delegated write-limits trigger exists');
SELECT ok((SELECT p.prosecdef AND p.proconfig = ARRAY['search_path=""'] FROM pg_proc p WHERE p.oid = 'public.check_asset_consistency()'::regprocedure),
  'check_asset_consistency: SECURITY DEFINER with an empty search_path');
SELECT ok(NOT has_function_privilege('anon', 'public.check_asset_consistency()', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.check_asset_consistency()', 'EXECUTE'),
  'check_asset_consistency: no direct EXECUTE for anon/authenticated (runs only as a trigger)');
SELECT ok((SELECT prosrc FROM pg_proc WHERE oid = 'public.check_asset_consistency()'::regprocedure) LIKE '%FROM public.assets WHERE id = NEW.parent_asset_id%'
  AND (SELECT prosrc FROM pg_proc WHERE oid = 'public.check_asset_consistency()'::regprocedure) LIKE '%FROM public.asset_categories WHERE id = NEW.asset_category_id%'
  AND (SELECT prosrc FROM pg_proc WHERE oid = 'public.check_asset_consistency()'::regprocedure) LIKE '%FROM public.client_branches WHERE id = NEW.branch_id%',
  'check_asset_consistency: same three schema-qualified checks as before');
SELECT has_trigger('public', 'assets', 'trg_assets_check_consistency', 'check_asset_consistency still runs as the assets trigger');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000006');
SELECT throws_ok($$ UPDATE public.assets SET branch_id = 'a9600000-0000-0000-0000-0000000000b1' WHERE id = 'a9400000-0000-0000-0000-0000000000a2' $$,
  'P0001', 'branch_id must belong to the same organization_id', 'check_asset_consistency: a cross-tenant branch is still rejected for the FM');
SELECT pg_temp.as_user('a9100000-0000-0000-0000-000000000002');
SELECT throws_ok($$ UPDATE public.assets SET branch_id = 'a9600000-0000-0000-0000-0000000000b1' WHERE id = 'a9400000-0000-0000-0000-0000000000a1' $$,
  'P0001', 'branch_id must belong to the same organization_id', 'check_asset_consistency: ...and for a direct client member');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
