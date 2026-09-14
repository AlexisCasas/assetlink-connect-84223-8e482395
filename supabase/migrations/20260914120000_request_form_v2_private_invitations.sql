-- Fase 19 — Formulario de Solicitud v2 + Invitaciones Privadas.
--
-- No crea catálogo paralelo de proveedores ni tabla nueva de invitaciones:
-- reutiliza request_provider_access (20260721172541_provider_request_visibility.sql,
-- ya usada por can_user_read_request/can_provider_quote_request desde Fase 16/17)
-- como única ACL de audiencia privada, y organization_relationships +
-- get_provider_relationship_directory (Fase 18,
-- 20260831110000_tenant_aware_provider_homologation.sql) como único directorio
-- de proveedores homologados. La lectura de requests/quotes por parte de un
-- proveedor invitado YA está correctamente resuelta por las policies
-- existentes de esas dos migraciones (is_public OR request_provider_access
-- activo) — este archivo no las toca.
--
-- Bloques:
--   A) requests: contacto de coordinación (snapshot) + dirección de servicio
--      (snapshot).
--   B) requests: visita técnica mejorada (visit_schedule_mode, contacto de
--      visita).
--   C) Trigger de consistencia para los dos member_id nuevos (mismo patrón
--      que check_request_internal_responsible).
--   D) get_coordination_contacts — directorio de miembros activos de la
--      propia organización (cualquier rol; a diferencia de
--      get_assignable_technicians esto no filtra por rol porque cualquier
--      miembro activo puede coordinar un servicio).
--   E) set_request_audience — RPC transaccional: única vía para pasar una
--      solicitud externa de pública a privada (o viceversa) y sincronizar
--      sus invitaciones, notificaciones y auditoría en una sola transacción.

-- =========================================================================
-- A) requests.coordination_contact_* + requests.service_address
--
-- coordination_contact_member_id apunta al organization_members vivo (para
-- poder cambiarlo); coordination_contact_name/email son el snapshot al
-- momento de guardar — una solicitud histórica nunca cambia si el perfil del
-- miembro cambia después. No se agrega coordination_contact_phone: el modelo
-- actual (organization_members / auth.users) no tiene ningún campo de
-- teléfono que snapshotear — agregar la columna sin una fuente real violaría
-- "no agregar campos para escenarios que no pueden pasar".
--
-- service_address es el snapshot de client_branches.address al momento de
-- seleccionar la sucursal; requests.branch_id sigue siendo la referencia
-- viva, pero el texto mostrado/histórico nunca depende de ella after the fact.
-- =========================================================================
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS coordination_contact_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS coordination_contact_name text NULL,
  ADD COLUMN IF NOT EXISTS coordination_contact_email text NULL,
  ADD COLUMN IF NOT EXISTS service_address text NULL;

CREATE INDEX IF NOT EXISTS idx_requests_coordination_contact_member_id
  ON public.requests (coordination_contact_member_id);

-- =========================================================================
-- B) requests.visit_schedule_mode + requests.visit_contact_member_id
--
-- visit_schedule_mode is only meaningful while requires_visit is true:
-- 'scheduled' requires a visit_date; 'to_schedule' forbids one (the provider
-- coordinates it later with visit_contact_member_id). Legacy rows predate
-- this column entirely, so they are backfilled first from their existing
-- requires_visit/visit_date pair before the CHECK below can be added safely.
-- =========================================================================
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS visit_schedule_mode text NULL,
  ADD COLUMN IF NOT EXISTS visit_contact_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE SET NULL;

-- Defensive cleanup for any pre-existing inconsistent row (requires_visit
-- false/null but a stale visit_date) — otherwise the CHECK constraint below
-- would fail to apply against real data.
UPDATE public.requests
SET visit_date = NULL
WHERE COALESCE(requires_visit, false) = false
  AND visit_date IS NOT NULL;

