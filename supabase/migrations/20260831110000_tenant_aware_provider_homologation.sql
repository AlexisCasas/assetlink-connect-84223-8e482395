-- Fase 18 — Proveedores homologados tenant-aware. Reemplaza el modelo legacy
-- (client_approved_providers / client_specialties, ambas 0 filas, ambas
-- keyed por user.email en vez de organization_id) por un directorio
-- construido sobre organizations + organization_relationships, ya
-- existentes desde 20260717224621_multitenant_foundation.sql pero sin
-- ningún consumidor hasta ahora (organization_relationships: 0 filas).
--
-- No se crea ninguna tabla nueva de proveedores. La identidad de cada
-- proveedor sigue siendo su propia fila en organizations (organization_type
-- IN ('provider_company','facility_manager','subcontractor_company'));
-- providers/provider_profiles (legacy, 0 filas) no se usan como fuente.
--
-- Tres bloques:
--   A) organization_profiles.specialties — las especialidades pertenecen a
--      la organización proveedora, no a cada cliente que la homologa.
--   B) get_provider_relationship_directory — RPC de lectura, SECURITY
--      DEFINER porque necesita listar organizaciones que el cliente
--      llamante no puede leer directamente por RLS (la policy SELECT de
--      organizations solo expone las del propio tenant). No se abre esa
--      policy: la RPC es la única puerta, y solo expone id/name/type/
--      specialties + el estado de relación con el cliente que llama —
--      nunca email/teléfono/miembros/otros datos privados de otro tenant.
--   C) set_provider_relationship_status — única vía de escritura sobre
--      organization_relationships desde ahora; deriva relationship_type en
--      servidor (nunca confía en un valor enviado por el frontend) y hace
--      UPSERT preservando created_by en la rama de UPDATE.
--   D) Hardening de organization_relationships — confirmado por búsqueda
--      en todo el repo (grep "organization_relationships" src/): el único
--      resultado es el tipo autogenerado en
--      src/integrations/supabase/types.ts, ningún componente ni hook hace
--      .from('organization_relationships').insert/update/delete directo.
--
--      CORRECCIÓN (contrastado directamente contra Supabase producción
--      hplchnsseylngjopgbtl después de una primera versión de este bloque
--      que asumía, incorrectamente, que authenticated ya solo tenía
--      SELECT): ninguna migración versionada de este repo otorgó nunca
--      INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER sobre esta tabla
--      a anon ni a authenticated — pero en producción AMBOS roles tienen
--      hoy esos privilegios de forma efectiva. Es el mismo patrón de
--      drift ya documentado para funciones en
--      20260831100000_function_acl_hardening.sql (pg_default_acl del
--      owner postgres, configurado fuera de las migraciones versionadas,
--      probablemente el template de bootstrap de Supabase que otorga
--      privilegios por defecto sobre tablas a anon/authenticated/
--      service_role), aplicado aquí también a nivel de tabla, no solo de
--      función. Por eso este bloque revoca de forma explícita e
--      idempotente TODO privilegio de anon y de authenticated sobre esta
--      tabla y solo vuelve a otorgar SELECT a authenticated — no basta
--      con asumir el estado a partir del historial de migraciones.

-- =========================================================================
-- A) organization_profiles.specialties
-- =========================================================================
ALTER TABLE public.organization_profiles
  ADD COLUMN specialties text[] NOT NULL DEFAULT '{}';

