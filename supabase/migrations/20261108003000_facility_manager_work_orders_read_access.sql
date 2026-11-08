-- One Facility | 9C.6-B1 | Facility Manager delegated Work Orders (read-only).
-- Additive functions only. No tables, policies, grants to tables or business data modified.
-- Requires 9C.1 operational access helper and 9C.5 quote price visibility helper.
DO $preflight$
BEGIN
  IF to_regprocedure('public.has_facility_management_operational_access_all(uuid,public.facility_management_permission[],public.organization_member_role[])') IS NULL
    OR to_regprocedure('public.facility_management_quote_prices_visible(uuid)') IS NULL
    OR to_regclass('public.work_orders') IS NULL THEN
    RAISE EXCEPTION '9C.6-B1 dependencies are missing';
  END IF;
END;
$preflight$;

-- Same active relation + assigned FM member must have BOTH prerequisite grants.
-- A user who is also a direct client member gets no additional delegated privileges.
CREATE OR REPLACE FUNCTION public.can_view_work_orders_as_facility_manager(
  _client_organization_id uuid
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['requests.view', 'work_orders.view']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
  );
$function$;

-- Never return an amount merely because the OT stores total_amount.
-- Requires ALL three grants in the SAME relationship and exactly the
-- same quote visibility rule as 9C.5 (min_quotes OR quotes_closed).
-- Validate approved quote provenance to avoid trusting unrelated UUIDs.
CREATE OR REPLACE FUNCTION public.can_view_facility_management_work_order_price(
  _client_organization_id uuid,
  _work_order public.work_orders
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE(
    _work_order.client_organization_id = _client_organization_id
    AND _work_order.work_order_type = 'external'
    AND _work_order.quote_id IS NOT NULL
    AND public.has_facility_management_operational_access_all(
      _client_organization_id,
      ARRAY['requests.view', 'work_orders.view', 'quotes.view']::public.facility_management_permission[],
      ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
    )
    AND EXISTS (
      SELECT 1
      FROM public.quotes q
      WHERE q.id = _work_order.quote_id
        AND q.request_id = _work_order.request_id
        AND q.provider_organization_id = _work_order.provider_organization_id
        AND q.status = 'approved'
    )
    AND public.facility_management_quote_prices_visible(_work_order.request_id),
    false
  );
$function$;

-- Explicit allowlist. No SELECT * / to_jsonb(work_order), provider org IDs,
-- personal IDs, provider observations, material, stock, log, evidence or URLs.
-- External title/description are free text; mask BOTH whenever the financial
-- gate is closed to prevent a repeat of 9C.5-HF01.
CREATE OR REPLACE FUNCTION public.facility_management_work_order_read_payload(
  _work_order public.work_orders,
  _show_price boolean,
  _show_asset boolean
)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO ''
AS $function$
  SELECT pg_catalog.jsonb_build_object(
    'id', _work_order.id,
    'work_order_number', _work_order.work_order_number,
    'work_order_type', _work_order.work_order_type,
    'status', _work_order.status,
    'priority', _work_order.priority,
    'title', CASE
      WHEN _work_order.work_order_type = 'external' AND NOT COALESCE(_show_price, false)
      THEN 'Orden externa'
      ELSE _work_order.title
    END,
    'description', CASE
      WHEN _work_order.work_order_type = 'external' AND NOT COALESCE(_show_price, false)
      THEN NULL
      ELSE _work_order.description
    END,
    'request_number', (
      SELECT r.request_number
      FROM public.requests r
      WHERE r.id = _work_order.request_id
        AND r.organization_id = _work_order.client_organization_id
    ),
    'asset_label', CASE
      WHEN COALESCE(_show_asset, false) THEN (
        SELECT a.name
        FROM public.assets a
        WHERE a.id = _work_order.asset_id
          AND a.organization_id = _work_order.client_organization_id
      )
      ELSE NULL
    END,
    'operator_label', CASE
      WHEN _work_order.work_order_type = 'internal' THEN 'Interna'
      ELSE 'Proveedor externo'
    END,
    'has_planner', _work_order.planner_member_id IS NOT NULL,
    'has_technician', _work_order.assigned_member_id IS NOT NULL,
    'scheduled_at', _work_order.scheduled_at,
    'due_at', _work_order.due_at,
    'created_at', _work_order.created_at,
    'started_at', _work_order.started_at,
    'completed_at', _work_order.completed_at,
    'total_amount', CASE
      WHEN COALESCE(_show_price, false) THEN _work_order.total_amount
      ELSE NULL
    END,
    'prices_visible', COALESCE(_show_price, false),
    'can_manage', false
  );
$function$;

-- _status NULL = all five states; pagination is always bounded.
CREATE OR REPLACE FUNCTION public.get_facility_management_work_orders(
  _client_organization_id uuid,
  _status text DEFAULT NULL,
  _limit integer DEFAULT 50,
  _offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_items jsonb;
  v_total bigint;
  v_show_asset boolean;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.can_view_work_orders_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view work orders'
      USING ERRCODE = '42501';
  END IF;

  IF (_status IS NOT NULL AND _status NOT IN
      ('pending', 'assigned', 'in_progress', 'completed', 'closed'))
     OR _limit IS NULL OR _limit < 1 OR _limit > 100
     OR _offset IS NULL OR _offset < 0 OR _offset > 100000 THEN
    RAISE EXCEPTION 'Invalid work order filter'
      USING ERRCODE = '22023';
  END IF;

  v_show_asset := public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['requests.view', 'work_orders.view', 'assets.view']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
  );

  SELECT COUNT(*) INTO v_total
  FROM public.work_orders wo
  WHERE wo.client_organization_id = _client_organization_id
    AND (_status IS NULL OR wo.status = _status);

  SELECT COALESCE(pg_catalog.jsonb_agg(
    public.facility_management_work_order_read_payload(
      wo,
      public.can_view_facility_management_work_order_price(_client_organization_id, wo),
      v_show_asset
    )
    ORDER BY wo.created_at DESC, wo.id DESC
  ), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT *
    FROM public.work_orders wo
    WHERE wo.client_organization_id = _client_organization_id
      AND (_status IS NULL OR wo.status = _status)
    ORDER BY wo.created_at DESC, wo.id DESC
    LIMIT _limit OFFSET _offset
  ) wo;

  RETURN pg_catalog.jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'limit', _limit,
    'offset', _offset
  );