UPDATE public.requests
SET visit_schedule_mode = CASE
  WHEN requires_visit IS TRUE AND visit_date IS NOT NULL THEN 'scheduled'
  WHEN requires_visit IS TRUE THEN 'to_schedule'
  ELSE NULL
END
WHERE visit_schedule_mode IS NULL;

DO $$ BEGIN
  ALTER TABLE public.requests
    ADD CONSTRAINT requests_visit_schedule_mode_check CHECK (
      (COALESCE(requires_visit, false) = false AND visit_schedule_mode IS NULL AND visit_date IS NULL)
      OR (requires_visit IS TRUE AND visit_schedule_mode = 'scheduled' AND visit_date IS NOT NULL)
      OR (requires_visit IS TRUE AND visit_schedule_mode = 'to_schedule' AND visit_date IS NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_requests_visit_contact_member_id
  ON public.requests (visit_contact_member_id);

-- =========================================================================
-- C) Consistency guard for the two new member_id columns — same pattern as
-- check_request_internal_responsible (20260827043747_internal_requests_work_orders.sql),
-- minus the role restriction: a coordination/visit contact can be any active
-- member of the request's own organization, not only a technician. SECURITY
-- INVOKER on purpose (no privilege escalation needed: the caller already has
-- RLS read access to their own organization's members).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.check_request_contact_members()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  member_org uuid;
  member_active boolean;
BEGIN
  IF NEW.coordination_contact_member_id IS NOT NULL THEN
    SELECT organization_id, is_active INTO member_org, member_active
      FROM public.organization_members WHERE id = NEW.coordination_contact_member_id;

    IF member_org IS NULL THEN
      RAISE EXCEPTION 'coordination_contact_member_id does not reference an existing organization member';
    END IF;
    IF NEW.organization_id IS NULL OR member_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'coordination_contact_member_id must belong to the request organization';
    END IF;
    IF NOT member_active THEN
      RAISE EXCEPTION 'coordination_contact_member_id must be an active member';
    END IF;
  END IF;

  IF NEW.visit_contact_member_id IS NOT NULL THEN
    SELECT organization_id, is_active INTO member_org, member_active
      FROM public.organization_members WHERE id = NEW.visit_contact_member_id;

    IF member_org IS NULL THEN
      RAISE EXCEPTION 'visit_contact_member_id does not reference an existing organization member';
    END IF;
    IF NEW.organization_id IS NULL OR member_org <> NEW.organization_id THEN
      RAISE EXCEPTION 'visit_contact_member_id must belong to the request organization';
    END IF;
    IF NOT member_active THEN
      RAISE EXCEPTION 'visit_contact_member_id must be an active member';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_requests_check_contact_members ON public.requests;
CREATE TRIGGER trg_requests_check_contact_members
BEFORE INSERT OR UPDATE ON public.requests
FOR EACH ROW EXECUTE FUNCTION public.check_request_contact_members();

REVOKE ALL ON FUNCTION public.check_request_contact_members() FROM PUBLIC, anon, authenticated;

-- =========================================================================
-- D) get_coordination_contacts — mirrors get_assignable_technicians
-- (20260827041707_operation_members_roles.sql) exactly, minus the
-- `role = 'technician'` filter: any active member of the organization is a
-- valid coordination/visit contact. organization_members has no name/email
-- of its own (they live in auth.users), same reason the technician RPC needs
-- to be SECURITY DEFINER and join auth.users itself instead of letting the
-- frontend query organization_members directly.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_coordination_contacts(p_organization_id uuid)
RETURNS TABLE (
  member_id uuid,
  user_id uuid,
  name text,
  email text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to list members for this organization';
  END IF;

  RETURN QUERY
  SELECT
    member.id AS member_id,
    member.user_id,
    COALESCE(NULLIF(TRIM(user_account.raw_user_meta_data->>'name'), ''), split_part(user_account.email, '@', 1)) AS name,
    user_account.email::text AS email
  FROM public.organization_members member
  INNER JOIN auth.users user_account ON user_account.id = member.user_id
  WHERE member.organization_id = p_organization_id
    AND member.is_active
  ORDER BY 3;
END;
$$;

REVOKE ALL ON FUNCTION public.get_coordination_contacts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_coordination_contacts(uuid) TO authenticated;

-- =========================================================================
-- E) set_request_audience — the single transactional entry point for
-- switching an external request between public/private and syncing its
-- private invitations. Runs entirely inside one PL/pgSQL function, so a
-- failure partway through (e.g. an invalid provider) rolls back everything,
-- including any request_provider_access row already touched in this same
-- call — there is no way to end up with is_public flipped but no ACL synced,
-- or vice versa.
--
-- Frontend keeps inserting/updating the requests row directly (unchanged
-- pattern from RequestList.tsx) for every other field; only the audience
-- (is_public + the private provider list) goes through this RPC, called
-- right after that insert/update succeeds.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.set_request_audience(
  p_request_id uuid,
  p_is_public boolean,
  p_provider_organization_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS TABLE (is_public boolean, provider_organization_ids uuid[])
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
  -- request may manage its audience. A caller from another organization
  -- (Cliente B) is rejected here regardless of what ids it sends.
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
    -- Public marketplace mode never carries private invitations alongside
    -- it in this MVP — any ids sent together with is_public=true are
    -- ignored rather than silently kept as a mixed state.
    v_desired := '{}'::uuid[];
  ELSIF array_length(v_desired, 1) IS NULL THEN
    RAISE EXCEPTION 'Selecciona al menos un proveedor para enviar una invitación privada.';
  END IF;

  -- Validate every target from scratch: active provider-facing organization,
  -- and homologated/active specifically for THIS client organization via
  -- organization_relationships (Fase 18) — never trusts organization_type,
  -- name or homologation status sent by the frontend.
  IF array_length(v_desired, 1) > 0 THEN
    FOREACH v_target IN ARRAY v_desired LOOP
      SELECT * INTO v_provider_org FROM public.organizations WHERE id = v_target;
      IF v_provider_org.id IS NULL
        OR v_provider_org.status <> 'active'
        OR v_provider_org.organization_type NOT IN ('provider_company', 'facility_manager', 'subcontractor_company') THEN
        RAISE EXCEPTION 'Organización proveedora inválida: %', v_target;
      END IF;

      SELECT status INTO v_relationship_status
      FROM public.organization_relationships
      WHERE source_organization_id = v_request.organization_id
        AND target_organization_id = v_target;

      IF v_relationship_status IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'La organización % no está homologada/activa para tu organización', v_provider_org.name;
      END IF;
    END LOOP;
  END IF;

  -- Current active "invited" audience for this request (access_type =
  -- 'invited' — 'marketplace'/'relationship' access rows, if any ever exist,
  -- are a separate concept this RPC never touches).
  SELECT COALESCE(ARRAY_AGG(provider_organization_id), '{}'::uuid[]) INTO v_current
  FROM public.request_provider_access
  WHERE request_id = p_request_id
    AND access_type = 'invited'
    AND status = 'active';

  v_to_add := ARRAY(SELECT unnest(v_desired) EXCEPT SELECT unnest(v_current));
  v_to_remove := ARRAY(SELECT unnest(v_current) EXCEPT SELECT unnest(v_desired));

  -- A provider that already submitted a quote can never be removed from the
  -- audience through this path — formal cancellation of its participation is
  -- out of scope for this phase.
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

      -- Only owner/admin/manager/quote_manager of the invited organization —
      -- same role set can_provider_quote_request already requires to act on
      -- this request — are notified, never a broadcast to the whole org.
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

REVOKE ALL ON FUNCTION public.set_request_audience(uuid, boolean, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_request_audience(uuid, boolean, uuid[]) TO authenticated;
