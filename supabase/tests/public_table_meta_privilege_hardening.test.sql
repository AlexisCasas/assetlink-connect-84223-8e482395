-- Public table meta-privilege hardening
-- (20260928062721_public_table_meta_privilege_hardening.sql).
-- Se ejecuta con: supabase test db --local
--
-- No asume el baseline local como producción: el default ACL de postgres
-- concede CRUD a anon/authenticated en producción y no en el Supabase local.
-- Las aserciones exigen la AUSENCIA de TRUNCATE/REFERENCES/TRIGGER/MAINTAIN
-- y que CRUD no dependa de esta migración, sin fijar un CRUD concreto donde
-- difiere entre entornos.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(33);

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;

-- has_table_privilege con una lista devuelve true si tiene CUALQUIERA; esto
-- exige TODOS.
CREATE FUNCTION pg_temp.has_all(p_role text, p_table text, p_privs text[]) RETURNS boolean
LANGUAGE sql AS $$
  SELECT bool_and(has_table_privilege(p_role, p_table, p)) FROM unnest(p_privs) p;
$$;

CREATE FUNCTION pg_temp.default_acl(p_owner text, p_grantee text) RETURNS text[]
LANGUAGE sql AS $$
  SELECT coalesce(array_agg(a.privilege_type ORDER BY a.privilege_type), ARRAY[]::text[])
  FROM pg_default_acl d, LATERAL aclexplode(d.defaclacl) a
  WHERE d.defaclrole = p_owner::regrole AND d.defaclnamespace = 'public'::regnamespace
    AND d.defaclobjtype = 'r' AND a.grantee = p_grantee::regrole;
$$;

CREATE FUNCTION pg_temp.can_set_supabase_admin() RETURNS boolean LANGUAGE sql AS $$
  SELECT to_regrole('supabase_admin') IS NOT NULL AND pg_has_role(current_user, 'supabase_admin', 'SET');
$$;

-- Sentencias de esta migración tal como quedaron registradas, sin comentarios.
CREATE FUNCTION pg_temp.migration_sql() RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(regexp_replace(s, '--[^\n]*', '', 'g'), E'\n')
  FROM supabase_migrations.schema_migrations m, unnest(m.statements) s
  WHERE m.version = '20260928062721';
$$;

