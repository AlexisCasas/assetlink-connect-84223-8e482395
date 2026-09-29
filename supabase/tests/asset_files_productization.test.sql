-- Fase 1 · Punto 10 — Fotos y documentos de activos sobre R2
-- (…_asset_files_productization.sql). Se ejecuta con: supabase test db --local
--
-- Cada intento corre como `authenticated` con un auth.uid() sintético.
-- Los rechazos de autorización son RAISE sin código (P0001) con mensajes
-- estables que asset-files traduce a HTTP.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(101);

-- -------------------------------------------------------------------------
-- Fixture (sintético, se descarta con el ROLLBACK final)
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('f1100000-0000-0000-0000-000000000001', 'ca-owner@files.test'),
  ('f1100000-0000-0000-0000-000000000002', 'ca-manager@files.test'),
  ('f1100000-0000-0000-0000-000000000003', 'ca-technician@files.test'),
  ('f1100000-0000-0000-0000-000000000004', 'ca-viewer@files.test'),
  ('f1100000-0000-0000-0000-000000000005', 'ca-manager-inactive@files.test'),
  ('f1100000-0000-0000-0000-000000000011', 'fa-owner@files.test'),
  ('f1100000-0000-0000-0000-000000000012', 'fa-admin@files.test'),
  ('f1100000-0000-0000-0000-000000000013', 'fa-manager@files.test'),
  ('f1100000-0000-0000-0000-000000000014', 'fa-technician@files.test'),
  ('f1100000-0000-0000-0000-000000000015', 'fa-viewer@files.test'),
  ('f1100000-0000-0000-0000-000000000016', 'fa-requester@files.test'),
  ('f1100000-0000-0000-0000-000000000017', 'fa-manager-unassigned@files.test'),
  ('f1100000-0000-0000-0000-000000000018', 'fa-technician-inactive@files.test'),
  ('f1100000-0000-0000-0000-000000000021', 'fb-manager@files.test'),
  ('f1100000-0000-0000-0000-000000000031', 'cb-owner@files.test'),
  ('f1100000-0000-0000-0000-000000000041', 'outsider@files.test'),
  ('f1100000-0000-0000-0000-000000000051', 'platform@files.test');

