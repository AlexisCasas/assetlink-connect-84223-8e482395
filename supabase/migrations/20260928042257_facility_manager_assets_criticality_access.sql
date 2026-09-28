-- =========================================================================
-- Fase 1 · Punto 9C.1 — Acceso operativo de Facility Manager a
-- Activos + Criticidad.
--
-- Hace efectivos SOLO assets.view, assets.manage, criticality.view y
-- criticality.manage. Ningún otro permiso delegado (inspections.*,
-- preventive_maintenance.*, maintenance_notices.*, requests.*, providers.*,
-- quotes.*, work_orders.*, reports.*) abre nada todavía.
--
-- Acceso delegado efectivo = relación facility_management ACTIVE + cliente
-- ACTIVE + FM ACTIVE + membresía ACTIVA del usuario en ESE FM + ESA
-- membresía asignada a ESA relación + permiso(s) delegado(s) en ESA relación
-- + rol interno compatible. Todo en la misma fila de relación: nunca se
-- mezcla la relación de un FM con el rol/membresía de otro.
--
-- Matriz de roles del FM (solo acceso delegado; el acceso directo de los
-- miembros del cliente NO cambia):
--   assets.view                          owner/admin/manager/technician
--   assets.view + assets.manage          owner/admin/manager
--   criticality.view                     owner/admin/manager
--   criticality.view + criticality.manage owner/admin/manager
--   evaluar criticidad de un activo:
--     assets.view + criticality.view + criticality.manage, owner/admin/manager
-- *.manage nunca sustituye a *.view.
--
-- Todo acceso nuevo se AÑADE como rama OR a las reglas existentes
-- (policies permisivas adicionales / helpers que conservan la condición
-- directa). Ver docs/FACILITY_MANAGER_ASSETS_CRITICALITY.md.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1) Helper central de acceso operativo delegado
-- -------------------------------------------------------------------------
-- Todos los permisos de _permissions deben existir en la MISMA relación
-- que cumple el resto de condiciones. Array vacío => false.
CREATE OR REPLACE FUNCTION public.has_facility_management_operational_access_all(
  _client_organization_id uuid,
  _permissions public.facility_management_permission[],
  _allowed_roles public.organization_member_role[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL
    AND COALESCE(array_length(_permissions, 1), 0) > 0
    AND COALESCE(array_length(_allowed_roles, 1), 0) > 0
    AND EXISTS (
      SELECT 1
      FROM public.organizations client
      JOIN public.organization_relationships rel
        ON rel.source_organization_id = client.id
       AND rel.relationship_type = 'facility_management'
       AND rel.status = 'active'
      JOIN public.organizations fm
        ON fm.id = rel.target_organization_id
       AND fm.organization_type = 'facility_manager'
       AND fm.status = 'active'
      JOIN public.organization_members membership
        ON membership.organization_id = fm.id
       AND membership.user_id = auth.uid()
       AND membership.is_active
       AND membership.role = ANY (_allowed_roles)
      JOIN public.facility_management_relationship_members assignment
        ON assignment.relationship_id = rel.id
       AND assignment.organization_member_id = membership.id
      WHERE client.id = _client_organization_id
        AND client.organization_type = 'client_company'
        AND client.status = 'active'
        AND NOT EXISTS (
          SELECT 1
          FROM unnest(_permissions) AS required(permission)
          WHERE required.permission IS NULL
             OR NOT EXISTS (
               SELECT 1
               FROM public.facility_management_permissions fmp
               WHERE fmp.relationship_id = rel.id
                 AND fmp.permission = required.permission
             )
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.has_facility_management_operational_access(
  _client_organization_id uuid,
  _permission public.facility_management_permission,
  _allowed_roles public.organization_member_role[]
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _client_organization_id, ARRAY[_permission], _allowed_roles
  );
$$;

-- RLS de assets/asset_categories/asset_events los evalúa como el rol que
-- consulta: authenticated necesita EXECUTE. Solo revelan el acceso del
-- propio auth.uid(); no reciben user_id, FM ni membership id.
REVOKE ALL ON FUNCTION public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_facility_management_operational_access(uuid, public.facility_management_permission, public.organization_member_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_facility_management_operational_access_all(uuid, public.facility_management_permission[], public.organization_member_role[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_facility_management_operational_access(uuid, public.facility_management_permission, public.organization_member_role[]) TO authenticated;

-- -------------------------------------------------------------------------
-- 2) Capacidades de criticidad: acceso directo histórico (idéntico) OR
--    acceso delegado. Internas: solo las usan RPCs SECURITY DEFINER.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_view_criticality_matrix(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.is_platform_admin()
    OR public.is_organization_member(_organization_id)
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['criticality.view']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_criticality_matrix(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.is_platform_admin()
    OR public.has_organization_role(_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['criticality.view', 'criticality.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_asset_criticality_assessments(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.is_platform_admin()
    OR public.is_organization_member(_organization_id)
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['assets.view', 'criticality.view']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    );
$$;

-- Evaluar no exige assets.manage (criticality.manage es la capacidad
-- específica), pero sí poder ver el activo.
CREATE OR REPLACE FUNCTION public.can_evaluate_asset_criticality(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.is_platform_admin()
    OR public.has_organization_role(_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['assets.view', 'criticality.view', 'criticality.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_criticality_matrix(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_manage_criticality_matrix(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_view_asset_criticality_assessments(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_evaluate_asset_criticality(uuid) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 3) RLS delegada — policies permisivas ADICIONALES (las directas no se
--    tocan). Sin DELETE: el flujo actual no borra activos (archivar =
--    UPDATE de status).
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "facility managers can view delegated assets" ON public.assets;
CREATE POLICY "facility managers can view delegated assets" ON public.assets
  FOR SELECT TO authenticated
  USING ((SELECT public.has_facility_management_operational_access(
    assets.organization_id, 'assets.view',
    ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[])));

DROP POLICY IF EXISTS "facility managers can create delegated assets" ON public.assets;
CREATE POLICY "facility managers can create delegated assets" ON public.assets
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_facility_management_operational_access_all(
    assets.organization_id,
    ARRAY['assets.view', 'assets.manage']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])));

DROP POLICY IF EXISTS "facility managers can update delegated assets" ON public.assets;
CREATE POLICY "facility managers can update delegated assets" ON public.assets
  FOR UPDATE TO authenticated
  USING ((SELECT public.has_facility_management_operational_access_all(
    assets.organization_id,
    ARRAY['assets.view', 'assets.manage']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])))
  WITH CHECK ((SELECT public.has_facility_management_operational_access_all(
    assets.organization_id,
    ARRAY['assets.view', 'assets.manage']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])));

DROP POLICY IF EXISTS "facility managers can view delegated asset categories" ON public.asset_categories;
CREATE POLICY "facility managers can view delegated asset categories" ON public.asset_categories
  FOR SELECT TO authenticated
  USING ((SELECT public.has_facility_management_operational_access(
    asset_categories.organization_id, 'assets.view',
    ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[])));

-- Solo el evento de auditoría que registra el propio flujo de Activos, del
-- mismo actor, sobre un activo del mismo cliente delegado.
DROP POLICY IF EXISTS "facility managers can log delegated asset events" ON public.asset_events;
CREATE POLICY "facility managers can log delegated asset events" ON public.asset_events
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.has_facility_management_operational_access_all(
      asset_events.organization_id,
      ARRAY['assets.view', 'assets.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]))
    AND asset_events.created_by_user_id = (SELECT auth.uid())
    AND asset_events.event_type IN ('created', 'updated', 'archived', 'restored')
    AND EXISTS (
      SELECT 1 FROM public.assets a
      WHERE a.id = asset_events.asset_id
        AND a.organization_id = asset_events.organization_id
    )
  );

-- -------------------------------------------------------------------------
-- 4) Sucursales del cliente para el FM: RPC en vez de RLS. La fila de
--    client_branches incluye client_email (legacy); el FM solo necesita lo
--    que muestra Activos.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_facility_management_client_branches(_client_organization_id uuid)
RETURNS TABLE (
  id uuid,
  name text,
  city text,
  site text,
  address text,
  is_active boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.has_facility_management_operational_access(
    _client_organization_id, 'assets.view',
    ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this client''s branches' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT b.id, b.name, b.city, b.site, b.address, b.is_active
  FROM public.client_branches b
  WHERE b.organization_id = _client_organization_id
    AND b.is_active
  ORDER BY b.name, b.id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_facility_management_client_branches(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_management_client_branches(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- 5) Límites de escritura delegada sobre assets. La policy delegada
--    autoriza una FILA, no columnas: este trigger define QUÉ puede escribir
--    un FM. Solo actúa cuando quien escribe vía PostgREST (rol
--    authenticated) NO es miembro directo activo del cliente (de ningún
--    rol) ni platform_admin: el comportamiento de los miembros directos
--    queda exactamente igual (su RLS histórica ya decide qué pueden
--    escribir). postgres, service_role y las RPCs SECURITY DEFINER (que
--    corren como su owner y traen su propia autorización, p. ej.
--    calculate_asset_criticality) no pasan por aquí.
--
--    Clasificación de columnas de public.assets para el FM delegado:
--      escribibles (flujo actual de Activos): name, node_type, status,
--        parent_asset_id, branch_id, asset_category_id, code, description,
--        manufacturer, model, serial_number, barcode, purchase_date,
--        warranty_until, location_text;
--      condicionada: criticality — exige además criticality.view +
--        criticality.manage en la MISMA relación (assets.view +
--        assets.manage ya los exige la policy);
--      sistema: updated_at (lo fija touch_updated_at; en INSERT también se
--        normaliza created_at/updated_at a now());
--      reservadas: id, organization_id, default_responsible_member_id
--        (CLIENT-ONLY), created_by_user_id, created_at, qr_code, image_url,
--        metadata, technical_data.
--    En UPDATE la comparación es sobre la fila completa: cualquier columna
--    fuera de la lista escribible — incluida una futura — queda protegida
--    sin tener que acordarse de añadirla aquí.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_delegated_asset_write_limits()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_organization_id uuid := CASE WHEN TG_OP = 'UPDATE' THEN OLD.organization_id ELSE NEW.organization_id END;
  v_writable constant text[] := ARRAY[
    'name', 'node_type', 'status', 'parent_asset_id', 'branch_id', 'asset_category_id', 'code',
    'description', 'manufacturer', 'model', 'serial_number', 'barcode', 'purchase_date',
    'warranty_until', 'location_text',
    'criticality',  -- condicionada, ver abajo
    'updated_at'    -- sistema (touch_updated_at)
  ];
  v_reserved_changes text[];
BEGIN
  IF current_user <> 'authenticated'
    OR auth.uid() IS NULL
    OR public.is_platform_admin()
    OR public.is_organization_member(v_organization_id) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
      RAISE EXCEPTION 'A delegated writer cannot move an asset to another organization' USING ERRCODE = '42501';
    END IF;
    IF NEW.default_responsible_member_id IS DISTINCT FROM OLD.default_responsible_member_id THEN
      RAISE EXCEPTION 'The default responsible of an asset can only be set by the client organization' USING ERRCODE = '42501';
    END IF;

    SELECT array_agg(changed.key ORDER BY changed.key)
    INTO v_reserved_changes
    FROM jsonb_each(to_jsonb(NEW)) AS changed
    WHERE changed.key <> ALL (v_writable)
      AND changed.value IS DISTINCT FROM (to_jsonb(OLD) -> changed.key);

    IF v_reserved_changes IS NOT NULL THEN
      RAISE EXCEPTION 'A delegated writer cannot modify reserved asset columns: %', array_to_string(v_reserved_changes, ', ')
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF NEW.default_responsible_member_id IS NOT NULL THEN
      RAISE EXCEPTION 'The default responsible of an asset can only be set by the client organization' USING ERRCODE = '42501';
    END IF;
    IF NEW.created_by_user_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'A delegated writer must create assets as itself (created_by_user_id)' USING ERRCODE = '42501';
    END IF;
    IF NEW.qr_code IS NOT NULL OR NEW.image_url IS NOT NULL THEN
      RAISE EXCEPTION 'A delegated writer cannot preload qr_code or image_url' USING ERRCODE = '42501';
    END IF;
    IF NEW.metadata IS DISTINCT FROM '{}'::jsonb OR NEW.technical_data IS DISTINCT FROM '{}'::jsonb THEN
      RAISE EXCEPTION 'A delegated writer cannot set metadata or technical_data' USING ERRCODE = '42501';
    END IF;
    NEW.created_at := now();
    NEW.updated_at := now();
  END IF;

  IF (TG_OP = 'INSERT' AND NEW.criticality IS NOT NULL)
    OR (TG_OP = 'UPDATE' AND NEW.criticality IS DISTINCT FROM OLD.criticality) THEN
    IF NOT public.has_facility_management_operational_access_all(
      v_organization_id,
      ARRAY['assets.view', 'assets.manage', 'criticality.view', 'criticality.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    ) THEN
      RAISE EXCEPTION 'Changing the criticality of an asset requires the delegated criticality permissions' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_delegated_asset_write_limits() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_assets_enforce_delegated_write_limits ON public.assets;
CREATE TRIGGER trg_assets_enforce_delegated_write_limits
  BEFORE INSERT OR UPDATE ON public.assets
  FOR EACH ROW EXECUTE FUNCTION public.enforce_delegated_asset_write_limits();

-- -------------------------------------------------------------------------
-- 6) check_asset_consistency pasa a SECURITY DEFINER con search_path = ''
--    (cuerpo idéntico; ya usaba solo referencias public.* explícitas).
--    Antes corría con la RLS del que escribe; como el FM no lee
--    client_branches por RLS (ver 4), no podría validar un branch_id legítimo.
--    Solo compara organization_id de padre/categoría/sucursal contra
--    NEW.organization_id: el resultado para un miembro directo es el mismo
--    (una referencia a otro tenant sigue fallando).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_asset_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  parent_org uuid;
  category_org uuid;
  branch_org uuid;
BEGIN
  IF NEW.parent_asset_id IS NOT NULL THEN
    SELECT organization_id INTO parent_org FROM public.assets WHERE id = NEW.parent_asset_id;
    IF parent_org IS NULL OR parent_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'parent_asset_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.asset_category_id IS NOT NULL THEN
    SELECT organization_id INTO category_org FROM public.asset_categories WHERE id = NEW.asset_category_id;
    IF category_org IS NULL OR category_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'asset_category_id must belong to the same organization_id';
    END IF;
  END IF;

  IF NEW.branch_id IS NOT NULL THEN
    SELECT organization_id INTO branch_org FROM public.client_branches WHERE id = NEW.branch_id;
    IF branch_org IS NULL OR branch_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'branch_id must belong to the same organization_id';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.check_asset_consistency() FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 7) RPCs de criticidad: SOLO cambia su llamada de autorización; el resto
--    del cuerpo es el de la definición vigente. CREATE OR REPLACE conserva
--    sus grants actuales.
--      READ MATRIX      get_criticality_matrix, get_criticality_templates,
--                       get_criticality_thresholds,
--                       can_access_criticality_template (interna, usada por
--                       get_criticality_template/apply_criticality_template)
--                       -> can_view_criticality_matrix
--      MANAGE MATRIX    upsert_criticality_parameter/option,
--                       set_criticality_parameter/option_active,
--                       set_criticality_thresholds,
--                       replace_criticality_configuration,
--                       replace_criticality_matrix,
--                       clear_active_criticality_matrix,
--                       apply_criticality_template,
--                       create_template_from_current_matrix
--                       -> can_manage_criticality_matrix
--      READ ASSESSMENT  get_asset_criticality_assessments
--                       -> can_view_asset_criticality_assessments
--      EVALUATE         calculate_asset_criticality,
--                       preview_bulk_asset_criticality,
--                       bulk_calculate_asset_criticality
--                       -> can_evaluate_asset_criticality
--      INTERNAL (sin cambios): validate_and_score_asset_criticality,
--      write_criticality_thresholds, criticality_* helpers.
--    NO se amplían get_asset_traffic_light, get_branch_traffic_light ni
--    get_asset_integrated_history: mezclan OT/inspecciones/preventivo/avisos,
--    módulos todavía no delegados.
-- -------------------------------------------------------------------------
-- public.get_criticality_matrix(uuid,boolean)
CREATE OR REPLACE FUNCTION public.get_criticality_matrix(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_view_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the criticality matrix for this organization';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cp.id,
    'code', cp.code,
    'name', cp.name,
    'description', cp.description,
    'weight', cp.weight,
    'sequence', cp.sequence,
    'is_active', cp.is_active,
    'options', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cpo.id,
        'code', cpo.code,
        'label', cpo.label,
        'score', cpo.score,
        'sequence', cpo.sequence,
        'is_active', cpo.is_active
      ) ORDER BY cpo.sequence, cpo.label)
      FROM public.criticality_parameter_options cpo
      WHERE cpo.parameter_id = cp.id AND (p_include_inactive OR cpo.is_active)
    ), '[]'::jsonb)
  ) ORDER BY cp.sequence, cp.name), '[]'::jsonb)
  INTO v_result
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = p_organization_id AND (p_include_inactive OR cp.is_active);

  RETURN v_result;
END;
$function$;

-- public.get_criticality_templates(uuid)
CREATE OR REPLACE FUNCTION public.get_criticality_templates(p_organization_id uuid)
 RETURNS TABLE(id uuid, organization_id uuid, scope text, name text, description text, category text, is_active boolean, parameter_count integer, option_count integer, total_weight numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_view_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view criticality templates for this organization';
  END IF;

  RETURN QUERY
  SELECT
    cmt.id,
    cmt.organization_id,
    cmt.scope,
    cmt.name,
    cmt.description,
    cmt.category,
    cmt.is_active,
    COALESCE((
      SELECT COUNT(*)::integer FROM public.criticality_template_parameters ctp
      WHERE ctp.template_id = cmt.id AND ctp.is_active
    ), 0) AS parameter_count,
    COALESCE((
      SELECT COUNT(*)::integer
      FROM public.criticality_template_options cto
      INNER JOIN public.criticality_template_parameters ctp2 ON ctp2.id = cto.template_parameter_id
      WHERE ctp2.template_id = cmt.id AND ctp2.is_active AND cto.is_active
    ), 0) AS option_count,
    COALESCE((
      SELECT SUM(ctp3.weight) FROM public.criticality_template_parameters ctp3
      WHERE ctp3.template_id = cmt.id AND ctp3.is_active
    ), 0)::numeric AS total_weight,
    cmt.created_at
  FROM public.criticality_matrix_templates cmt
  WHERE cmt.is_active
    AND (
      cmt.scope = 'system'
      OR cmt.organization_id = p_organization_id
    )
  ORDER BY cmt.scope DESC, cmt.name;
END;
$function$;

-- public.get_criticality_thresholds(uuid)
CREATE OR REPLACE FUNCTION public.get_criticality_thresholds(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_view_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the criticality thresholds for this organization';
  END IF;

  RETURN public.criticality_thresholds_payload(p_organization_id);
END;
$function$;

-- public.can_access_criticality_template(uuid)
CREATE OR REPLACE FUNCTION public.can_access_criticality_template(p_template_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.criticality_matrix_templates cmt
    WHERE cmt.id = p_template_id
      AND (
        public.is_platform_admin()
        OR cmt.scope = 'system'
        OR (cmt.organization_id IS NOT NULL AND public.can_view_criticality_matrix(cmt.organization_id))
      )
  );
$function$;

-- public.upsert_criticality_parameter(uuid,text,text,numeric,integer,uuid,boolean)
CREATE OR REPLACE FUNCTION public.upsert_criticality_parameter(p_organization_id uuid, p_name text, p_description text DEFAULT NULL::text, p_weight numeric DEFAULT 0, p_sequence integer DEFAULT 1, p_parameter_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true)
 RETURNS criticality_parameters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_saved public.criticality_parameters%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;
  IF p_weight IS NULL OR p_weight < 0 THEN
    RAISE EXCEPTION 'weight must be >= 0';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_parameter_id IS NOT NULL THEN
    UPDATE public.criticality_parameters cp
    SET name = TRIM(p_name),
        description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
        weight = p_weight,
        sequence = p_sequence,
        is_active = p_is_active
    WHERE cp.id = p_parameter_id AND cp.organization_id = p_organization_id
    RETURNING cp.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Parameter not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.criticality_parameters AS cp (organization_id, name, description, weight, sequence, is_active)
    VALUES (p_organization_id, TRIM(p_name), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_weight, p_sequence, p_is_active)
    RETURNING cp.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$function$;

-- public.upsert_criticality_option(uuid,text,numeric,integer,uuid,boolean)
CREATE OR REPLACE FUNCTION public.upsert_criticality_option(p_parameter_id uuid, p_label text, p_score numeric DEFAULT 0, p_sequence integer DEFAULT 1, p_option_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true)
 RETURNS criticality_parameter_options
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parameter public.criticality_parameters%ROWTYPE;
  v_saved public.criticality_parameter_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT cp.* INTO v_parameter FROM public.criticality_parameters cp WHERE cp.id = p_parameter_id;
  IF v_parameter.id IS NULL THEN
    RAISE EXCEPTION 'Parameter not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(v_parameter.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this parameter''s options';
  END IF;

  IF p_label IS NULL OR TRIM(p_label) = '' THEN
    RAISE EXCEPTION 'label is required';
  END IF;
  IF p_score IS NULL OR p_score < 0 THEN
    RAISE EXCEPTION 'score must be >= 0';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_option_id IS NOT NULL THEN
    UPDATE public.criticality_parameter_options cpo
    SET label = TRIM(p_label),
        score = p_score,
        sequence = p_sequence,
        is_active = p_is_active
    WHERE cpo.id = p_option_id AND cpo.parameter_id = p_parameter_id
    RETURNING cpo.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Option not found for this parameter';
    END IF;
  ELSE
    INSERT INTO public.criticality_parameter_options AS cpo (parameter_id, label, score, sequence, is_active)
    VALUES (p_parameter_id, TRIM(p_label), p_score, p_sequence, p_is_active)
    RETURNING cpo.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$function$;

-- public.set_criticality_parameter_active(uuid,boolean)
CREATE OR REPLACE FUNCTION public.set_criticality_parameter_active(p_parameter_id uuid, p_is_active boolean)
 RETURNS criticality_parameters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parameter public.criticality_parameters%ROWTYPE;
  v_saved public.criticality_parameters%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT cp.* INTO v_parameter FROM public.criticality_parameters cp WHERE cp.id = p_parameter_id;
  IF v_parameter.id IS NULL THEN
    RAISE EXCEPTION 'Parameter not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(v_parameter.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  UPDATE public.criticality_parameters cp
  SET is_active = p_is_active
  WHERE cp.id = p_parameter_id
  RETURNING cp.* INTO v_saved;

  RETURN v_saved;
END;
$function$;

-- public.set_criticality_option_active(uuid,boolean)
CREATE OR REPLACE FUNCTION public.set_criticality_option_active(p_option_id uuid, p_is_active boolean)
 RETURNS criticality_parameter_options
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_organization_id uuid;
  v_saved public.criticality_parameter_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT cp.organization_id INTO v_organization_id
  FROM public.criticality_parameter_options cpo
  INNER JOIN public.criticality_parameters cp ON cp.id = cpo.parameter_id
  WHERE cpo.id = p_option_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Option not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(v_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this parameter''s options';
  END IF;

  UPDATE public.criticality_parameter_options cpo
  SET is_active = p_is_active
  WHERE cpo.id = p_option_id
  RETURNING cpo.* INTO v_saved;

  RETURN v_saved;
END;
$function$;

-- public.set_criticality_thresholds(uuid,numeric,numeric,numeric)
CREATE OR REPLACE FUNCTION public.set_criticality_thresholds(p_organization_id uuid, p_medium_min numeric, p_high_min numeric, p_critical_min numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality thresholds for this organization';
  END IF;

  PERFORM public.write_criticality_thresholds(p_organization_id, p_medium_min, p_high_min, p_critical_min);

  RETURN public.criticality_thresholds_payload(p_organization_id);
END;
$function$;

-- public.replace_criticality_configuration(uuid,jsonb,jsonb)
CREATE OR REPLACE FUNCTION public.replace_criticality_configuration(p_organization_id uuid, p_matrix jsonb, p_thresholds jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_has_thresholds boolean := p_thresholds IS NOT NULL AND jsonb_typeof(p_thresholds) <> 'null';
  v_medium_min numeric;
  v_high_min numeric;
  v_critical_min numeric;
  v_matrix jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  -- Umbrales primero: si son inválidos se aborta antes de tocar la matriz.
  IF v_has_thresholds THEN
    SELECT t.medium_min, t.high_min, t.critical_min
      INTO v_medium_min, v_high_min, v_critical_min
      FROM public.criticality_thresholds_from_jsonb(p_thresholds) AS t;
  END IF;

  v_matrix := public.replace_criticality_matrix(p_organization_id, p_matrix);

  IF v_has_thresholds THEN
    PERFORM public.write_criticality_thresholds(p_organization_id, v_medium_min, v_high_min, v_critical_min);
  END IF;

  RETURN jsonb_build_object(
    'matrix', v_matrix,
    'thresholds', public.criticality_thresholds_payload(p_organization_id)
  );
END;
$function$;

-- public.replace_criticality_matrix(uuid,jsonb)
CREATE OR REPLACE FUNCTION public.replace_criticality_matrix(p_organization_id uuid, p_matrix jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parameters jsonb;
  v_parameter jsonb;
  v_option jsonb;
  v_codes text[] := ARRAY[]::text[];
  v_option_codes text[];
  v_code text;
  v_option_code text;
  v_index integer := 0;
  v_option_index integer;
  v_new_parameter_id uuid;
  v_is_active boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  v_parameters := p_matrix->'parameters';

  IF v_parameters IS NULL OR jsonb_typeof(v_parameters) <> 'array' OR jsonb_array_length(v_parameters) = 0 THEN
    RAISE EXCEPTION 'p_matrix.parameters debe ser un arreglo con al menos un parámetro';
  END IF;

  -- PASADA 1: validar TODO el payload antes de tocar una sola fila.
  FOR v_parameter IN SELECT * FROM jsonb_array_elements(v_parameters) LOOP
    v_index := v_index + 1;
    v_code := NULLIF(TRIM(COALESCE(v_parameter->>'code', '')), '');
    v_is_active := COALESCE((v_parameter->>'is_active')::boolean, true);

    IF v_code IS NULL THEN
      RAISE EXCEPTION 'Parámetro %: el código es obligatorio', v_index;
    END IF;
    IF LOWER(v_code) = ANY (SELECT LOWER(x) FROM unnest(v_codes) AS x) THEN
      RAISE EXCEPTION 'Código de parámetro duplicado: %', v_code;
    END IF;
    v_codes := array_append(v_codes, v_code);

    IF NULLIF(TRIM(COALESCE(v_parameter->>'name', '')), '') IS NULL THEN
      RAISE EXCEPTION 'Parámetro %s: el nombre es obligatorio', v_code;
    END IF;
    IF COALESCE((v_parameter->>'weight')::numeric, -1) < 0 THEN
      RAISE EXCEPTION 'Parámetro %: el peso debe ser >= 0', v_code;
    END IF;
    IF COALESCE((v_parameter->>'sequence')::integer, 0) <= 0 THEN
      RAISE EXCEPTION 'Parámetro %: el orden debe ser > 0', v_code;
    END IF;

    IF v_parameter->'options' IS NULL OR jsonb_typeof(v_parameter->'options') <> 'array' THEN
      RAISE EXCEPTION 'Parámetro %: options debe ser un arreglo', v_code;
    END IF;

    v_option_codes := ARRAY[]::text[];
    v_option_index := 0;

    FOR v_option IN SELECT * FROM jsonb_array_elements(v_parameter->'options') LOOP
      v_option_index := v_option_index + 1;
      v_option_code := NULLIF(TRIM(COALESCE(v_option->>'code', '')), '');

      IF v_option_code IS NULL THEN
        RAISE EXCEPTION 'Parámetro %, opción %: el código es obligatorio', v_code, v_option_index;
      END IF;
      IF LOWER(v_option_code) = ANY (SELECT LOWER(x) FROM unnest(v_option_codes) AS x) THEN
        RAISE EXCEPTION 'Parámetro %: código de opción duplicado (%)', v_code, v_option_code;
      END IF;
      v_option_codes := array_append(v_option_codes, v_option_code);

      IF NULLIF(TRIM(COALESCE(v_option->>'label', '')), '') IS NULL THEN
        RAISE EXCEPTION 'Parámetro %, opción %: la etiqueta es obligatoria', v_code, v_option_code;
      END IF;
      IF COALESCE((v_option->>'score')::numeric, -1) < 0 THEN
        RAISE EXCEPTION 'Parámetro %, opción %: el puntaje debe ser >= 0', v_code, v_option_code;
      END IF;
      IF COALESCE((v_option->>'sequence')::integer, 0) <= 0 THEN
        RAISE EXCEPTION 'Parámetro %, opción %: el orden debe ser > 0', v_code, v_option_code;
      END IF;
    END LOOP;

    -- Un parámetro activo sin ninguna opción activa haría imposible
    -- responderlo, y calculate_asset_criticality exige responder todos los
    -- activos: la matriz quedaría inevaluable.
    IF v_is_active AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_parameter->'options') o
      WHERE COALESCE((o.value->>'is_active')::boolean, true)
    ) THEN
      RAISE EXCEPTION 'Parámetro %: un parámetro activo necesita al menos una opción activa', v_code;
    END IF;
  END LOOP;

  -- PASADA 2: recién ahora se toca la base. Desactivar (NUNCA borrar) la
  -- configuración activa actual, incluidas sus opciones.
  UPDATE public.criticality_parameter_options cpo
  SET is_active = false
  WHERE cpo.is_active
    AND cpo.parameter_id IN (
      SELECT cp.id FROM public.criticality_parameters cp
      WHERE cp.organization_id = p_organization_id AND cp.is_active
    );

  UPDATE public.criticality_parameters cp
  SET is_active = false
  WHERE cp.organization_id = p_organization_id AND cp.is_active;

  -- PASADA 3: insertar la configuración nueva.
  FOR v_parameter IN SELECT * FROM jsonb_array_elements(v_parameters) LOOP
    INSERT INTO public.criticality_parameters AS cp (
      organization_id, code, name, description, weight, sequence, is_active
    ) VALUES (
      p_organization_id,
      TRIM(v_parameter->>'code'),
      TRIM(v_parameter->>'name'),
      NULLIF(TRIM(COALESCE(v_parameter->>'description', '')), ''),
      (v_parameter->>'weight')::numeric,
      (v_parameter->>'sequence')::integer,
      COALESCE((v_parameter->>'is_active')::boolean, true)
    ) RETURNING cp.id INTO v_new_parameter_id;

    FOR v_option IN SELECT * FROM jsonb_array_elements(v_parameter->'options') LOOP
      INSERT INTO public.criticality_parameter_options (
        parameter_id, code, label, score, sequence, is_active
      ) VALUES (
        v_new_parameter_id,
        TRIM(v_option->>'code'),
        TRIM(v_option->>'label'),
        (v_option->>'score')::numeric,
        (v_option->>'sequence')::integer,
        COALESCE((v_option->>'is_active')::boolean, true)
      );
    END LOOP;
  END LOOP;

  RETURN public.get_criticality_matrix(p_organization_id, true);
END;
$function$;

-- public.clear_active_criticality_matrix(uuid)
CREATE OR REPLACE FUNCTION public.clear_active_criticality_matrix(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_deactivated_parameters integer;
  v_deactivated_options integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  -- Options first (their parameter_id must still resolve to an active
  -- parameter of this org when this runs), then the parameters themselves.
  -- One UPDATE per table — never N calls per row.
  WITH deactivated_options AS (
    UPDATE public.criticality_parameter_options cpo
    SET is_active = false
    WHERE cpo.is_active
      AND cpo.parameter_id IN (
        SELECT cp.id FROM public.criticality_parameters cp
        WHERE cp.organization_id = p_organization_id AND cp.is_active
      )
    RETURNING cpo.id
  )
  SELECT COUNT(*) INTO v_deactivated_options FROM deactivated_options;

  WITH deactivated_parameters AS (
    UPDATE public.criticality_parameters cp
    SET is_active = false
    WHERE cp.organization_id = p_organization_id AND cp.is_active
    RETURNING cp.id
  )
  SELECT COUNT(*) INTO v_deactivated_parameters FROM deactivated_parameters;

  -- No active parameters to begin with: idempotent, both counts are 0, no
  -- exception — matches "Si no hay parámetros activos: operación
  -- idempotente, no error."
  RETURN jsonb_build_object(
    'deactivated_parameters', v_deactivated_parameters,
    'deactivated_options', v_deactivated_options
  );
END;
$function$;

-- public.apply_criticality_template(uuid,uuid)
CREATE OR REPLACE FUNCTION public.apply_criticality_template(p_organization_id uuid, p_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template public.criticality_matrix_templates%ROWTYPE;
  v_payload jsonb;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage the criticality matrix for this organization';
  END IF;

  SELECT cmt.* INTO v_template FROM public.criticality_matrix_templates cmt WHERE cmt.id = p_template_id;
  IF v_template.id IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF NOT public.can_access_criticality_template(p_template_id) THEN
    RAISE EXCEPTION 'Not authorized to use this criticality template';
  END IF;

  SELECT jsonb_build_object('parameters', COALESCE(jsonb_agg(parameter_payload ORDER BY sequence, code), '[]'::jsonb))
  INTO v_payload
  FROM (
    SELECT
      ctp.sequence AS sequence,
      ctp.code AS code,
      jsonb_build_object(
        'code', ctp.code,
        'name', ctp.name,
        'description', ctp.description,
        'weight', ctp.weight,
        'sequence', ctp.sequence,
        'is_active', true,
        'options', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'code', cto.code,
            'label', cto.label,
            'score', cto.score,
            'sequence', cto.sequence,
            'is_active', true
          ) ORDER BY cto.sequence, cto.code)
          FROM public.criticality_template_options cto
          WHERE cto.template_parameter_id = ctp.id AND cto.is_active
        ), '[]'::jsonb)
      ) AS parameter_payload
    FROM public.criticality_template_parameters ctp
    WHERE ctp.template_id = p_template_id AND ctp.is_active
  ) AS source;

  IF v_payload IS NULL OR jsonb_array_length(v_payload->'parameters') = 0 THEN
    RAISE EXCEPTION 'La plantilla no tiene parámetros activos';
  END IF;

  v_result := public.replace_criticality_matrix(p_organization_id, v_payload);

  IF v_template.medium_min IS NOT NULL THEN
    PERFORM public.write_criticality_thresholds(
      p_organization_id, v_template.medium_min, v_template.high_min, v_template.critical_min
    );
  END IF;

  RETURN v_result;
END;
$function$;

-- public.create_template_from_current_matrix(uuid,text,text,text)
CREATE OR REPLACE FUNCTION public.create_template_from_current_matrix(p_organization_id uuid, p_name text, p_description text DEFAULT NULL::text, p_category text DEFAULT NULL::text)
 RETURNS criticality_matrix_templates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template public.criticality_matrix_templates%ROWTYPE;
  v_parameter public.criticality_parameters%ROWTYPE;
  v_new_parameter_id uuid;
  v_active_count integer;
  v_thresholds record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_manage_criticality_matrix(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage criticality templates for this organization';
  END IF;

  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'El nombre de la plantilla es obligatorio';
  END IF;

  SELECT COUNT(*) INTO v_active_count
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = p_organization_id AND cp.is_active;

  IF v_active_count = 0 THEN
    RAISE EXCEPTION 'No hay una matriz activa que guardar como plantilla';
  END IF;

  SELECT e.* INTO v_thresholds FROM public.get_effective_criticality_thresholds(p_organization_id) AS e;

  INSERT INTO public.criticality_matrix_templates AS cmt (
    organization_id, name, description, category, scope, is_active, created_by_user_id,
    medium_min, high_min, critical_min
  ) VALUES (
    p_organization_id,
    TRIM(p_name),
    NULLIF(TRIM(COALESCE(p_description, '')), ''),
    NULLIF(TRIM(COALESCE(p_category, '')), ''),
    'organization',
    true,
    auth.uid(),
    v_thresholds.medium_min,
    v_thresholds.high_min,
    v_thresholds.critical_min
  ) RETURNING cmt.* INTO v_template;

  FOR v_parameter IN
    SELECT cp.* FROM public.criticality_parameters cp
    WHERE cp.organization_id = p_organization_id AND cp.is_active
    ORDER BY cp.sequence, cp.name
  LOOP
    INSERT INTO public.criticality_template_parameters AS ctp (
      template_id, code, name, description, weight, sequence, is_active
    ) VALUES (
      v_template.id, v_parameter.code, v_parameter.name, v_parameter.description,
      v_parameter.weight, v_parameter.sequence, true
    ) RETURNING ctp.id INTO v_new_parameter_id;

    INSERT INTO public.criticality_template_options (
      template_parameter_id, code, label, score, sequence, is_active
    )
    SELECT v_new_parameter_id, cpo.code, cpo.label, cpo.score, cpo.sequence, true
    FROM public.criticality_parameter_options cpo
    WHERE cpo.parameter_id = v_parameter.id AND cpo.is_active
    ORDER BY cpo.sequence, cpo.label;
  END LOOP;

  RETURN v_template;
END;
$function$;

-- public.get_asset_criticality_assessments(uuid)
CREATE OR REPLACE FUNCTION public.get_asset_criticality_assessments(p_asset_id uuid)
 RETURNS TABLE(id uuid, asset_id uuid, organization_id uuid, score numeric, calculated_criticality text, manual_criticality text, effective_criticality text, notes text, created_by_user_id uuid, created_by_name text, created_at timestamp with time zone, answers jsonb, threshold_medium_min numeric, threshold_high_min numeric, threshold_critical_min numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_asset_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.organization_id INTO v_asset_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset_org IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_view_asset_criticality_assessments(v_asset_org)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view criticality assessments for this asset';
  END IF;

  RETURN QUERY
  SELECT
    aca.id,
    aca.asset_id,
    aca.organization_id,
    aca.score,
    aca.calculated_criticality,
    aca.manual_criticality,
    aca.effective_criticality,
    aca.notes,
    aca.created_by_user_id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS created_by_name,
    aca.created_at,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'parameter_id', acaa.parameter_id,
        'parameter_name', acaa.parameter_name,
        'option_id', acaa.option_id,
        'option_label', acaa.option_label,
        'weight', acaa.weight,
        'option_score', acaa.option_score,
        'weighted_score', acaa.weighted_score
      ) ORDER BY acaa.parameter_name)
      FROM public.asset_criticality_assessment_answers acaa
      WHERE acaa.assessment_id = aca.id
    ), '[]'::jsonb) AS answers,
    aca.threshold_medium_min::numeric,
    aca.threshold_high_min::numeric,
    aca.threshold_critical_min::numeric
  FROM public.asset_criticality_assessments aca
  LEFT JOIN auth.users au ON au.id = aca.created_by_user_id
  WHERE aca.asset_id = p_asset_id
  ORDER BY aca.created_at DESC;
END;
$function$;

-- public.calculate_asset_criticality(uuid,jsonb,text)
CREATE OR REPLACE FUNCTION public.calculate_asset_criticality(p_asset_id uuid, p_answers jsonb, p_notes text DEFAULT NULL::text)
 RETURNS asset_criticality_assessments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_asset public.assets%ROWTYPE;
  v_result jsonb;
  v_answer jsonb;
  v_score numeric(10, 2);
  v_calculated text;
  v_thresholds jsonb;
  v_assessment public.asset_criticality_assessments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.* INTO v_asset FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset.id IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_evaluate_asset_criticality(v_asset.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to evaluate criticality for this asset';
  END IF;

  v_result := public.validate_and_score_asset_criticality(p_asset_id, p_answers, NULL);

  IF NOT (v_result->>'valid')::boolean THEN
    RAISE EXCEPTION '%', array_to_string(
      ARRAY(SELECT jsonb_array_elements_text(v_result->'errors')), '; '
    );
  END IF;

  v_score := (v_result->>'score')::numeric;
  v_calculated := v_result->>'calculated_criticality';
  v_thresholds := v_result->'thresholds';

  INSERT INTO public.asset_criticality_assessments AS aca (
    asset_id, organization_id, score, calculated_criticality, manual_criticality, effective_criticality, notes, created_by_user_id,
    threshold_medium_min, threshold_high_min, threshold_critical_min
  ) VALUES (
    p_asset_id, v_asset.organization_id, v_score, v_calculated, v_asset.criticality, v_calculated, p_notes, auth.uid(),
    (v_thresholds->>'medium_min')::numeric, (v_thresholds->>'high_min')::numeric, (v_thresholds->>'critical_min')::numeric
  ) RETURNING aca.* INTO v_assessment;

  FOR v_answer IN SELECT * FROM jsonb_array_elements(v_result->'answers') LOOP
    INSERT INTO public.asset_criticality_assessment_answers (
      assessment_id, parameter_id, option_id, parameter_name, option_label, weight, option_score, weighted_score
    ) VALUES (
      v_assessment.id,
      (v_answer->>'parameter_id')::uuid,
      (v_answer->>'option_id')::uuid,
      v_answer->>'parameter_name',
      v_answer->>'option_label',
      (v_answer->>'weight')::numeric,
      (v_answer->>'option_score')::numeric,
      (v_answer->>'weighted_score')::numeric
    );
  END LOOP;

  UPDATE public.assets a SET criticality = v_calculated WHERE a.id = p_asset_id;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_asset.organization_id,
    p_asset_id,
    'criticality_assessed',
    'Criticidad evaluada: ' || public.criticality_label_es(v_calculated) || ' (score ' || v_score || ')',
    jsonb_build_object(
      'score', v_score,
      'calculated_criticality', v_calculated,
      'assessment_id', v_assessment.id,
      'thresholds', v_thresholds
    ),
    auth.uid()
  );

  RETURN v_assessment;
END;
$function$;

-- public.preview_bulk_asset_criticality(uuid,jsonb)
CREATE OR REPLACE FUNCTION public.preview_bulk_asset_criticality(p_organization_id uuid, p_rows jsonb)
 RETURNS TABLE(row_number integer, asset_id uuid, asset_code text, asset_name text, valid boolean, score numeric, calculated_criticality text, errors jsonb, warnings jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row jsonb;
  v_result jsonb;
  v_asset_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_evaluate_asset_criticality(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to evaluate criticality for this organization';
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'p_rows debe ser un arreglo';
  END IF;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    v_asset_id := NULLIF(v_row->>'asset_id', '')::uuid;
    row_number := COALESCE((v_row->>'row_number')::integer, 0);

    IF v_asset_id IS NULL THEN
      asset_id := NULL;
      asset_code := NULL;
      asset_name := NULL;
      valid := false;
      score := NULL;
      calculated_criticality := NULL;
      errors := to_jsonb(ARRAY['La fila no tiene un ID interno de activo válido.']);
      warnings := '[]'::jsonb;
      RETURN NEXT;
      CONTINUE;
    END IF;

    v_result := public.validate_and_score_asset_criticality(
      v_asset_id, v_row->'answers', p_organization_id
    );

    asset_id := v_asset_id;
    asset_code := v_result->>'asset_code';
    asset_name := v_result->>'asset_name';
    valid := (v_result->>'valid')::boolean;
    score := NULLIF(v_result->>'score', '')::numeric;
    calculated_criticality := v_result->>'calculated_criticality';
    errors := v_result->'errors';
    warnings := v_result->'warnings';
    RETURN NEXT;
  END LOOP;
END;
$function$;

-- public.bulk_calculate_asset_criticality(uuid,jsonb)
CREATE OR REPLACE FUNCTION public.bulk_calculate_asset_criticality(p_organization_id uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row jsonb;
  v_result jsonb;
  v_asset_id uuid;
  v_row_number integer;
  v_failures text[] := ARRAY[]::text[];
  v_assessment public.asset_criticality_assessments%ROWTYPE;
  v_results jsonb := '[]'::jsonb;
  v_low integer := 0;
  v_medium integer := 0;
  v_high integer := 0;
  v_critical integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.can_evaluate_asset_criticality(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to evaluate criticality for this organization';
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
    RAISE EXCEPTION 'p_rows debe ser un arreglo con al menos una fila';
  END IF;

  -- PASADA 1 — validar todo, sin escribir.
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    v_row_number := COALESCE((v_row->>'row_number')::integer, 0);
    v_asset_id := NULLIF(v_row->>'asset_id', '')::uuid;

    IF v_asset_id IS NULL THEN
      v_failures := array_append(v_failures, format('Fila %s: ID interno de activo inválido', v_row_number));
      CONTINUE;
    END IF;

    v_result := public.validate_and_score_asset_criticality(v_asset_id, v_row->'answers', p_organization_id);

    IF NOT (v_result->>'valid')::boolean THEN
      v_failures := array_append(v_failures, format('Fila %s: %s', v_row_number,
        array_to_string(ARRAY(SELECT jsonb_array_elements_text(v_result->'errors')), '; ')));
    END IF;
  END LOOP;

  IF array_length(v_failures, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'No se aplicó ninguna evaluación: % fila(s) inválida(s). %',
      array_length(v_failures, 1), array_to_string(v_failures, ' | ');
  END IF;

  -- PASADA 2 — escribir, reutilizando el único escritor existente.
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    v_row_number := COALESCE((v_row->>'row_number')::integer, 0);
    v_asset_id := (v_row->>'asset_id')::uuid;

    v_assessment := public.calculate_asset_criticality(
      v_asset_id,
      v_row->'answers',
      NULLIF(TRIM(COALESCE(v_row->>'notes', '')), '')
    );

    v_results := v_results || jsonb_build_object(
      'row_number', v_row_number,
      'asset_id', v_asset_id,
      'assessment_id', v_assessment.id,
      'score', v_assessment.score,
      'calculated_criticality', v_assessment.calculated_criticality
    );

    CASE v_assessment.calculated_criticality
      WHEN 'low' THEN v_low := v_low + 1;
      WHEN 'medium' THEN v_medium := v_medium + 1;
      WHEN 'high' THEN v_high := v_high + 1;
      ELSE v_critical := v_critical + 1;
    END CASE;
  END LOOP;

  RETURN jsonb_build_object(
    'evaluated', jsonb_array_length(v_results),
    'counts', jsonb_build_object('low', v_low, 'medium', v_medium, 'high', v_high, 'critical', v_critical),
    'results', v_results
  );
END;
$function$;
