-- =========================================================================
-- Organization access hardening (Fase 1 · Punto 6, prerrequisito)
--
-- Vulnerabilidad: organizations, organization_members,
-- organization_invitations, activity_logs y audit_logs heredaron los
-- default privileges de Supabase (ALL para anon y authenticated), y
-- 20260717224621_multitenant_foundation.sql creó policies RLS que dejan a
-- cualquier owner/admin de un tenant escribir directamente vía PostgREST.
-- Combinados, un admin de tenant podía:
--   - autopromoverse a owner (UPDATE organization_members.role);
--   - desactivar o degradar al owner (salteando la protección de "último
--     owner", que solo existe en admin-update-organization-member);
--   - insertar cualquier usuario como miembro sin invitación;
--   - cambiar organizations.organization_type a 'platform_admin', con lo
--     que is_platform_admin() pasaba a true (lectura cross-tenant total);
--   - borrar o reescribir activity_logs / audit_logs.
--
-- Esta migración cierra SOLO esa superficie directa. Ver
-- docs/ORGANIZATION_ACCESS_HARDENING.md.
--
-- Escrituras que siguen funcionando:
--   - OrganizationProfile.tsx: UPDATE de organizations(name, legal_name,
--     tax_id), vía privilegio de columna + la policy owner/admin existente.
--   - Edge Functions admin-*: usan service_role (BYPASSRLS); sus
--     privilegios sobre estas cinco tablas se declaran explícitamente abajo.
--   - set_request_audience (SECURITY DEFINER) sigue insertando en
--     audit_logs como su owner, no como authenticated.
--
-- No toca ALTER DEFAULT PRIVILEGES (a propósito: cambiarlos para todo
-- public podría romper otras áreas). Toda tabla sensible nueva debe traer
-- su propio REVOKE/GRANT explícito, igual que esta migración.
--
-- Defensa en profundidad: además de revocar los GRANT, se eliminan las
-- policies de escritura que ya no deben existir, para que un GRANT
-- reabierto por accidente en el futuro no reabra la vulnerabilidad.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1) anon: ningún acceso directo a las cinco tablas.
-- -------------------------------------------------------------------------
REVOKE ALL ON TABLE
  public.organizations,
  public.organization_members,
  public.organization_invitations,
  public.activity_logs,
  public.audit_logs
FROM PUBLIC, anon;

-- -------------------------------------------------------------------------
-- 2) authenticated: se parte de cero y se concede solo lo necesario.
--    SELECT sigue gobernado por las policies RLS existentes (sin cambios).
-- -------------------------------------------------------------------------
REVOKE ALL ON TABLE
  public.organizations,
  public.organization_members,
  public.organization_invitations,
  public.activity_logs,
  public.audit_logs
FROM authenticated;

GRANT SELECT ON TABLE
  public.organizations,
  public.organization_members,
  public.organization_invitations,
  public.activity_logs,
  public.audit_logs
TO authenticated;

-- organizations: única escritura cliente legítima (OrganizationProfile.tsx).
-- Privilegio de COLUMNA: organization_type, status, settings, created_by,
-- id y timestamps quedan fuera de alcance desde PostgREST. updated_at lo
-- sigue fijando el trigger touch_updated_at (los triggers no requieren
-- privilegio de columna). La policy "organization administrators can
-- update organizations" (owner/admin del tenant) se mantiene tal cual.
GRANT UPDATE (name, legal_name, tax_id) ON TABLE public.organizations TO authenticated;

-- service_role (Edge Functions admin-*): se declara explícitamente en vez de
-- depender de default privileges. En el remoto ya los tiene (no-op); en un
-- entorno donde las tablas nuevas no se auto-exponen (Supabase CLI
-- `[api] auto_expose_new_tables` sin definir) esto garantiza que
-- crear/listar/actualizar miembros, invitar, archivar y auditar siguen
-- funcionando. service_role tiene BYPASSRLS: RLS no le aplica.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.organizations,
  public.organization_members,
  public.organization_invitations,
  public.activity_logs,
  public.audit_logs
TO service_role;

-- -------------------------------------------------------------------------
-- 3) Policies de escritura directa que dejan de existir.
--    Las escrituras de membresías/invitaciones pasan exclusivamente por
--    Edge Functions con service_role o RPCs SECURITY DEFINER controladas.
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "organization administrators can add memberships" ON public.organization_members;
DROP POLICY IF EXISTS "organization administrators can update memberships" ON public.organization_members;
DROP POLICY IF EXISTS "organization administrators can remove memberships" ON public.organization_members;

-- Ningún cliente escribe activity_logs directamente (verificado en src/ y
-- supabase/functions/: solo Edge Functions con service_role insertan).
DROP POLICY IF EXISTS "members can write their own activity logs" ON public.activity_logs;