INSERT INTO public.organizations (id, name, organization_type) VALUES
  ('f1200000-0000-0000-0000-0000000000a1', 'Client A', 'client_company'),
  ('f1200000-0000-0000-0000-0000000000b1', 'Client B', 'client_company'),
  ('f1200000-0000-0000-0000-0000000000c1', 'Client C (manage sin view)', 'client_company'),
  ('f1200000-0000-0000-0000-0000000000d1', 'Client D (relación suspendida)', 'client_company'),
  ('f1200000-0000-0000-0000-0000000000e1', 'Client E (solo view)', 'client_company'),
  ('f1200000-0000-0000-0000-0000000000fa', 'FM A', 'facility_manager'),
  ('f1200000-0000-0000-0000-0000000000fb', 'FM B', 'facility_manager'),
  ('f1200000-0000-0000-0000-0000000000ff', 'Plataforma', 'platform_admin');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('f1300000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-0000000000a1', 'f1100000-0000-0000-0000-000000000001', 'owner', true),
  ('f1300000-0000-0000-0000-000000000002', 'f1200000-0000-0000-0000-0000000000a1', 'f1100000-0000-0000-0000-000000000002', 'manager', true),
  ('f1300000-0000-0000-0000-000000000003', 'f1200000-0000-0000-0000-0000000000a1', 'f1100000-0000-0000-0000-000000000003', 'technician', true),
  ('f1300000-0000-0000-0000-000000000004', 'f1200000-0000-0000-0000-0000000000a1', 'f1100000-0000-0000-0000-000000000004', 'viewer', true),
  ('f1300000-0000-0000-0000-000000000005', 'f1200000-0000-0000-0000-0000000000a1', 'f1100000-0000-0000-0000-000000000005', 'manager', false),
  ('f1300000-0000-0000-0000-000000000011', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000011', 'owner', true),
  ('f1300000-0000-0000-0000-000000000012', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000012', 'admin', true),
  ('f1300000-0000-0000-0000-000000000013', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000013', 'manager', true),
  ('f1300000-0000-0000-0000-000000000014', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000014', 'technician', true),
  ('f1300000-0000-0000-0000-000000000015', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000015', 'viewer', true),
  ('f1300000-0000-0000-0000-000000000016', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000016', 'requester', true),
  ('f1300000-0000-0000-0000-000000000017', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000017', 'manager', true),
  ('f1300000-0000-0000-0000-000000000018', 'f1200000-0000-0000-0000-0000000000fa', 'f1100000-0000-0000-0000-000000000018', 'technician', true),
  ('f1300000-0000-0000-0000-000000000021', 'f1200000-0000-0000-0000-0000000000fb', 'f1100000-0000-0000-0000-000000000021', 'manager', true),
  ('f1300000-0000-0000-0000-000000000031', 'f1200000-0000-0000-0000-0000000000b1', 'f1100000-0000-0000-0000-000000000031', 'owner', true),
  ('f1300000-0000-0000-0000-000000000051', 'f1200000-0000-0000-0000-0000000000ff', 'f1100000-0000-0000-0000-000000000051', 'owner', true);

INSERT INTO public.assets (id, organization_id, name, node_type, status) VALUES
  ('f1400000-0000-0000-0000-0000000000a1', 'f1200000-0000-0000-0000-0000000000a1', 'Activo A1', 'equipment', 'active'),
  ('f1400000-0000-0000-0000-0000000000a2', 'f1200000-0000-0000-0000-0000000000a1', 'Activo A2 (sin fotos)', 'equipment', 'active'),
  ('f1400000-0000-0000-0000-0000000000a9', 'f1200000-0000-0000-0000-0000000000a1', 'Activo A9 archivado', 'equipment', 'archived'),
  ('f1400000-0000-0000-0000-0000000000b1', 'f1200000-0000-0000-0000-0000000000b1', 'Activo B1', 'equipment', 'active'),
  ('f1400000-0000-0000-0000-0000000000c1', 'f1200000-0000-0000-0000-0000000000c1', 'Activo C1', 'equipment', 'active'),
  ('f1400000-0000-0000-0000-0000000000d1', 'f1200000-0000-0000-0000-0000000000d1', 'Activo D1', 'equipment', 'active'),
  ('f1400000-0000-0000-0000-0000000000e1', 'f1200000-0000-0000-0000-0000000000e1', 'Activo E1', 'equipment', 'active');

INSERT INTO public.organization_relationships (id, source_organization_id, target_organization_id, relationship_type, status) VALUES
  ('f1700000-0000-0000-0000-0000000000aa', 'f1200000-0000-0000-0000-0000000000a1', 'f1200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('f1700000-0000-0000-0000-0000000000bb', 'f1200000-0000-0000-0000-0000000000b1', 'f1200000-0000-0000-0000-0000000000fb', 'facility_management', 'pending'),
  ('f1700000-0000-0000-0000-0000000000ca', 'f1200000-0000-0000-0000-0000000000c1', 'f1200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('f1700000-0000-0000-0000-0000000000da', 'f1200000-0000-0000-0000-0000000000d1', 'f1200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending'),
  ('f1700000-0000-0000-0000-0000000000ea', 'f1200000-0000-0000-0000-0000000000e1', 'f1200000-0000-0000-0000-0000000000fa', 'facility_management', 'pending');
INSERT INTO public.facility_management_permissions (relationship_id, permission) VALUES
  ('f1700000-0000-0000-0000-0000000000aa', 'assets.view'), ('f1700000-0000-0000-0000-0000000000aa', 'assets.manage'),
  ('f1700000-0000-0000-0000-0000000000bb', 'assets.view'), ('f1700000-0000-0000-0000-0000000000bb', 'assets.manage'),
  ('f1700000-0000-0000-0000-0000000000ca', 'assets.manage'),
  ('f1700000-0000-0000-0000-0000000000da', 'assets.view'), ('f1700000-0000-0000-0000-0000000000da', 'assets.manage'),
  ('f1700000-0000-0000-0000-0000000000ea', 'assets.view');
INSERT INTO public.facility_management_relationship_members (relationship_id, organization_member_id)
SELECT 'f1700000-0000-0000-0000-0000000000aa'::uuid, m::uuid FROM unnest(ARRAY[
  'f1300000-0000-0000-0000-000000000011', 'f1300000-0000-0000-0000-000000000012', 'f1300000-0000-0000-0000-000000000013',
  'f1300000-0000-0000-0000-000000000014', 'f1300000-0000-0000-0000-000000000015', 'f1300000-0000-0000-0000-000000000016',
  'f1300000-0000-0000-0000-000000000018']) m
UNION ALL SELECT 'f1700000-0000-0000-0000-0000000000bb', 'f1300000-0000-0000-0000-000000000021'
UNION ALL SELECT r::uuid, 'f1300000-0000-0000-0000-000000000013' FROM unnest(ARRAY[
  'f1700000-0000-0000-0000-0000000000ca', 'f1700000-0000-0000-0000-0000000000da', 'f1700000-0000-0000-0000-0000000000ea']) r;
UPDATE public.organization_relationships SET status = 'active' WHERE id::text LIKE 'f1700000-%';
UPDATE public.organization_relationships SET status = 'suspended' WHERE id = 'f1700000-0000-0000-0000-0000000000da';
UPDATE public.organization_members SET is_active = false WHERE id = 'f1300000-0000-0000-0000-000000000018';

CREATE FUNCTION pg_temp.key(p_org text, p_asset text, p_kind text, p_id text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT 'organizations/' || p_org || '/assets/' || p_asset || '/' || CASE p_kind WHEN 'photo' THEN 'photos/' || p_id || '.jpg' ELSE 'documents/' || p_id || '.pdf' END;
$$;

-- Archivos: A1 (principal, secundaria, documento, pendiente, fallido),
-- A9 archivado, B1, C1, E1.
INSERT INTO public.asset_documents (id, organization_id, asset_id, kind, name, storage_path, content_type, size_bytes, etag, status, is_primary, uploaded_by_user_id, confirmed_at, created_at) VALUES
  ('f1500000-0000-0000-0000-0000000000a1', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'principal.jpg',
   pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'f1600000-0000-0000-0000-0000000000a1'), 'image/jpeg', 1000, '"e1"', 'available', true, 'f1100000-0000-0000-0000-000000000001', now(), now() - interval '3 days'),
  ('f1500000-0000-0000-0000-0000000000a2', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'secundaria.jpg',
   pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'f1600000-0000-0000-0000-0000000000a2'), 'image/jpeg', 2000, '"e2"', 'available', false, 'f1100000-0000-0000-0000-000000000001', now(), now() - interval '2 days'),
  ('f1500000-0000-0000-0000-0000000000a3', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'document', 'manual.pdf',
   pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'document', 'f1600000-0000-0000-0000-0000000000a3'), 'application/pdf', 3000, '"e3"', 'available', false, 'f1100000-0000-0000-0000-000000000001', now(), now() - interval '1 day'),
  ('f1500000-0000-0000-0000-0000000000a4', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'pendiente.jpg',
   pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'f1600000-0000-0000-0000-0000000000a4'), 'image/jpeg', NULL, NULL, 'pending', false, 'f1100000-0000-0000-0000-000000000001', NULL, now()),
  ('f1500000-0000-0000-0000-0000000000a5', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'document', 'fallido.pdf',
   pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'document', 'f1600000-0000-0000-0000-0000000000a5'), 'application/pdf', NULL, NULL, 'failed', false, 'f1100000-0000-0000-0000-000000000001', NULL, now()),
  ('f1500000-0000-0000-0000-0000000000a9', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a9', 'photo', 'archivado.jpg',
   pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a9', 'photo', 'f1600000-0000-0000-0000-0000000000a9'), 'image/jpeg', 900, '"e9"', 'available', true, 'f1100000-0000-0000-0000-000000000001', now(), now()),
  ('f1500000-0000-0000-0000-0000000000b1', 'f1200000-0000-0000-0000-0000000000b1', 'f1400000-0000-0000-0000-0000000000b1', 'photo', 'cliente-b.jpg',
   pg_temp.key('f1200000-0000-0000-0000-0000000000b1', 'f1400000-0000-0000-0000-0000000000b1', 'photo', 'f1600000-0000-0000-0000-0000000000b1'), 'image/jpeg', 800, '"eb"', 'available', true, 'f1100000-0000-0000-0000-000000000031', now(), now()),
  ('f1500000-0000-0000-0000-0000000000c1', 'f1200000-0000-0000-0000-0000000000c1', 'f1400000-0000-0000-0000-0000000000c1', 'photo', 'cliente-c.jpg',
   pg_temp.key('f1200000-0000-0000-0000-0000000000c1', 'f1400000-0000-0000-0000-0000000000c1', 'photo', 'f1600000-0000-0000-0000-0000000000c1'), 'image/jpeg', 700, '"ec"', 'available', false, NULL, now(), now()),
  ('f1500000-0000-0000-0000-0000000000e1', 'f1200000-0000-0000-0000-0000000000e1', 'f1400000-0000-0000-0000-0000000000e1', 'photo', 'cliente-e.jpg',
   pg_temp.key('f1200000-0000-0000-0000-0000000000e1', 'f1400000-0000-0000-0000-0000000000e1', 'photo', 'f1600000-0000-0000-0000-0000000000e1'), 'image/jpeg', 600, '"ee"', 'available', false, NULL, now(), now());

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
$$;
-- ¿Autorizado? (true / false) sin abortar la suite.
CREATE FUNCTION pg_temp.can(p_asset uuid, p_op text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN PERFORM public.authorize_asset_file_access(p_asset, p_op); RETURN true;
EXCEPTION WHEN OTHERS THEN RETURN false; END $$;
-- Filas afectadas por un DML directo; 0 si el entorno no otorga el GRANT.
CREATE FUNCTION pg_temp.dml_rows(p_sql text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v integer; BEGIN EXECUTE p_sql; GET DIAGNOSTICS v = ROW_COUNT; RETURN v;
EXCEPTION WHEN insufficient_privilege THEN RETURN 0; END $$;
-- INSERT directo bloqueado por cualquier motivo (sin GRANT, RLS o constraint).
CREATE FUNCTION pg_temp.insert_blocked(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v integer; BEGIN EXECUTE p_sql; GET DIAGNOSTICS v = ROW_COUNT; RETURN v = 0;
EXCEPTION WHEN OTHERS THEN RETURN true; END $$;
CREATE FUNCTION pg_temp.files(p_asset uuid) RETURNS SETOF text LANGUAGE sql AS $$
  SELECT f.name FROM public.get_asset_files(p_asset) f ORDER BY f.name;
$$;

-- =========================================================================
-- 0. Estructura, grants e invariantes
-- =========================================================================
SELECT ok((SELECT bool_and(p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
                AND NOT has_function_privilege('anon', p.oid, 'EXECUTE') AND array_to_string(p.proconfig, ',') = 'search_path=""')
           FROM pg_proc p WHERE p.oid IN (
             'public.authorize_asset_file_access(uuid,text)'::regprocedure, 'public.authorize_asset_file_operation(uuid,text)'::regprocedure,
             'public.get_asset_files(uuid)'::regprocedure, 'public.set_asset_primary_photo(uuid)'::regprocedure)),
  'entrypoints: SECURITY DEFINER, empty search_path, authenticated only (never anon)');
SELECT ok((SELECT bool_and(NOT has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
           FROM pg_proc p WHERE p.oid IN (
             'public.can_access_asset_files(uuid,text)'::regprocedure, 'public.asset_file_mark_available(uuid,bigint,text,text)'::regprocedure,
             'public.asset_file_begin_delete(uuid)'::regprocedure, 'public.asset_file_finish_delete(uuid)'::regprocedure,
             'public.asset_file_mark_failed(uuid)'::regprocedure)),
  'internal helpers and lifecycle functions: no EXECUTE for authenticated/anon');
SELECT ok((SELECT bool_and(has_function_privilege('service_role', p.oid, 'EXECUTE'))
           FROM pg_proc p WHERE p.oid IN (
             'public.asset_file_mark_available(uuid,bigint,text,text)'::regprocedure, 'public.asset_file_begin_delete(uuid)'::regprocedure,
             'public.asset_file_finish_delete(uuid)'::regprocedure, 'public.asset_file_mark_failed(uuid)'::regprocedure)),
  'lifecycle functions: service_role only (asset-files, after authorizing the caller)');
SELECT ok(has_table_privilege('service_role', 'public.asset_documents', 'SELECT')
      AND has_table_privilege('service_role', 'public.asset_documents', 'INSERT')
      AND has_table_privilege('service_role', 'public.assets', 'SELECT'),
  'service_role: explicit SELECT + INSERT on asset_documents and SELECT on assets (independent of the environment default ACL)');
-- Exactly what asset-files does as service_role: INSERT the pending row
-- (through the historic org-consistency trigger, which reads assets) with
-- RETURNING. Rolled back via a sub-transaction: fixtures stay intact.
CREATE FUNCTION pg_temp.service_pending_insert_probe() RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  BEGIN
    INSERT INTO public.asset_documents (organization_id, asset_id, kind, name, storage_path, content_type, status, uploaded_by_user_id)
    VALUES ('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'sonda.jpg',
            pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'f1600000-0000-0000-0000-0000000000f9'),
            'image/jpeg', 'pending', 'f1100000-0000-0000-0000-000000000001')
    RETURNING id INTO v_id;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'probe rollback';
  EXCEPTION WHEN raise_exception THEN
    RETURN CASE WHEN v_id IS NOT NULL THEN 'inserted' ELSE 'no id' END;
  WHEN OTHERS THEN
    RETURN SQLSTATE;
  END;
END $$;
SET LOCAL ROLE service_role;
SELECT is(pg_temp.service_pending_insert_probe(), 'inserted',
  'service_role can create the pending row with RETURNING (asset-files create-upload), rolled back');
RESET ROLE;
SELECT is((SELECT array_agg(cmd::text ORDER BY cmd) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'asset_documents'), ARRAY['SELECT'],
  'asset_documents: only the historic SELECT policy remains (no raw INSERT/UPDATE/DELETE policy)');
SELECT ok((SELECT bool_and(COALESCE(qual, '') !~ 'facility_management') FROM pg_policies WHERE schemaname = 'public' AND tablename = 'asset_documents'),
  'asset_documents: no raw read policy for the Facility Manager');
SELECT ok((SELECT count(*) = 6 FROM pg_constraint WHERE conrelid = 'public.asset_documents'::regclass AND conname IN (
             'asset_documents_kind_check', 'asset_documents_status_check', 'asset_documents_size_bytes_check',
             'asset_documents_primary_photo_check', 'asset_documents_r2_shape_check', 'asset_documents_available_confirmed_check'))
      AND (SELECT count(*) = 2 FROM pg_indexes WHERE tablename = 'asset_documents' AND indexname IN ('asset_documents_storage_path_key', 'asset_documents_one_primary_photo')),
  'asset_documents: metadata constraints and unique indexes exist');
SELECT is(
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND (has_table_privilege('anon', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       OR has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'))),
  0::bigint, '9C.1H preserved: no meta privileges for anon/authenticated');

SET LOCAL ROLE authenticated;

-- =========================================================================
-- 1. Acceso directo del cliente (sin regresión)
-- =========================================================================
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000001');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'direct owner: read/write/delete');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000002');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'direct manager: read/write/delete');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000003');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'direct technician: read only');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000004');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'direct viewer: read only');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000005');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'direct inactive membership: not even read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000001');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a9', 'read') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a9', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a9', 'delete'), 'archived asset: read yes, write/delete no (even the owner)');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000051');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read') AND pg_temp.can('f1400000-0000-0000-0000-0000000000b1', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a9', 'write'), 'platform admin: preserved (and still blocked on archived)');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000031');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read') AND pg_temp.can('f1400000-0000-0000-0000-0000000000b1', 'write'), 'Client B owner: its own asset yes, Client A no');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000041');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'outsider: no access');

-- =========================================================================
-- 2. Facility Manager: lectura (assets.view, o/a/m/technician)
-- =========================================================================
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000011');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM owner: read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000012');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM admin: read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM manager: read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000014');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM technician: read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000015');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM viewer: no read (9C.1 matrix)');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000016');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM requester: no read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000017');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM manager not assigned: no read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000018');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read'), 'FM technician with inactive membership: no read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000c1', 'read'), 'FM manager with assets.manage WITHOUT assets.view: no read');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000d1', 'read'), 'FM manager on a suspended relationship: no read');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000b1', 'read'), 'FM A manager on Client B: no read');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000021');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'read') AND pg_temp.can('f1400000-0000-0000-0000-0000000000b1', 'read'), 'FM B: its client yes, Client A no');