END;
$function$;

-- A nonexistent / cross-client ID must produce the SAME static 42501 error.
CREATE OR REPLACE FUNCTION public.get_facility_management_work_order(
  _client_organization_id uuid,
  _work_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_work_order public.work_orders%ROWTYPE;
  v_show_asset boolean;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.can_view_work_orders_as_facility_manager(_client_organization_id) THEN
    RAISE EXCEPTION 'Not authorized to view work order'
      USING ERRCODE = '42501';
  END IF;

  SELECT wo.* INTO v_work_order
  FROM public.work_orders wo
  WHERE wo.client_organization_id = _client_organization_id
    AND wo.id = _work_order_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized to view work order'
      USING ERRCODE = '42501';
  END IF;

  v_show_asset := public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['requests.view', 'work_orders.view', 'assets.view']::public.facility_management_permission[],
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
  );

  RETURN public.facility_management_work_order_read_payload(
    v_work_order,
    public.can_view_facility_management_work_order_price(_client_organization_id, v_work_order),
    v_show_asset
  );
END;
$function$;

-- Helper RPCs are private even to authenticated clients. Only the two
-- fully authorized entrypoints are reachable via authenticated PostgREST.
REVOKE ALL ON FUNCTION public.can_view_work_orders_as_facility_manager(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.can_view_facility_management_work_order_price(uuid,public.work_orders)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.facility_management_work_order_read_payload(public.work_orders,boolean,boolean)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_facility_management_work_orders(uuid,text,integer,integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_facility_management_work_order(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_work_orders(uuid,text,integer,integer)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_facility_management_work_order(uuid,uuid)
  TO authenticated;
