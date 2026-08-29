-- Fase 17 — Estabilización crítica: cierra el gap que permitió que una
-- misma solicitud terminara con una OT externa Y una OT interna
-- simultáneamente (caso confirmado: SOL-596329). Tres candados
-- independientes en la cadena cotización → aprobación → OT, más un
-- trigger que congela request_type fuera de 'draft'. No cambia el
-- comportamiento del flujo externo normal ni del interno normal —
-- cada candado nuevo solo añade una condición adicional sobre el
-- camino que ya exigía todo lo demás.

-- =========================================================================
-- 1) can_provider_quote_request — ya no permite cotizar una solicitud
--    'internal'. Único cambio respecto a la versión de
--    20260721174717_quotes_tenant_migration.sql: la condición
--    "request.request_type = 'external'" agregada al EXISTS.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.can_provider_quote_request(
  target_request_id uuid,
  target_provider_organization_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND public.is_provider_facing_organization(target_provider_organization_id)
    AND public.has_organization_role(
      target_provider_organization_id,
      ARRAY['owner', 'admin', 'manager', 'quote_manager']::public.organization_member_role[]
    )
    AND EXISTS (
      SELECT 1
      FROM public.requests request
      WHERE request.id = target_request_id
        AND request.status <> 'draft'
        AND request.request_type = 'external'
        AND COALESCE(request.quotes_closed, false) IS FALSE
        AND (
          request.is_public IS TRUE
          OR EXISTS (
            SELECT 1
            FROM public.request_provider_access access
            WHERE access.request_id = request.id
              AND access.provider_organization_id = target_provider_organization_id
              AND access.status = 'active'
          )
        )
    );
$$;

-- =========================================================================
-- 2) approve_quote — segunda capa: aunque ya exista una cotización sobre
--    una solicitud 'internal' (dato legacy, p. ej. SOL-596329), no puede
--    volver a aprobarse. Único cambio respecto a
--    20260721181719_quote_approval_tenant_flow.sql: se agrega
--    request_request_type a la selección inicial y el chequeo
--    correspondiente antes de tocar cualquier fila.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.approve_quote(target_quote_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  quote_request_id uuid;
  client_organization_id uuid;
  request_status public.request_status;
  request_request_type text;
  is_authorized boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT quote.request_id, request.organization_id, request.status, request.request_type
  INTO quote_request_id, client_organization_id, request_status, request_request_type
  FROM public.quotes quote
  INNER JOIN public.requests request ON request.id = quote.request_id
  WHERE quote.id = target_quote_id;

  IF quote_request_id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
  END IF;

  IF request_request_type <> 'external' THEN
    RAISE EXCEPTION 'Only quotes on external requests can be approved';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.organizations organization
    WHERE organization.id = client_organization_id
      AND organization.organization_type = 'client_company'
      AND organization.status = 'active'
      AND public.has_organization_role(
        client_organization_id,
        ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
      )
  ) INTO is_authorized;

  IF NOT public.is_platform_admin() AND NOT is_authorized THEN
    RAISE EXCEPTION 'Not authorized to approve this quote';
  END IF;

  IF request_status NOT IN ('sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status does not allow quote approval';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.quotes quote
    WHERE quote.id = target_quote_id AND quote.status = 'submitted'
  ) THEN
    RAISE EXCEPTION 'Only submitted quotes can be approved';
  END IF;

  UPDATE public.quotes
  SET status = 'approved',
      approved_at = now(),
      approved_by_user_id = auth.uid(),
      rejected_at = NULL,
      rejected_by_user_id = NULL,
      rejection_reason = NULL
  WHERE id = target_quote_id;

  -- There can be one selected quote per request. Submitted alternatives are
  -- recorded as rejected without touching their commercial content.
  UPDATE public.quotes
  SET status = 'rejected',
      rejected_at = now(),
      rejected_by_user_id = auth.uid(),
      rejection_reason = COALESCE(rejection_reason, 'Not selected')
  WHERE request_id = quote_request_id
    AND id <> target_quote_id
    AND status = 'submitted';
END;
$$;

