-- =========================================================================
-- Fase 1 · Punto 9B — UI de administración de Facility Managers.
--
-- Backend complementario a 20260927194923_facility_manager_delegated_permissions.sql
-- (9A, ya desplegada, no se modifica):
--
--   A) get_facility_manager_directory — directorio propio de empresas FM
--      para la pantalla "Facility Managers" del cliente.
--   B) Cierre de la deuda legacy documentada en 9A: la homologación de
--      proveedores (get_provider_relationship_directory /
--      set_provider_relationship_status) deja de administrar
--      facility_manager. Desde aquí, toda relación facility_management se
--      gestiona EXCLUSIVAMENTE con las RPCs de 9A.
--   C) facility_manager deja de ser provider-facing: no recibe invitaciones,
--      no lee solicitudes como proveedor ni cotiza
--      (is_provider_facing_organization, can_user_read_request,
--      set_request_audience).
--
-- No abre acceso delegado a ningún módulo funcional (eso es 9C) ni crea
-- tablas. Ver docs/FACILITY_MANAGER_DELEGATED_PERMISSIONS.md.
--
-- SQLSTATE (misma convención que 9A): 42501 no autorizado, 22023
-- parámetro inválido.
-- =========================================================================

-- -------------------------------------------------------------------------
-- A) get_facility_manager_directory
--    Empresas facility_manager activas, con la relación facility_management
--    (si existe) que el cliente tiene con cada una. Solo id/nombre/estado
--    de relación: nunca miembros, emails ni metadata.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_facility_manager_directory(
  _client_organization_id uuid
)
RETURNS TABLE (
  facility_manager_organization_id uuid,
  facility_manager_organization_name text,
  relationship_id uuid,
  relationship_status public.organization_relationship_status
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(_client_organization_id, ARRAY['owner', 'admin']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this organization''s facility manager directory' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = _client_organization_id AND o.organization_type = 'client_company'
  ) THEN
    RAISE EXCEPTION '_client_organization_id must reference a client company' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT fm.id, fm.name, rel.id, rel.status
  FROM public.organizations fm
  LEFT JOIN public.organization_relationships rel
    ON rel.source_organization_id = _client_organization_id
   AND rel.target_organization_id = fm.id
   AND rel.relationship_type = 'facility_management'
  WHERE fm.organization_type = 'facility_manager'
    AND fm.status = 'active'
  ORDER BY fm.name, fm.id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_facility_manager_directory(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_manager_directory(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- B.1) get_provider_relationship_directory — mismo contrato de retorno
--      (el frontend no cambia de forma), pero solo provider_company y
--      subcontractor_company. Los facility_manager tienen su propio
--      directorio (A).
-- -------------------------------------------------------------------------
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
    CASE org.organization_type
      WHEN 'provider_company' THEN 'provider'::public.organization_relationship_type
      WHEN 'subcontractor_company' THEN 'subcontracting'::public.organization_relationship_type
    END,
    rel.status,
    COALESCE(prof.specialties, '{}'::text[])
  FROM public.organizations org
  LEFT JOIN public.organization_relationships rel
    ON rel.source_organization_id = p_client_organization_id
    AND rel.target_organization_id = org.id
    -- Solo la relación que corresponde al tipo (provider/subcontracting);
    -- nunca una fila facility_management.
    AND rel.relationship_type = CASE org.organization_type
      WHEN 'provider_company' THEN 'provider'::public.organization_relationship_type
      WHEN 'subcontractor_company' THEN 'subcontracting'::public.organization_relationship_type
    END
  LEFT JOIN public.organization_profiles prof
    ON prof.organization_id = org.id
  WHERE org.organization_type IN ('provider_company', 'subcontractor_company')
    AND org.status = 'active'
  ORDER BY org.name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_provider_relationship_directory(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_provider_relationship_directory(uuid) TO authenticated;

-- -------------------------------------------------------------------------
-- B.2) set_provider_relationship_status — solo provider/subcontracting.
--      Un target facility_manager se rechaza con 22023 (antes de cualquier
--      escritura): las relaciones facility_management tienen su propia
--      máquina de estados, permisos, equipo asignado y auditoría en 9A.
--      Todo lo demás (autorización, validaciones, upsert que preserva
--      created_by) queda idéntico.
-- -------------------------------------------------------------------------
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

  IF target_org.organization_type = 'facility_manager' THEN
    RAISE EXCEPTION 'Facility managers are managed with the facility management RPCs, not provider homologation'
      USING ERRCODE = '22023';
  END IF;

  IF target_org.id IS NULL
    OR target_org.status <> 'active'
    OR target_org.organization_type NOT IN ('provider_company', 'subcontractor_company') THEN
    RAISE EXCEPTION 'p_target_organization_id must reference an active provider organization';
  END IF;

  derived_type := CASE target_org.organization_type
    WHEN 'provider_company' THEN 'provider'::public.organization_relationship_type
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

REVOKE ALL ON FUNCTION public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_provider_relationship_status(uuid, uuid, public.organization_relationship_status) TO authenticated;

-- =========================================================================
-- C) Facility Manager deja de ser provider-facing (decisión funcional MVP).
--
--    provider_company y subcontractor_company reciben invitaciones y
--    cotizan. facility_manager NO actúa como proveedor/ofertante: administra
--    procesos del cliente mediante permisos delegados (9A/9C). Los permisos
--    quotes.view/quotes.manage/quotes.approve son gestión delegada de las
--    cotizaciones DEL CLIENTE, nunca presentar una cotización como FM. Si una
--    organización debiera ser FM y proveedor a la vez, se modelará como
--    capacidad dual explícita, no se inferirá de organization_type.
--
--    is_provider_facing_organization es la única fuente de verdad: las
--    policies de request_provider_access, can_provider_quote_request y
--    can_user_read_request dependen de ella.
-- =========================================================================

-- C.1) Antes: provider_company + facility_manager (subcontractor_company
--      faltaba). Ahora: solo provider_company y subcontractor_company activos.
CREATE OR REPLACE FUNCTION public.is_provider_facing_organization(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organizations organization
    WHERE organization.id = _organization_id
      AND organization.organization_type IN ('provider_company', 'subcontractor_company')
      AND organization.status = 'active'
  );
