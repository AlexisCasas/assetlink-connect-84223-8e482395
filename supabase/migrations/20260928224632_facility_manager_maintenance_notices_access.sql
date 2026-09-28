-- =========================================================================
-- Fase 1 · Punto 9C.3 — Acceso operativo de Facility Manager a Avisos de
-- avería / Backlog.
--
-- Hace efectivos SOLO maintenance_notices.view, maintenance_notices.report y
-- maintenance_notices.manage. No abre requests.*, providers.*, quotes.*,
-- work_orders.*, reports.*, inventario ni R2.
--
-- Acceso delegado = has_facility_management_operational_access_all (9C.1):
-- relación facility_management ACTIVE + cliente ACTIVE + FM ACTIVE +
-- membresía ACTIVA en ESE FM + ESA membresía asignada a ESA relación +
-- todos los permisos en ESA relación + rol compatible.
--
-- Matriz del FM (el acceso directo de los miembros del cliente NO cambia):
--   ver       maintenance_notices.view               o/a/m/t/requester/viewer
--   reportar  view + report                          o/a/m/t/requester
--   gestionar view + manage (revisar, prioridad,     o/a/m
--             notas, descartar)
-- manage no exige report. *.manage / *.report nunca sustituyen a *.view.
--
-- Reglas propias del modo delegado:
--   - convert_maintenance_notice (convertir en Solicitud) NO se delega: sigue
--     con can_manage_maintenance_notice, que es directa. Pertenece a 9C.4.
--   - responsible_member_id es del CLIENTE: el FM no lo asigna, cambia ni
--     limpia al revisar, y no recibe el roster del cliente.
--   - Respuestas minimizadas: sin source_id, item_id, request id/número, ids
--     de usuario ni de membresía; nombres nunca derivados del email;
--     criticidad viva solo con criticality.view efectivo.
--   - Aviso desde una inspección: exige además inspections.view.
--   - Aviso manual: el FM no puede usar un activo archivado.
-- Ver docs/FACILITY_MANAGER_MAINTENANCE_NOTICES.md.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1) Capacidades: acceso directo histórico (idéntico) OR delegado. Internas.
--    can_report_maintenance_notice y can_manage_maintenance_notice (directas)
--    NO cambian: la segunda también protege convert_maintenance_notice.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_view_maintenance_notices(_organization_id uuid)
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
      ARRAY['maintenance_notices.view']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager', 'technician', 'requester', 'viewer']::public.organization_member_role[]
    );
$$;

CREATE OR REPLACE FUNCTION public.can_create_maintenance_notice(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.can_report_maintenance_notice(_organization_id)
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['maintenance_notices.view', 'maintenance_notices.report']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager', 'technician', 'requester']::public.organization_member_role[]
    );
$$;