-- =========================================================================
-- 3. Facility Manager: escritura/borrado (assets.view + assets.manage, o/a/m)
-- =========================================================================
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000011');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'FM owner: write/delete');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000012');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'FM admin: write/delete');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT ok(pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'FM manager: write/delete');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000c1', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000c1', 'delete'), 'FM manager with manage WITHOUT view: no write/delete');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000e1', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000e1', 'delete') AND pg_temp.can('f1400000-0000-0000-0000-0000000000e1', 'read'), 'FM manager with view only: read yes, write/delete no');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a9', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a9', 'delete') AND pg_temp.can('f1400000-0000-0000-0000-0000000000a9', 'read'), 'FM manager on an archived asset: read yes, write/delete no');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000014');
SELECT ok(NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'write') AND NOT pg_temp.can('f1400000-0000-0000-0000-0000000000a1', 'delete'), 'FM technician: no write/delete');

-- =========================================================================
-- 4. authorize_asset_file_operation (contrato por file_id, sin enumeración)
-- =========================================================================
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT is(public.authorize_asset_file_operation('f1500000-0000-0000-0000-0000000000a3', 'read'), 'f1200000-0000-0000-0000-0000000000a1'::uuid, 'file_id: FM manager reads a Client A document');
SELECT is(public.authorize_asset_file_operation('f1500000-0000-0000-0000-0000000000a3', 'delete'), 'f1200000-0000-0000-0000-0000000000a1'::uuid, 'file_id: FM manager may delete it');
SELECT throws_ok($$ SELECT public.authorize_asset_file_operation('f1500000-0000-0000-0000-0000000000b1', 'read') $$, 'P0001', 'File not found', 'file_id: another tenant''s file => "File not found"');
SELECT throws_ok($$ SELECT public.authorize_asset_file_operation(gen_random_uuid(), 'read') $$, 'P0001', 'File not found', 'file_id: a missing file => the same "File not found" (no enumeration)');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.authorize_asset_file_operation('f1500000-0000-0000-0000-0000000000a3', 'delete') $$, 'P0001', 'Not authorized to delete files for this asset',
  'file_id: FM technician (can read) cannot delete');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.authorize_asset_file_operation('f1500000-0000-0000-0000-0000000000a9', 'delete') $$, 'P0001', 'Cannot delete files on an archived asset',
  'file_id: an archived asset''s file cannot be deleted');