$$;

REVOKE ALL ON FUNCTION public.is_provider_facing_organization(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_provider_facing_organization(uuid) TO authenticated;

-- C.2) can_user_read_request: la rama provider-facing ya no duplica tipos;
--      delega en is_provider_facing_organization. Un FM no lee solicitudes
--      como proveedor (ni públicas ni invitadas). El acceso delegado de un FM
--      a solicitudes de su cliente llegará en 9C por otra vía.
CREATE OR REPLACE FUNCTION public.can_user_read_request(_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = _request_id
        AND request.organization_id IS NOT NULL
        AND public.is_organization_member(request.organization_id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.requests request
      INNER JOIN public.organization_members membership
        ON membership.user_id = auth.uid()
        AND membership.is_active
      LEFT JOIN public.request_provider_access access
        ON access.request_id = request.id
        AND access.provider_organization_id = membership.organization_id
        AND access.status = 'active'
      WHERE request.id = _request_id
        AND request.status <> 'draft'
        AND public.is_provider_facing_organization(membership.organization_id)
        AND (request.is_public IS TRUE OR access.id IS NOT NULL)
    )
  );
$$;

REVOKE ALL ON FUNCTION public.can_user_read_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_user_read_request(uuid) TO authenticated;

-- C.3) can_provider_quote_request no cambia: ya depende exclusivamente de
--      is_provider_facing_organization (C.1), así que un FM queda fuera de
--      forma automática. Los permisos delegados quotes.* no intervienen aquí.

-- C.4) set_request_audience: mismo contrato, reglas del cliente, atomicidad,
--      auditoría y protección de cotizaciones. Solo cambia la validación de
--      destinatarios: facility_manager se rechaza con 22023; el resto debe
--      ser provider-facing (C.1) con una relación ACTIVA del tipo que le
--      corresponde (provider/subcontracting), nunca facility_management.
CREATE OR REPLACE FUNCTION public.set_request_audience(
  p_request_id uuid,
  p_is_public boolean,
  p_provider_organization_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS TABLE(is_public boolean, provider_organization_ids uuid[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.set_request_audience(uuid, boolean, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_request_audience(uuid, boolean, uuid[]) TO authenticated;
