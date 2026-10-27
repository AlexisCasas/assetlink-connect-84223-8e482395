-- =========================================================================
-- Fase 1 · Punto 9C.5 (hardening) — serializar las decisiones sobre
-- cotizaciones de una misma solicitud.
--
-- Hallazgo: approve_quote y reject_quote (flujo directo del cliente) no
-- bloqueaban ninguna fila. Con dos decisiones simultáneas sobre la misma
-- solicitud, ambas leían la cotización como 'submitted' antes de que la otra
-- confirmara, y el UPDATE final (WHERE id = ...) no vuelve a comprobar el
-- estado. Resultado reproducido en Supabase local: dos cotizaciones aprobadas
-- en la misma solicitud, la misma cotización aprobada por dos usuarios, o una
-- cotización aprobada que otro rechazo deja como rechazada. Una decisión
-- delegada del Facility Manager (9C.5, que sí bloquea la solicitud) tampoco
-- quedaba serializada frente a una decisión directa.
--
-- Corrección mínima: ambas funciones toman FOR UPDATE sobre la fila de la
-- solicitud en su primera lectura, el mismo bloqueo que ya usan
-- approve_facility_management_quote y reject_facility_management_quote. Todas
-- las decisiones (directas, delegadas o de platform_admin) sobre una solicitud
-- pasan a ejecutarse una detrás de otra, y las comprobaciones de estado que
-- siguen al bloqueo (solicitud abierta, cotización 'submitted') ven el estado
-- confirmado por la decisión anterior; la perdedora recibe el mismo error de
-- estado de siempre.
--
-- Sin cambios: reglas comerciales, roles permitidos, estados admitidos,
-- mensajes de error, SECURITY DEFINER, search_path y grants. El cuerpo es
-- idéntico a 20260831090000_request_type_integrity.sql (approve_quote) y a
-- 20260721181719_quote_approval_tenant_flow.sql (reject_quote) salvo por la
-- cláusula FOR UPDATE OF request.
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

  -- FOR UPDATE OF request: serializa las decisiones de esta solicitud.
  SELECT quote.request_id, request.organization_id, request.status, request.request_type
  INTO quote_request_id, client_organization_id, request_status, request_request_type
  FROM public.quotes quote
  INNER JOIN public.requests request ON request.id = quote.request_id
  WHERE quote.id = target_quote_id
  FOR UPDATE OF request;

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

CREATE OR REPLACE FUNCTION public.reject_quote(
  target_quote_id uuid,
  reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  client_organization_id uuid;
  request_status public.request_status;
  is_authorized boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  -- FOR UPDATE OF request: serializa las decisiones de esta solicitud.
  SELECT request.organization_id, request.status
  INTO client_organization_id, request_status
  FROM public.quotes quote
  INNER JOIN public.requests request ON request.id = quote.request_id
  WHERE quote.id = target_quote_id
  FOR UPDATE OF request;

  IF client_organization_id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
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
    RAISE EXCEPTION 'Not authorized to reject this quote';
  END IF;

  IF request_status NOT IN ('sent', 'quoted') THEN
    RAISE EXCEPTION 'Request status does not allow quote rejection';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.quotes quote
    WHERE quote.id = target_quote_id AND quote.status = 'submitted'
  ) THEN
    RAISE EXCEPTION 'Only submitted quotes can be rejected';
  END IF;

  UPDATE public.quotes
  SET status = 'rejected',
      rejected_at = now(),
      rejected_by_user_id = auth.uid(),
      rejection_reason = NULLIF(btrim(reason), '')
  WHERE id = target_quote_id;
END;
$$;

-- CREATE OR REPLACE conserva ACL y owner; se reafirman por claridad.
REVOKE ALL ON FUNCTION public.approve_quote(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_quote(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_quote(uuid, text) TO authenticated;
