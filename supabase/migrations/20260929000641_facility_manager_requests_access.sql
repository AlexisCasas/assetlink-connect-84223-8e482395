-- =========================================================================
-- Fase 1 · Punto 9C.4 — Acceso operativo de Facility Manager a Solicitudes.
--
-- Hace efectivos SOLO requests.view, requests.create y requests.manage, e
-- integra Aviso -> Solicitud y Ocurrencia preventiva -> Solicitud. No abre
-- quotes.*, work_orders.*, reports.*, providers.manage, inventario ni R2.
-- El FM nunca es provider-facing y no recibe membresías del cliente.
--
-- Acceso delegado = has_facility_management_operational_access_all (9C.1):
-- relación facility_management ACTIVE + cliente ACTIVE + FM ACTIVE +
-- membresía ACTIVA en ESE FM + ESA membresía asignada a ESA relación +
-- todos los permisos en ESA relación + rol compatible.
--
-- Matriz del FM (el acceso directo de los miembros del cliente NO cambia):
--   ver        requests.view                 o/a/m/requester
--   crear      view + create                 o/a/m/requester
--              (sus propios borradores: editar, enviar, eliminar, audiencia)
--   gestionar  view + manage                 o/a/m
--              (editar y anular solicitudes enviadas, audiencia)
-- manage no exige create. *.create / *.manage nunca sustituyen a *.view.
--
-- Diseño:
--   - can_user_read_request y la RLS de requests, request_details y
--     request_provider_access NO cambian. El FM opera solo con RPCs
--     SECURITY DEFINER minimizadas (listado, detalle, guardado transaccional,
--     eliminar borrador propio, anular) y directorios mínimos (sedes, activos,
--     proveedores homologados activos del cliente).
--   - La audiencia usa la MISMA lógica que set_request_audience: su cuerpo se
--     movió tal cual a apply_request_audience_internal (interna) y
--     set_request_audience conserva su autorización histórica.
--   - Respuestas sin created_by_user_id/email, ids/emails de contactos, id del
--     responsable interno, adjuntos, ni ids de cotizaciones u OT. Nombres
--     nunca derivados del email.
--   - Contacto de coordinación, contacto de visita y responsable interno son
--     del cliente: el FM no los asigna, cambia ni limpia (42501). Una
--     solicitud nueva del FM guarda el snapshot del propio FM como contacto.
--   - create_internal_work_order_from_request, get_coordination_contacts,
--     get_assignable_technicians y get_assignable_planners NO se amplían.
--   - convert_maintenance_notice y plan_preventive_maintenance_occurrence
--     aceptan al FM solo con los permisos combinados de ambos módulos.
-- Ver docs/FACILITY_MANAGER_REQUESTS.md.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1) Capacidades delegadas. Internas (no ejecutables por clientes).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_view_requests_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['requests.view']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
  );
$$;

CREATE OR REPLACE FUNCTION public.can_create_requests_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['requests.view', 'requests.create']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_requests_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['requests.view', 'requests.manage']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
  );
$$;

-- Aviso -> Solicitud: gestionar avisos Y crear solicitudes.
CREATE OR REPLACE FUNCTION public.can_convert_maintenance_notice_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['maintenance_notices.view', 'maintenance_notices.manage', 'requests.view', 'requests.create']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
  );
$$;

-- Ocurrencia preventiva -> Solicitud: gestionar el preventivo Y crear
-- solicitudes. Es también la única capacidad delegada que ve
-- request_creation_id.
CREATE OR REPLACE FUNCTION public.can_plan_preventive_request_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['preventive_maintenance.view', 'preventive_maintenance.manage', 'requests.view', 'requests.create']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
  );
$$;

REVOKE ALL ON FUNCTION public.can_view_requests_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_create_requests_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_manage_requests_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_convert_maintenance_notice_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_plan_preventive_request_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 2) Minimización. Internas.
-- -------------------------------------------------------------------------