-- =========================================================================
-- 3) create_work_order_from_quote — tercera capa: aunque una cotización
--    sobre una solicitud 'internal' llegara a 'approved' (no debería,
--    dados los candados 1 y 2), no puede generar una OT. Único cambio
--    respecto a 20260829150000_operational_notifications.sql: el chequeo
--    de source_request.request_type agregado justo después de resolver
--    source_request, antes de la autorización.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.create_work_order_from_quote(target_quote_id uuid)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_quote public.quotes%ROWTYPE;
  source_request public.requests%ROWTYPE;
  created_work_order public.work_orders%ROWTYPE;
  can_create boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT quote.* INTO source_quote
  FROM public.quotes quote
  WHERE quote.id = target_quote_id
  FOR UPDATE;

  IF source_quote.id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
  END IF;

  IF source_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'A work order can only be created from an approved quote';
  END IF;

  IF source_quote.provider_organization_id IS NULL THEN
    RAISE EXCEPTION 'Approved quote has no provider organization';
  END IF;

  SELECT request.* INTO source_request
  FROM public.requests request
  WHERE request.id = source_quote.request_id;

  IF source_request.id IS NULL OR source_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Quote request has no client organization';
  END IF;

  IF source_request.request_type <> 'external' THEN
    RAISE EXCEPTION 'Only external requests can generate a work order from a quote';
  END IF;

  can_create := public.is_platform_admin()
    OR public.has_organization_role(
      source_request.organization_id,
      ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
    );

  IF NOT can_create THEN
    RAISE EXCEPTION 'Not authorized to create a work order for this quote';
  END IF;

  INSERT INTO public.work_orders (
    request_id,
    quote_id,
    client_organization_id,
    provider_organization_id,
    work_order_type,
    asset_id,
    priority,
    due_at,
    planner_member_id,
    status,
    title,
    description,
    total_amount,
    created_by_user_id
  ) VALUES (
    source_quote.request_id,
    source_quote.id,
    source_request.organization_id,
    source_quote.provider_organization_id,
    'external',
    source_request.asset_id,
    public.map_request_priority_to_work_order_priority(source_request.priority),
    source_request.deadline,
    public.resolve_caller_planner_member(source_quote.provider_organization_id),
    'pending',
    source_request.title,
    source_quote.description,
    source_quote.total_amount,
    auth.uid()
  )
  ON CONFLICT (quote_id) DO NOTHING
  RETURNING * INTO created_work_order;

  IF created_work_order.id IS NULL THEN
    SELECT work_order.* INTO created_work_order
    FROM public.work_orders work_order
    WHERE work_order.quote_id = source_quote.id;

    RETURN created_work_order;
  END IF;

  PERFORM public.notify_role_members(
    source_quote.provider_organization_id,
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
    auth.uid(),
    'work_order_created',
    'Nueva orden de trabajo',
    'Se creó la orden ' || created_work_order.work_order_number || ' a partir de una cotización aprobada.',
    'work_order',
    created_work_order.id,
    'medium',
    jsonb_build_object('work_order_number', created_work_order.work_order_number)
  );

  RETURN created_work_order;
END;
$$;

-- Los tres REVOKE/GRANT de estas funciones ya existen desde sus migraciones
-- originales (CREATE OR REPLACE conserva el ACL vigente) — no se repiten
-- aquí a propósito, para no interferir con MIGRACIÓN 2
-- (function_acl_hardening), que es la que trata el ACL explícitamente.

-- =========================================================================
-- 4) lock_request_type_after_submission — congela request_type una vez
--    que la solicitud deja 'draft', e impide que una solicitud ya enviada
--    vuelva a 'draft'. SECURITY INVOKER on purpose: solo compara OLD/NEW
--    de la fila que el caller ya tiene permiso de actualizar (la política
--    RLS de UPDATE sobre requests es la barrera real de "quién puede
--    tocar esta fila"; este trigger solo restringe "qué puede cambiar"
--    dentro de esa fila), sin necesidad de escalar privilegios.
--
--    Dos reglas independientes:
--    A) status no puede retroceder a 'draft' una vez que salió de ahí.
--    B) request_type solo puede cambiar mientras OLD.status = 'draft' Y
--       la solicitud todavía no tiene ninguna quote ni ningún work_order
--       (dato legacy huérfano incluido — no solo "todavía en draft"). El
--       caso normal draft-external -> cambiar a internal -> enviar sigue
--       permitido: en esa misma UPDATE, OLD.status sigue siendo 'draft' y
--       nada se ha creado todavía sobre esa solicitud.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.lock_request_type_after_submission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.status <> 'draft' AND NEW.status = 'draft' THEN
    RAISE EXCEPTION 'A request cannot return to draft status once it has left draft';
  END IF;

  IF NEW.request_type IS DISTINCT FROM OLD.request_type THEN
    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'request_type cannot change once a request has left draft status';
    END IF;

    IF EXISTS (SELECT 1 FROM public.quotes WHERE request_id = OLD.id) THEN
      RAISE EXCEPTION 'request_type cannot change once the request already has a quote';
    END IF;

    IF EXISTS (SELECT 1 FROM public.work_orders WHERE request_id = OLD.id) THEN
      RAISE EXCEPTION 'request_type cannot change once the request already has a work order';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_requests_lock_request_type ON public.requests;
CREATE TRIGGER trg_requests_lock_request_type
  BEFORE UPDATE ON public.requests
  FOR EACH ROW EXECUTE FUNCTION public.lock_request_type_after_submission();
