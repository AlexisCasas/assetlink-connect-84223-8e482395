-- =========================================================================
-- Public table meta-privilege hardening (Fase 1 · Punto 9C.1H)
--
-- Hallazgo (producción): 55 de las 72 tablas de public conceden a anon y a
-- authenticated, además de SELECT/INSERT/UPDATE/DELETE (parte del modelo
-- PostgREST + RLS), cuatro privilegios de objeto que ninguna superficie de
-- la app usa: TRUNCATE, REFERENCES, TRIGGER y MAINTAIN (PostgreSQL 17+).
-- Los default privileges de tablas de public para los owners postgres y
-- supabase_admin conceden a anon/authenticated CRUD + esos cuatro.
--
-- RLS filtra FILAS para SELECT/INSERT/UPDATE/DELETE; no interviene en
-- TRUNCATE (vacía la tabla entera), REFERENCES, TRIGGER ni MAINTAIN
-- (VACUUM/ANALYZE/CLUSTER/REINDEX), que se autorizan sólo por GRANT. Por eso
-- se revocan en el nivel de GRANT.
--
-- Alcance: se retiran ÚNICAMENTE esos cuatro privilegios, de PUBLIC, anon y
-- authenticated. SELECT/INSERT/UPDATE/DELETE se conservan tal como estén en
-- cada entorno (tablas y default ACL); service_role, owners, RLS, policies,
-- sequences y functions no se tocan.
--
-- supabase_admin: ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin exige
-- poder asumir ese rol. En Supabase (local y hosted) el rol que aplica las
-- migraciones, postgres, no puede; entonces se omite con un NOTICE y ese
-- default ACL queda pendiente de plataforma/operación. Hoy ninguna tabla de
-- public pertenece a supabase_admin. Ver
-- docs/PUBLIC_TABLE_META_PRIVILEGE_HARDENING.md.
-- =========================================================================

-- 1) Tablas existentes de public (las 72 actuales; no-op donde no estaba).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON ALL TABLES IN SCHEMA public
  FROM PUBLIC, anon, authenticated;

-- 2) Tablas futuras creadas por postgres (todas las migraciones del repo).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON TABLES
  FROM PUBLIC, anon, authenticated;

-- 3) Tablas futuras creadas por supabase_admin: sólo si el rol actual puede
--    asumirlo; si no, se informa y se continúa sin fallar.
DO $$
BEGIN
  IF to_regrole('supabase_admin') IS NULL THEN
    RAISE NOTICE 'public_table_meta_privilege_hardening: role supabase_admin does not exist; nothing to do for its default privileges.';
  ELSIF pg_has_role(current_user, 'supabase_admin', 'SET') THEN
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
      REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
      ON TABLES
      FROM PUBLIC, anon, authenticated;
    RAISE NOTICE 'public_table_meta_privilege_hardening: supabase_admin default privileges on public tables hardened.';
  ELSE
    RAISE NOTICE 'public_table_meta_privilege_hardening: role % cannot modify the default privileges of supabase_admin; they still grant TRUNCATE/REFERENCES/TRIGGER/MAINTAIN on new public tables to anon/authenticated. Pending platform/operations action. No public table is owned by supabase_admin today, so the existing tables are hardened by step 1.', current_user;
  END IF;
END $$;