CREATE OR REPLACE FUNCTION public.can_triage_maintenance_notice(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.can_manage_maintenance_notice(_organization_id)
    OR public.has_facility_management_operational_access_all(
      _organization_id,
      ARRAY['maintenance_notices.view', 'maintenance_notices.manage']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_maintenance_notices(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_create_maintenance_notice(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_triage_maintenance_notice(uuid) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 2) Fila de aviso minimizada para un escritor delegado (create/triage/
--    dismiss devuelven la fila completa). Sin ids de otros módulos ni de
--    usuarios/membresías del cliente. Interna.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sanitize_maintenance_notice_for_delegate(_notice public.maintenance_notices)
RETURNS public.maintenance_notices
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_notice public.maintenance_notices := _notice;
BEGIN
  v_notice.source_id := NULL;
  v_notice.source_metadata := COALESCE(v_notice.source_metadata, '{}'::jsonb) - 'item_id';
  v_notice.reported_by_user_id := NULL;
  v_notice.responsible_member_id := NULL;
  v_notice.triaged_by_user_id := NULL;
  v_notice.converted_request_id := NULL;
  v_notice.converted_by_user_id := NULL;
  v_notice.dismissed_by_user_id := NULL;
  RETURN v_notice;
END;
$$;

REVOKE ALL ON FUNCTION public.sanitize_maintenance_notice_for_delegate(public.maintenance_notices) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 3) Directorio mínimo de activos para reportar (solo modo delegado).
--    maintenance_notices.report NO implica assets.view: no abre la RLS de
--    assets ni el módulo #assets. Solo activos no archivados del cliente;
--    sin metadata, datos técnicos, imagen, QR, responsable, criticidad,
--    inventario ni R2.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_facility_management_maintenance_notice_assets(_client_organization_id uuid)
RETURNS TABLE (id uuid, name text, code text, status text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['maintenance_notices.view', 'maintenance_notices.report']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager', 'technician', 'requester']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized to report maintenance notices for this client' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT a.id, a.name, a.code, a.status
  FROM public.assets a
  WHERE a.organization_id = _client_organization_id AND a.status <> 'archived'
  ORDER BY lower(a.name);
END;
$$;

REVOKE ALL ON FUNCTION public.get_facility_management_maintenance_notice_assets(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_management_maintenance_notice_assets(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- 4) RPCs existentes: solo cambian su autorización y la minimización para
--    el delegado (verificado contra la definición vigente; firmas,
--    SECURITY DEFINER, search_path y grants se conservan).
-- -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_maintenance_notices(p_organization_id uuid)
 RETURNS TABLE(id uuid, organization_id uuid, notice_number text, asset_id uuid, title text, description text, priority text, status text, source_type text, source_id uuid, source_metadata jsonb, asset_name_snapshot text, asset_code_snapshot text, asset_path_snapshot text, branch_id_snapshot uuid, branch_name_snapshot text, asset_current_criticality text, reported_by_user_id uuid, reported_by_name text, reported_at timestamp with time zone, responsible_member_id uuid, responsible_name text, triage_notes text, triaged_by_name text, triaged_at timestamp with time zone, converted_request_id uuid, converted_request_number text, converted_by_name text, converted_at timestamp with time zone, dismissal_reason text, dismissed_by_name text, dismissed_at timestamp with time zone, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- Miembro directo / platform admin: respuesta histórica completa.
  -- Facility Manager delegado: respuesta minimizada (ver cabecera).
  v_direct boolean := public.is_platform_admin() OR public.is_organization_member(p_organization_id);
  -- La criticidad viva es del módulo Criticidad: el delegado la ve solo
  -- con criticality.view efectivo (matriz 9C.1).
  v_show_criticality boolean := v_direct OR public.can_view_criticality_matrix(p_organization_id);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.can_view_maintenance_notices(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view the maintenance backlog for this organization';
  END IF;

  RETURN QUERY
  SELECT
    mn.id,
    mn.organization_id,
    mn.notice_number,
    mn.asset_id,
    mn.title,
    mn.description,
    mn.priority,
    mn.status,
    mn.source_type,
    CASE WHEN v_direct THEN mn.source_id END,
    CASE WHEN v_direct THEN mn.source_metadata ELSE mn.source_metadata - 'item_id' END,
    mn.asset_name_snapshot,
    mn.asset_code_snapshot,
    mn.asset_path_snapshot,
    mn.branch_id_snapshot,
    mn.branch_name_snapshot,
    CASE WHEN v_show_criticality THEN a.criticality END AS asset_current_criticality,
    CASE WHEN v_direct THEN mn.reported_by_user_id END,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(reporter.raw_user_meta_data->>'name'), ''), split_part(reporter.email, '@', 1)) ELSE NULLIF(TRIM(reporter.raw_user_meta_data->>'name'), '') END AS reported_by_name,
    mn.reported_at,
    CASE WHEN v_direct THEN mn.responsible_member_id END,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(responsible_user.raw_user_meta_data->>'name'), ''), split_part(responsible_user.email, '@', 1)) ELSE COALESCE(NULLIF(TRIM(responsible_user.raw_user_meta_data->>'name'), ''), CASE WHEN mn.responsible_member_id IS NOT NULL THEN 'Asignado por el cliente' END) END AS responsible_name,
    mn.triage_notes,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(triager.raw_user_meta_data->>'name'), ''), split_part(triager.email, '@', 1)) ELSE NULLIF(TRIM(triager.raw_user_meta_data->>'name'), '') END AS triaged_by_name,
    mn.triaged_at,
    CASE WHEN v_direct THEN mn.converted_request_id END,
    CASE WHEN v_direct THEN r.request_number END AS converted_request_number,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(converter.raw_user_meta_data->>'name'), ''), split_part(converter.email, '@', 1)) ELSE NULLIF(TRIM(converter.raw_user_meta_data->>'name'), '') END AS converted_by_name,
    mn.converted_at,
    mn.dismissal_reason,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(dismisser.raw_user_meta_data->>'name'), ''), split_part(dismisser.email, '@', 1)) ELSE NULLIF(TRIM(dismisser.raw_user_meta_data->>'name'), '') END AS dismissed_by_name,
    mn.dismissed_at,
    mn.created_at
  FROM public.maintenance_notices mn
  INNER JOIN public.assets a ON a.id = mn.asset_id
  LEFT JOIN auth.users reporter ON reporter.id = mn.reported_by_user_id
  LEFT JOIN auth.users triager ON triager.id = mn.triaged_by_user_id
  LEFT JOIN auth.users converter ON converter.id = mn.converted_by_user_id
  LEFT JOIN auth.users dismisser ON dismisser.id = mn.dismissed_by_user_id
  LEFT JOIN public.organization_members responsible_member ON responsible_member.id = mn.responsible_member_id
  LEFT JOIN auth.users responsible_user ON responsible_user.id = responsible_member.user_id
  LEFT JOIN public.requests r ON r.id = mn.converted_request_id
  WHERE mn.organization_id = p_organization_id
  ORDER BY
    CASE mn.priority
      WHEN 'urgent' THEN 1
      WHEN 'high' THEN 2
      WHEN 'medium' THEN 3
      ELSE 4
    END,
    mn.reported_at ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_maintenance_notice(p_organization_id uuid, p_asset_id uuid, p_title text, p_description text, p_priority text DEFAULT 'medium'::text, p_source_type text DEFAULT 'manual'::text, p_source_id uuid DEFAULT NULL::uuid, p_source_item_id uuid DEFAULT NULL::uuid)
 RETURNS maintenance_notices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_asset public.assets%ROWTYPE;
  v_branch_id uuid;
  v_branch_name text;
  v_notice public.maintenance_notices%ROWTYPE;
  v_metadata jsonb := '{}'::jsonb;
  v_answer record;
  v_asset_label text;
  v_responsible_member_id uuid;
  v_direct boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.can_create_maintenance_notice(p_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to report maintenance notices for this organization';
  END IF;
  v_direct := public.can_report_maintenance_notice(p_organization_id);

  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'El título del aviso es obligatorio';
  END IF;
  IF p_description IS NULL OR TRIM(p_description) = '' THEN
    RAISE EXCEPTION 'La descripción del aviso es obligatoria';
  END IF;
  IF p_priority IS NULL OR p_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Prioridad inválida';
  END IF;
  IF p_source_type IS NULL OR p_source_type NOT IN ('manual', 'inspection_run') THEN
    RAISE EXCEPTION 'Origen inválido';
  END IF;

  SELECT a.* INTO v_asset FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset.id IS NULL THEN
    RAISE EXCEPTION 'El activo no existe';
  END IF;
  IF v_asset.organization_id <> p_organization_id THEN
    RAISE EXCEPTION 'El activo no pertenece a esta organización';
  END IF;
  -- 9C.3: un Facility Manager no reporta manualmente sobre un activo
  -- archivado (su directorio mínimo tampoco lo ofrece).
  IF NOT v_direct AND p_source_type = 'manual' AND v_asset.status = 'archived' THEN
    RAISE EXCEPTION 'Un activo archivado no admite avisos nuevos' USING ERRCODE = '22023';
  END IF;

  IF p_source_type = 'inspection_run' THEN
    -- 9C.3: reportar desde una no conformidad exige además poder ver esa
    -- inspección (no inspections.manage).
    IF NOT v_direct AND NOT public.can_view_inspections(p_organization_id) THEN
      RAISE EXCEPTION 'Not authorized to report from this inspection' USING ERRCODE = '42501';
    END IF;
    IF p_source_id IS NULL OR p_source_item_id IS NULL THEN
      RAISE EXCEPTION 'Un aviso originado en una inspección requiere la ejecución y el ítem';
    END IF;

    SELECT
      ira.is_failure,
      ira.item_question,
      ira.response_label,
      ir.organization_id AS run_organization_id,
      ct.name AS template_name
    INTO v_answer
    FROM public.inspection_run_answers ira
    INNER JOIN public.inspection_runs ir ON ir.id = ira.run_id
    INNER JOIN public.checklist_templates ct ON ct.id = ir.template_id
    WHERE ira.run_id = p_source_id AND ira.template_item_id = p_source_item_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se encontró la respuesta indicada en esa inspección';
    END IF;
    IF v_answer.run_organization_id <> p_organization_id THEN
      RAISE EXCEPTION 'La inspección no pertenece a esta organización';
    END IF;
    IF NOT v_answer.is_failure THEN
      RAISE EXCEPTION 'Solo se puede crear un aviso desde una respuesta marcada como no conformidad';
    END IF;

    v_metadata := jsonb_build_object(
      'template_name', v_answer.template_name,
      'item_id', p_source_item_id,
      'item_question', v_answer.item_question,
      'response_label', v_answer.response_label
    );
  END IF;

  v_branch_id := public.resolve_asset_branch(p_asset_id);
  SELECT cb.name INTO v_branch_name FROM public.client_branches cb WHERE cb.id = v_branch_id;

  -- Responsable predeterminado del PROPIO activo (sin herencia), solo si
  -- sigue siendo elegible en este momento.
  IF public.is_eligible_follow_up_responsible(v_asset.default_responsible_member_id, p_organization_id) THEN
    v_responsible_member_id := v_asset.default_responsible_member_id;
  END IF;

  INSERT INTO public.maintenance_notices AS mn (
    organization_id, notice_number, asset_id, title, description, priority, status,
    source_type, source_id, source_metadata,
    asset_name_snapshot, asset_code_snapshot, asset_path_snapshot,
    branch_id_snapshot, branch_name_snapshot,
    reported_by_user_id, responsible_member_id
  ) VALUES (
    p_organization_id,
    public.next_maintenance_notice_number(p_organization_id),
    p_asset_id,
    TRIM(p_title),
    TRIM(p_description),
    p_priority,
    'open',
    p_source_type,
    CASE WHEN p_source_type = 'manual' THEN NULL ELSE p_source_id END,
    v_metadata,
    v_asset.name,
    v_asset.code,
    public.resolve_asset_path(p_asset_id),
    v_branch_id,
    v_branch_name,
    auth.uid(),
    v_responsible_member_id
  ) RETURNING mn.* INTO v_notice;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    p_organization_id,
    p_asset_id,
    'maintenance_notice_created',
    v_notice.notice_number || ' — ' || v_notice.title,
    jsonb_build_object(
      'notice_id', v_notice.id,
      'notice_number', v_notice.notice_number,
      'priority', v_notice.priority
    ),
    auth.uid()
  );

  v_asset_label := COALESCE(NULLIF(TRIM(COALESCE(v_asset.code, '')), ''), v_asset.name);

  -- priority del aviso y de organization_notifications comparten exactamente
  -- los mismos 4 valores (low/medium/high/urgent): mapeo identidad, sin
  -- inventar ningún valor que el CHECK del schema no acepte.
  PERFORM public.notify_role_members(
    p_organization_id,
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
    auth.uid(),
    'maintenance_notice_created',
    'Nuevo aviso de avería',
    'Nuevo aviso ' || v_notice.notice_number || ' — ' || v_notice.title || ' en ' || v_asset_label || '.',
    'maintenance_notice',
    v_notice.id,
    v_notice.priority,
    jsonb_build_object(
      'notice_number', v_notice.notice_number,
      'priority', v_notice.priority,
      'asset_id', p_asset_id,
      'asset_name', v_asset.name,
      'asset_code', v_asset.code
    )
  );

  -- Mismo type/entity_type/entity_id que arriba: si el responsable ya fue
  -- notificado por su rol, idx_organization_notifications_targeted_dedup
  -- descarta este segundo insert (ON CONFLICT DO NOTHING).
  IF v_responsible_member_id IS NOT NULL THEN
    PERFORM public.notify_member(
      v_responsible_member_id,
      auth.uid(),
      'maintenance_notice_created',
      'Nuevo aviso de avería',
      'Nuevo aviso ' || v_notice.notice_number || ' — ' || v_notice.title || ' en ' || v_asset_label || '.',
      'maintenance_notice',
      v_notice.id,
      v_notice.priority,
      jsonb_build_object(
        'notice_number', v_notice.notice_number,
        'priority', v_notice.priority,
        'asset_id', p_asset_id,
        'asset_name', v_asset.name,
        'asset_code', v_asset.code
      )
    );
  END IF;

  RETURN CASE WHEN v_direct THEN v_notice ELSE public.sanitize_maintenance_notice_for_delegate(v_notice) END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.triage_maintenance_notice(p_notice_id uuid, p_priority text DEFAULT NULL::text, p_triage_notes text DEFAULT NULL::text, p_responsible_member_id uuid DEFAULT NULL::uuid, p_clear_responsible boolean DEFAULT false)
 RETURNS maintenance_notices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_notice public.maintenance_notices%ROWTYPE;
  v_saved public.maintenance_notices%ROWTYPE;
  v_clear boolean := COALESCE(p_clear_responsible, false);
  v_direct boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT mn.* INTO v_notice FROM public.maintenance_notices mn WHERE mn.id = p_notice_id;
  IF v_notice.id IS NULL THEN
    RAISE EXCEPTION 'El aviso no existe';
  END IF;

  IF NOT public.can_triage_maintenance_notice(v_notice.organization_id) THEN
    RAISE EXCEPTION 'Not authorized to triage maintenance notices for this organization';
  END IF;
  -- 9C.3: responsible_member_id es del cliente. Un Facility Manager revisa
  -- (prioridad, notas) sin asignar, cambiar ni limpiar el responsable; "no
  -- cambiar" se expresa con los parámetros, nunca reenviando un UUID.
  v_direct := public.can_manage_maintenance_notice(v_notice.organization_id);
  IF NOT v_direct AND (p_responsible_member_id IS NOT NULL OR v_clear) THEN
    RAISE EXCEPTION 'The notice responsible is assigned by the client' USING ERRCODE = '42501';
  END IF;

  IF v_notice.status NOT IN ('open', 'triaged') THEN
    RAISE EXCEPTION 'Solo se puede revisar un aviso pendiente (estado actual: %)', v_notice.status;
  END IF;

  IF p_priority IS NOT NULL AND p_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Prioridad inválida';
  END IF;

  IF v_clear AND p_responsible_member_id IS NOT NULL THEN
    RAISE EXCEPTION 'Indica un responsable o desasígnalo, pero no ambas cosas';
  END IF;

  -- Solo se valida un responsable que CAMBIA; conservar el actual no lo
  -- revalida. Mismo directorio que get_assignable_planners.
  IF p_responsible_member_id IS NOT NULL
    AND p_responsible_member_id IS DISTINCT FROM v_notice.responsible_member_id
    AND NOT public.is_eligible_follow_up_responsible(p_responsible_member_id, v_notice.organization_id) THEN
    RAISE EXCEPTION 'El responsable indicado no es un miembro activo con rol de seguimiento en esta organización';
  END IF;

  UPDATE public.maintenance_notices mn
  SET priority = COALESCE(p_priority, mn.priority),
      triage_notes = COALESCE(NULLIF(TRIM(COALESCE(p_triage_notes, '')), ''), mn.triage_notes),
      responsible_member_id = CASE
        WHEN v_clear THEN NULL
        WHEN p_responsible_member_id IS NOT NULL THEN p_responsible_member_id
        ELSE mn.responsible_member_id
      END,
      status = 'triaged',
      triaged_by_user_id = auth.uid(),
      triaged_at = now()
  WHERE mn.id = p_notice_id
  RETURNING mn.* INTO v_saved;

  RETURN CASE WHEN v_direct THEN v_saved ELSE public.sanitize_maintenance_notice_for_delegate(v_saved) END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dismiss_maintenance_notice(p_notice_id uuid, p_reason text)
 RETURNS maintenance_notices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_notice public.maintenance_notices%ROWTYPE;
  v_saved public.maintenance_notices%ROWTYPE;
  v_direct boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT mn.* INTO v_notice FROM public.maintenance_notices mn WHERE mn.id = p_notice_id;
  IF v_notice.id IS NULL THEN
    RAISE EXCEPTION 'El aviso no existe';
  END IF;

  IF NOT public.can_triage_maintenance_notice(v_notice.organization_id) THEN
    RAISE EXCEPTION 'Not authorized to dismiss maintenance notices for this organization';
  END IF;
  v_direct := public.can_manage_maintenance_notice(v_notice.organization_id);

  IF v_notice.status = 'dismissed' THEN
    RETURN CASE WHEN v_direct THEN v_notice ELSE public.sanitize_maintenance_notice_for_delegate(v_notice) END;
  END IF;

  IF v_notice.status = 'converted' THEN
    RAISE EXCEPTION 'Un aviso ya convertido en solicitud no puede descartarse';
  END IF;

  IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
    RAISE EXCEPTION 'El motivo del descarte es obligatorio';
  END IF;

  UPDATE public.maintenance_notices mn
  SET status = 'dismissed',
      dismissal_reason = TRIM(p_reason),
      dismissed_by_user_id = auth.uid(),
      dismissed_at = now()
  WHERE mn.id = p_notice_id
  RETURNING mn.* INTO v_saved;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_saved.organization_id,
    v_saved.asset_id,
    'maintenance_notice_dismissed',
    v_saved.notice_number || ' — descartado: ' || v_saved.dismissal_reason,
    jsonb_build_object(
      'notice_id', v_saved.id,
      'notice_number', v_saved.notice_number,
      'priority', v_saved.priority,
      'dismissal_reason', v_saved.dismissal_reason
    ),
    auth.uid()
  );

  RETURN CASE WHEN v_direct THEN v_saved ELSE public.sanitize_maintenance_notice_for_delegate(v_saved) END;
END;
$function$;

-- convert_maintenance_notice (convertir en Solicitud) NO se reemplaza: sigue
-- usando can_manage_maintenance_notice, que no incluye acceso delegado.
-- Pertenece a 9C.4 (Requests).
