-- =========================================================================
-- Fase 1 · Punto 9C.5 — Acceso operativo de Facility Manager a Cotizaciones.
--
-- Hace efectivos SOLO quotes.view y quotes.approve. quotes.manage NO abre
-- nada: la única escritura del cliente sobre una cotización que no es
-- aprobar/rechazar (client_observation) está deshabilitada en la UI directa
-- y la policy de UPDATE de quotes es solo del proveedor, así que no existe
-- una operación de gestión validada que delegar. No abre work_orders.*,
-- reports.*, providers.manage, inventario ni R2.
--
-- El FM actúa en representación del CLIENTE. Nunca es proveedor: las
-- policies de quotes (INSERT/UPDATE/DELETE de proveedor), can_provider_quote_request
-- y is_provider_facing_organization no cambian y siguen dando false a un FM.
--
-- Acceso delegado = has_facility_management_operational_access_all (9C.1):
-- relación facility_management ACTIVE + cliente ACTIVE + FM ACTIVE +
-- membresía ACTIVA en ESE FM + ESA membresía asignada a ESA relación +
-- todos los permisos en ESA relación + rol compatible.
--
-- Matriz del FM (el acceso directo de los miembros del cliente NO cambia):
--   ver        requests.view + quotes.view                    o/a/m/requester
--   aprobar /  requests.view + quotes.view + quotes.approve   o/a/m
--   rechazar
-- *.approve nunca sustituye a *.view.
--
-- Diseño:
--   - La RLS de quotes NO cambia: can_user_read_quote sigue exigiendo
--     membresía del cliente o del proveedor. El FM opera solo con RPCs
--     SECURITY DEFINER que devuelven una respuesta minimizada.
--   - Ocultación de importes en SERVIDOR: el importe (amount) solo se
--     devuelve cuando las cotizaciones recibidas (submitted/approved/
--     rejected) alcanzan requests.min_quotes, la misma regla que aplica la
--     UI directa al recargar. Mientras estén ocultos, el delegado tampoco
--     puede aprobar ni rechazar (55000): decidir a ciegas anularía el
--     propósito de la regla.
--   - Respuestas sin provider_id, provider_organization_id, team_member_id,
--     created_by_user_id, approved_by_user_id, rejected_by_user_id,
--     client_observation, desglose económico (subtotal, IGV, gastos
--     generales, utilidades, secciones, condiciones) ni id de OT.
--   - aprobar/rechazar replican la lógica vigente de approve_quote (con la
--     capa request_type de 20260831090000) y reject_quote, más un bloqueo
--     de la solicitud para serializar decisiones concurrentes. Un id
--     inexistente, de otro cliente o de un borrador responde igual que una
--     falta de permiso (42501).
--   - Auditoría en audit_logs con organization_id = cliente, sin importes.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1) Capacidades delegadas. Internas (no ejecutables por clientes).
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_view_quotes_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['requests.view', 'quotes.view']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
  );
$$;

CREATE OR REPLACE FUNCTION public.can_approve_quotes_as_facility_manager(_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.has_facility_management_operational_access_all(
    _organization_id,
    ARRAY['requests.view', 'quotes.view', 'quotes.approve']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
  );
$$;

REVOKE ALL ON FUNCTION public.can_view_quotes_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_approve_quotes_as_facility_manager(uuid) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 2) Minimización. Internas.
-- -------------------------------------------------------------------------

-- ¿Los importes de esta solicitud son visibles? Misma regla que
-- QuoteListDialog.loadQuotes: cotizaciones recibidas >= min_quotes.
CREATE OR REPLACE FUNCTION public.facility_management_quote_prices_visible(_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE((
    SELECT (
      SELECT count(*) FROM public.quotes q
      WHERE q.request_id = r.id AND q.status IN ('submitted', 'approved', 'rejected')
    ) >= r.min_quotes
    FROM public.requests r
    WHERE r.id = _request_id
  ), false);
$$;

-- Cotización minimizada. amount solo con importes visibles; can_approve ya
-- viene combinado (capacidad + solicitud abierta + importes visibles).
CREATE OR REPLACE FUNCTION public.facility_management_quote_payload(_quote public.quotes, _prices_visible boolean, _can_decide boolean)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'id', _quote.id,
    'request_id', _quote.request_id,
    'status', _quote.status,
    'description', _quote.description,
    'created_at', _quote.created_at,
    'amount', CASE WHEN COALESCE(_prices_visible, false) THEN _quote.amount END,
    'approved_at', _quote.approved_at,
    'approval_reason', CASE WHEN _quote.status = 'approved' THEN _quote.approval_reason END,
    'rejected_at', _quote.rejected_at,
    'rejection_reason', _quote.rejection_reason,
    'can_approve', COALESCE(_can_decide, false) AND COALESCE(_prices_visible, false) AND _quote.status = 'submitted'
  );
$$;