-- =========================================================================
-- 5. get_asset_files: listado minimizado
-- =========================================================================
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000001');
SELECT results_eq($$ SELECT * FROM pg_temp.files('f1400000-0000-0000-0000-0000000000a1') $$, ARRAY['fallido.pdf', 'manual.pdf', 'pendiente.jpg', 'principal.jpg', 'secundaria.jpg'],
  'list (direct owner, can manage): available + operational statuses');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000004');
SELECT results_eq($$ SELECT * FROM pg_temp.files('f1400000-0000-0000-0000-0000000000a1') $$, ARRAY['manual.pdf', 'principal.jpg', 'secundaria.jpg'],
  'list (direct viewer): available only');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT results_eq($$ SELECT * FROM pg_temp.files('f1400000-0000-0000-0000-0000000000a1') $$, ARRAY['fallido.pdf', 'manual.pdf', 'pendiente.jpg', 'principal.jpg', 'secundaria.jpg'],
  'list (FM manager, can manage): available + operational statuses');
SELECT results_eq($$ SELECT * FROM pg_temp.files('f1400000-0000-0000-0000-0000000000a9') $$, ARRAY['archivado.jpg'], 'list (FM manager, archived asset): readable');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000014');
SELECT results_eq($$ SELECT * FROM pg_temp.files('f1400000-0000-0000-0000-0000000000a1') $$, ARRAY['manual.pdf', 'principal.jpg', 'secundaria.jpg'],
  'list (FM technician): available only');
