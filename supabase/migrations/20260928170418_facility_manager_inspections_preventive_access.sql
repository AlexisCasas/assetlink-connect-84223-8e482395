-- =========================================================================
-- Fase 1 · Punto 9C.2 — Acceso operativo de Facility Manager a
-- Inspecciones + Mantenimiento preventivo.
--
-- Hace efectivos SOLO inspections.view, inspections.manage,
-- preventive_maintenance.view y preventive_maintenance.manage. No abre
-- maintenance_notices.*, requests.*, providers.*, quotes.*, work_orders.*,
-- reports.*, inventario ni R2.
--
-- Acceso delegado = has_facility_management_operational_access_all (9C.1):
-- relación facility_management ACTIVE + cliente ACTIVE + FM ACTIVE +
-- membresía ACTIVA en ESE FM + ESA membresía asignada a ESA relación +
-- todos los permisos en ESA relación + rol compatible. No hay un segundo
-- sistema de delegación.
--
-- Matriz del FM (el acceso directo de los miembros del cliente NO cambia):
--   Inspecciones  ver           inspections.view                        o/a/m/t
--                 planificar    inspections.view + inspections.manage   o/a/m
--                 ejecutar      inspections.view + inspections.manage   o/a/m/t
--   Preventivo    ver           preventive_maintenance.view             o/a/m/t
--                 planificar /  preventive_maintenance.view + .manage   o/a/m
--                 administrar medidores
--                 registrar     preventive_maintenance.view + .manage   o/a/m/t
--                 lectura
-- *.manage nunca sustituye a *.view.
--
-- Reglas propias del modo delegado (el cliente directo no cambia):
--   - responsible_member_id (inspección y preventivo) es del CLIENTE: el FM
--     no lo fija en un plan nuevo ni lo cambia en uno existente, y no recibe
--     el roster del cliente (get_assignable_technicians/planners intactas).
--   - Un technician FM ejecuta inspecciones por estar asignado a la relación
--     con view+manage; nunca se compara su membresía FM con el
--     responsible_member_id del cliente ni se crea una membresía ficticia.
--   - Inventario no se delega: el FM no ve stock/catálogo ni vincula
--     material_id; los materiales vinculados por el cliente se conservan.
--   - plan_preventive_maintenance_occurrence (vincular una Solicitud) queda
--     fuera: pertenece a 9C.4.
--   - Evidencias de inspección: solo metadata/enlace, como hoy. Sin R2.
-- Ver docs/FACILITY_MANAGER_INSPECTIONS_PREVENTIVE.md.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1) Capacidades de Inspecciones: acceso directo histórico (idéntico) OR
--    delegado. Internas: solo las usan RPCs SECURITY DEFINER.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_view_inspections(_organization_id uuid)
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
      ARRAY['inspections.view']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
    );
$$;

CREATE OR REPLACE FUNCTION public.can_plan_inspections(_organization_id uuid)
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
      ARRAY['inspections.view', 'inspections.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    );
$$;

-- Solo la rama delegada: la ejecución directa conserva su regla histórica
-- (platform admin, owner/admin/manager del cliente o responsable del plan/
-- ejecución) dentro de cada RPC.
CREATE OR REPLACE FUNCTION public.can_execute_inspections_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['inspections.view', 'inspections.manage']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
  );
$$;

-- -------------------------------------------------------------------------
-- 2) Capacidades de Preventivo. can_manage_preventive_maintenance y
--    can_record_asset_meter_reading (directas) NO cambian: la primera
--    también protege plan_preventive_maintenance_occurrence, que no se
--    delega.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_view_preventive_maintenance(_organization_id uuid)
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
      ARRAY['preventive_maintenance.view']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
    );
$$;