REVOKE ALL ON FUNCTION public.facility_management_quote_prices_visible(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.facility_management_quote_payload(public.quotes, boolean, boolean) FROM PUBLIC, anon, authenticated;

-- Cotizaciones de una solicitud (resumen + lista). Compartida por las dos
-- lecturas para que el listado y el detalle apliquen la MISMA ocultación.
CREATE OR REPLACE FUNCTION public.facility_management_request_quotes_payload(_request public.requests, _can_approve boolean, _only_quote_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_visible boolean := public.facility_management_quote_prices_visible(_request.id);
  v_can_decide boolean := COALESCE(_can_approve, false) AND _request.status IN ('sent', 'quoted');
BEGIN
  RETURN jsonb_build_object(
    'request_id', _request.id,
    'min_quotes', _request.min_quotes,
    'quotes_received', (
      SELECT count(*) FROM public.quotes q
      WHERE q.request_id = _request.id AND q.status IN ('submitted', 'approved', 'rejected')
    ),
    'quotes_closed', COALESCE(_request.quotes_closed, false),
    'prices_visible', v_visible,
    'can_approve', v_can_decide AND v_visible,
    'quotes', COALESCE((
      SELECT jsonb_agg(public.facility_management_quote_payload(q, v_visible, v_can_decide) ORDER BY q.created_at DESC, q.id)
      FROM public.quotes q
      WHERE q.request_id = _request.id
        AND q.status IN ('submitted', 'approved', 'rejected')
        AND (_only_quote_id IS NULL OR q.id = _only_quote_id)
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.facility_management_request_quotes_payload(public.requests, boolean, uuid) FROM PUBLIC, anon, authenticated;

-- -------------------------------------------------------------------------
-- 3) Lecturas delegadas (quotes.view).
-- -------------------------------------------------------------------------

-- Cotizaciones de UNA solicitud externa y no borrador del cliente. NULL si
-- la solicitud no existe, es de otro cliente, es interna o es un borrador
-- (no distingue entre esos casos).
CREATE OR REPLACE FUNCTION public.get_facility_management_request_quotes(_client_organization_id uuid, _request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request public.requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_quotes_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view this client''s quotes' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_request FROM public.requests r
  WHERE r.id = _request_id
    AND r.organization_id = _client_organization_id
    AND r.request_type = 'external'
    AND r.status <> 'draft';
  IF v_request.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN public.facility_management_request_quotes_payload(
    v_request, public.can_approve_quotes_as_facility_manager(_client_organization_id)
  );
END;
$$;

-- Detalle de UNA cotización (deep link): el mismo contrato, filtrado a la
-- cotización pedida. NULL si no existe o no es visible para el delegado.
CREATE OR REPLACE FUNCTION public.get_facility_management_quote(_client_organization_id uuid, _quote_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request public.requests%ROWTYPE;
  v_payload jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_quotes_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view this client''s quotes' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_request
  FROM public.requests r
  JOIN public.quotes q ON q.request_id = r.id
  WHERE q.id = _quote_id
    AND q.status IN ('submitted', 'approved', 'rejected')
    AND r.organization_id = _client_organization_id
    AND r.request_type = 'external'
    AND r.status <> 'draft';
  IF v_request.id IS NULL THEN
    RETURN NULL;
  END IF;

  v_payload := public.facility_management_request_quotes_payload(
    v_request, public.can_approve_quotes_as_facility_manager(_client_organization_id), _quote_id
  );
  RETURN (v_payload - 'quotes') || jsonb_build_object('quote', v_payload->'quotes'->0);
END;
$$;

-- Conteo de cotizaciones en revisión por solicitud (la columna de la lista).
-- Solo solicitudes externas no borrador del cliente. Sin importes.
CREATE OR REPLACE FUNCTION public.get_facility_management_quote_counts(_client_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_quotes_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view this client''s quotes' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('request_id', r.id, 'submitted_quotes', s.submitted_quotes) ORDER BY r.created_at DESC, r.id)
    FROM public.requests r
    JOIN LATERAL (
      SELECT count(*) AS submitted_quotes FROM public.quotes q
      WHERE q.request_id = r.id AND q.status = 'submitted'
    ) s ON s.submitted_quotes > 0
    WHERE r.organization_id = _client_organization_id
      AND r.request_type = 'external'
      AND r.status <> 'draft'
  ), '[]'::jsonb);
END;
$$;

-- -------------------------------------------------------------------------
-- 4) Decisiones delegadas (quotes.approve).
-- -------------------------------------------------------------------------

-- Misma lógica que approve_quote (20260831090000), por el FM en nombre del
-- cliente. La solicitud se bloquea para serializar decisiones concurrentes.
CREATE OR REPLACE FUNCTION public.approve_facility_management_quote(_client_organization_id uuid, _quote_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_request public.requests%ROWTYPE;
  v_quote public.quotes%ROWTYPE;
  v_old_status text;
  v_rejected uuid[];
BEGIN
  IF v_actor IS NULL OR NOT public.can_approve_quotes_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to approve quotes for this client' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_request
  FROM public.requests r
  JOIN public.quotes q ON q.request_id = r.id
  WHERE q.id = _quote_id AND r.organization_id = _client_organization_id AND r.status <> 'draft'
  FOR UPDATE OF r;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized to approve this quote' USING ERRCODE = '42501';
  END IF;
  IF v_request.request_type <> 'external' THEN
    RAISE EXCEPTION 'Only quotes on external requests can be approved' USING ERRCODE = '55000';
  END IF;
  IF v_request.status NOT IN ('sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status does not allow quote approval' USING ERRCODE = '55000';
  END IF;

  SELECT q.* INTO v_quote FROM public.quotes q WHERE q.id = _quote_id FOR UPDATE;
  IF v_quote.status <> 'submitted' THEN
    RAISE EXCEPTION 'Only submitted quotes can be approved' USING ERRCODE = '55000';
  END IF;
  IF NOT public.facility_management_quote_prices_visible(v_request.id) THEN
    RAISE EXCEPTION 'Quote amounts are not visible yet for this request' USING ERRCODE = '55000';
  END IF;

  v_old_status := v_quote.status;
  UPDATE public.quotes
  SET status = 'approved',
      approved_at = now(),
      approved_by_user_id = v_actor,
      rejected_at = NULL,
      rejected_by_user_id = NULL,
      rejection_reason = NULL
  WHERE id = _quote_id
  RETURNING * INTO v_quote;

  -- Una sola cotización elegida por solicitud; las demás en revisión pasan
  -- a rechazadas sin tocar su contenido comercial.
  WITH rejected AS (
    UPDATE public.quotes
    SET status = 'rejected',
        rejected_at = now(),
        rejected_by_user_id = v_actor,
        rejection_reason = COALESCE(rejection_reason, 'Not selected')
    WHERE request_id = v_request.id
      AND id <> _quote_id
      AND status = 'submitted'
    RETURNING id
  )
  SELECT COALESCE(array_agg(id), '{}'::uuid[]) INTO v_rejected FROM rejected;

  INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data, new_data)
  VALUES (
    _client_organization_id, v_actor, 'quotes', _quote_id, 'facility_management.quote_approved',
    jsonb_build_object('status', v_old_status),
    jsonb_build_object('status', 'approved', 'request_id', v_request.id, 'auto_rejected_quote_ids', to_jsonb(v_rejected))
  );

  RETURN public.facility_management_quote_payload(v_quote, true, false);
END;
$$;

-- Misma lógica que reject_quote, por el FM en nombre del cliente.
CREATE OR REPLACE FUNCTION public.reject_facility_management_quote(_client_organization_id uuid, _quote_id uuid, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_request public.requests%ROWTYPE;
  v_quote public.quotes%ROWTYPE;
  v_old_status text;
  v_reason text := NULLIF(btrim(_reason), '');
BEGIN
  IF v_actor IS NULL OR NOT public.can_approve_quotes_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to reject quotes for this client' USING ERRCODE = '42501';
  END IF;
  IF v_reason IS NOT NULL AND char_length(v_reason) > 1000 THEN
    RAISE EXCEPTION 'La razón del rechazo no puede superar 1000 caracteres' USING ERRCODE = '22023';
  END IF;

  SELECT r.* INTO v_request
  FROM public.requests r
  JOIN public.quotes q ON q.request_id = r.id
  WHERE q.id = _quote_id AND r.organization_id = _client_organization_id AND r.status <> 'draft'
  FOR UPDATE OF r;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized to reject this quote' USING ERRCODE = '42501';
  END IF;
  IF v_request.request_type <> 'external' THEN
    RAISE EXCEPTION 'Only quotes on external requests can be rejected' USING ERRCODE = '55000';
  END IF;
  IF v_request.status NOT IN ('sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status does not allow quote rejection' USING ERRCODE = '55000';
  END IF;

  SELECT q.* INTO v_quote FROM public.quotes q WHERE q.id = _quote_id FOR UPDATE;
  IF v_quote.status <> 'submitted' THEN
    RAISE EXCEPTION 'Only submitted quotes can be rejected' USING ERRCODE = '55000';
  END IF;
  IF NOT public.facility_management_quote_prices_visible(v_request.id) THEN
    RAISE EXCEPTION 'Quote amounts are not visible yet for this request' USING ERRCODE = '55000';
  END IF;

  v_old_status := v_quote.status;
  UPDATE public.quotes
  SET status = 'rejected',
      rejected_at = now(),
      rejected_by_user_id = v_actor,
      rejection_reason = v_reason
  WHERE id = _quote_id
  RETURNING * INTO v_quote;

  INSERT INTO public.audit_logs (organization_id, actor_user_id, table_name, record_id, action, old_data, new_data)
  VALUES (
    _client_organization_id, v_actor, 'quotes', _quote_id, 'facility_management.quote_rejected',
    jsonb_build_object('status', v_old_status),
    jsonb_build_object('status', 'rejected', 'request_id', v_request.id, 'has_reason', v_reason IS NOT NULL)
  );

  RETURN public.facility_management_quote_payload(v_quote, true, false);
END;
$$;

-- -------------------------------------------------------------------------
-- 5) ACL de los puntos de entrada.
-- -------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_facility_management_request_quotes(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_quote(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_quote_counts(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_facility_management_quote(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_facility_management_quote(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_management_request_quotes(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_quote(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_quote_counts(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_facility_management_quote(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_facility_management_quote(uuid, uuid, text) TO authenticated;