SELECT ok((SELECT bool_and(NOT (to_jsonb(f) ?| ARRAY['storage_path', 'file_url', 'uploaded_by_user_id', 'organization_id', 'etag'])) FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000a1') f)
      AND (SELECT string_agg(to_jsonb(f)::text, '') FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000a1') f) !~ 'organizations/|f1100000-0000-0000-0000-000000000001',
  'list payload: no storage_path, file_url, uploader, org or etag');
SELECT is((SELECT count(*) FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000a1') f WHERE f.is_primary), 1::bigint, 'list: exactly one primary photo');
SELECT is((SELECT count(*) FROM public.asset_documents), 0::bigint, 'raw table: the FM reads no asset_documents row (uses get_asset_files)');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000021');
SELECT throws_ok($$ SELECT * FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'list: FM B cannot list Client A');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000031');
SELECT throws_ok($$ SELECT * FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'list: Client B owner cannot list Client A');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000017');
SELECT throws_ok($$ SELECT * FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000a1') $$, 'P0001', NULL, 'list: FM manager not assigned cannot list');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT * FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000c1') $$, 'P0001', NULL, 'list: manage without view cannot list');

-- =========================================================================
-- 6. Foto principal
-- =========================================================================
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT lives_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a2') $$, 'primary: FM manager sets the secondary photo as primary');
SELECT results_eq($$ SELECT name FROM public.get_asset_files('f1400000-0000-0000-0000-0000000000a1') WHERE is_primary $$, ARRAY['secundaria.jpg'], 'primary: switched atomically (old one unset)');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000001');
SELECT lives_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a1') $$, 'primary: direct owner sets it back');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a1') $$, 'primary: direct manager (already primary => no-op)');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000014');
SELECT throws_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a2') $$, 'P0001', 'Not authorized to write files for this asset', 'primary: FM technician cannot');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000003');
SELECT throws_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a2') $$, 'P0001', 'Not authorized to write files for this asset', 'primary: direct technician cannot');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT throws_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000c1') $$, 'P0001', 'File not found', 'primary: FM manage without view cannot (file not even visible)');
SELECT throws_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a3') $$, '22023', NULL, 'primary: a document can never be primary');
SELECT throws_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a4') $$, '22023', NULL, 'primary: a pending photo cannot be primary');
SELECT throws_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000a9') $$, 'P0001', 'Cannot write files on an archived asset', 'primary: archived asset => rejected');
SELECT throws_ok($$ SELECT public.set_asset_primary_photo('f1500000-0000-0000-0000-0000000000b1') $$, 'P0001', 'File not found', 'primary: a Client B file => "File not found"');
RESET ROLE;
SELECT is((SELECT count(*) FROM (SELECT asset_id FROM public.asset_documents WHERE is_primary GROUP BY asset_id HAVING count(*) > 1) x), 0::bigint,
  'primary invariant: never more than one primary photo per asset');