-- Nombre de persona apto para el delegado: nunca un email ni el prefijo del
-- email (el fallback histórico de get_coordination_contacts).
CREATE OR REPLACE FUNCTION public.facility_management_safe_person_name(_name text, _email text, _fallback text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN NULLIF(btrim(_name), '') IS NULL THEN _fallback
    WHEN position('@' IN _name) > 0 THEN _fallback
    WHEN NULLIF(btrim(_email), '') IS NOT NULL
      AND lower(btrim(_name)) = lower(split_part(btrim(_email), '@', 1)) THEN _fallback
    ELSE btrim(_name)
  END;
$$;

-- Solicitud minimizada + lo que el delegado puede hacer con ella.
CREATE OR REPLACE FUNCTION public.facility_management_request_payload(_request public.requests, _can_create boolean, _can_manage boolean)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_own boolean := _request.created_by_user_id IS NOT NULL AND _request.created_by_user_id = auth.uid();
  v_active boolean := _request.status IN ('sent', 'quoted');
  v_attachments boolean := EXISTS (
    SELECT 1 FROM public.request_details d
    WHERE d.request_id = _request.id AND COALESCE(cardinality(d.attachment_urls), 0) > 0
  );
  v_can_edit boolean;
BEGIN
  v_can_edit := NOT v_attachments AND (
    (_request.status = 'draft' AND v_own AND COALESCE(_can_create, false))
    OR (v_active AND COALESCE(_can_manage, false))
  );
  RETURN jsonb_build_object(
    'id', _request.id,
    'organization_id', _request.organization_id,
    'request_number', _request.request_number,
    'title', _request.title,
    'description', _request.description,
    'asset', _request.asset,
    'asset_id', _request.asset_id,
    'location', _request.location,
    'service_type', _request.service_type,
    'observations', _request.observations,
    'deadline', _request.deadline,
    'start_time', _request.start_time,
    'status', _request.status,
    'created_at', _request.created_at,
    'updated_at', _request.updated_at,
    'priority', _request.priority,
    'client_name', _request.client_name,
    'client_branch', _request.client_branch,
    'is_public', _request.is_public,
    'quotes_closed', _request.quotes_closed,
    'city', _request.city,
    'store', _request.store,
    'branch', _request.branch,
    'branch_id', _request.branch_id,
    'requires_visit', _request.requires_visit,
    'visit_date', _request.visit_date,
    'visit_schedule_mode', _request.visit_schedule_mode,
    'min_quotes', _request.min_quotes,
    'request_type', _request.request_type,
    'service_address', _request.service_address,
    'created_by_name', public.facility_management_safe_person_name(_request.created_by_name, _request.created_by_email, 'Usuario del cliente'),
    'coordination_contact_name', CASE
      WHEN _request.coordination_contact_member_id IS NULL AND NULLIF(btrim(_request.coordination_contact_name), '') IS NULL THEN NULL
      ELSE public.facility_management_safe_person_name(_request.coordination_contact_name, _request.coordination_contact_email, 'Asignado por el cliente')
    END,
    'has_client_coordination_contact', _request.coordination_contact_member_id IS NOT NULL,
    'has_client_visit_contact', _request.visit_contact_member_id IS NOT NULL,
    'internal_responsible_name', CASE WHEN _request.internal_responsible_member_id IS NOT NULL THEN 'Asignado por el cliente' END,
    'has_client_attachments', v_attachments,
    'is_own', v_own,
    'can_edit', v_can_edit,
    'can_delete_draft', _request.status = 'draft' AND v_own AND COALESCE(_can_create, false),
    'can_annul', v_active AND COALESCE(_can_manage, false)
  );
END;
$$;

-- ¿El delegado puede ver ESTA solicitud? Enviadas con view; borradores solo
-- los propios y con create.
CREATE OR REPLACE FUNCTION public.facility_management_can_see_request(_request public.requests, _can_view boolean, _can_create boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN _request.id IS NULL THEN false
    WHEN _request.status = 'draft' THEN COALESCE(_can_create, false)
      AND _request.created_by_user_id IS NOT NULL AND _request.created_by_user_id = auth.uid()
    ELSE COALESCE(_can_view, false)
  END;
$$;

-- Ocurrencia preventiva devuelta a un delegado por una RPC que retorna la
-- fila: snapshot sin datos de inventario ni personas; request_creation_id
-- solo con la capacidad de planificar en solicitud; request_id solo con
-- requests.view; work_order_id nunca.
CREATE OR REPLACE FUNCTION public.sanitize_preventive_occurrence_for_delegate(_occurrence public.preventive_maintenance_occurrences)
RETURNS public.preventive_maintenance_occurrences
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_occurrence public.preventive_maintenance_occurrences := _occurrence;
BEGIN
  v_occurrence.scope_snapshot := public.sanitize_preventive_scope_snapshot(v_occurrence.scope_snapshot);
  IF NOT public.can_plan_preventive_request_as_facility_manager(v_occurrence.organization_id) THEN
    v_occurrence.request_creation_id := NULL;
  END IF;
  IF NOT public.can_view_requests_as_facility_manager(v_occurrence.organization_id) THEN
    v_occurrence.request_id := NULL;
  END IF;
  v_occurrence.work_order_id := NULL;
  RETURN v_occurrence;
END;
$$;

-- 9C.3 ocultaba siempre converted_request_id. Desde 9C.4 el delegado lo ve si
-- tiene requests.view y la solicitud le es visible (no un borrador ajeno).
CREATE OR REPLACE FUNCTION public.sanitize_maintenance_notice_for_delegate(_notice public.maintenance_notices)
RETURNS public.maintenance_notices
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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
  IF v_notice.converted_request_id IS NOT NULL AND NOT (
    public.can_view_requests_as_facility_manager(v_notice.organization_id)
    AND EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = v_notice.converted_request_id
        AND public.facility_management_can_see_request(r, true, public.can_create_requests_as_facility_manager(v_notice.organization_id))
    )
  ) THEN
    v_notice.converted_request_id := NULL;
  END IF;
  v_notice.converted_by_user_id := NULL;
  v_notice.dismissed_by_user_id := NULL;
  RETURN v_notice;
END;
$$;

-- 9C.2 dejaba en el snapshot delegado plan.responsible.membership_id y role.
-- Desde 9C.4 el responsable queda como {"assigned": true}: ningún id interno
-- del cliente (membresía, usuario, email) llega al Facility Manager. El
-- nombre ya se quitaba en 9C.2 (podía derivar del email).
CREATE OR REPLACE FUNCTION public.sanitize_preventive_scope_snapshot(_snapshot jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN _snapshot IS NULL OR jsonb_typeof(_snapshot) <> 'object' THEN _snapshot
    ELSE (
      SELECT CASE
        WHEN jsonb_typeof(s.value #> '{plan,responsible}') = 'object'
          THEN jsonb_set(s.value, '{plan,responsible}', '{"assigned": true}'::jsonb)
        ELSE s.value
      END
      FROM (SELECT CASE
        WHEN jsonb_typeof(_snapshot #> '{card,materials}') IS DISTINCT FROM 'array' THEN _snapshot
        ELSE jsonb_set(_snapshot, '{card,materials}', COALESCE((
          SELECT jsonb_agg(
            (item.value - 'material_id' - 'code' - 'name')
              || jsonb_build_object('client_linked_material', NULLIF(item.value->>'material_id', '') IS NOT NULL)
            ORDER BY item.ord)
          FROM jsonb_array_elements(_snapshot #> '{card,materials}') WITH ORDINALITY AS item(value, ord)
        ), '[]'::jsonb))
      END AS value) s
    )
  END;
$$;

-- Plan preventivo devuelto a un delegado: sin el responsable del cliente ni
-- el usuario creador. El responsable real se conserva en el servidor.
CREATE OR REPLACE FUNCTION public.sanitize_preventive_plan_for_delegate(_plan public.preventive_maintenance_plans)
RETURNS public.preventive_maintenance_plans
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_plan public.preventive_maintenance_plans := _plan;
BEGIN
  v_plan.responsible_member_id := NULL;
  v_plan.created_by_user_id := NULL;
  RETURN v_plan;
END;
$$;

REVOKE ALL ON FUNCTION public.sanitize_preventive_scope_snapshot(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sanitize_preventive_plan_for_delegate(public.preventive_maintenance_plans) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.facility_management_safe_person_name(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.facility_management_request_payload(public.requests, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.facility_management_can_see_request(public.requests, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sanitize_preventive_occurrence_for_delegate(public.preventive_maintenance_occurrences) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sanitize_maintenance_notice_for_delegate(public.maintenance_notices) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 3) Audiencia de una solicitud externa: el cuerpo histórico de
--    set_request_audience se movió SIN CAMBIOS a
--    apply_request_audience_internal (interna, sin autorización propia).
--    set_request_audience conserva su autorización histórica (miembro
--    o/a/m/requester del cliente o platform admin) y delega en ella;
--    save_facility_management_request la usa tras autorizar al FM.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_request_audience_internal(p_request_id uuid, p_is_public boolean, p_provider_organization_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS TABLE(is_public boolean, provider_organization_ids uuid[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request public.requests%ROWTYPE;
  v_client_org_name text;
  v_target uuid;
  v_desired uuid[];
  v_current uuid[];
  v_to_add uuid[];
  v_to_remove uuid[];
  v_blocked_names text;
  v_relationship_status public.organization_relationship_status;
  v_provider_org public.organizations%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO v_request FROM public.requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  IF v_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Request has no client organization';
  END IF;

  IF v_request.request_type <> 'external' THEN
    RAISE EXCEPTION 'Only external requests have a provider audience';
  END IF;

  -- Autorización: la hace quien llama (set_request_audience o
  -- save_facility_management_request). Nunca expuesta a clientes.

  v_desired := COALESCE(ARRAY(SELECT DISTINCT unnest(p_provider_organization_ids)), '{}'::uuid[]);

  IF p_is_public IS TRUE THEN
    -- Public marketplace mode never carries private invitations alongside it.
    v_desired := '{}'::uuid[];
  ELSIF array_length(v_desired, 1) IS NULL THEN
    RAISE EXCEPTION 'Selecciona al menos un proveedor para enviar una invitación privada.';
  END IF;

  IF array_length(v_desired, 1) > 0 THEN
    FOREACH v_target IN ARRAY v_desired LOOP
      SELECT * INTO v_provider_org FROM public.organizations WHERE id = v_target;

      IF v_provider_org.organization_type = 'facility_manager' THEN
        RAISE EXCEPTION 'Un Facility Manager no puede recibir invitaciones a cotizar: %', v_provider_org.name
          USING ERRCODE = '22023';
      END IF;

      IF v_provider_org.id IS NULL OR NOT public.is_provider_facing_organization(v_target) THEN
        RAISE EXCEPTION 'Organización proveedora inválida: %', v_target;
      END IF;

      SELECT rel.status INTO v_relationship_status
      FROM public.organization_relationships rel
      WHERE rel.source_organization_id = v_request.organization_id
        AND rel.target_organization_id = v_target
        AND rel.relationship_type = CASE v_provider_org.organization_type
          WHEN 'provider_company' THEN 'provider'::public.organization_relationship_type
          WHEN 'subcontractor_company' THEN 'subcontracting'::public.organization_relationship_type
        END;

      IF v_relationship_status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'La organización % no está homologada/activa para tu organización', v_provider_org.name;
      END IF;
    END LOOP;
  END IF;

  SELECT COALESCE(ARRAY_AGG(provider_organization_id), '{}'::uuid[]) INTO v_current
  FROM public.request_provider_access
  WHERE request_id = p_request_id
    AND access_type = 'invited'
    AND status = 'active';

  v_to_add := ARRAY(SELECT unnest(v_desired) EXCEPT SELECT unnest(v_current));
  v_to_remove := ARRAY(SELECT unnest(v_current) EXCEPT SELECT unnest(v_desired));

  -- A provider that already submitted a quote can never be removed from the
  -- audience through this path.
  IF array_length(v_to_remove, 1) > 0 THEN
    SELECT string_agg(DISTINCT organization.name, ', ')
      INTO v_blocked_names
      FROM public.quotes quote
      INNER JOIN public.organizations organization ON organization.id = quote.provider_organization_id
      WHERE quote.request_id = p_request_id
        AND quote.provider_organization_id = ANY (v_to_remove);

    IF v_blocked_names IS NOT NULL THEN
      RAISE EXCEPTION 'Este proveedor ya presentó una cotización y no puede eliminarse de la convocatoria sin anular formalmente su participación: %', v_blocked_names;
    END IF;
  END IF;

  SELECT organization.name INTO v_client_org_name
  FROM public.organizations organization WHERE organization.id = v_request.organization_id;

  IF array_length(v_to_add, 1) > 0 THEN
    FOREACH v_target IN ARRAY v_to_add LOOP
      INSERT INTO public.request_provider_access (
        request_id, provider_organization_id, access_type, status, invited_by_user_id
      ) VALUES (
        p_request_id, v_target, 'invited', 'active', auth.uid()
      )
      ON CONFLICT (request_id, provider_organization_id)
        DO UPDATE SET status = 'active', access_type = 'invited', updated_at = now();

      PERFORM public.notify_role_members(
        v_target,
        ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[],
        auth.uid(),
        'request_private_invitation',
        'Nueva invitación a cotizar',
        COALESCE(v_client_org_name, 'Un cliente') || ' te invitó a cotizar ' || v_request.request_number
          || ' — ' || COALESCE(v_request.title, v_request.request_number) || '.',
        'request',
        p_request_id,
        'medium',
        jsonb_build_object(
          'request_id', p_request_id,
          'request_number', v_request.request_number,
          'title', v_request.title,
          'client_organization_id', v_request.organization_id,
          'client_organization_name', v_client_org_name,
          'provider_organization_id', v_target,
          'visibility', 'private'
        )
      );

      INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, new_data)
      VALUES (
        v_request.organization_id, auth.uid(), 'request_provider_access', p_request_id, 'provider_invited',
        jsonb_build_object('provider_organization_id', v_target)
      );
    END LOOP;
  END IF;

  IF array_length(v_to_remove, 1) > 0 THEN
    UPDATE public.request_provider_access
    SET status = 'revoked'
    WHERE request_id = p_request_id
      AND provider_organization_id = ANY (v_to_remove)
      AND access_type = 'invited';

    INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data)
    VALUES (
      v_request.organization_id, auth.uid(), 'request_provider_access', p_request_id, 'provider_revoked',
      jsonb_build_object('provider_organization_ids', v_to_remove)
    );
  END IF;

  IF v_request.is_public IS DISTINCT FROM p_is_public THEN
    UPDATE public.requests SET is_public = p_is_public WHERE id = p_request_id;

    INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data, new_data)
    VALUES (
      v_request.organization_id, auth.uid(), 'requests', p_request_id, 'audience_visibility_changed',
      jsonb_build_object('is_public', v_request.is_public), jsonb_build_object('is_public', p_is_public)
    );
  END IF;

  RETURN QUERY SELECT p_is_public, v_desired;
END;
$function$;

REVOKE ALL ON FUNCTION public.apply_request_audience_internal(uuid, boolean, uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_request_audience(p_request_id uuid, p_is_public boolean, p_provider_organization_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS TABLE(is_public boolean, provider_organization_ids uuid[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request public.requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO v_request FROM public.requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  IF v_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Request has no client organization';
  END IF;

  IF v_request.request_type <> 'external' THEN
    RAISE EXCEPTION 'Only external requests have a provider audience';
  END IF;

  -- Tenant + role check: only the client organization that owns this
  -- request may manage its audience.
  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      v_request.organization_id,
      ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this request''s audience';
  END IF;

  RETURN QUERY SELECT * FROM public.apply_request_audience_internal(p_request_id, p_is_public, p_provider_organization_ids);
END;
$function$;

-- -------------------------------------------------------------------------
-- 4) RPCs delegadas de Solicitudes (solo el FM las usa; un miembro directo
--    del cliente sigue con su camino histórico). Todas re-autorizan contra
--    el cliente recibido: `managedClient` en el frontend es contexto visual.
-- -------------------------------------------------------------------------

-- Listado: 'sent' = enviadas (igual que la vista histórica del cliente),
-- 'drafts' = borradores PROPIOS del usuario (requiere create).
CREATE OR REPLACE FUNCTION public.get_facility_management_requests(_client_organization_id uuid, _scope text DEFAULT 'sent')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_can_view boolean := public.can_view_requests_as_facility_manager(_client_organization_id);
  v_can_create boolean := public.can_create_requests_as_facility_manager(_client_organization_id);
  v_can_manage boolean := public.can_manage_requests_as_facility_manager(_client_organization_id);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;
  IF _scope IS NULL OR _scope NOT IN ('sent', 'drafts') THEN
    RAISE EXCEPTION 'Invalid scope' USING ERRCODE = '22023';
  END IF;
  IF (_scope = 'sent' AND NOT v_can_view) OR (_scope = 'drafts' AND NOT v_can_create) THEN
    RAISE EXCEPTION 'Not authorized to view this client''s requests' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(public.facility_management_request_payload(r, v_can_create, v_can_manage) ORDER BY r.created_at DESC, r.id)
    FROM public.requests r
    WHERE r.organization_id = _client_organization_id
      AND (
        (_scope = 'sent' AND r.status = 'sent')
        OR (_scope = 'drafts' AND r.status = 'draft' AND r.created_by_user_id = auth.uid())
      )
  ), '[]'::jsonb);
END;
$$;

-- Detalle: solicitud + filas de detalle (sin adjuntos) + audiencia solo si
-- el delegado puede editarla. NULL si no existe o no le es visible (no
-- distingue entre ambos casos).
CREATE OR REPLACE FUNCTION public.get_facility_management_request(_client_organization_id uuid, _request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_can_view boolean := public.can_view_requests_as_facility_manager(_client_organization_id);
  v_can_create boolean := public.can_create_requests_as_facility_manager(_client_organization_id);
  v_can_manage boolean := public.can_manage_requests_as_facility_manager(_client_organization_id);
  v_request public.requests%ROWTYPE;
  v_payload jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT v_can_view THEN
    RAISE EXCEPTION 'Not authorized to view this client''s requests' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_request FROM public.requests r
  WHERE r.id = _request_id AND r.organization_id = _client_organization_id;
  IF NOT public.facility_management_can_see_request(v_request, v_can_view, v_can_create) THEN
    RETURN NULL;
  END IF;

  v_payload := public.facility_management_request_payload(v_request, v_can_create, v_can_manage);
  RETURN jsonb_build_object(
    'request', v_payload,
    'details', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', d.id,
        'equipment', d.equipment,
        'sub_equipment', d.sub_equipment,
        'area', d.area,
        'sub_area', d.sub_area,
        'activities', d.activities,
        'relevant_materials', d.relevant_materials,
        'quantity', d.quantity,
        'unit_measure', d.unit_measure,
        'observation', d.observation,
        'responsible_user', d.responsible_user,
        'delegate_type', d.delegate_type
      ) ORDER BY d.created_at, d.id)
      FROM public.request_details d WHERE d.request_id = v_request.id
    ), '[]'::jsonb),
    'audience', CASE WHEN (v_payload->>'can_edit')::boolean AND v_request.request_type = 'external' THEN jsonb_build_object(
      'is_public', COALESCE(v_request.is_public, false),
      'providers', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('organization_id', o.id, 'organization_name', o.name) ORDER BY o.name, o.id)
        FROM public.request_provider_access a
        JOIN public.organizations o ON o.id = a.provider_organization_id
        WHERE a.request_id = v_request.id AND a.access_type = 'invited' AND a.status = 'active'
      ), '[]'::jsonb)
    ) END
  );
END;
$$;

-- Guardado transaccional (la misma semántica que persistRequest, en una
-- sola transacción): escribe la solicitud, reemplaza el detalle, sincroniza
-- la audiencia con la lógica de set_request_audience y solo después
-- promueve draft -> sent. Si cualquier paso falla, no queda nada a medias.
CREATE OR REPLACE FUNCTION public.save_facility_management_request(
  _client_organization_id uuid,
  _request_id uuid,
  _request jsonb,
  _details jsonb DEFAULT '[]'::jsonb,
  _submit boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_can_create boolean := public.can_create_requests_as_facility_manager(_client_organization_id);
  v_can_manage boolean := public.can_manage_requests_as_facility_manager(_client_organization_id);
  v_allowed constant text[] := ARRAY[
    'request_number', 'title', 'description', 'asset', 'asset_id', 'location', 'service_type',
    'deadline', 'branch_id', 'city', 'store', 'branch', 'requires_visit', 'visit_date',
    'visit_schedule_mode', 'request_type', 'min_quotes', 'service_address', 'client_name',
    'client_branch', 'is_public', 'provider_organization_ids'
  ];
  v_client_owned constant text[] := ARRAY[
    'coordination_contact_member_id', 'coordination_contact_name', 'coordination_contact_email',
    'visit_contact_member_id', 'internal_responsible_member_id'
  ];
  v_detail_allowed constant text[] := ARRAY[
    'equipment', 'sub_equipment', 'area', 'sub_area', 'activities', 'relevant_materials',
    'quantity', 'unit_measure', 'observation', 'responsible_user', 'delegate_type'
  ];
  v_existing public.requests%ROWTYPE;
  v_is_new boolean;
  v_id uuid;
  v_key text;
  v_detail jsonb;
  v_status public.request_status;
  v_request_number text;
  v_branch_id uuid;
  v_asset_id uuid;
  v_service_type public.service_type;
  v_request_type text;
  v_requires_visit boolean;
  v_min_quotes integer;
  v_actor_email text;
  v_actor_name text;
  v_provider_ids uuid[];
BEGIN
  IF auth.uid() IS NULL OR NOT (v_can_create OR v_can_manage) THEN
    RAISE EXCEPTION 'Not authorized to edit this client''s requests' USING ERRCODE = '42501';
  END IF;

  IF _request IS NULL OR jsonb_typeof(_request) <> 'object' THEN
    RAISE EXCEPTION 'The request payload must be an object' USING ERRCODE = '22023';
  END IF;
  FOR v_key IN SELECT jsonb_object_keys(_request) LOOP
    IF v_key = ANY (v_client_owned) THEN
      RAISE EXCEPTION 'Los contactos y el responsable de la solicitud los asigna el cliente' USING ERRCODE = '42501';
    END IF;
    IF NOT (v_key = ANY (v_allowed)) THEN
      RAISE EXCEPTION 'Field not allowed: %', v_key USING ERRCODE = '22023';
    END IF;
  END LOOP;

  _details := COALESCE(_details, '[]'::jsonb);
  IF jsonb_typeof(_details) <> 'array' OR jsonb_array_length(_details) > 200 THEN
    RAISE EXCEPTION 'Invalid request details' USING ERRCODE = '22023';
  END IF;
  FOR v_detail IN SELECT value FROM jsonb_array_elements(_details) LOOP
    IF jsonb_typeof(v_detail) <> 'object' THEN
      RAISE EXCEPTION 'Invalid request detail' USING ERRCODE = '22023';
    END IF;
    FOR v_key IN SELECT jsonb_object_keys(v_detail) LOOP
      IF NOT (v_key = ANY (v_detail_allowed)) THEN
        RAISE EXCEPTION 'Detail field not allowed: %', v_key USING ERRCODE = '22023';
      END IF;
    END LOOP;
  END LOOP;

  IF _request ? 'provider_organization_ids' AND jsonb_typeof(_request->'provider_organization_ids') NOT IN ('array', 'null') THEN
    RAISE EXCEPTION 'provider_organization_ids must be an array' USING ERRCODE = '22023';
  END IF;

  IF _request_id IS NOT NULL THEN
    SELECT r.* INTO v_existing FROM public.requests r WHERE r.id = _request_id FOR UPDATE;
  END IF;
  v_is_new := v_existing.id IS NULL;
  v_id := COALESCE(_request_id, gen_random_uuid());

  IF v_is_new THEN
    IF NOT v_can_create THEN
      RAISE EXCEPTION 'Not authorized to create requests for this client' USING ERRCODE = '42501';
    END IF;
    v_request_number := NULLIF(btrim(_request->>'request_number'), '');
    IF v_request_number IS NULL OR length(v_request_number) > 64 THEN
      RAISE EXCEPTION 'A request number is required' USING ERRCODE = '22023';
    END IF;
    v_status := 'draft';
  ELSE
    IF v_existing.organization_id IS DISTINCT FROM _client_organization_id THEN
      RAISE EXCEPTION 'Not authorized to edit this request' USING ERRCODE = '42501';
    END IF;
    IF v_existing.status = 'draft' THEN
      IF NOT (v_can_create AND v_existing.created_by_user_id IS NOT NULL AND v_existing.created_by_user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to edit this request' USING ERRCODE = '42501';
      END IF;
    ELSIF v_existing.status IN ('sent', 'quoted') THEN
      IF NOT v_can_manage THEN
        RAISE EXCEPTION 'Not authorized to edit this request' USING ERRCODE = '42501';
      END IF;
    ELSE
      RAISE EXCEPTION 'La solicitud no se puede editar en su estado actual' USING ERRCODE = '55000';
    END IF;
    IF _request ? 'request_number' AND (_request->>'request_number') IS DISTINCT FROM v_existing.request_number THEN
      RAISE EXCEPTION 'request_number is immutable' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.request_details d
      WHERE d.request_id = v_existing.id AND COALESCE(cardinality(d.attachment_urls), 0) > 0
    ) THEN
      RAISE EXCEPTION 'La solicitud tiene adjuntos del cliente; solo el cliente puede editarla' USING ERRCODE = '55000';
    END IF;
    v_status := v_existing.status;
  END IF;

  v_branch_id := NULLIF(_request->>'branch_id', '')::uuid;
  IF v_branch_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.client_branches b
      WHERE b.id = v_branch_id AND b.organization_id = _client_organization_id
    ) THEN
      RAISE EXCEPTION 'The branch does not belong to this client' USING ERRCODE = '22023';
    END IF;
    IF (v_is_new OR v_branch_id IS DISTINCT FROM v_existing.branch_id) AND NOT EXISTS (
      SELECT 1 FROM public.client_branches b WHERE b.id = v_branch_id AND b.is_active
    ) THEN
      RAISE EXCEPTION 'The branch is inactive' USING ERRCODE = '22023';
    END IF;
  END IF;

  v_asset_id := NULLIF(_request->>'asset_id', '')::uuid;
  IF v_asset_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.assets a
      WHERE a.id = v_asset_id AND a.organization_id = _client_organization_id
    ) THEN
      RAISE EXCEPTION 'The asset does not belong to this client' USING ERRCODE = '22023';
    END IF;
    IF (v_is_new OR v_asset_id IS DISTINCT FROM v_existing.asset_id) AND EXISTS (
      SELECT 1 FROM public.assets a WHERE a.id = v_asset_id AND a.status = 'archived'
    ) THEN
      RAISE EXCEPTION 'The asset is archived' USING ERRCODE = '22023';
    END IF;
  END IF;

  v_service_type := (_request->>'service_type')::public.service_type;
  v_request_type := COALESCE(NULLIF(_request->>'request_type', ''), 'external');
  IF v_request_type NOT IN ('external', 'internal') THEN
    RAISE EXCEPTION 'Invalid request type' USING ERRCODE = '22023';
  END IF;
  v_requires_visit := COALESCE((_request->>'requires_visit')::boolean, false);
  v_min_quotes := COALESCE((_request->>'min_quotes')::integer, 3);
  IF v_min_quotes < 1 THEN
    RAISE EXCEPTION 'min_quotes must be at least 1' USING ERRCODE = '22023';
  END IF;

  IF v_is_new THEN
    SELECT u.email::text, NULLIF(btrim(u.raw_user_meta_data->>'name'), '')
      INTO v_actor_email, v_actor_name
    FROM auth.users u WHERE u.id = auth.uid();
    v_actor_name := COALESCE(v_actor_name, split_part(v_actor_email, '@', 1));

    INSERT INTO public.requests (
      id, organization_id, request_number, title, description, service_type, deadline,
      branch_id, city, store, branch, location, requires_visit, visit_date, visit_schedule_mode,
      visit_contact_member_id, asset, asset_id, request_type, internal_responsible_member_id,
      status, created_by, created_by_user_id, created_by_name, created_by_email,
      client_name, client_branch, priority, min_quotes,
      coordination_contact_member_id, coordination_contact_name, coordination_contact_email,
      service_address
    ) VALUES (
      v_id, _client_organization_id, v_request_number, NULLIF(_request->>'title', ''),
      _request->>'description', v_service_type, (_request->>'deadline')::timestamptz,
      v_branch_id, _request->>'city', _request->>'store', _request->>'branch', _request->>'location',
      v_requires_visit,
      CASE WHEN v_requires_visit THEN NULLIF(_request->>'visit_date', '')::timestamptz END,
      CASE WHEN v_requires_visit THEN NULLIF(_request->>'visit_schedule_mode', '') END,
      NULL, _request->>'asset', v_asset_id, v_request_type, NULL,
      'draft', COALESCE(v_actor_email, ''), auth.uid(), v_actor_name, v_actor_email,
      _request->>'client_name', _request->>'client_branch',
      CASE v_service_type WHEN 'emergencia' THEN 1 WHEN 'correctivo' THEN 2 WHEN 'preventivo' THEN 3 ELSE 4 END,
      v_min_quotes,
      NULL, v_actor_name, v_actor_email,
      NULLIF(_request->>'service_address', '')
    );
  ELSE
    -- Contactos, contacto de visita y responsable interno: se conservan.
    UPDATE public.requests SET
      title = NULLIF(_request->>'title', ''),
      description = _request->>'description',
      service_type = v_service_type,
      deadline = (_request->>'deadline')::timestamptz,
      branch_id = v_branch_id,
      city = _request->>'city',
      store = _request->>'store',
      branch = _request->>'branch',
      location = _request->>'location',
      requires_visit = v_requires_visit,
      visit_date = CASE WHEN v_requires_visit THEN NULLIF(_request->>'visit_date', '')::timestamptz END,
      visit_schedule_mode = CASE WHEN v_requires_visit THEN NULLIF(_request->>'visit_schedule_mode', '') END,
      asset = _request->>'asset',
      asset_id = v_asset_id,
      request_type = v_request_type,
      min_quotes = v_min_quotes,
      service_address = NULLIF(_request->>'service_address', '')
    WHERE id = v_id;
  END IF;

  DELETE FROM public.request_details WHERE request_id = v_id;
  INSERT INTO public.request_details (
    request_id, equipment, sub_equipment, area, sub_area, activities, relevant_materials,
    quantity, unit_measure, observation, responsible_user, delegate_type
  )
  SELECT
    v_id,
    NULLIF(e.value->>'equipment', ''),
    NULLIF(e.value->>'sub_equipment', ''),
    NULLIF(e.value->>'area', ''),
    NULLIF(e.value->>'sub_area', ''),
    NULLIF(e.value->>'activities', ''),
    NULLIF(e.value->>'relevant_materials', ''),
    NULLIF(NULLIF(e.value->>'quantity', '')::numeric, 0),
    NULLIF(e.value->>'unit_measure', ''),
    NULLIF(e.value->>'observation', ''),
    NULLIF(e.value->>'responsible_user', ''),
    NULLIF(e.value->>'delegate_type', '')
  FROM jsonb_array_elements(_details) WITH ORDINALITY AS e(value, ordinality)
  ORDER BY e.ordinality;

  IF v_request_type = 'external' THEN
    v_provider_ids := COALESCE(ARRAY(
      SELECT p.value::uuid FROM jsonb_array_elements_text(COALESCE(_request->'provider_organization_ids', '[]'::jsonb)) AS p(value)
    ), '{}'::uuid[]);
    PERFORM public.apply_request_audience_internal(
      v_id, COALESCE((_request->>'is_public')::boolean, true), v_provider_ids
    );
  END IF;

  IF COALESCE(_submit, false) AND v_status = 'draft' THEN
    UPDATE public.requests SET status = 'sent' WHERE id = v_id;
  END IF;

  RETURN public.get_facility_management_request(_client_organization_id, v_id);
END;
$$;

-- Eliminar un borrador PROPIO (requests.create).
CREATE OR REPLACE FUNCTION public.delete_facility_management_request_draft(_client_organization_id uuid, _request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request public.requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_create_requests_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to delete drafts for this client' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_request FROM public.requests r
  WHERE r.id = _request_id AND r.organization_id = _client_organization_id
  FOR UPDATE;
  IF v_request.id IS NULL OR v_request.status <> 'draft'
    OR v_request.created_by_user_id IS NULL OR v_request.created_by_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only your own draft can be deleted' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (SELECT 1 FROM public.maintenance_notices mn WHERE mn.converted_request_id = v_request.id)
    OR EXISTS (SELECT 1 FROM public.preventive_maintenance_occurrences o WHERE o.request_id = v_request.id) THEN
    RAISE EXCEPTION 'El borrador está vinculado a un aviso o a un preventivo y no se puede eliminar' USING ERRCODE = '55000';
  END IF;

  DELETE FROM public.request_details WHERE request_id = v_request.id;
  DELETE FROM public.requests WHERE id = v_request.id;
END;
$$;

-- Anular una solicitud enviada (requests.manage).
CREATE OR REPLACE FUNCTION public.annul_facility_management_request(_client_organization_id uuid, _request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request public.requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_requests_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to annul requests for this client' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_request FROM public.requests r
  WHERE r.id = _request_id AND r.organization_id = _client_organization_id
  FOR UPDATE;
  IF v_request.id IS NULL OR v_request.status = 'draft' THEN
    RAISE EXCEPTION 'Not authorized to annul this request' USING ERRCODE = '42501';
  END IF;
  IF v_request.status NOT IN ('sent', 'quoted') THEN
    RAISE EXCEPTION 'La solicitud no se puede anular en su estado actual' USING ERRCODE = '55000';
  END IF;

  UPDATE public.requests SET status = 'anulado' WHERE id = v_request.id
  RETURNING * INTO v_request;

  RETURN public.facility_management_request_payload(v_request, public.can_create_requests_as_facility_manager(_client_organization_id), true);
END;
$$;

-- -------------------------------------------------------------------------
-- 5) Directorios mínimos para el formulario (create o manage). Nunca el
--    roster del cliente.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_facility_management_request_branches(_client_organization_id uuid)
RETURNS TABLE (id uuid, name text, city text, site text, address text, is_active boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT (public.can_create_requests_as_facility_manager(_client_organization_id)
    OR public.can_manage_requests_as_facility_manager(_client_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized to edit this client''s requests' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT b.id, b.name, b.city, b.site, b.address, b.is_active
  FROM public.client_branches b
  WHERE b.organization_id = _client_organization_id
  ORDER BY b.name, b.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_facility_management_request_assets(_client_organization_id uuid)
RETURNS TABLE (id uuid, name text, code text, node_type text, parent_asset_id uuid, branch_id uuid, status text, path text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT (public.can_create_requests_as_facility_manager(_client_organization_id)
    OR public.can_manage_requests_as_facility_manager(_client_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized to edit this client''s requests' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT a.id, a.name, a.code, a.node_type, a.parent_asset_id, a.branch_id, a.status, public.resolve_asset_path(a.id)
  FROM public.assets a
  WHERE a.organization_id = _client_organization_id AND a.status <> 'archived'
  ORDER BY lower(a.name), a.id;
END;
$$;

-- Solo proveedores/subcontratistas con relación ACTIVA del cliente (nunca
-- un facility_manager). providers.manage no se delega.
CREATE OR REPLACE FUNCTION public.get_facility_management_request_providers(_client_organization_id uuid)
RETURNS TABLE (organization_id uuid, organization_name text, organization_type public.organization_type, specialties text[])
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT (public.can_create_requests_as_facility_manager(_client_organization_id)
    OR public.can_manage_requests_as_facility_manager(_client_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized to edit this client''s requests' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT org.id, org.name, org.organization_type, COALESCE(prof.specialties, '{}'::text[])
  FROM public.organizations org
  JOIN public.organization_relationships rel
    ON rel.source_organization_id = _client_organization_id
   AND rel.target_organization_id = org.id
   AND rel.status = 'active'
   AND rel.relationship_type = CASE org.organization_type
     WHEN 'provider_company' THEN 'provider'::public.organization_relationship_type
     WHEN 'subcontractor_company' THEN 'subcontracting'::public.organization_relationship_type
   END
  LEFT JOIN public.organization_profiles prof ON prof.organization_id = org.id
  WHERE org.organization_type IN ('provider_company', 'subcontractor_company')
    AND org.status = 'active'
  ORDER BY org.name, org.id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_facility_management_requests(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_request(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_facility_management_request(uuid, uuid, jsonb, jsonb, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_facility_management_request_draft(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.annul_facility_management_request(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_request_branches(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_request_assets(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_request_providers(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_management_requests(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_facility_management_request(uuid, uuid, jsonb, jsonb, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_facility_management_request_draft(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.annul_facility_management_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_request_branches(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_request_assets(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_request_providers(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- 6) Integraciones (verificado contra la definición vigente; firmas,
--    SECURITY DEFINER, search_path y grants se conservan).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.convert_maintenance_notice(p_notice_id uuid, p_request_id uuid)
 RETURNS maintenance_notices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_notice public.maintenance_notices%ROWTYPE;
  v_request public.requests%ROWTYPE;
  v_saved public.maintenance_notices%ROWTYPE;
  v_other_notice_number text;
  -- Miembro directo (o/a/m) / platform admin: comportamiento histórico.
  -- Facility Manager: avisos view+manage Y solicitudes view+create.
  v_direct boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT mn.* INTO v_notice FROM public.maintenance_notices mn WHERE mn.id = p_notice_id FOR UPDATE;
  IF v_notice.id IS NULL THEN
    RAISE EXCEPTION 'El aviso no existe';
  END IF;

  v_direct := public.can_manage_maintenance_notice(v_notice.organization_id);
  IF NOT v_direct AND NOT public.can_convert_maintenance_notice_as_facility_manager(v_notice.organization_id) THEN
    RAISE EXCEPTION 'Not authorized to convert maintenance notices for this organization';
  END IF;

  -- Reintento seguro de la MISMA conversión: no-op exitoso.
  IF v_notice.status = 'converted' THEN
    IF v_notice.converted_request_id = p_request_id THEN
      RETURN CASE WHEN v_direct THEN v_notice ELSE public.sanitize_maintenance_notice_for_delegate(v_notice) END;
    END IF;
    RAISE EXCEPTION 'Este aviso ya fue convertido en otra solicitud';
  END IF;

  IF v_notice.status <> 'open' AND v_notice.status <> 'triaged' THEN
    RAISE EXCEPTION 'Solo un aviso pendiente puede convertirse (estado actual: %)', v_notice.status;
  END IF;

  SELECT r.* INTO v_request FROM public.requests r WHERE r.id = p_request_id;
  -- Un borrador ajeno no existe para el delegado.
  IF v_request.id IS NULL OR (NOT v_direct AND NOT public.facility_management_can_see_request(v_request, true, true)) THEN
    RAISE EXCEPTION 'La solicitud no existe';
  END IF;
  IF v_request.organization_id IS DISTINCT FROM v_notice.organization_id THEN
    RAISE EXCEPTION 'La solicitud pertenece a otra organización';
  END IF;
  IF v_request.asset_id IS DISTINCT FROM v_notice.asset_id THEN
    RAISE EXCEPTION 'La solicitud debe referirse al mismo activo del aviso';
  END IF;
  IF v_request.status = 'anulado' THEN
    RAISE EXCEPTION 'La solicitud está anulada';
  END IF;

  -- 1 aviso <-> 1 solicitud (consolidar varios avisos está fuera de alcance).
  SELECT mn.notice_number INTO v_other_notice_number
  FROM public.maintenance_notices mn
  WHERE mn.converted_request_id = p_request_id AND mn.id <> p_notice_id;

  IF v_other_notice_number IS NOT NULL THEN
    RAISE EXCEPTION 'Esa solicitud ya está vinculada al aviso %', v_other_notice_number;
  END IF;

  UPDATE public.maintenance_notices mn
  SET status = 'converted',
      converted_request_id = p_request_id,
      converted_by_user_id = auth.uid(),
      converted_at = now()
  WHERE mn.id = p_notice_id
  RETURNING mn.* INTO v_saved;

  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_saved.organization_id,
    v_saved.asset_id,
    'maintenance_notice_converted',
    v_saved.notice_number || ' — convertido en ' || COALESCE(v_request.request_number, 'solicitud'),
    jsonb_build_object(
      'notice_id', v_saved.id,
      'notice_number', v_saved.notice_number,
      'priority', v_saved.priority,
      'request_id', p_request_id,
      'request_number', v_request.request_number
    ),
    auth.uid()
  );

  RETURN CASE WHEN v_direct THEN v_saved ELSE public.sanitize_maintenance_notice_for_delegate(v_saved) END;
END;
$function$;
CREATE OR REPLACE FUNCTION public.plan_preventive_maintenance_occurrence(p_occurrence_id uuid, p_request_id uuid)
 RETURNS preventive_maintenance_occurrences
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_plan_id uuid;
  v_occ public.preventive_maintenance_occurrences%ROWTYPE;
  v_request public.requests%ROWTYPE;
  -- Miembro directo (o/a/m) / platform admin: comportamiento histórico.
  -- Facility Manager: preventivo view+manage Y solicitudes view+create.
  v_direct boolean;
BEGIN
  SELECT o.plan_id INTO v_plan_id FROM public.preventive_maintenance_occurrences o WHERE o.id = p_occurrence_id;
  IF v_plan_id IS NULL THEN RAISE EXCEPTION 'Preventive maintenance occurrence not found'; END IF;
  PERFORM p.id FROM public.preventive_maintenance_plans p WHERE p.id = v_plan_id FOR UPDATE;
  SELECT * INTO v_occ FROM public.preventive_maintenance_occurrences WHERE id = p_occurrence_id FOR UPDATE;
  v_direct := public.can_manage_preventive_maintenance(v_occ.organization_id);
  IF NOT v_direct AND NOT public.can_plan_preventive_request_as_facility_manager(v_occ.organization_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_occ.status = 'planned' AND v_occ.request_id = p_request_id THEN RETURN CASE WHEN v_direct THEN v_occ ELSE public.sanitize_preventive_occurrence_for_delegate(v_occ) END; END IF;
  IF v_occ.status <> 'open' THEN RAISE EXCEPTION 'Only an open occurrence can be planned'; END IF;
  IF p_request_id <> v_occ.request_creation_id THEN
    RAISE EXCEPTION 'The request id must equal the occurrence request_creation_id';
  END IF;
  SELECT * INTO v_request FROM public.requests WHERE id = p_request_id FOR UPDATE;
  -- Un borrador ajeno no existe para el delegado.
  IF v_request.id IS NULL OR (NOT v_direct AND NOT public.facility_management_can_see_request(v_request, true, true)) THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_request.organization_id IS DISTINCT FROM v_occ.organization_id
    OR v_request.asset_id IS DISTINCT FROM v_occ.asset_id
    OR v_request.service_type::text <> 'preventivo' THEN
    RAISE EXCEPTION 'Request tenant, asset and service type must match the occurrence';
  END IF;
  IF v_request.status::text NOT IN ('draft', 'sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status cannot be linked to preventive maintenance';
  END IF;

  UPDATE public.preventive_maintenance_occurrences SET
    status = 'planned', request_id = v_request.id, planned_at = now()
  WHERE id = v_occ.id RETURNING * INTO v_occ;
  INSERT INTO public.asset_events (organization_id, asset_id, event_type, description, payload, created_by_user_id)
  VALUES (
    v_occ.organization_id, v_occ.asset_id, 'preventive_maintenance_planned',
    'Mantenimiento preventivo planificado en una solicitud',
    jsonb_build_object('plan_id', v_occ.plan_id, 'occurrence_id', v_occ.id,
      'request_id', v_request.id, 'sequence', v_occ.sequence), auth.uid()
  );
  PERFORM public.notify_preventive_occurrence(
    v_occ.id, 'preventive_maintenance_planned', 'Mantenimiento preventivo planificado',
    'La ocurrencia preventiva #' || v_occ.sequence::text || ' fue vinculada a una solicitud.'
  );
  RETURN CASE WHEN v_direct THEN v_occ ELSE public.sanitize_preventive_occurrence_for_delegate(v_occ) END;
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
  IF v_occ.status = 'skipped' THEN RETURN CASE WHEN public.is_platform_admin() OR public.is_organization_member(v_occ.organization_id) THEN v_occ
    ELSE public.sanitize_preventive_occurrence_for_delegate(v_occ) END; END IF;
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
  RETURN CASE WHEN public.is_platform_admin() OR public.is_organization_member(v_occ.organization_id) THEN v_occ
    ELSE public.sanitize_preventive_occurrence_for_delegate(v_occ) END;
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
  -- 9C.4: el delegado ve request_id con requests.view y request_creation_id
  -- solo si puede planificar la ocurrencia en una solicitud. OT: nunca.
  v_show_request boolean := v_direct OR public.can_view_requests_as_facility_manager(p_organization_id);
  v_show_request_creation boolean := v_direct OR public.can_plan_preventive_request_as_facility_manager(p_organization_id);
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
      -- 9C.4: el id del responsable es del cliente; el delegado solo sabe si
      -- hay uno ("Asignado por el cliente").
      'default_request_type', p.default_request_type,
      'responsible_member_id', CASE WHEN v_direct THEN p.responsible_member_id END,
      'has_responsible', p.responsible_member_id IS NOT NULL,
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
        'request_creation_id', CASE WHEN v_show_request_creation THEN o.request_creation_id END,
        'request_id', CASE WHEN v_show_request THEN o.request_id END,
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
  -- 9C.4: el delegado ve request_id con requests.view y request_creation_id
  -- solo si puede planificar la ocurrencia en una solicitud. OT: nunca.
  v_show_request boolean := v_direct OR public.can_view_requests_as_facility_manager(p_organization_id);
  v_show_request_creation boolean := v_direct OR public.can_plan_preventive_request_as_facility_manager(p_organization_id);
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
           'request_creation_id', CASE WHEN v_show_request_creation THEN o.request_creation_id END,
           'request_id', CASE WHEN v_show_request THEN o.request_id END,
           'work_order_id', NULL) END
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
  -- 9C.4: la solicitud generada, con requests.view (nunca un borrador ajeno).
  v_view_requests boolean := v_direct OR public.can_view_requests_as_facility_manager(p_organization_id);
  v_create_requests boolean := public.can_create_requests_as_facility_manager(p_organization_id);
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
    CASE WHEN v_direct OR (v_view_requests AND public.facility_management_can_see_request(r, true, v_create_requests)) THEN mn.converted_request_id END,
    CASE WHEN v_direct OR (v_view_requests AND public.facility_management_can_see_request(r, true, v_create_requests)) THEN r.request_number END AS converted_request_number,
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

-- -------------------------------------------------------------------------
-- 7) Responsable del plan preventivo (cierre 9C.4). Es del cliente: el
--    delegado no lo recibe (plans, snapshot, save, activar/desactivar) y no
--    lo envía; el servidor conserva el valor real al editar otros campos.
-- -------------------------------------------------------------------------
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
    -- 9C.4: el delegado nunca conoce el id; NULL = conservar el responsable
    -- real. Cualquier UUID (cliente o FM, incluso el mismo) se rechaza.
    IF NOT v_direct AND p_responsible_member_id IS NOT NULL THEN
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
      responsible_member_id = CASE WHEN v_direct THEN p_responsible_member_id ELSE v_plan.responsible_member_id END,
      planning_lead_days = p_planning_lead_days,
      frequency = p_frequency, custom_interval = p_custom_interval, custom_unit = p_custom_unit,
      first_due_at = p_first_due_at, interval_value = p_interval_value,
      meter_lead_value = p_meter_lead_value
    WHERE id = p_plan_id RETURNING * INTO v_plan;
  END IF;
  RETURN CASE WHEN v_direct THEN v_plan ELSE public.sanitize_preventive_plan_for_delegate(v_plan) END;
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
  IF v_plan.is_active = p_is_active THEN RETURN CASE WHEN public.is_platform_admin() OR public.is_organization_member(v_plan.organization_id) THEN v_plan
    ELSE public.sanitize_preventive_plan_for_delegate(v_plan) END; END IF;

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
  RETURN CASE WHEN public.is_platform_admin() OR public.is_organization_member(v_plan.organization_id) THEN v_plan
    ELSE public.sanitize_preventive_plan_for_delegate(v_plan) END;
END;
$function$;


-- -------------------------------------------------------------------------
-- 8) Inspecciones (último hardening 9C.4). responsible_member_id es del
--    cliente: el delegado recibe NULL + has_responsible y un nombre seguro
--    (nunca derivado del email); no lo envía nunca (cualquier UUID => 42501,
--    incluido el actual) y el servidor conserva el responsable real. Los
--    retornos de escritura (plan, ejecución) van minimizados. La regla 9C.2
--    "el FM reenvía exactamente el id actual" queda reemplazada.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sanitize_inspection_plan_for_delegate(_plan public.inspection_plans)
RETURNS public.inspection_plans
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_plan public.inspection_plans := _plan;
BEGIN
  v_plan.responsible_member_id := NULL;
  v_plan.created_by_user_id := NULL;
  RETURN v_plan;
END;
$$;

CREATE OR REPLACE FUNCTION public.sanitize_inspection_run_for_delegate(_run public.inspection_runs)
RETURNS public.inspection_runs
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_run public.inspection_runs := _run;
BEGIN
  v_run.responsible_member_id := NULL;
  v_run.created_by_user_id := NULL;
  RETURN v_run;
END;
$$;

REVOKE ALL ON FUNCTION public.sanitize_inspection_plan_for_delegate(public.inspection_plans) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sanitize_inspection_run_for_delegate(public.inspection_runs) FROM PUBLIC, anon, authenticated;

-- Lecturas: agregar has_responsible cambia el RETURNS TABLE, así que se
-- recrean con los mismos grants (authenticated + service_role; nunca anon).
DROP FUNCTION public.get_inspection_plans(uuid, boolean);
CREATE OR REPLACE FUNCTION public.get_inspection_plans(p_organization_id uuid, p_include_inactive boolean DEFAULT false)
 RETURNS TABLE(id uuid, template_id uuid, template_name text, branch_id uuid, branch_name text, area_asset_id uuid, area_asset_name text, asset_id uuid, asset_name text, responsible_member_id uuid, responsible_name text, has_responsible boolean, title text, description text, frequency text, custom_interval integer, custom_unit text, start_date date, next_due_at timestamp with time zone, is_active boolean, created_at timestamp with time zone, alert_rules jsonb)
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
    CASE WHEN v_direct THEN ip.responsible_member_id END,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) ELSE NULLIF(TRIM(au.raw_user_meta_data->>'name'), '') END AS responsible_name,
    ip.responsible_member_id IS NOT NULL AS has_responsible,
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
REVOKE ALL ON FUNCTION public.get_inspection_plans(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_inspection_plans(uuid, boolean) TO authenticated, service_role;

DROP FUNCTION public.get_inspection_runs(uuid, text);
CREATE OR REPLACE FUNCTION public.get_inspection_runs(p_organization_id uuid, p_status text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, organization_id uuid, plan_id uuid, template_id uuid, template_name text, branch_name text, area_asset_name text, asset_name text, responsible_member_id uuid, responsible_name text, has_responsible boolean, scheduled_for timestamp with time zone, started_at timestamp with time zone, completed_at timestamp with time zone, status text, result text)
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
    CASE WHEN v_direct THEN ir.responsible_member_id END,
    CASE WHEN v_direct THEN COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) ELSE NULLIF(TRIM(au.raw_user_meta_data->>'name'), '') END AS responsible_name,
    ir.responsible_member_id IS NOT NULL AS has_responsible,
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
REVOKE ALL ON FUNCTION public.get_inspection_runs(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_inspection_runs(uuid, text) TO authenticated, service_role;

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
    'responsible_member_id', CASE WHEN v_direct THEN ir.responsible_member_id END,
    'has_responsible', ir.responsible_member_id IS NOT NULL,
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

  RETURN CASE WHEN public.is_platform_admin() OR public.is_organization_member(v_saved.organization_id) THEN v_saved
    ELSE public.sanitize_inspection_run_for_delegate(v_saved) END;
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

  RETURN CASE WHEN public.is_platform_admin() OR public.is_organization_member(v_saved.organization_id) THEN v_saved
    ELSE public.sanitize_inspection_run_for_delegate(v_saved) END;
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
  v_direct boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.can_plan_inspections(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage inspection plans for this organization';
  END IF;

  -- responsible_member_id pertenece al modelo de membresías del CLIENTE. El
  -- Facility Manager delegado nunca conoce el id: envía NULL (un plan nuevo
  -- queda sin responsable; uno existente conserva el real en el servidor).
  -- Cualquier UUID (cliente, FM o el mismo actual) => 42501 (9C.4).
  v_direct := public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]);
  IF NOT v_direct THEN
    IF p_responsible_member_id IS NOT NULL THEN
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
        responsible_member_id = CASE WHEN v_direct THEN p_responsible_member_id ELSE ip.responsible_member_id END,
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

  RETURN CASE WHEN public.is_platform_admin() OR public.is_organization_member(v_saved.organization_id) THEN v_saved
    ELSE public.sanitize_inspection_plan_for_delegate(v_saved) END;
END;
$function$;