-- -------------------------------------------------------------------------
-- 1. Tablas existentes: ninguna tabla de public concede los cuatro
--    privilegios a PUBLIC/anon/authenticated.
-- -------------------------------------------------------------------------
SELECT is(
  (SELECT coalesce(array_agg(c.relname::text ORDER BY c.relname), ARRAY[]::text[])
   FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND has_table_privilege('anon', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')),
  ARRAY[]::text[],
  'anon: ninguna tabla de public conserva TRUNCATE/REFERENCES/TRIGGER/MAINTAIN');

SELECT is(
  (SELECT coalesce(array_agg(c.relname::text ORDER BY c.relname), ARRAY[]::text[])
   FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND has_table_privilege('authenticated', c.oid, 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')),
  ARRAY[]::text[],
  'authenticated: ninguna tabla de public conserva TRUNCATE/REFERENCES/TRIGGER/MAINTAIN');

SELECT is(
  (SELECT coalesce(array_agg(c.relname::text ORDER BY c.relname), ARRAY[]::text[])
   FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, LATERAL aclexplode(c.relacl) a
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
     AND a.grantee = 0 AND a.privilege_type IN ('TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')),
  ARRAY[]::text[],
  'PUBLIC: ninguna tabla de public le concede TRUNCATE/REFERENCES/TRIGGER/MAINTAIN');

SELECT ok(
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','p')) >= 70,
  'guard: se examinaron al menos 70 tablas de public');

-- -------------------------------------------------------------------------
-- 2. CRUD no se destruye. Superficies representativas: se exige el CRUD que
--    usa la app (mínimo), no un conjunto exacto que difiere entre entornos.
--    Las tablas endurecidas por 20260926203242 sí tienen un contrato exacto
--    (REVOKE + GRANT explícitos), igual en todo entorno.
-- -------------------------------------------------------------------------
SELECT ok(pg_temp.has_all('authenticated', 'public.assets', ARRAY['SELECT','INSERT','UPDATE']),
  'assets: authenticated conserva SELECT/INSERT/UPDATE');
SELECT ok(pg_temp.has_all('authenticated', 'public.quotes', ARRAY['SELECT','INSERT','UPDATE','DELETE']),
  'quotes: authenticated conserva SELECT/INSERT/UPDATE/DELETE');
SELECT ok(pg_temp.has_all('authenticated', 'public.requests', ARRAY['SELECT','INSERT','UPDATE','DELETE']),
  'requests: authenticated conserva SELECT/INSERT/UPDATE/DELETE');
SELECT ok(pg_temp.has_all('authenticated', 'public.work_orders', ARRAY['SELECT']),
  'work_orders: authenticated conserva SELECT');

SELECT table_privs_are('public', 'organization_members', 'authenticated', ARRAY['SELECT'],
  'organization_members: contrato previo exacto sin cambios (solo SELECT)');
SELECT table_privs_are('public', 'organizations', 'authenticated', ARRAY['SELECT'],
  'organizations: contrato previo sin UPDATE de tabla completa');
SELECT ok(has_column_privilege('authenticated', 'public.organizations', 'name', 'UPDATE'),
  'organizations: authenticated conserva UPDATE(name)');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organizations', 'organization_type', 'UPDATE'),
  'organizations: authenticated sigue sin UPDATE(organization_type)');

-- La migración nunca retira CRUD ni hace un REVOKE total: todo REVOKE que
-- contiene enumera sólo los cuatro privilegios (revisión de sus sentencias
-- registradas, válida en cualquier entorno).
SELECT ok(pg_temp.migration_sql() ~* 'REVOKE',
  'la migración está registrada en supabase_migrations con sus sentencias');
SELECT is(
  (SELECT coalesce(array_agg(DISTINCT upper(btrim(p)) ORDER BY upper(btrim(p))), ARRAY[]::text[])
   FROM regexp_matches(pg_temp.migration_sql(), 'REVOKE\s+((?:[A-Za-z]+\s*,\s*)*[A-Za-z]+)\s+ON\s', 'gi') m,
        LATERAL regexp_split_to_table(m[1], ',') p),
  ARRAY['MAINTAIN','REFERENCES','TRIGGER','TRUNCATE'],
  'la migración sólo revoca TRUNCATE/REFERENCES/TRIGGER/MAINTAIN (sin REVOKE ALL ni CRUD)');

-- -------------------------------------------------------------------------
-- 3. Default ACL de postgres: sin los cuatro privilegios para PUBLIC/anon/
--    authenticated. El CRUD que tenga cada entorno no se evalúa aquí (se
--    conserva, ver la aserción anterior y la tabla futura de la sección 6).
-- -------------------------------------------------------------------------
SELECT is(
  (SELECT coalesce(array_agg(DISTINCT a.grantee::regrole::text || ':' || a.privilege_type), ARRAY[]::text[])
   FROM pg_default_acl d, LATERAL aclexplode(d.defaclacl) a
   WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'r'
     AND a.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
     AND a.privilege_type IN ('TRUNCATE','REFERENCES','TRIGGER','MAINTAIN')),
  ARRAY[]::text[],
  'default ACL postgres/public: PUBLIC/anon/authenticated sin TRUNCATE/REFERENCES/TRIGGER/MAINTAIN');

SELECT ok(pg_temp.default_acl('postgres', 'postgres')
            @> ARRAY['DELETE','INSERT','MAINTAIN','REFERENCES','SELECT','TRIGGER','TRUNCATE','UPDATE'],
  'default ACL postgres/public: el owner postgres conserva sus privilegios por defecto');

SELECT ok(pg_temp.default_acl('postgres', 'service_role') @> ARRAY['MAINTAIN','REFERENCES','TRIGGER','TRUNCATE'],
  'default ACL postgres/public: service_role conserva sus privilegios (no se tocó)');

-- -------------------------------------------------------------------------
-- 4. Default ACL de supabase_admin. Si el rol actual puede asumirlo, los
--    cuatro deben haber desaparecido; si no (Supabase local y hosted), queda
--    pendiente de plataforma y lo que se verifica es que ninguna tabla de
--    public le pertenece, así que las 72 existentes sí quedaron endurecidas.
-- -------------------------------------------------------------------------
SELECT ok(
  CASE WHEN pg_temp.can_set_supabase_admin() THEN
    NOT (pg_temp.default_acl('supabase_admin', 'anon') && ARRAY['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'])
    AND NOT (pg_temp.default_acl('supabase_admin', 'authenticated') && ARRAY['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'])
  ELSE
    NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND c.relowner = 'supabase_admin'::regrole)
  END,
  'default ACL supabase_admin/public: sin los cuatro privilegios si es modificable; si no, ninguna tabla le pertenece');

-- relkind r/p: excluye tipos compuestos como dblink_pkey_results.
SELECT is((SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind IN ('r','p') AND c.relowner = 'supabase_admin'::regrole), 0::bigint,
  'ninguna tabla de public pertenece a supabase_admin');

-- Tabla futura de supabase_admin: sólo se puede crear si el rol actual
-- puede asumirlo; si no, se omite (limitación documentada).
CREATE FUNCTION pg_temp.supabase_admin_future_table_check() RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  EXECUTE 'SET LOCAL ROLE supabase_admin';
  EXECUTE 'CREATE TABLE public.zz_meta_privilege_future_test_sa (id integer)';
  EXECUTE 'RESET ROLE';
  v_ok := NOT has_table_privilege('anon', 'public.zz_meta_privilege_future_test_sa', 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
      AND NOT has_table_privilege('authenticated', 'public.zz_meta_privilege_future_test_sa', 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN');
  EXECUTE 'DROP TABLE public.zz_meta_privilege_future_test_sa';
  RETURN ok(v_ok, 'tabla futura creada por supabase_admin: anon/authenticated sin TRUNCATE/REFERENCES/TRIGGER/MAINTAIN');
END $$;

SELECT CASE WHEN pg_temp.can_set_supabase_admin()
  THEN pg_temp.supabase_admin_future_table_check()
  ELSE skip('el rol actual no puede asumir supabase_admin: su default ACL queda pendiente de plataforma (documentado)', 1)
END;

-- -------------------------------------------------------------------------
-- 5. service_role: su baseline no se tocó.
-- -------------------------------------------------------------------------
SELECT ok(pg_temp.has_all('service_role', 'public.organization_members', ARRAY['SELECT','INSERT','UPDATE','DELETE']),
  'service_role conserva SELECT/INSERT/UPDATE/DELETE en organization_members');
SELECT ok(pg_temp.has_all('service_role', 'public.organizations', ARRAY['SELECT','INSERT','UPDATE','DELETE']),
  'service_role conserva SELECT/INSERT/UPDATE/DELETE en organizations');
SELECT ok(pg_temp.has_all('service_role', 'public.assets', ARRAY['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']),
  'service_role conserva sus meta-privilegios en assets (no se revocaron)');

-- -------------------------------------------------------------------------
-- 6. Tabla futura creada por postgres + ejecución real.
-- -------------------------------------------------------------------------
SET LOCAL ROLE postgres;
CREATE TABLE public.zz_meta_privilege_future_test (id integer);
CREATE UNIQUE INDEX zz_meta_privilege_future_test_idx ON public.zz_meta_privilege_future_test (id);
RESET ROLE;

SELECT ok(
  NOT has_table_privilege('anon', 'public.zz_meta_privilege_future_test', 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
  AND NOT has_table_privilege('authenticated', 'public.zz_meta_privilege_future_test', 'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'),
  'tabla futura (postgres): anon/authenticated nacen sin TRUNCATE/REFERENCES/TRIGGER/MAINTAIN');

-- El CRUD con el que nace es exactamente el que concede el default ACL de
-- postgres en ese entorno (producción: CRUD; local: ninguno).
SELECT is(
  ARRAY(SELECT p FROM unnest(ARRAY['DELETE','INSERT','SELECT','UPDATE']) p
        WHERE has_table_privilege('anon', 'public.zz_meta_privilege_future_test', p) ORDER BY p),
  ARRAY(SELECT p FROM unnest(pg_temp.default_acl('postgres', 'anon')) p
        WHERE p IN ('DELETE','INSERT','SELECT','UPDATE') ORDER BY p),
  'tabla futura: anon recibe exactamente el CRUD del default ACL de postgres');
SELECT is(
  ARRAY(SELECT p FROM unnest(ARRAY['DELETE','INSERT','SELECT','UPDATE']) p
        WHERE has_table_privilege('authenticated', 'public.zz_meta_privilege_future_test', p) ORDER BY p),
  ARRAY(SELECT p FROM unnest(pg_temp.default_acl('postgres', 'authenticated')) p
        WHERE p IN ('DELETE','INSERT','SELECT','UPDATE') ORDER BY p),
  'tabla futura: authenticated recibe exactamente el CRUD del default ACL de postgres');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000001');
SELECT throws_ok($$ TRUNCATE public.zz_meta_privilege_future_test $$, '42501', NULL,
  'authenticated no puede TRUNCATE una tabla futura');
SELECT throws_ok($$ REINDEX TABLE public.zz_meta_privilege_future_test $$, '42501', NULL,
  'authenticated no puede REINDEX (MAINTAIN) una tabla futura');
RESET ROLE;

SET LOCAL ROLE anon;
SELECT throws_ok($$ TRUNCATE public.zz_meta_privilege_future_test $$, '42501', NULL,
  'anon no puede TRUNCATE una tabla futura');
SELECT throws_ok($$ REINDEX TABLE public.zz_meta_privilege_future_test $$, '42501', NULL,
  'anon no puede REINDEX (MAINTAIN) una tabla futura');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a1000000-0000-0000-0000-000000000001');
SELECT throws_ok($$ TRUNCATE public.assets $$, '42501', NULL,
  'authenticated no puede TRUNCATE assets (tabla existente)');
SELECT throws_ok($$ REINDEX TABLE public.assets $$, '42501', NULL,
  'authenticated no puede REINDEX (MAINTAIN) assets (tabla existente)');
RESET ROLE;

SET LOCAL ROLE anon;
SELECT throws_ok($$ TRUNCATE public.assets $$, '42501', NULL,
  'anon no puede TRUNCATE assets (tabla existente)');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