SELECT is((SELECT name FROM public.asset_documents WHERE asset_id = 'f1400000-0000-0000-0000-0000000000a1' AND is_primary), 'principal.jpg', 'primary: final state is the one set last');

-- =========================================================================
-- 7. Sin escritura raw desde el navegador (independiente de los GRANT)
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000001');
SELECT ok(pg_temp.insert_blocked(format($q$ INSERT INTO public.asset_documents (organization_id, asset_id, kind, name, storage_path, content_type, size_bytes, status, confirmed_at)
            VALUES (%L, %L, 'photo', 'forjada.jpg', %L, 'image/jpeg', 1, 'available', now()) $q$,
            'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a1', 'photo', 'f1600000-0000-0000-0000-0000000000f1'))),
  'raw: even the direct owner cannot INSERT an "available" R2 row');
SELECT is(pg_temp.dml_rows($q$ UPDATE public.asset_documents SET status = 'available', size_bytes = 1, confirmed_at = now() WHERE id = 'f1500000-0000-0000-0000-0000000000a4' $q$), 0,
  'raw: pending => available cannot be forged');
SELECT is(pg_temp.dml_rows($q$ UPDATE public.asset_documents SET is_primary = true WHERE id = 'f1500000-0000-0000-0000-0000000000a2' $q$), 0, 'raw: is_primary cannot be forged');
SELECT is(pg_temp.dml_rows($q$ UPDATE public.asset_documents SET storage_path = 'organizations/x', etag = 'forged' WHERE id = 'f1500000-0000-0000-0000-0000000000a3' $q$), 0,
  'raw: storage_path/etag cannot be forged');