CREATE OR REPLACE FUNCTION public.can_plan_preventive_maintenance(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.can_manage_preventive_maintenance(_organization_id)
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['preventive_maintenance.view', 'preventive_maintenance.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    );
$$;

CREATE OR REPLACE FUNCTION public.can_record_preventive_meter_reading(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.can_record_asset_meter_reading(_organization_id)
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['preventive_maintenance.view', 'preventive_maintenance.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_inspections(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_plan_inspections(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_execute_inspections_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_view_preventive_maintenance(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_plan_preventive_maintenance(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_record_preventive_meter_reading(uuid) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 3) Snapshot de alcance de una ocurrencia sin inventario, para lecturas
--    delegadas: quita material_id y el código/nombre del catálogo, y marca
--    si la línea está vinculada por el cliente. Interna.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sanitize_preventive_scope_snapshot(_snapshot jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  -- El nombre del responsable del snapshot pudo derivarse del email: se
  -- quita (queda membership_id/role, igual que responsible_member_id).
  SELECT CASE
    WHEN _snapshot IS NULL OR jsonb_typeof(_snapshot) <> 'object' THEN _snapshot
    ELSE (CASE
      WHEN jsonb_typeof(_snapshot #> '{card,materials}') IS DISTINCT FROM 'array' THEN _snapshot
      ELSE jsonb_set(_snapshot, '{card,materials}', COALESCE((
        SELECT jsonb_agg(
          (item.value - 'material_id' - 'code' - 'name')
            || jsonb_build_object('client_linked_material', NULLIF(item.value->>'material_id', '') IS NOT NULL)
          ORDER BY item.ord)
        FROM jsonb_array_elements(_snapshot #> '{card,materials}') WITH ORDINALITY AS item(value, ord)
      ), '[]'::jsonb))
    END) #- '{plan,responsible,name}'
  END;
$$;

REVOKE ALL ON FUNCTION public.sanitize_preventive_scope_snapshot(jsonb) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 4) Directorios mínimos de referencia (solo modo delegado). No abren
--    #assets ni la RLS de assets/client_branches: devuelven lo estrictamente
--    necesario para elegir destino y nada más (sin client_email, contacto,
--    metadata, technical_data, responsables, R2 ni inventario).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_facility_management_inspection_targets(_client_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Solo para planificar (crear/editar planes): leer planes y ejecuciones ya
  -- trae los nombres de sede/área/activo.
  IF NOT public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['inspections.view', 'inspections.manage']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized to view inspection targets for this client' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'branches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', cb.id, 'name', cb.name, 'is_active', cb.is_active) ORDER BY lower(cb.name))
      FROM public.client_branches cb
      WHERE cb.organization_id = _client_organization_id AND cb.is_active
    ), '[]'::jsonb),
    'assets', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'name', a.name, 'code', a.code, 'node_type', a.node_type,
        'parent_asset_id', a.parent_asset_id, 'branch_id', a.branch_id, 'status', a.status
      ) ORDER BY lower(a.name))
      FROM public.assets a
      WHERE a.organization_id = _client_organization_id AND a.status <> 'archived'
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_facility_management_preventive_assets(_client_organization_id uuid)
RETURNS TABLE (id uuid, name text, code text, status text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['preventive_maintenance.view']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager', 'technician']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized to view preventive maintenance assets for this client' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT a.id, a.name, a.code, a.status
  FROM public.assets a
  WHERE a.organization_id = _client_organization_id AND a.status <> 'archived'
  ORDER BY lower(a.name);
END;
$$;

REVOKE ALL ON FUNCTION public.get_facility_management_inspection_targets(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_preventive_assets(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_management_inspection_targets(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_preventive_assets(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- 5) RPCs existentes: solo cambia su autorización (verificado contra la
--    definición vigente; firmas, SECURITY DEFINER, search_path y grants
--    se conservan).
-- -------------------------------------------------------------------------

-- ---- Inspecciones: lectura (READ) ----

CREATE OR REPLACE FUNCTION public.get_checklist_templates(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
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
    public.can_view_inspections(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view checklist templates for this organization';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', ct.id,
    'name', ct.name,
    'description', ct.description,
    'category', ct.category,
    'is_active', ct.is_active,
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cti.id,
        'section', cti.section,
        'question', cti.question,
        'help_text', cti.help_text,
        'sequence', cti.sequence,
        'is_required', cti.is_required,
        'is_active', cti.is_active
      ) ORDER BY cti.sequence, cti.question)
      FROM public.checklist_template_items cti
      WHERE cti.template_id = ct.id AND (p_include_inactive OR cti.is_active)
    ), '[]'::jsonb),
    'response_options', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ctro.id,
        'label', ctro.label,
        'value', ctro.value,
        'score', ctro.score,
        'is_failure', ctro.is_failure,
        'sequence', ctro.sequence,
        'is_active', ctro.is_active
      ) ORDER BY ctro.sequence, ctro.label)
      FROM public.checklist_template_response_options ctro
      WHERE ctro.template_id = ct.id AND (p_include_inactive OR ctro.is_active)
    ), '[]'::jsonb)
  ) ORDER BY ct.name), '[]'::jsonb)
  INTO v_result
  FROM public.checklist_templates ct
  WHERE ct.organization_id = p_organization_id AND (p_include_inactive OR ct.is_active);

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_inspection_plans(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
 RETURNS TABLE(id uuid, template_id uuid, template_name text, branch_id uuid, branch_name text, area_asset_id uuid, area_asset_name text, asset_id uuid, asset_name text, responsible_member_id uuid, responsible_name text, title text, description text, frequency text, custom_interval integer, custom_unit text, start_date date, next_due_at timestamp with time zone, is_active boolean, created_at timestamp with time zone, alert_rules jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- Miembro directo / platform admin: respuesta histórica. Facility Manager
  -- delegado: el nombre del responsable nunca se deriva del email.
  v_direct boolean := public.is_platform_admin() OR public.is_organization_member(p_organization_id);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.can_view_inspections(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view inspection plans for this organization';
  END IF;

  RETURN QUERY
  SELECT
    ip.id,
    ip.template_id,
    ct.name AS template_name,
    ip.branch_id,
    cb.name AS branch_name,
    ip.area_asset_id,
    area_a.name AS area_asset_name,
    ip.asset_id,
    a.name AS asset_name,
    ip.responsible_member_id,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) ELSE NULLIF(TRIM(au.raw_user_meta_data->>'name'), '') END AS responsible_name,
    ip.title,
    ip.description,
    ip.frequency,
    ip.custom_interval,
    ip.custom_unit,
    ip.start_date,
    ip.next_due_at,
    ip.is_active,
    ip.created_at,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ipar.id,
        'alert_type', ipar.alert_type,
        'days_before', ipar.days_before,
        'label', ipar.label,
        'is_active', ipar.is_active
      ) ORDER BY ipar.alert_type, ipar.days_before DESC NULLS LAST)
      FROM public.inspection_plan_alert_rules ipar
      WHERE ipar.plan_id = ip.id AND ipar.is_active
    ), '[]'::jsonb) AS alert_rules
  FROM public.inspection_plans ip
  INNER JOIN public.checklist_templates ct ON ct.id = ip.template_id
  LEFT JOIN public.client_branches cb ON cb.id = ip.branch_id
  LEFT JOIN public.assets area_a ON area_a.id = ip.area_asset_id
  LEFT JOIN public.assets a ON a.id = ip.asset_id
  LEFT JOIN public.organization_members om ON om.id = ip.responsible_member_id
  LEFT JOIN auth.users au ON au.id = om.user_id
  WHERE ip.organization_id = p_organization_id AND (p_include_inactive OR ip.is_active)
  ORDER BY ip.next_due_at NULLS LAST, ip.title;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_inspection_runs(p_organization_id uuid, p_status text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, organization_id uuid, plan_id uuid, template_id uuid, template_name text, branch_name text, area_asset_name text, asset_name text, responsible_member_id uuid, responsible_name text, scheduled_for timestamp with time zone, started_at timestamp with time zone, completed_at timestamp with time zone, status text, result text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- Miembro directo / platform admin: respuesta histórica. Facility Manager
  -- delegado: el nombre del responsable nunca se deriva del email.
  v_direct boolean := public.is_platform_admin() OR public.is_organization_member(p_organization_id);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.can_view_inspections(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view inspection runs for this organization';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('scheduled', 'in_progress', 'completed', 'cancelled', 'overdue') THEN
    RAISE EXCEPTION 'Invalid status value';
  END IF;

  RETURN QUERY
  SELECT
    ir.id,
    ir.organization_id,
    ir.plan_id,
    ir.template_id,
    ct.name AS template_name,
    cb.name AS branch_name,
    area_a.name AS area_asset_name,
    a.name AS asset_name,
    ir.responsible_member_id,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) ELSE NULLIF(TRIM(au.raw_user_meta_data->>'name'), '') END AS responsible_name,
    ir.scheduled_for,
    ir.started_at,
    ir.completed_at,
    ir.status,
    ir.result
  FROM public.inspection_runs ir
  INNER JOIN public.checklist_templates ct ON ct.id = ir.template_id
  LEFT JOIN public.client_branches cb ON cb.id = ir.branch_id
  LEFT JOIN public.assets area_a ON area_a.id = ir.area_asset_id
  LEFT JOIN public.assets a ON a.id = ir.asset_id
  LEFT JOIN public.organization_members om ON om.id = ir.responsible_member_id
  LEFT JOIN auth.users au ON au.id = om.user_id
  WHERE ir.organization_id = p_organization_id AND (p_status IS NULL OR ir.status = p_status)
  ORDER BY COALESCE(ir.scheduled_for, ir.created_at) DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_inspection_plan_alert_rules(p_plan_id uuid)
 RETURNS TABLE(id uuid, plan_id uuid, alert_type text, days_before integer, label text, is_active boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_organization_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.organization_id INTO v_organization_id FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  IF NOT (
    public.can_view_inspections(v_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view alert rules for this plan';
  END IF;

  RETURN QUERY
  SELECT ipar.id, ipar.plan_id, ipar.alert_type, ipar.days_before, ipar.label, ipar.is_active
  FROM public.inspection_plan_alert_rules ipar
  WHERE ipar.plan_id = p_plan_id AND ipar.is_active
  ORDER BY ipar.alert_type, ipar.days_before DESC NULLS LAST;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_inspection_run_detail(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run public.inspection_runs%ROWTYPE;
  v_result jsonb;
  v_direct boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ir.* INTO v_run FROM public.inspection_runs ir WHERE ir.id = p_run_id;
  IF v_run.id IS NULL THEN
    RAISE EXCEPTION 'Run not found';
  END IF;

  IF NOT (
    public.can_view_inspections(v_run.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this inspection run';
  END IF;
  -- Facility Manager delegado: el nombre del responsable nunca se deriva del email.
  v_direct := public.is_platform_admin() OR public.is_organization_member(v_run.organization_id);

  SELECT jsonb_build_object(
    'id', ir.id,
    'organization_id', ir.organization_id,
    'plan_id', ir.plan_id,
    'template_id', ir.template_id,
    'template_name', ct.name,
    'branch_id', ir.branch_id,
    'branch_name', cb.name,
    'area_asset_id', ir.area_asset_id,
    'area_asset_name', area_a.name,
    'asset_id', ir.asset_id,
    'asset_name', a.name,
    'responsible_member_id', ir.responsible_member_id,
    'responsible_name', CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) ELSE NULLIF(TRIM(au.raw_user_meta_data->>'name'), '') END,
    'scheduled_for', ir.scheduled_for,
    'started_at', ir.started_at,
    'completed_at', ir.completed_at,
    'status', ir.status,
    'result', ir.result,
    'notes', ir.notes,
    'created_at', ir.created_at,
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cti.id,
        'section', cti.section,
        'question', cti.question,
        'help_text', cti.help_text,
        'sequence', cti.sequence,
        'is_required', cti.is_required
      ) ORDER BY cti.sequence, cti.question)
      FROM public.checklist_template_items cti
      WHERE cti.template_id = ir.template_id AND cti.is_active
    ), '[]'::jsonb),
    'response_options', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ctro.id,
        'label', ctro.label,
        'value', ctro.value,
        'is_failure', ctro.is_failure,
        'sequence', ctro.sequence
      ) ORDER BY ctro.sequence, ctro.label)
      FROM public.checklist_template_response_options ctro
      WHERE ctro.template_id = ir.template_id AND ctro.is_active
    ), '[]'::jsonb),
    'answers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ira.id,
        'template_item_id', ira.template_item_id,
        'response_option_id', ira.response_option_id,
        'item_question', ira.item_question,
        'response_label', ira.response_label,
        'response_value', ira.response_value,
        'is_failure', ira.is_failure,
        'observations', ira.observations
      ))
      FROM public.inspection_run_answers ira
      WHERE ira.run_id = ir.id
    ), '[]'::jsonb),
    'evidences', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ire.id,
        'answer_id', ire.answer_id,
        'file_name', ire.file_name,
        'file_url', ire.file_url,
        'file_path', ire.file_path,
        'mime_type', ire.mime_type,
        'size_bytes', ire.size_bytes,
        'notes', ire.notes
      ))
      FROM public.inspection_run_evidences ire
      WHERE ire.run_id = ir.id
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.inspection_runs ir
  INNER JOIN public.checklist_templates ct ON ct.id = ir.template_id
  LEFT JOIN public.client_branches cb ON cb.id = ir.branch_id
  LEFT JOIN public.assets area_a ON area_a.id = ir.area_asset_id
  LEFT JOIN public.assets a ON a.id = ir.asset_id
  LEFT JOIN public.organization_members om ON om.id = ir.responsible_member_id
  LEFT JOIN auth.users au ON au.id = om.user_id
  WHERE ir.id = p_run_id;

  RETURN v_result;
END;
$function$;

-- ---- Inspecciones: planificación (PLAN / MANAGE) ----

