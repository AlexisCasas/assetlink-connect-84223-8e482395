-- E1-FIX02: historical request visibility + received-quote counts for the FM.
-- Additive RPC scope: 'sent' and 'drafts' remain unchanged.
-- No business data updates, RLS changes, or broader permissions.
DO $preflight$
BEGIN
  IF to_regprocedure('public.get_facility_management_requests(uuid,text)') IS NULL
     OR to_regprocedure('public.get_facility_management_quote_counts(uuid)') IS NULL THEN
    RAISE EXCEPTION 'E1-FIX02 preflight: expected existing RPCs are missing';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.get_facility_management_requests(
  _client_organization_id uuid,
  _scope text DEFAULT 'sent'::text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_can_view boolean := public.can_view_requests_as_facility_manager(_client_organization_id);
  v_can_create boolean := public.can_create_requests_as_facility_manager(_client_organization_id);
  v_can_manage boolean := public.can_manage_requests_as_facility_manager(_client_organization_id);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;
  IF _scope IS NULL OR _scope NOT IN ('sent', 'history', 'drafts') THEN
    RAISE EXCEPTION 'Invalid scope' USING ERRCODE = '22023';
  END IF;
  IF (_scope IN ('sent','history') AND NOT v_can_view)
     OR (_scope = 'drafts' AND NOT v_can_create) THEN
    RAISE EXCEPTION 'Not authorized to view this client''s requests' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(
      public.facility_management_request_payload(r, v_can_create, v_can_manage)
      ORDER BY r.created_at DESC, r.id
    )
    FROM public.requests r
    WHERE r.organization_id = _client_organization_id
      AND (
        (_scope = 'sent' AND r.status = 'sent')
        OR (_scope = 'history' AND r.status IN ('sent', 'quoted', 'completed'))
        OR (_scope = 'drafts' AND r.status = 'draft' AND r.created_by_user_id = auth.uid())
      )
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_facility_management_quote_counts(
  _client_organization_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_quotes_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view this client''s quotes' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'request_id', r.id,
      'submitted_quotes', s.submitted_quotes,
      'received_quotes', s.received_quotes
    ) ORDER BY r.created_at DESC, r.id)
    FROM public.requests r
    JOIN LATERAL (
      SELECT count(*) FILTER (WHERE q.status = 'submitted') AS submitted_quotes,
             count(*) FILTER (WHERE q.status IN ('submitted', 'approved', 'rejected')) AS received_quotes
      FROM public.quotes q
      WHERE q.request_id = r.id
    ) s ON s.received_quotes > 0
    WHERE r.organization_id = _client_organization_id
      AND r.request_type = 'external'
      AND r.status <> 'draft'
  ), '[]'::jsonb);
END;
$function$;

-- Preserve the existing RPC's callable surface; helpers and underlying tables
-- remain protected and no Guest permission is introduced.
REVOKE ALL ON FUNCTION public.get_facility_management_requests(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_facility_management_quote_counts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_management_requests(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_quote_counts(uuid) TO authenticated;