SELECT is(pg_temp.dml_rows($q$ DELETE FROM public.asset_documents WHERE id = 'f1500000-0000-0000-0000-0000000000a3' $q$), 0, 'raw: rows cannot be deleted directly');
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000013');
SELECT is(pg_temp.dml_rows($q$ UPDATE public.asset_documents SET status = 'available' WHERE id = 'f1500000-0000-0000-0000-0000000000a4' $q$), 0, 'raw: the FM cannot forge either');
RESET ROLE;
SELECT results_eq($$ SELECT status, is_primary, storage_path LIKE 'organizations/f1200000-0000-0000-0000-0000000000a1/%', etag FROM public.asset_documents WHERE id IN ('f1500000-0000-0000-0000-0000000000a2', 'f1500000-0000-0000-0000-0000000000a3', 'f1500000-0000-0000-0000-0000000000a4') ORDER BY id $$,
  $$ VALUES ('available'::text, false, true, '"e2"'::text), ('available', false, true, '"e3"'), ('pending', false, true, NULL) $$,
  'raw: rows are untouched');
SELECT is((SELECT count(*) FROM public.asset_documents WHERE name = 'forjada.jpg'), 0::bigint, 'raw: no forged row exists');

-- =========================================================================
-- 8. Invariantes de metadata (aunque escriba el backend)
-- =========================================================================
SELECT throws_ok($$ UPDATE public.asset_documents SET is_primary = true WHERE id = 'f1500000-0000-0000-0000-0000000000a3' $$, '23514', NULL, 'invariant: a document cannot be primary');
SELECT throws_ok($$ UPDATE public.asset_documents SET is_primary = true WHERE id = 'f1500000-0000-0000-0000-0000000000a2' $$, '23505', NULL, 'invariant: two primary photos are impossible');
SELECT throws_ok($$ UPDATE public.asset_documents SET is_primary = true WHERE id = 'f1500000-0000-0000-0000-0000000000a4' $$, '23514', NULL, 'invariant: a pending photo cannot be primary');
SELECT throws_ok($$ UPDATE public.asset_documents SET storage_path = pg_temp.key('f1200000-0000-0000-0000-0000000000b1', 'f1400000-0000-0000-0000-0000000000b1', 'photo', 'f1600000-0000-0000-0000-0000000000f2') WHERE id = 'f1500000-0000-0000-0000-0000000000a2' $$,
  '23514', NULL, 'invariant: storage_path must match the row''s organization/asset/kind');
SELECT throws_ok($$ UPDATE public.asset_documents SET file_url = 'https://x.r2.cloudflarestorage.com/k?X-Amz-Signature=abc' WHERE id = 'f1500000-0000-0000-0000-0000000000a2' $$,
  '23514', NULL, 'invariant: an R2 row never stores a URL (signed or not)');
SELECT throws_ok($$ UPDATE public.asset_documents SET status = 'available' WHERE id = 'f1500000-0000-0000-0000-0000000000a4' $$, '23514', NULL, 'invariant: available requires real size + confirmation');
SELECT throws_ok($$ UPDATE public.asset_documents SET storage_path = (SELECT d.storage_path FROM public.asset_documents d WHERE d.id = 'f1500000-0000-0000-0000-0000000000a1') WHERE id = 'f1500000-0000-0000-0000-0000000000a2' $$,
  '23505', NULL, 'invariant: storage_path is unique');