CREATE OR REPLACE FUNCTION public.upsert_checklist_template(p_organization_id uuid, p_name text, p_description text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_template_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true)
 RETURNS checklist_templates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_saved public.checklist_templates%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.can_plan_inspections(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage checklist templates for this organization';
  END IF;

  IF p_name IS NULL OR TRIM(p_name) = '' THEN
    RAISE EXCEPTION 'name is required';
  END IF;

  IF p_template_id IS NOT NULL THEN
    UPDATE public.checklist_templates ct
    SET name = TRIM(p_name),
        description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
        category = NULLIF(TRIM(COALESCE(p_category, '')), ''),
        is_active = p_is_active
    WHERE ct.id = p_template_id AND ct.organization_id = p_organization_id
    RETURNING ct.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Template not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.checklist_templates AS ct (organization_id, name, description, category, is_active, created_by_user_id)
    VALUES (p_organization_id, TRIM(p_name), NULLIF(TRIM(COALESCE(p_description, '')), ''), NULLIF(TRIM(COALESCE(p_category, '')), ''), p_is_active, auth.uid())
    RETURNING ct.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_checklist_template_item(p_template_id uuid, p_question text, p_section text DEFAULT NULL::text, p_help_text text DEFAULT NULL::text, p_sequence integer DEFAULT 1, p_is_required boolean DEFAULT true, p_item_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true)
 RETURNS checklist_template_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template public.checklist_templates%ROWTYPE;
  v_saved public.checklist_template_items%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.* INTO v_template FROM public.checklist_templates ct WHERE ct.id = p_template_id;
  IF v_template.id IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF NOT (
    public.can_plan_inspections(v_template.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s items';
  END IF;

  IF p_question IS NULL OR TRIM(p_question) = '' THEN
    RAISE EXCEPTION 'question is required';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_item_id IS NOT NULL THEN
    UPDATE public.checklist_template_items cti
    SET question = TRIM(p_question),
        section = NULLIF(TRIM(COALESCE(p_section, '')), ''),
        help_text = NULLIF(TRIM(COALESCE(p_help_text, '')), ''),
        sequence = p_sequence,
        is_required = p_is_required,
        is_active = p_is_active
    WHERE cti.id = p_item_id AND cti.template_id = p_template_id
    RETURNING cti.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Item not found for this template';
    END IF;
  ELSE
    INSERT INTO public.checklist_template_items AS cti (template_id, section, question, help_text, sequence, is_required, is_active)
    VALUES (p_template_id, NULLIF(TRIM(COALESCE(p_section, '')), ''), TRIM(p_question), NULLIF(TRIM(COALESCE(p_help_text, '')), ''), p_sequence, p_is_required, p_is_active)
    RETURNING cti.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_checklist_template_item_active(p_item_id uuid, p_is_active boolean)
 RETURNS checklist_template_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_organization_id uuid;
  v_saved public.checklist_template_items%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.organization_id INTO v_organization_id
  FROM public.checklist_template_items cti
  INNER JOIN public.checklist_templates ct ON ct.id = cti.template_id
  WHERE cti.id = p_item_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Item not found';
  END IF;

  IF NOT (
    public.can_plan_inspections(v_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s items';
  END IF;

  UPDATE public.checklist_template_items cti
  SET is_active = p_is_active
  WHERE cti.id = p_item_id
  RETURNING cti.* INTO v_saved;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_checklist_response_option(p_template_id uuid, p_label text, p_value text, p_score numeric DEFAULT NULL::numeric, p_is_failure boolean DEFAULT false, p_sequence integer DEFAULT 1, p_option_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true)
 RETURNS checklist_template_response_options
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template public.checklist_templates%ROWTYPE;
  v_saved public.checklist_template_response_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.* INTO v_template FROM public.checklist_templates ct WHERE ct.id = p_template_id;
  IF v_template.id IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF NOT (
    public.can_plan_inspections(v_template.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s response options';
  END IF;

  IF p_label IS NULL OR TRIM(p_label) = '' THEN
    RAISE EXCEPTION 'label is required';
  END IF;
  IF p_value IS NULL OR TRIM(p_value) = '' THEN
    RAISE EXCEPTION 'value is required';
  END IF;
  IF p_sequence IS NULL OR p_sequence <= 0 THEN
    RAISE EXCEPTION 'sequence must be > 0';
  END IF;

  IF p_option_id IS NOT NULL THEN
    UPDATE public.checklist_template_response_options ctro
    SET label = TRIM(p_label),
        value = TRIM(p_value),
        score = p_score,
        is_failure = p_is_failure,
        sequence = p_sequence,
        is_active = p_is_active
    WHERE ctro.id = p_option_id AND ctro.template_id = p_template_id
    RETURNING ctro.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Response option not found for this template';
    END IF;
  ELSE
    INSERT INTO public.checklist_template_response_options AS ctro (template_id, label, value, score, is_failure, sequence, is_active)
    VALUES (p_template_id, TRIM(p_label), TRIM(p_value), p_score, p_is_failure, p_sequence, p_is_active)
    RETURNING ctro.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_checklist_response_option_active(p_option_id uuid, p_is_active boolean)
 RETURNS checklist_template_response_options
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_organization_id uuid;
  v_saved public.checklist_template_response_options%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ct.organization_id INTO v_organization_id
  FROM public.checklist_template_response_options ctro
  INNER JOIN public.checklist_templates ct ON ct.id = ctro.template_id
  WHERE ctro.id = p_option_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Response option not found';
  END IF;

  IF NOT (
    public.can_plan_inspections(v_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this template''s response options';
  END IF;

  UPDATE public.checklist_template_response_options ctro
  SET is_active = p_is_active
  WHERE ctro.id = p_option_id
  RETURNING ctro.* INTO v_saved;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.replace_inspection_plan_alert_rules(p_plan_id uuid, p_rules jsonb)
 RETURNS SETOF inspection_plan_alert_rules
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plan public.inspection_plans%ROWTYPE;
  v_rule jsonb;
  v_alert_type text;
  v_days_before integer;
  v_seen_keys text[] := ARRAY[]::text[];
  v_key text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.* INTO v_plan FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  IF NOT (
    public.can_plan_inspections(v_plan.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage alert rules for this plan';
  END IF;

  IF p_rules IS NULL OR jsonb_typeof(p_rules) <> 'array' THEN
    RAISE EXCEPTION 'p_rules must be a JSON array';
  END IF;

  -- Validate every rule (and check for in-payload duplicates) before
  -- touching any row.
  FOR v_rule IN SELECT * FROM jsonb_array_elements(p_rules) LOOP
    v_alert_type := v_rule->>'alert_type';
    v_days_before := NULLIF(v_rule->>'days_before', '')::integer;

    IF v_alert_type NOT IN ('before_due', 'overdue') THEN
      RAISE EXCEPTION 'Invalid alert_type value: %', v_alert_type;
    END IF;
    IF v_alert_type = 'before_due' AND (v_days_before IS NULL OR v_days_before < 0) THEN
      RAISE EXCEPTION 'days_before is required and must be >= 0 for a before_due alert';
    END IF;
    IF v_alert_type = 'overdue' AND v_days_before IS NOT NULL THEN
      RAISE EXCEPTION 'days_before must be null for an overdue alert';
    END IF;

    v_key := v_alert_type || ':' || COALESCE(v_days_before::text, 'null');
    IF v_key = ANY (v_seen_keys) THEN
      RAISE EXCEPTION 'Duplicate alert rule in payload: %', v_key;
    END IF;
    v_seen_keys := array_append(v_seen_keys, v_key);
  END LOOP;

  DELETE FROM public.inspection_plan_alert_rules ipar WHERE ipar.plan_id = p_plan_id;

  FOR v_rule IN SELECT * FROM jsonb_array_elements(p_rules) LOOP
    INSERT INTO public.inspection_plan_alert_rules (plan_id, organization_id, alert_type, days_before, label, is_active)
    VALUES (
      p_plan_id,
      v_plan.organization_id,
      v_rule->>'alert_type',
      NULLIF(v_rule->>'days_before', '')::integer,
      NULLIF(TRIM(COALESCE(v_rule->>'label', '')), ''),
      true
    );
  END LOOP;

  RETURN QUERY
  SELECT ipar.* FROM public.inspection_plan_alert_rules ipar
  WHERE ipar.plan_id = p_plan_id
  ORDER BY ipar.alert_type, ipar.days_before DESC NULLS LAST;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_inspection_plan_alert_rule(p_plan_id uuid, p_alert_type text, p_days_before integer DEFAULT NULL::integer, p_label text DEFAULT NULL::text, p_rule_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true)
 RETURNS inspection_plan_alert_rules
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plan public.inspection_plans%ROWTYPE;
  v_saved public.inspection_plan_alert_rules%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.* INTO v_plan FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  IF NOT (
    public.can_plan_inspections(v_plan.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage alert rules for this plan';
  END IF;

  IF p_alert_type NOT IN ('before_due', 'overdue') THEN
    RAISE EXCEPTION 'Invalid alert_type value';
  END IF;
  IF p_alert_type = 'before_due' AND (p_days_before IS NULL OR p_days_before < 0) THEN
    RAISE EXCEPTION 'days_before is required and must be >= 0 for a before_due alert';
  END IF;
  IF p_alert_type = 'overdue' AND p_days_before IS NOT NULL THEN
    RAISE EXCEPTION 'days_before must be null for an overdue alert';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.inspection_plan_alert_rules ipar
    WHERE ipar.plan_id = p_plan_id
      AND ipar.alert_type = p_alert_type
      AND ipar.days_before IS NOT DISTINCT FROM p_days_before
      AND (p_rule_id IS NULL OR ipar.id <> p_rule_id)
  ) THEN
    RAISE EXCEPTION 'A rule with this alert_type/days_before already exists for this plan';
  END IF;

  IF p_rule_id IS NOT NULL THEN
    UPDATE public.inspection_plan_alert_rules ipar
    SET alert_type = p_alert_type,
        days_before = p_days_before,
        label = NULLIF(TRIM(COALESCE(p_label, '')), ''),
        is_active = p_is_active
    WHERE ipar.id = p_rule_id AND ipar.plan_id = p_plan_id
    RETURNING ipar.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Alert rule not found for this plan';
    END IF;
  ELSE
    INSERT INTO public.inspection_plan_alert_rules AS ipar (plan_id, organization_id, alert_type, days_before, label, is_active)
    VALUES (p_plan_id, v_plan.organization_id, p_alert_type, p_days_before, NULLIF(TRIM(COALESCE(p_label, '')), ''), p_is_active)
    RETURNING ipar.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_inspection_plan_alert_rule_active(p_rule_id uuid, p_is_active boolean)
 RETURNS inspection_plan_alert_rules
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_organization_id uuid;
  v_saved public.inspection_plan_alert_rules%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ipar.organization_id INTO v_organization_id
  FROM public.inspection_plan_alert_rules ipar
  WHERE ipar.id = p_rule_id;

  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'Alert rule not found';
  END IF;

  IF NOT (
    public.can_plan_inspections(v_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this alert rule';
  END IF;

  UPDATE public.inspection_plan_alert_rules ipar
  SET is_active = p_is_active
  WHERE ipar.id = p_rule_id
  RETURNING ipar.* INTO v_saved;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_inspection_plan(p_organization_id uuid, p_template_id uuid, p_title text, p_branch_id uuid DEFAULT NULL::uuid, p_area_asset_id uuid DEFAULT NULL::uuid, p_asset_id uuid DEFAULT NULL::uuid, p_responsible_member_id uuid DEFAULT NULL::uuid, p_description text DEFAULT NULL::text, p_frequency text DEFAULT 'one_time'::text, p_start_date date DEFAULT CURRENT_DATE, p_next_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_plan_id uuid DEFAULT NULL::uuid, p_is_active boolean DEFAULT true, p_custom_interval integer DEFAULT NULL::integer, p_custom_unit text DEFAULT NULL::text)
 RETURNS inspection_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_saved public.inspection_plans%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.can_plan_inspections(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage inspection plans for this organization';
  END IF;

  -- 9C.2: responsible_member_id pertenece al modelo de membresías del
  -- CLIENTE. Un Facility Manager delegado no lo fija en un plan nuevo ni lo
  -- cambia/limpia en uno existente; solo lo conserva.
  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    IF p_plan_id IS NULL THEN
      IF p_responsible_member_id IS NOT NULL THEN
        RAISE EXCEPTION 'The inspection plan responsible is assigned by the client' USING ERRCODE = '42501';
      END IF;
    ELSIF p_responsible_member_id IS DISTINCT FROM (
      SELECT ip.responsible_member_id FROM public.inspection_plans ip
      WHERE ip.id = p_plan_id AND ip.organization_id = p_organization_id
    ) THEN
      RAISE EXCEPTION 'The inspection plan responsible is assigned by the client' USING ERRCODE = '42501';
    END IF;

    -- Un destino histórico (sede inactiva / activo archivado) se conserva
    -- al editar otros campos, pero el FM no puede asignarlo de nuevo: el
    -- directorio mínimo tampoco lo ofrece.
    IF p_branch_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.client_branches cb WHERE cb.id = p_branch_id AND NOT cb.is_active)
      AND p_branch_id IS DISTINCT FROM (SELECT ip.branch_id FROM public.inspection_plans ip WHERE ip.id = p_plan_id AND ip.organization_id = p_organization_id) THEN
      RAISE EXCEPTION 'An inactive branch cannot be newly assigned to an inspection plan' USING ERRCODE = '22023';
    END IF;
    IF p_area_asset_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.assets a WHERE a.id = p_area_asset_id AND a.status = 'archived')
      AND p_area_asset_id IS DISTINCT FROM (SELECT ip.area_asset_id FROM public.inspection_plans ip WHERE ip.id = p_plan_id AND ip.organization_id = p_organization_id) THEN
      RAISE EXCEPTION 'An archived asset cannot be newly assigned to an inspection plan' USING ERRCODE = '22023';
    END IF;
    IF p_asset_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.assets a WHERE a.id = p_asset_id AND a.status = 'archived')
      AND p_asset_id IS DISTINCT FROM (SELECT ip.asset_id FROM public.inspection_plans ip WHERE ip.id = p_plan_id AND ip.organization_id = p_organization_id) THEN
      RAISE EXCEPTION 'An archived asset cannot be newly assigned to an inspection plan' USING ERRCODE = '22023';
    END IF;
  END IF;

  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'title is required';
  END IF;
  IF p_frequency NOT IN ('one_time', 'daily', 'weekly', 'monthly', 'quarterly', 'semiannual', 'annual', 'custom') THEN
    RAISE EXCEPTION 'Invalid frequency value';
  END IF;
  IF p_frequency = 'custom' THEN
    IF p_custom_interval IS NULL OR p_custom_interval <= 0 THEN
      RAISE EXCEPTION 'custom_interval must be > 0 when frequency is custom';
    END IF;
    IF p_custom_unit IS NULL OR p_custom_unit NOT IN ('days', 'weeks', 'months', 'years') THEN
      RAISE EXCEPTION 'custom_unit must be one of days/weeks/months/years when frequency is custom';
    END IF;
  ELSE
    -- Never persist stray custom_interval/custom_unit for a non-custom
    -- frequency, regardless of what the caller passed — keeps the two
    -- columns meaningful only together with frequency = 'custom'.
    p_custom_interval := NULL;
    p_custom_unit := NULL;
  END IF;
  IF p_branch_id IS NULL AND p_area_asset_id IS NULL AND p_asset_id IS NULL THEN
    RAISE EXCEPTION 'At least one of branch_id, area_asset_id or asset_id is required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.checklist_templates ct WHERE ct.id = p_template_id AND ct.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'template_id must belong to this organization';
  END IF;
  IF p_branch_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.client_branches cb WHERE cb.id = p_branch_id AND cb.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'branch_id must belong to this organization';
  END IF;
  IF p_area_asset_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.assets a WHERE a.id = p_area_asset_id AND a.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'area_asset_id must belong to this organization';
  END IF;
  IF p_asset_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.assets a WHERE a.id = p_asset_id AND a.organization_id = p_organization_id) THEN
    RAISE EXCEPTION 'asset_id must belong to this organization';
  END IF;
  IF p_responsible_member_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = p_responsible_member_id
      AND om.organization_id = p_organization_id
      AND om.is_active
      AND om.role IN ('owner', 'admin', 'manager', 'technician')
  ) THEN
    RAISE EXCEPTION 'responsible_member_id must be an active owner/admin/manager/technician of this organization';
  END IF;

  IF p_plan_id IS NOT NULL THEN
    UPDATE public.inspection_plans ip
    SET template_id = p_template_id,
        branch_id = p_branch_id,
        area_asset_id = p_area_asset_id,
        asset_id = p_asset_id,
        responsible_member_id = p_responsible_member_id,
        title = TRIM(p_title),
        description = NULLIF(TRIM(COALESCE(p_description, '')), ''),
        frequency = p_frequency,
        start_date = p_start_date,
        next_due_at = p_next_due_at,
        is_active = p_is_active,
        custom_interval = p_custom_interval,
        custom_unit = p_custom_unit
    WHERE ip.id = p_plan_id AND ip.organization_id = p_organization_id
    RETURNING ip.* INTO v_saved;

    IF v_saved.id IS NULL THEN
      RAISE EXCEPTION 'Plan not found for this organization';
    END IF;
  ELSE
    INSERT INTO public.inspection_plans AS ip (
      organization_id, template_id, branch_id, area_asset_id, asset_id, responsible_member_id,
      title, description, frequency, start_date, next_due_at, is_active, created_by_user_id,
      custom_interval, custom_unit
    ) VALUES (
      p_organization_id, p_template_id, p_branch_id, p_area_asset_id, p_asset_id, p_responsible_member_id,
      TRIM(p_title), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_frequency, p_start_date, p_next_due_at, p_is_active, auth.uid(),
      p_custom_interval, p_custom_unit
    )
    RETURNING ip.* INTO v_saved;
  END IF;

  RETURN v_saved;
END;
$function$;

-- ---- Inspecciones: ejecución (EXECUTE) ----

CREATE OR REPLACE FUNCTION public.create_inspection_run_from_plan(p_plan_id uuid)
 RETURNS inspection_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plan public.inspection_plans%ROWTYPE;
  v_is_responsible boolean;
  v_saved public.inspection_runs%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ip.* INTO v_plan FROM public.inspection_plans ip WHERE ip.id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RAISE EXCEPTION 'Plan not found';
  END IF;

  -- om.organization_id = v_plan.organization_id is redundant with the
  -- write-time guarantee in upsert_inspection_plan (a plan's
  -- responsible_member_id can never belong to another organization), but
  -- kept explicit here so this authorization check is self-contained and
  -- does not silently depend on that other function's behavior.
  v_is_responsible := v_plan.responsible_member_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = v_plan.responsible_member_id
      AND om.user_id = auth.uid()
      AND om.organization_id = v_plan.organization_id
      AND om.is_active
  );

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_plan.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
    OR v_is_responsible
    OR public.can_execute_inspections_as_facility_manager(v_plan.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to create a run for this plan';
  END IF;

  INSERT INTO public.inspection_runs AS ir (
    organization_id, plan_id, template_id, branch_id, area_asset_id, asset_id, responsible_member_id,
    scheduled_for, status, created_by_user_id
  ) VALUES (
    v_plan.organization_id, v_plan.id, v_plan.template_id, v_plan.branch_id, v_plan.area_asset_id, v_plan.asset_id, v_plan.responsible_member_id,
    v_plan.next_due_at, 'scheduled', auth.uid()
  )
  RETURNING ir.* INTO v_saved;

  RETURN v_saved;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_inspection_run(p_run_id uuid, p_started_at timestamp with time zone, p_completed_at timestamp with time zone, p_answers jsonb, p_evidences jsonb DEFAULT '[]'::jsonb, p_notes text DEFAULT NULL::text)
 RETURNS inspection_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run public.inspection_runs%ROWTYPE;
  v_is_responsible boolean;
  v_answer jsonb;
  v_evidence jsonb;
  v_item_id uuid;
  v_option_id uuid;
  v_item public.checklist_template_items%ROWTYPE;
  v_option public.checklist_template_response_options%ROWTYPE;
  v_required_count integer;
  v_answered_item_ids uuid[] := ARRAY[]::uuid[];
  v_distinct_answered_count integer;
  v_any_failure boolean := false;
  v_all_not_applicable boolean := true;
  v_answered_count integer := 0;
  v_result text;
  v_saved public.inspection_runs%ROWTYPE;
  v_answer_id uuid;
  v_frequency_interval interval;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT ir.* INTO v_run FROM public.inspection_runs ir WHERE ir.id = p_run_id;
  IF v_run.id IS NULL THEN
    RAISE EXCEPTION 'Run not found';
  END IF;

  v_is_responsible := v_run.responsible_member_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.organization_members om
    WHERE om.id = v_run.responsible_member_id
      AND om.user_id = auth.uid()
      AND om.organization_id = v_run.organization_id
      AND om.is_active
  );

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(v_run.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
    OR v_is_responsible
    OR public.can_execute_inspections_as_facility_manager(v_run.organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to submit this inspection run';
  END IF;

  IF p_started_at IS NULL OR p_completed_at IS NULL THEN
    RAISE EXCEPTION 'started_at and completed_at are required';
  END IF;
  IF p_completed_at < p_started_at THEN
    RAISE EXCEPTION 'completed_at must not be before started_at';
  END IF;
  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'array' OR jsonb_array_length(p_answers) = 0 THEN
    RAISE EXCEPTION 'p_answers must be a non-empty JSON array';
  END IF;

  SELECT COUNT(*) INTO v_required_count
  FROM public.checklist_template_items cti
  WHERE cti.template_id = v_run.template_id AND cti.is_active AND cti.is_required;

  FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
    v_item_id := NULLIF(v_answer->>'template_item_id', '')::uuid;
    v_option_id := NULLIF(v_answer->>'response_option_id', '')::uuid;

    IF v_item_id IS NULL THEN
      RAISE EXCEPTION 'Each answer requires a template_item_id';
    END IF;

    SELECT cti.* INTO v_item FROM public.checklist_template_items cti
      WHERE cti.id = v_item_id AND cti.template_id = v_run.template_id;
    IF v_item.id IS NULL THEN
      RAISE EXCEPTION 'template_item_id % does not belong to this run''s template', v_item_id;
    END IF;

    IF v_option_id IS NOT NULL THEN
      SELECT ctro.* INTO v_option FROM public.checklist_template_response_options ctro
        WHERE ctro.id = v_option_id AND ctro.template_id = v_run.template_id AND ctro.is_active;
      IF v_option.id IS NULL THEN
        RAISE EXCEPTION 'response_option_id % is not an active option of this run''s template', v_option_id;
      END IF;
    END IF;

    v_answered_item_ids := array_append(v_answered_item_ids, v_item_id);
  END LOOP;

  SELECT COUNT(DISTINCT x) INTO v_distinct_answered_count FROM unnest(v_answered_item_ids) AS x;
  IF v_distinct_answered_count <> array_length(v_answered_item_ids, 1) THEN
    RAISE EXCEPTION 'p_answers contains a duplicate template_item_id';
  END IF;

  IF (
    SELECT COUNT(*) FROM public.checklist_template_items cti
    WHERE cti.template_id = v_run.template_id AND cti.is_active AND cti.is_required
      AND cti.id = ANY (v_answered_item_ids)
  ) <> v_required_count THEN
    RAISE EXCEPTION 'All required items of this template must be answered';
  END IF;

  DELETE FROM public.inspection_run_answers ira WHERE ira.run_id = p_run_id;

  FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
    v_item_id := (v_answer->>'template_item_id')::uuid;
    v_option_id := NULLIF(v_answer->>'response_option_id', '')::uuid;

    SELECT cti.* INTO v_item FROM public.checklist_template_items cti WHERE cti.id = v_item_id;

    IF v_option_id IS NOT NULL THEN
      SELECT ctro.* INTO v_option FROM public.checklist_template_response_options ctro WHERE ctro.id = v_option_id;
      v_answered_count := v_answered_count + 1;
      IF v_option.is_failure THEN v_any_failure := true; END IF;
      IF v_option.value <> 'not_applicable' THEN v_all_not_applicable := false; END IF;
    ELSE
      v_option := NULL;
      v_all_not_applicable := false;
    END IF;

    INSERT INTO public.inspection_run_answers AS ira (
      run_id, template_item_id, response_option_id, item_question, response_label, response_value, is_failure, observations
    ) VALUES (
      p_run_id, v_item_id, v_option_id, v_item.question,
      CASE WHEN v_option_id IS NOT NULL THEN v_option.label ELSE NULL END,
      CASE WHEN v_option_id IS NOT NULL THEN v_option.value ELSE NULL END,
      CASE WHEN v_option_id IS NOT NULL THEN v_option.is_failure ELSE false END,
      NULLIF(TRIM(COALESCE(v_answer->>'observations', '')), '')
    )
    RETURNING ira.id INTO v_answer_id;

    IF p_evidences IS NOT NULL THEN
      FOR v_evidence IN
        SELECT e.value FROM jsonb_array_elements(p_evidences) AS e(value)
        WHERE (e.value->>'template_item_id')::uuid = v_item_id
      LOOP
        INSERT INTO public.inspection_run_evidences (run_id, answer_id, file_name, file_url, file_path, mime_type, size_bytes, notes)
        VALUES (
          p_run_id, v_answer_id, v_evidence->>'file_name', NULLIF(v_evidence->>'file_url', ''),
          NULLIF(v_evidence->>'file_path', ''), NULLIF(v_evidence->>'mime_type', ''),
          NULLIF(v_evidence->>'size_bytes', '')::bigint, NULLIF(v_evidence->>'notes', '')
        );
      END LOOP;
    END IF;
  END LOOP;

  IF p_evidences IS NOT NULL THEN
    FOR v_evidence IN
      SELECT e.value FROM jsonb_array_elements(p_evidences) AS e(value)
      WHERE NULLIF(e.value->>'template_item_id', '') IS NULL
    LOOP
      INSERT INTO public.inspection_run_evidences (run_id, answer_id, file_name, file_url, file_path, mime_type, size_bytes, notes)
      VALUES (
        p_run_id, NULL, v_evidence->>'file_name', NULLIF(v_evidence->>'file_url', ''),
        NULLIF(v_evidence->>'file_path', ''), NULLIF(v_evidence->>'mime_type', ''),
        NULLIF(v_evidence->>'size_bytes', '')::bigint, NULLIF(v_evidence->>'notes', '')
      );
    END LOOP;
  END IF;

  v_result := CASE
    WHEN v_any_failure THEN 'failed'
    WHEN v_answered_count > 0 AND v_all_not_applicable THEN 'not_applicable'
    ELSE 'passed'
  END;

  UPDATE public.inspection_runs ir
  SET started_at = p_started_at,
      completed_at = p_completed_at,
      status = 'completed',
      result = v_result,
      notes = NULLIF(TRIM(COALESCE(p_notes, '')), '')
  WHERE ir.id = p_run_id
  RETURNING ir.* INTO v_saved;

  -- Advance the originating plan's next_due_at from the completion time
  -- (never from the previous next_due_at), so a late inspection never
  -- compounds drift into the following cycle. one_time plans are left
  -- as-is (a single occurrence has no "next").
  IF v_saved.plan_id IS NOT NULL THEN
    SELECT CASE
      WHEN ip.frequency = 'daily' THEN interval '1 day'
      WHEN ip.frequency = 'weekly' THEN interval '7 days'
      WHEN ip.frequency = 'monthly' THEN interval '1 month'
      WHEN ip.frequency = 'quarterly' THEN interval '3 months'
      WHEN ip.frequency = 'semiannual' THEN interval '6 months'
      WHEN ip.frequency = 'annual' THEN interval '1 year'
      WHEN ip.frequency = 'custom' AND ip.custom_interval IS NOT NULL AND ip.custom_unit IS NOT NULL THEN
        CASE ip.custom_unit
          WHEN 'days' THEN make_interval(days => ip.custom_interval)
          WHEN 'weeks' THEN make_interval(weeks => ip.custom_interval)
          WHEN 'months' THEN make_interval(months => ip.custom_interval)
          WHEN 'years' THEN make_interval(years => ip.custom_interval)
          ELSE NULL
        END
      ELSE NULL
    END INTO v_frequency_interval
    FROM public.inspection_plans ip
    WHERE ip.id = v_saved.plan_id AND ip.is_active;

    IF v_frequency_interval IS NOT NULL THEN
      UPDATE public.inspection_plans ip
      SET next_due_at = v_saved.completed_at + v_frequency_interval
      WHERE ip.id = v_saved.plan_id;
    END IF;
  END IF;

  IF v_saved.asset_id IS NOT NULL THEN
    INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
    SELECT
      v_saved.organization_id,
      v_saved.asset_id,
      'inspection_completed',
      'Inspección completada: ' || ct.name || ' (' || v_result || ')',
      jsonb_build_object('result', v_result, 'template_id', v_saved.template_id, 'template_name', ct.name, 'run_id', v_saved.id),
      auth.uid()
    FROM public.checklist_templates ct
    WHERE ct.id = v_saved.template_id;
  END IF;

  RETURN v_saved;
END;
$function$;

-- ---- Preventivo: lectura (READ) ----

CREATE OR REPLACE FUNCTION public.get_maintenance_cards(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  -- Miembro directo / platform admin: respuesta histórica completa.
  -- Facility Manager delegado: sin datos de inventario.
  v_direct boolean := public.is_platform_admin() OR public.is_organization_member(p_organization_id);
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_preventive_maintenance(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view maintenance cards';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'organization_id', c.organization_id, 'code', c.code, 'name', c.name,
      'description', c.description, 'category', c.category, 'estimated_hours', c.estimated_hours,
      'procedure_notes', c.procedure_notes, 'safety_notes', c.safety_notes,
      'is_active', c.is_active, 'created_at', c.created_at, 'updated_at', c.updated_at,
      'tasks', COALESCE((SELECT jsonb_agg(to_jsonb(t) - 'card_id' ORDER BY t.sequence)
        FROM public.maintenance_card_tasks t WHERE t.card_id = c.id), '[]'::jsonb),
      'materials', COALESCE((SELECT jsonb_agg(
        CASE WHEN v_direct THEN
        (to_jsonb(cm) - 'card_id') || jsonb_build_object(
          'material_code', m.code, 'material_name', m.name, 'current_stock', m.stock,
          'material_is_active', m.is_active
        )
        ELSE (to_jsonb(cm) - 'card_id' - 'material_id')
          || jsonb_build_object('client_linked_material', cm.material_id IS NOT NULL)
        END ORDER BY cm.sequence)
        FROM public.maintenance_card_materials cm
        LEFT JOIN public.materials m ON m.id = cm.material_id
        WHERE cm.card_id = c.id), '[]'::jsonb)
    ) ORDER BY c.is_active DESC, lower(c.code))
    FROM public.maintenance_cards c
    WHERE c.organization_id = p_organization_id AND (p_include_inactive OR c.is_active)
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_preventive_maintenance_plans(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  -- Miembro directo / platform admin: respuesta histórica completa.
  -- Facility Manager delegado: sin datos de inventario.
  v_direct boolean := public.is_platform_admin() OR public.is_organization_member(p_organization_id);
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_preventive_maintenance(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', p.id, 'organization_id', p.organization_id, 'asset_id', p.asset_id,
      'asset_name', a.name, 'asset_code', a.code, 'asset_path', public.resolve_asset_path(a.id),
      'card_id', p.card_id, 'card_code', c.code, 'card_name', c.name,
      'trigger_type', p.trigger_type, 'priority', p.priority,
      'default_request_type', p.default_request_type, 'responsible_member_id', p.responsible_member_id,
      'planning_lead_days', p.planning_lead_days, 'frequency', p.frequency,
      'custom_interval', p.custom_interval, 'custom_unit', p.custom_unit,
      'first_due_at', p.first_due_at, 'meter_id', p.meter_id, 'meter_name', m.name,
      'meter_unit', m.unit, 'interval_value', p.interval_value, 'baseline_value', p.baseline_value,
      'baseline_reading_id', p.baseline_reading_id, 'meter_lead_value', p.meter_lead_value,
      'is_active', p.is_active, 'created_at', p.created_at, 'updated_at', p.updated_at,
      'latest_meter_value', lr.value, 'latest_meter_recorded_at', lr.recorded_at,
      'current_occurrence', CASE WHEN o.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', o.id, 'sequence', o.sequence, 'status', o.status, 'due_at', o.due_at,
        'due_meter_value', o.due_meter_value,
        -- Solicitudes y OT no se delegan en 9C.2: el delegado no ve sus ids.
        'request_creation_id', CASE WHEN v_direct THEN o.request_creation_id END,
        'request_id', CASE WHEN v_direct THEN o.request_id END,
        'work_order_id', CASE WHEN v_direct THEN o.work_order_id END,
        'scope_snapshot', CASE WHEN v_direct THEN o.scope_snapshot ELSE public.sanitize_preventive_scope_snapshot(o.scope_snapshot) END, 'planned_at', o.planned_at
      ) END,
      'timing_status', CASE
        WHEN o.id IS NULL THEN NULL
        WHEN p.trigger_type = 'calendar' AND now() > o.due_at THEN 'overdue'
        WHEN p.trigger_type = 'calendar' AND now() >= o.due_at - make_interval(days => p.planning_lead_days) THEN 'due'
        WHEN p.trigger_type = 'calendar' THEN 'upcoming'
        WHEN lr.value IS NULL THEN 'no_reading'
        WHEN lr.value > o.due_meter_value THEN 'overdue'
        WHEN lr.value >= o.due_meter_value - p.meter_lead_value THEN 'due'
        ELSE 'upcoming'
      END,
      'meter_remaining_value', CASE
        WHEN p.trigger_type = 'meter' AND lr.value IS NOT NULL
          THEN o.due_meter_value - lr.value
        ELSE NULL
      END
    ) ORDER BY p.is_active DESC, lower(a.name), lower(c.code))
    FROM public.preventive_maintenance_plans p
    JOIN public.assets a ON a.id = p.asset_id
    JOIN public.maintenance_cards c ON c.id = p.card_id
    LEFT JOIN public.asset_meters m ON m.id = p.meter_id
    LEFT JOIN LATERAL (
      SELECT r.value, r.recorded_at FROM public.asset_meter_readings r
      WHERE r.meter_id = p.meter_id AND r.voided_at IS NULL ORDER BY r.recorded_at DESC LIMIT 1
    ) lr ON true
    LEFT JOIN public.preventive_maintenance_occurrences o
      ON o.plan_id = p.id AND o.status IN ('open', 'planned')
    WHERE p.organization_id = p_organization_id
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_preventive_maintenance_occurrences(p_organization_id uuid, p_asset_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  -- Miembro directo / platform admin: respuesta histórica completa.
  -- Facility Manager delegado: sin datos de inventario.
  v_direct boolean := public.is_platform_admin() OR public.is_organization_member(p_organization_id);
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_preventive_maintenance(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(o) || jsonb_build_object(
      'card_code', c.code, 'card_name', c.name, 'trigger_type', p.trigger_type,
      'priority', p.priority, 'asset_name', a.name, 'asset_code', a.code
    ) || CASE WHEN v_direct THEN '{}'::jsonb
         ELSE jsonb_build_object(
           'scope_snapshot', public.sanitize_preventive_scope_snapshot(o.scope_snapshot),
           -- Solicitudes y OT no se delegan en 9C.2: el delegado no ve sus ids.
           'request_creation_id', NULL, 'request_id', NULL, 'work_order_id', NULL) END
    ORDER BY o.created_at DESC)
    FROM public.preventive_maintenance_occurrences o
    JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
    JOIN public.maintenance_cards c ON c.id = p.card_id
    JOIN public.assets a ON a.id = o.asset_id
    WHERE o.organization_id = p_organization_id
      AND (p_asset_id IS NULL OR o.asset_id = p_asset_id)
      AND (p_status IS NULL OR o.status = p_status)
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_asset_meters(p_asset_id uuid, p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_org uuid;
BEGIN
  SELECT a.organization_id INTO v_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_org IS NULL THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF auth.uid() IS NULL OR NOT public.can_view_preventive_maintenance(v_org) THEN
    RAISE EXCEPTION 'Not authorized to view asset meters';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', m.id, 'organization_id', m.organization_id, 'asset_id', m.asset_id,
      'name', m.name, 'unit', m.unit, 'is_active', m.is_active,
      'replaces_meter_id', m.replaces_meter_id, 'retired_at', m.retired_at,
      'retirement_reason', m.retirement_reason, 'created_at', m.created_at,
      'readings', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', r.id, 'value', r.value, 'recorded_at', r.recorded_at, 'notes', r.notes,
          'supersedes_reading_id', r.supersedes_reading_id, 'created_at', r.created_at
        ) ORDER BY r.recorded_at DESC)
        FROM public.asset_meter_readings r WHERE r.meter_id = m.id AND r.voided_at IS NULL
      ), '[]'::jsonb)
    ) ORDER BY m.is_active DESC, lower(m.name))
    FROM public.asset_meters m
    WHERE m.asset_id = p_asset_id AND (p_include_inactive OR m.is_active)
  ), '[]'::jsonb);
END;
$function$;

-- ---- Preventivo: planificación y administración de medidores (MANAGE) ----

CREATE OR REPLACE FUNCTION public.set_maintenance_card_active(p_card_id uuid, p_is_active boolean)
 RETURNS maintenance_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_card public.maintenance_cards%ROWTYPE;
BEGIN
  SELECT * INTO v_card FROM public.maintenance_cards WHERE id = p_card_id FOR UPDATE;
  IF v_card.id IS NULL THEN RAISE EXCEPTION 'Maintenance card not found'; END IF;
  IF NOT public.can_plan_preventive_maintenance(v_card.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT p_is_active AND EXISTS (
    SELECT 1 FROM public.preventive_maintenance_plans p WHERE p.card_id = p_card_id AND p.is_active
  ) THEN RAISE EXCEPTION 'Cannot deactivate a card used by an active preventive maintenance plan'; END IF;
  UPDATE public.maintenance_cards SET is_active = p_is_active WHERE id = p_card_id RETURNING * INTO v_card;
  RETURN v_card;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_preventive_maintenance_plan_active(p_plan_id uuid, p_is_active boolean, p_reason text DEFAULT NULL::text)
 RETURNS preventive_maintenance_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_latest numeric;
BEGIN
  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = p_plan_id FOR UPDATE;
  IF v_plan.id IS NULL THEN RAISE EXCEPTION 'Plan not found'; END IF;
  IF NOT public.can_plan_preventive_maintenance(v_plan.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF v_plan.is_active = p_is_active THEN RETURN v_plan; END IF;

  IF NOT p_is_active THEN
    IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A deactivation reason is required'; END IF;
    SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences o
    WHERE o.plan_id = p_plan_id AND o.status IN ('open', 'planned') FOR UPDATE;
    IF v_occ.status = 'open' THEN
      UPDATE public.preventive_maintenance_occurrences SET
        status = 'cancelled', cancelled_at = now(), cancel_reason = TRIM(p_reason)
      WHERE id = v_occ.id;
    END IF;
    UPDATE public.preventive_maintenance_plans SET is_active = false WHERE id = p_plan_id RETURNING * INTO v_plan;
  ELSE
    UPDATE public.preventive_maintenance_plans SET is_active = true WHERE id = p_plan_id RETURNING * INTO v_plan;
    IF NOT EXISTS (
      SELECT 1 FROM public.preventive_maintenance_occurrences o
      WHERE o.plan_id = p_plan_id AND o.status IN ('open', 'planned')
    ) THEN
      IF v_plan.trigger_type = 'calendar' THEN
        v_occ := public.create_preventive_occurrence_locked(
          v_plan.id, now() + public.preventive_frequency_interval(v_plan.frequency, v_plan.custom_interval, v_plan.custom_unit), NULL
        );
      ELSE
        SELECT r.value INTO v_latest FROM public.asset_meter_readings r
        WHERE r.meter_id = v_plan.meter_id AND r.voided_at IS NULL ORDER BY r.recorded_at DESC LIMIT 1;
        IF v_latest IS NULL THEN RAISE EXCEPTION 'Cannot reactivate a meter plan without an effective reading'; END IF;
        v_occ := public.create_preventive_occurrence_locked(v_plan.id, NULL, v_latest + v_plan.interval_value);
      END IF;
    END IF;
  END IF;
  RETURN v_plan;
END;
$function$;

CREATE OR REPLACE FUNCTION public.skip_preventive_maintenance_occurrence(p_occurrence_id uuid, p_reason text)
 RETURNS preventive_maintenance_occurrences
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_plan_id uuid;
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
BEGIN
  SELECT o.plan_id INTO v_plan_id FROM public.preventive_maintenance_occurrences o WHERE o.id = p_occurrence_id;
  IF v_plan_id IS NULL THEN RAISE EXCEPTION 'Preventive maintenance occurrence not found'; END IF;
  SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = v_plan_id FOR UPDATE;
  SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences WHERE id = p_occurrence_id FOR UPDATE;
  IF NOT public.can_plan_preventive_maintenance(v_occ.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF v_occ.status = 'skipped' THEN RETURN v_occ; END IF;
  IF v_occ.status <> 'open' THEN RAISE EXCEPTION 'Only an open occurrence can be skipped'; END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A skip reason is required'; END IF;

  UPDATE public.preventive_maintenance_occurrences SET
    status = 'skipped', skipped_at = now(), skip_reason = TRIM(p_reason)
  WHERE id = v_occ.id RETURNING * INTO v_occ;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_occ.organization_id, v_occ.asset_id, 'preventive_maintenance_skipped',
    'Mantenimiento preventivo omitido: ' || TRIM(p_reason),
    jsonb_build_object('plan_id', v_occ.plan_id, 'occurrence_id', v_occ.id,
      'sequence', v_occ.sequence, 'reason', TRIM(p_reason)), auth.uid()
  );
  PERFORM public.notify_preventive_occurrence(
    v_occ.id, 'preventive_maintenance_skipped', 'Mantenimiento preventivo omitido',
    'La ocurrencia preventiva #' || v_occ.sequence::text || ' fue omitida: ' || TRIM(p_reason)
  );
  IF v_plan.is_active THEN
    IF v_plan.trigger_type = 'calendar' THEN
      PERFORM public.create_preventive_occurrence_locked(
        v_plan.id,
        v_occ.due_at + public.preventive_frequency_interval(v_plan.frequency, v_plan.custom_interval, v_plan.custom_unit),
        NULL
      );
    ELSE
      PERFORM public.create_preventive_occurrence_locked(v_plan.id, NULL, v_occ.due_meter_value + v_plan.interval_value);
    END IF;
  END IF;
  RETURN v_occ;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_asset_meter(p_organization_id uuid, p_asset_id uuid, p_name text, p_unit text, p_initial_value numeric DEFAULT NULL::numeric, p_recorded_at timestamp with time zone DEFAULT now(), p_notes text DEFAULT NULL::text)
 RETURNS asset_meters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_meter public.asset_meters%ROWTYPE;
BEGIN
  IF NOT public.can_plan_preventive_maintenance(p_organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  INSERT INTO public.asset_meters (organization_id, asset_id, name, unit, created_by_user_id)
  VALUES (p_organization_id, p_asset_id, TRIM(p_name), TRIM(p_unit), auth.uid()) RETURNING * INTO v_meter;
  IF p_initial_value IS NOT NULL THEN
    PERFORM public.record_asset_meter_reading(v_meter.id, p_initial_value, p_recorded_at, p_notes);
  END IF;
  RETURN v_meter;
END;
$function$;

CREATE OR REPLACE FUNCTION public.correct_asset_meter_reading(p_reading_id uuid, p_value numeric, p_reason text, p_notes text DEFAULT NULL::text)
 RETURNS asset_meter_readings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_original public.asset_meter_readings%ROWTYPE;
  v_meter public.asset_meters%ROWTYPE;
  v_replacement public.asset_meter_readings%ROWTYPE;
  v_previous numeric;
  v_next numeric;
BEGIN
  SELECT r.* INTO v_original FROM public.asset_meter_readings r WHERE r.id = p_reading_id;
  IF v_original.id IS NULL THEN RAISE EXCEPTION 'Meter reading not found'; END IF;
  SELECT * INTO v_meter FROM public.asset_meters WHERE id = v_original.meter_id FOR UPDATE;
  SELECT r.* INTO v_original FROM public.asset_meter_readings r WHERE r.id = p_reading_id FOR UPDATE;
  IF NOT public.can_plan_preventive_maintenance(v_meter.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF v_original.voided_at IS NOT NULL THEN RAISE EXCEPTION 'Only an effective reading can be corrected'; END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A correction reason is required'; END IF;
  IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'Meter reading must be non-negative'; END IF;

  SELECT r.value INTO v_previous FROM public.asset_meter_readings r
  WHERE r.meter_id = v_meter.id AND r.voided_at IS NULL AND r.id <> v_original.id
    AND r.recorded_at < v_original.recorded_at ORDER BY r.recorded_at DESC LIMIT 1;
  SELECT r.value INTO v_next FROM public.asset_meter_readings r
  WHERE r.meter_id = v_meter.id AND r.voided_at IS NULL AND r.id <> v_original.id
    AND r.recorded_at > v_original.recorded_at ORDER BY r.recorded_at ASC LIMIT 1;
  IF v_previous IS NOT NULL AND p_value < v_previous THEN RAISE EXCEPTION 'Corrected reading violates monotonic history'; END IF;
  IF v_next IS NOT NULL AND p_value > v_next THEN RAISE EXCEPTION 'Corrected reading violates monotonic history'; END IF;

  UPDATE public.asset_meter_readings SET voided_at = now(), voided_by_user_id = auth.uid(), void_reason = TRIM(p_reason)
  WHERE id = v_original.id;
  INSERT INTO public.asset_meter_readings (
    meter_id, value, recorded_at, notes, created_by_user_id, supersedes_reading_id
  ) VALUES (
    v_meter.id, p_value, v_original.recorded_at, COALESCE(NULLIF(TRIM(p_notes), ''), v_original.notes),
    auth.uid(), v_original.id
  ) RETURNING * INTO v_replacement;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_meter.organization_id, v_meter.asset_id, 'meter_reading_recorded',
    'Lectura de medidor corregida: ' || v_meter.name || ' = ' || p_value::text || ' ' || v_meter.unit,
    jsonb_build_object('meter_id', v_meter.id, 'reading_id', v_replacement.id,
      'supersedes_reading_id', v_original.id, 'value', p_value, 'unit', v_meter.unit,
      'recorded_at', v_original.recorded_at, 'correction_reason', TRIM(p_reason)), auth.uid()
  );
  RETURN v_replacement;
END;
$function$;

CREATE OR REPLACE FUNCTION public.retire_asset_meter(p_meter_id uuid, p_reason text)
 RETURNS asset_meters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_meter public.asset_meters%ROWTYPE;
BEGIN
  SELECT * INTO v_meter FROM public.asset_meters WHERE id = p_meter_id FOR UPDATE;
  IF v_meter.id IS NULL THEN RAISE EXCEPTION 'Asset meter not found'; END IF;
  IF NOT public.can_plan_preventive_maintenance(v_meter.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT v_meter.is_active THEN RETURN v_meter; END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A retirement reason is required'; END IF;
  IF EXISTS (SELECT 1 FROM public.preventive_maintenance_plans p WHERE p.meter_id = p_meter_id AND p.is_active) THEN
    RAISE EXCEPTION 'Deactivate active preventive plans before retiring their meter';
  END IF;
  UPDATE public.asset_meters SET is_active = false, retired_at = now(), retirement_reason = TRIM(p_reason)
  WHERE id = p_meter_id RETURNING * INTO v_meter;
  RETURN v_meter;
END;
$function$;

CREATE OR REPLACE FUNCTION public.replace_asset_meter(p_meter_id uuid, p_name text, p_unit text, p_initial_value numeric, p_recorded_at timestamp with time zone, p_reason text, p_notes text DEFAULT NULL::text)
 RETURNS asset_meters
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_old public.asset_meters%ROWTYPE; v_new public.asset_meters%ROWTYPE;
BEGIN
  SELECT * INTO v_old FROM public.asset_meters WHERE id = p_meter_id FOR UPDATE;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Asset meter not found'; END IF;
  IF NOT public.can_plan_preventive_maintenance(v_old.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT v_old.is_active THEN RAISE EXCEPTION 'Only an active meter can be replaced'; END IF;
  IF EXISTS (SELECT 1 FROM public.preventive_maintenance_plans p WHERE p.meter_id = p_meter_id AND p.is_active) THEN
    RAISE EXCEPTION 'Deactivate active preventive plans before replacing their meter';
  END IF;
  IF TRIM(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'A replacement reason is required'; END IF;
  UPDATE public.asset_meters SET is_active = false, retired_at = now(), retirement_reason = TRIM(p_reason)
  WHERE id = v_old.id;
  INSERT INTO public.asset_meters (
    organization_id, asset_id, name, unit, replaces_meter_id, created_by_user_id
  ) VALUES (
    v_old.organization_id, v_old.asset_id, TRIM(p_name), TRIM(p_unit), v_old.id, auth.uid()
  ) RETURNING * INTO v_new;
  PERFORM public.record_asset_meter_reading(v_new.id, p_initial_value, p_recorded_at, p_notes);
  RETURN v_new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_maintenance_card(p_organization_id uuid, p_code text, p_name text, p_description text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_estimated_hours numeric DEFAULT NULL::numeric, p_procedure_notes text DEFAULT NULL::text, p_safety_notes text DEFAULT NULL::text, p_tasks jsonb DEFAULT '[]'::jsonb, p_materials jsonb DEFAULT '[]'::jsonb, p_card_id uuid DEFAULT NULL::uuid)
 RETURNS maintenance_cards
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_card public.maintenance_cards%ROWTYPE;
  v_item jsonb;
  v_sequence integer;
  v_material_org uuid;
  v_direct boolean;
BEGIN
  IF NOT public.can_plan_preventive_maintenance(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to manage maintenance cards';
  END IF;
  -- 9C.2: Inventario no se delega. Un Facility Manager solo escribe
  -- materiales de descripción libre (material_id NULL); los materiales que
  -- el cliente vinculó a su catálogo se conservan intactos.
  v_direct := public.can_manage_preventive_maintenance(p_organization_id);
  IF TRIM(COALESCE(p_code, '')) = '' OR TRIM(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'Code and name are required';
  END IF;
  IF jsonb_typeof(COALESCE(p_tasks, '[]'::jsonb)) <> 'array'
    OR jsonb_typeof(COALESCE(p_materials, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Tasks and materials must be JSON arrays';
  END IF;
  IF NOT v_direct AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(p_materials, '[]'::jsonb)) AS item(value)
    WHERE NULLIF(item.value->>'material_id', '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A delegated facility manager cannot link inventory materials' USING ERRCODE = '42501';
  END IF;

  IF p_card_id IS NULL THEN
    INSERT INTO public.maintenance_cards (
      organization_id, code, name, description, category, estimated_hours,
      procedure_notes, safety_notes, created_by_user_id
    ) VALUES (
      p_organization_id, TRIM(p_code), TRIM(p_name), NULLIF(TRIM(p_description), ''),
      NULLIF(TRIM(p_category), ''), p_estimated_hours, NULLIF(TRIM(p_procedure_notes), ''),
      NULLIF(TRIM(p_safety_notes), ''), auth.uid()
    ) RETURNING * INTO v_card;
  ELSE
    SELECT * INTO v_card FROM public.maintenance_cards WHERE id = p_card_id FOR UPDATE;
    IF v_card.id IS NULL OR v_card.organization_id <> p_organization_id THEN
      RAISE EXCEPTION 'Maintenance card not found in this organization';
    END IF;
    UPDATE public.maintenance_cards SET
      code = TRIM(p_code), name = TRIM(p_name), description = NULLIF(TRIM(p_description), ''),
      category = NULLIF(TRIM(p_category), ''), estimated_hours = p_estimated_hours,
      procedure_notes = NULLIF(TRIM(p_procedure_notes), ''), safety_notes = NULLIF(TRIM(p_safety_notes), '')
    WHERE id = p_card_id RETURNING * INTO v_card;
    DELETE FROM public.maintenance_card_tasks WHERE card_id = p_card_id;
    DELETE FROM public.maintenance_card_materials WHERE card_id = p_card_id
      AND (v_direct OR material_id IS NULL);
  END IF;

  v_sequence := 0;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_tasks, '[]'::jsonb)) LOOP
    v_sequence := v_sequence + 1;
    INSERT INTO public.maintenance_card_tasks (card_id, sequence, title, description, estimated_hours, is_required)
    VALUES (
      v_card.id, v_sequence, TRIM(v_item->>'title'), NULLIF(TRIM(v_item->>'description'), ''),
      NULLIF(v_item->>'estimated_hours', '')::numeric, COALESCE((v_item->>'is_required')::boolean, true)
    );
  END LOOP;

  v_sequence := CASE WHEN v_direct THEN 0 ELSE COALESCE((
    SELECT max(cm.sequence) FROM public.maintenance_card_materials cm WHERE cm.card_id = v_card.id
  ), 0) END;
  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_materials, '[]'::jsonb)) LOOP
    v_sequence := v_sequence + 1;
    IF NULLIF(v_item->>'material_id', '') IS NOT NULL THEN
      SELECT m.organization_id INTO v_material_org FROM public.materials m
      WHERE m.id = (v_item->>'material_id')::uuid;
      IF v_material_org IS NULL OR v_material_org <> p_organization_id THEN
        RAISE EXCEPTION 'Linked material must belong to this organization';
      END IF;
    END IF;
    INSERT INTO public.maintenance_card_materials (card_id, sequence, material_id, description, quantity, unit, notes)
    VALUES (
      v_card.id, v_sequence, NULLIF(v_item->>'material_id', '')::uuid,
      TRIM(v_item->>'description'), (v_item->>'quantity')::numeric,
      TRIM(v_item->>'unit'), NULLIF(TRIM(v_item->>'notes'), '')
    );
  END LOOP;
  RETURN v_card;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_preventive_maintenance_plan(p_organization_id uuid, p_asset_id uuid, p_card_id uuid, p_trigger_type text, p_priority text DEFAULT 'medium'::text, p_default_request_type text DEFAULT 'internal'::text, p_responsible_member_id uuid DEFAULT NULL::uuid, p_planning_lead_days integer DEFAULT 30, p_frequency text DEFAULT NULL::text, p_custom_interval integer DEFAULT NULL::integer, p_custom_unit text DEFAULT NULL::text, p_first_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_meter_id uuid DEFAULT NULL::uuid, p_interval_value numeric DEFAULT NULL::numeric, p_baseline_reading_id uuid DEFAULT NULL::uuid, p_meter_lead_value numeric DEFAULT NULL::numeric, p_plan_id uuid DEFAULT NULL::uuid)
 RETURNS preventive_maintenance_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_plan public.preventive_maintenance_plans%ROWTYPE;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_baseline numeric;
  v_direct boolean;
BEGIN
  IF NOT public.can_plan_preventive_maintenance(p_organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  -- 9C.2: responsible_member_id pertenece al cliente; un Facility Manager
  -- delegado no lo fija en un plan nuevo ni lo cambia en uno existente.
  v_direct := public.can_manage_preventive_maintenance(p_organization_id);
  IF NOT v_direct AND p_plan_id IS NULL AND p_responsible_member_id IS NOT NULL THEN
    RAISE EXCEPTION 'The preventive plan responsible is assigned by the client' USING ERRCODE = '42501';
  END IF;
  IF p_trigger_type = 'meter' AND p_plan_id IS NULL THEN
    SELECT r.value INTO v_baseline FROM public.asset_meter_readings r
    WHERE r.id = p_baseline_reading_id AND r.meter_id = p_meter_id AND r.voided_at IS NULL;
    IF v_baseline IS NULL THEN RAISE EXCEPTION 'A valid baseline reading is required'; END IF;
  END IF;

  IF p_plan_id IS NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.maintenance_cards c WHERE c.id = p_card_id AND c.is_active) THEN
      RAISE EXCEPTION 'An active maintenance card is required';
    END IF;
    INSERT INTO public.preventive_maintenance_plans (
      organization_id, asset_id, card_id, trigger_type, priority, default_request_type,
      responsible_member_id, planning_lead_days, frequency, custom_interval, custom_unit,
      first_due_at, meter_id, interval_value, baseline_value, baseline_reading_id,
      meter_lead_value, created_by_user_id
    ) VALUES (
      p_organization_id, p_asset_id, p_card_id, p_trigger_type, p_priority, p_default_request_type,
      p_responsible_member_id, p_planning_lead_days, p_frequency, p_custom_interval, p_custom_unit,
      p_first_due_at, p_meter_id, p_interval_value, v_baseline, p_baseline_reading_id,
      p_meter_lead_value, auth.uid()
    ) RETURNING * INTO v_plan;

    IF v_plan.trigger_type = 'calendar' THEN
      v_occ := public.create_preventive_occurrence_locked(v_plan.id, v_plan.first_due_at, NULL);
    ELSE
      v_occ := public.create_preventive_occurrence_locked(v_plan.id, NULL, v_plan.baseline_value + v_plan.interval_value);
    END IF;
    INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
    VALUES (
      v_plan.organization_id, v_plan.asset_id, 'preventive_plan_created',
      'Plan de mantenimiento preventivo creado',
      jsonb_build_object('plan_id', v_plan.id, 'occurrence_id', v_occ.id, 'card_id', v_plan.card_id,
        'trigger_type', v_plan.trigger_type), auth.uid()
    );
  ELSE
    SELECT * INTO v_plan FROM public.preventive_maintenance_plans WHERE id = p_plan_id FOR UPDATE;
    IF v_plan.id IS NULL OR v_plan.organization_id <> p_organization_id THEN RAISE EXCEPTION 'Plan not found'; END IF;
    IF NOT v_direct AND p_responsible_member_id IS DISTINCT FROM v_plan.responsible_member_id THEN
      RAISE EXCEPTION 'The preventive plan responsible is assigned by the client' USING ERRCODE = '42501';
    END IF;
    IF v_plan.asset_id <> p_asset_id OR v_plan.card_id <> p_card_id
      OR v_plan.trigger_type <> p_trigger_type OR v_plan.meter_id IS DISTINCT FROM p_meter_id THEN
      RAISE EXCEPTION 'Asset, card, trigger type and meter are immutable';
    END IF;
    IF v_plan.baseline_reading_id IS DISTINCT FROM p_baseline_reading_id THEN
      RAISE EXCEPTION 'The meter baseline is immutable';
    END IF;
    UPDATE public.preventive_maintenance_plans SET
      priority = p_priority, default_request_type = p_default_request_type,
      responsible_member_id = p_responsible_member_id, planning_lead_days = p_planning_lead_days,
      frequency = p_frequency, custom_interval = p_custom_interval, custom_unit = p_custom_unit,
      first_due_at = p_first_due_at, interval_value = p_interval_value,
      meter_lead_value = p_meter_lead_value
    WHERE id = p_plan_id RETURNING * INTO v_plan;
  END IF;
  RETURN v_plan;
END;
$function$;

-- ---- Preventivo: registrar lectura (RECORD) ----

CREATE OR REPLACE FUNCTION public.record_asset_meter_reading(p_meter_id uuid, p_value numeric, p_recorded_at timestamp with time zone DEFAULT now(), p_notes text DEFAULT NULL::text)
 RETURNS asset_meter_readings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_meter public.asset_meters%ROWTYPE;
  v_reading public.asset_meter_readings%ROWTYPE;
  v_previous numeric;
  v_next numeric;
BEGIN
  SELECT * INTO v_meter FROM public.asset_meters WHERE id = p_meter_id FOR UPDATE;
  IF v_meter.id IS NULL THEN RAISE EXCEPTION 'Asset meter not found'; END IF;
  IF NOT public.can_record_preventive_meter_reading(v_meter.organization_id) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT v_meter.is_active THEN RAISE EXCEPTION 'Cannot record a reading on a retired meter'; END IF;
  IF p_value IS NULL OR p_value < 0 THEN RAISE EXCEPTION 'Meter reading must be non-negative'; END IF;

  SELECT r.value INTO v_previous FROM public.asset_meter_readings r
  WHERE r.meter_id = p_meter_id AND r.voided_at IS NULL AND r.recorded_at < p_recorded_at
  ORDER BY r.recorded_at DESC LIMIT 1;
  SELECT r.value INTO v_next FROM public.asset_meter_readings r
  WHERE r.meter_id = p_meter_id AND r.voided_at IS NULL AND r.recorded_at > p_recorded_at
  ORDER BY r.recorded_at ASC LIMIT 1;
  IF v_previous IS NOT NULL AND p_value < v_previous THEN
    RAISE EXCEPTION 'Reading cannot be lower than the previous effective reading (%)', v_previous;
  END IF;
  IF v_next IS NOT NULL AND p_value > v_next THEN
    RAISE EXCEPTION 'Reading cannot be higher than the next effective reading (%)', v_next;
  END IF;

  INSERT INTO public.asset_meter_readings (meter_id, value, recorded_at, notes, created_by_user_id)
  VALUES (p_meter_id, p_value, p_recorded_at, NULLIF(TRIM(p_notes), ''), auth.uid()) RETURNING * INTO v_reading;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_meter.organization_id, v_meter.asset_id, 'meter_reading_recorded',
    'Lectura de medidor registrada: ' || v_meter.name || ' = ' || p_value::text || ' ' || v_meter.unit,
    jsonb_build_object('meter_id', v_meter.id, 'reading_id', v_reading.id, 'value', p_value,
      'unit', v_meter.unit, 'recorded_at', p_recorded_at), auth.uid()
  );
  RETURN v_reading;
END;
$function$;

-- plan_preventive_maintenance_occurrence (vincula una Solicitud a la
-- ocurrencia) NO se reemplaza: sigue usando can_manage_preventive_maintenance,
-- que no incluye acceso delegado. Pertenece a 9C.4 (Requests).