-- =========================================================================
-- B) get_provider_relationship_directory — directorio seguro de
--    organizaciones proveedoras disponibles para un cliente, con su
--    relación (si existe) y sus especialidades.
--
--    SET search_path = '' (no 'public'): cada referencia a tabla/tipo en
--    el cuerpo de la función ya está schema-calificada explícitamente
--    (public.organizations, public.organization_relationships,
--    public.organization_profiles, public.organization_type, etc.), y
--    auth.uid() también. pg_catalog (uuid/text/boolean y los operadores
--    de comparación/cast implícito usados aquí) sigue disponible siempre,
--    con o sin search_path — así que un search_path vacío no rompe nada
--    y elimina por completo el riesgo de secuestro de search_path.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_provider_relationship_directory(
  p_client_organization_id uuid
)
RETURNS TABLE (
  organization_id uuid,
  organization_name text,
  organization_type public.organization_type,
  relationship_id uuid,
  relationship_type public.organization_relationship_type,
  relationship_status public.organization_relationship_status,
  specialties text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = p_client_organization_id
      AND o.organization_type = 'client_company'
      AND o.status = 'active'
  ) THEN
    RAISE EXCEPTION 'p_client_organization_id must reference an active client company';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(p_client_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this organization''s provider directory';
  END IF;

  RETURN QUERY
  SELECT
    org.id,
    org.name,
    org.organization_type,
    rel.id,
    -- Derivado de organization_type, no de rel.relationship_type: el
    -- directorio debe mostrar el tipo de relación aunque todavía no exista
    -- ninguna fila en organization_relationships (relationship_id NULL).
    CASE org.organization_type
      WHEN 'provider_company' THEN 'provider'::public.organization_relationship_type
      WHEN 'facility_manager' THEN 'facility_management'::public.organization_relationship_type
      WHEN 'subcontractor_company' THEN 'subcontracting'::public.organization_relationship_type
    END,
    rel.status,
    COALESCE(prof.specialties, '{}'::text[])
  FROM public.organizations org
  LEFT JOIN public.organization_relationships rel
    ON rel.source_organization_id = p_client_organization_id
    AND rel.target_organization_id = org.id
  LEFT JOIN public.organization_profiles prof
    ON prof.organization_id = org.id
  WHERE org.organization_type IN ('provider_company', 'facility_manager', 'subcontractor_company')
    AND org.status = 'active'
  ORDER BY org.name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_provider_relationship_directory(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_provider_relationship_directory(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_provider_relationship_directory(uuid) TO authenticated;

-- =========================================================================
-- C) set_provider_relationship_status — única vía de escritura sobre
--    organization_relationships. relationship_type siempre se deriva en
--    servidor desde target_org.organization_type; nunca se recibe del
--    llamante.
--
--    SET search_path = '' por el mismo motivo que en B): toda referencia
--    a tabla/tipo/función ya está schema-calificada explícitamente en el
--    cuerpo (public.organizations, public.organization_relationships,
--    public.organization_relationship_type, public.is_platform_admin(),
--    public.has_organization_role(...), auth.uid()) — nada depende de
--    search_path en tiempo de ejecución.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.set_provider_relationship_status(
  p_client_organization_id uuid,
  p_target_organization_id uuid,
  p_status public.organization_relationship_status
)
RETURNS public.organization_relationships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  source_org public.organizations%ROWTYPE;
  target_org public.organizations%ROWTYPE;
  derived_type public.organization_relationship_type;
  result_row public.organization_relationships%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      p_client_organization_id,
      ARRAY['owner', 'admin']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage provider relationships for this organization';
  END IF;

  SELECT * INTO source_org FROM public.organizations WHERE id = p_client_organization_id;
  IF source_org.id IS NULL
    OR source_org.status <> 'active'
    OR source_org.organization_type <> 'client_company' THEN
    RAISE EXCEPTION 'p_client_organization_id must reference an active client company';
  END IF;

  SELECT * INTO target_org FROM public.organizations WHERE id = p_target_organization_id;
  IF target_org.id IS NULL
    OR target_org.status <> 'active'
    OR target_org.organization_type NOT IN ('provider_company', 'facility_manager', 'subcontractor_company') THEN
    RAISE EXCEPTION 'p_target_organization_id must reference an active provider organization';
  END IF;

  derived_type := CASE target_org.organization_type
    WHEN 'provider_company' THEN 'provider'::public.organization_relationship_type
    WHEN 'facility_manager' THEN 'facility_management'::public.organization_relationship_type
    WHEN 'subcontractor_company' THEN 'subcontracting'::public.organization_relationship_type
  END;

  INSERT INTO public.organization_relationships (
    source_organization_id,
    target_organization_id,
    relationship_type,
    status,
    created_by
  ) VALUES (
    p_client_organization_id,
    p_target_organization_id,
    derived_type,
    p_status,
    auth.uid()
  )
  ON CONFLICT (source_organization_id, target_organization_id, relationship_type)
  DO UPDATE SET status = EXCLUDED.status
  -- created_by intencionalmente ausente del SET: se establece solo en el
  -- INSERT inicial y nunca se sobrescribe en la rama de conflicto/UPDATE.
  RETURNING * INTO result_row;

  RETURN result_row;
END;
$$;

REVOKE ALL ON FUNCTION public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status) TO authenticated;

-- =========================================================================
-- D) Hardening de organization_relationships — estado final:
--      anon:            ningún privilegio.
--      authenticated:   SELECT únicamente (bajo la policy RLS ya
--                        existente, sin tocar); toda escritura pasa
--                        exclusivamente por set_provider_relationship_status
--                        (SECURITY DEFINER, corre como el owner de la
--                        tabla — no depende de que authenticated tenga
--                        INSERT/UPDATE de tabla).
--      service_role/postgres: no se tocan en esta fase.
-- =========================================================================
REVOKE ALL ON TABLE public.organization_relationships FROM anon;
REVOKE ALL ON TABLE public.organization_relationships FROM authenticated;
GRANT SELECT ON TABLE public.organization_relationships TO authenticated;