-- =========================================================================
-- 9. Lifecycle interno (service_role)
-- =========================================================================
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f1100000-0000-0000-0000-000000000001');
SELECT throws_ok($$ SELECT public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000a4', 10, 'image/jpeg', '"x"') $$, '42501', NULL, 'lifecycle: authenticated cannot mark available');
SELECT throws_ok($$ SELECT public.asset_file_begin_delete('f1500000-0000-0000-0000-0000000000a2') $$, '42501', NULL, 'lifecycle: authenticated cannot start a delete');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT ok((SELECT status = 'available' AND NOT is_primary AND size_bytes = 1234 AND etag = '"real"' AND confirmed_at IS NOT NULL
           FROM public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000a4', 1234, 'image/jpeg', '"real"')),
  'lifecycle: pending => available with the REAL size/etag; not primary (one already exists)');
SELECT ok((SELECT status = 'available' FROM public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000a4', 1234, 'image/jpeg', '"real"')), 'lifecycle: confirm is idempotent');
SELECT throws_ok($$ SELECT public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000a5', 10, 'application/pdf', NULL) $$, '55000', NULL, 'lifecycle: a failed file cannot become available');
RESET ROLE;
INSERT INTO public.asset_documents (id, organization_id, asset_id, kind, name, storage_path, content_type, status, uploaded_by_user_id, created_at) VALUES
  ('f1500000-0000-0000-0000-0000000000f1', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a2', 'photo', 'primera.jpg', pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a2', 'photo', 'f1600000-0000-0000-0000-0000000000f3'), 'image/jpeg', 'pending', 'f1100000-0000-0000-0000-000000000013', now() - interval '2 hours'),
  ('f1500000-0000-0000-0000-0000000000f2', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a2', 'photo', 'segunda.jpg', pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a2', 'photo', 'f1600000-0000-0000-0000-0000000000f4'), 'image/jpeg', 'pending', 'f1100000-0000-0000-0000-000000000013', now() - interval '1 hour'),
  ('f1500000-0000-0000-0000-0000000000f3', 'f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a2', 'photo', 'tercera.jpg', pg_temp.key('f1200000-0000-0000-0000-0000000000a1', 'f1400000-0000-0000-0000-0000000000a2', 'photo', 'f1600000-0000-0000-0000-0000000000f5'), 'image/jpeg', 'pending', 'f1100000-0000-0000-0000-000000000013', now());
SET LOCAL ROLE service_role;
SELECT throws_ok($$ SELECT public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000f1', 50, 'image/png', NULL) $$, '22023', NULL, 'lifecycle: confirm never changes the declared type');
SELECT ok((SELECT is_primary FROM public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000f1', 50, 'image/jpeg', NULL)), 'lifecycle: the first available photo of an asset becomes primary');
SELECT ok((SELECT NOT is_primary FROM public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000f3', 70, 'image/jpeg', NULL)), 'lifecycle: a later one does not steal it');
SELECT ok((SELECT NOT is_primary FROM public.asset_file_mark_available('f1500000-0000-0000-0000-0000000000f2', 60, 'image/jpeg', NULL)), 'lifecycle: nor does another');
SELECT ok((SELECT status = 'deleting' AND NOT is_primary FROM public.asset_file_begin_delete('f1500000-0000-0000-0000-0000000000f1')), 'lifecycle: deleting the primary => deleting, unmarked');
SELECT is((SELECT name FROM public.asset_documents WHERE asset_id = 'f1400000-0000-0000-0000-0000000000a2' AND is_primary), 'segunda.jpg', 'lifecycle: the OLDEST remaining available photo is promoted');
SELECT ok((SELECT status = 'deleting' FROM public.asset_file_begin_delete('f1500000-0000-0000-0000-0000000000f1')), 'lifecycle: begin delete is idempotent (retryable)');
SELECT lives_ok($$ SELECT public.asset_file_finish_delete('f1500000-0000-0000-0000-0000000000f1') $$, 'lifecycle: finish delete removes the metadata');
SELECT throws_ok($$ SELECT public.asset_file_finish_delete('f1500000-0000-0000-0000-0000000000f2') $$, '55000', NULL, 'lifecycle: finish delete requires the deleting state');
SELECT lives_ok($$ SELECT public.asset_file_begin_delete('f1500000-0000-0000-0000-0000000000f2'); SELECT public.asset_file_begin_delete('f1500000-0000-0000-0000-0000000000f3') $$, 'lifecycle: deleting the remaining photos');
SELECT is((SELECT count(*) FROM public.asset_documents WHERE asset_id = 'f1400000-0000-0000-0000-0000000000a2' AND is_primary), 0::bigint, 'lifecycle: no available photos left => no primary');
SELECT lives_ok($$ SELECT public.asset_file_mark_failed('f1500000-0000-0000-0000-0000000000a5') $$, 'lifecycle: mark failed is a no-op outside pending');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.asset_documents WHERE id = 'f1500000-0000-0000-0000-0000000000f1'), 0::bigint, 'lifecycle: the deleted row is gone');
SELECT * FROM finish();
ROLLBACK;
