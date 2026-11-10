-- One Facility | 9C.6-B2.2 (D3) | Facility Manager delegated OT creation.
-- Two strictly scoped entrypoints. No table grants/RLS changes or legacy RPC changes.
-- Requires the B1 read DTO and the same-relation FM authorization helper.
DO $preflight$
BEGIN
  IF to_regprocedure('public.has_facility_management_operational_access_all(uuid,public.facility_management_permission[],public.organization_member_role[])') IS NULL
    OR to_regprocedure('public.get_facility_management_work_order(uuid,uuid)') IS NULL
    OR to_regprocedure('public.map_request_priority_to_work_order_priority(integer)') IS NULL
    OR to_regclass('public.audit_logs') IS NULL
    OR to_regclass('public.work_orders_quote_id_key') IS NULL
    OR to_regclass('public.uq_work_orders_internal_request') IS NULL
  THEN
    RAISE EXCEPTION '9C.6-B2.2 preflight failed: B1, audit, or OT unique indexes missing';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.create_facility_management_work_order_from_quote(
  _client_organization_id uuid,
  _quote_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO ''
SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_quote public.quotes%ROWTYPE;
  v_request public.requests%ROWTYPE;
  v_order public.work_orders%ROWTYPE;
  v_created boolean := false;
BEGIN
  IF auth.uid() IS NULL
    OR NOT public.has_facility_management_operational_access_all(
      _client_organization_id,
      ARRAY['requests.view','work_orders.view','work_orders.manage','quotes.view']::public.facility_management_permission[],
      ARRAY['owner','admin','manager']::public.organization_member_role[]
    )
  THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  -- Serializes same-quote calls; matches the row-lock order of the legacy
  -- create_work_order_from_quote function. Never call the legacy RPC.
  SELECT q.* INTO v_quote
  FROM public.quotes q
  WHERE q.id = _quote_id AND q.status = 'approved'
  FOR UPDATE OF q;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_request
  FROM public.requests r
  WHERE r.id = v_quote.request_id
    AND r.organization_id = _client_organization_id
    AND r.request_type = 'external'
    AND r.status NOT IN ('draft','anulado')
    AND v_quote.provider_organization_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.organizations provider
      WHERE provider.id = v_quote.provider_organization_id
        AND provider.organization_type = 'provider_company'
        AND provider.status = 'active'
    );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  -- Recheck after any lock wait. Access must not survive grant revocation.
  IF NOT public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['requests.view','work_orders.view','work_orders.manage','quotes.view']::public.facility_management_permission[],
    ARRAY['owner','admin','manager']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  SELECT wo.* INTO v_order
  FROM public.work_orders wo
  WHERE wo.quote_id = v_quote.id
    AND wo.request_id = v_request.id
    AND wo.client_organization_id = _client_organization_id
    AND wo.provider_organization_id = v_quote.provider_organization_id
    AND wo.work_order_type = 'external';

  IF NOT FOUND THEN
    -- Unique quote constraint also protects races with the direct client
    -- workflow. Ignore conflicts then load the winner, never return 23505.
    INSERT INTO public.work_orders (
      request_id, quote_id, client_organization_id, provider_organization_id,
      work_order_type, asset_id, priority, due_at,
      planner_member_id, assigned_member_id, status,
      title, description, total_amount, created_by_user_id
    )
    VALUES (
      v_request.id, v_quote.id, _client_organization_id, v_quote.provider_organization_id,
      'external', v_request.asset_id,
      public.map_request_priority_to_work_order_priority(v_request.priority),
      v_request.deadline, NULL, NULL, 'pending',
      v_request.title, v_quote.description, v_quote.total_amount, auth.uid()
    )
    ON CONFLICT (quote_id) DO NOTHING
    RETURNING * INTO v_order;

    IF FOUND THEN
      v_created := true;
    ELSE
      SELECT wo.* INTO v_order
      FROM public.work_orders wo
      WHERE wo.quote_id = v_quote.id
        AND wo.request_id = v_request.id
        AND wo.client_organization_id = _client_organization_id
        AND wo.provider_organization_id = v_quote.provider_organization_id
        AND wo.work_order_type = 'external';
    END IF;
  END IF;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  IF v_created THEN
    INSERT INTO public.audit_logs (
      organization_id, actor_user_id, table_name, record_id,
      action, old_data, new_data
    ) VALUES (
      _client_organization_id, auth.uid(), 'work_orders', v_order.id,
      'facility_manager_work_order_created_from_quote', NULL,
      pg_catalog.jsonb_build_object('work_order_id',v_order.id,'request_id',v_request.id,'source','approved_quote')
    );

    PERFORM public.notify_role_members(
      v_quote.provider_organization_id,
      ARRAY['owner','admin','manager']::public.organization_member_role[],
      auth.uid(), 'work_order_created', 'Nueva orden de trabajo',
      'Se creo la orden ' || v_order.work_order_number || ' a partir de una cotizacion aprobada.',
      'work_order', v_order.id, 'medium',
      pg_catalog.jsonb_build_object('work_order_number',v_order.work_order_number)
    );
  END IF;

  -- B1 independently rechecks access and masks prices, descriptions,
  -- provider identity, member IDs and operator-internal details.
  RETURN public.get_facility_management_work_order(_client_organization_id,v_order.id);
END
$function$;

CREATE OR REPLACE FUNCTION public.create_facility_management_internal_work_order(
  _client_organization_id uuid,
  _request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path TO ''
SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_request public.requests%ROWTYPE;
  v_order public.work_orders%ROWTYPE;
  v_created boolean := false;
BEGIN
  IF auth.uid() IS NULL
    OR NOT public.has_facility_management_operational_access_all(
      _client_organization_id,
      ARRAY['requests.view','work_orders.view','work_orders.manage']::public.facility_management_permission[],
      ARRAY['owner','admin','manager']::public.organization_member_role[]
    )
  THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  -- Serialize all delegated creations for the same request. The partial
  -- UNIQUE index additionally arbitrates races against the legacy RPC.
  SELECT r.* INTO v_request
  FROM public.requests r
  WHERE r.id = _request_id
    AND r.organization_id = _client_organization_id
    AND r.request_type = 'internal'
    AND r.status NOT IN ('draft','anulado')
  FOR UPDATE OF r;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY['requests.view','work_orders.view','work_orders.manage']::public.facility_management_permission[],
    ARRAY['owner','admin','manager']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  SELECT wo.* INTO v_order
  FROM public.work_orders wo
  WHERE wo.request_id = v_request.id
    AND wo.quote_id IS NULL
    AND wo.work_order_type = 'internal'
    AND wo.client_organization_id = _client_organization_id
    AND wo.provider_organization_id = _client_organization_id;

  IF NOT FOUND THEN
    INSERT INTO public.work_orders (
      request_id, quote_id, client_organization_id, provider_organization_id,
      work_order_type, asset_id, priority, due_at, scheduled_at,
      planner_member_id, assigned_member_id, status,
      title, description, created_by_user_id
    )
    VALUES (
      v_request.id, NULL, _client_organization_id, _client_organization_id,
      'internal', v_request.asset_id,
      public.map_request_priority_to_work_order_priority(v_request.priority),
      v_request.deadline, NULL, NULL, NULL, 'pending',
      v_request.title, v_request.description, auth.uid()
    )
    ON CONFLICT DO NOTHING
    RETURNING * INTO v_order;

    IF FOUND THEN
      v_created := true;
    ELSE
      SELECT wo.* INTO v_order
      FROM public.work_orders wo
      WHERE wo.request_id = v_request.id
        AND wo.quote_id IS NULL
        AND wo.work_order_type = 'internal'
        AND wo.client_organization_id = _client_organization_id
        AND wo.provider_organization_id = _client_organization_id;
    END IF;
  END IF;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized to create this work order' USING ERRCODE = '42501';
  END IF;

  IF v_created THEN
    INSERT INTO public.audit_logs (
      organization_id, actor_user_id, table_name, record_id,
      action, old_data, new_data
    ) VALUES (
      _client_organization_id, auth.uid(), 'work_orders', v_order.id,
      'facility_manager_internal_work_order_created', NULL,
      pg_catalog.jsonb_build_object('work_order_id',v_order.id,'request_id',v_request.id,'source','internal_request')
    );
    PERFORM public.notify_role_members(
      _client_organization_id,
      ARRAY['owner','admin','manager']::public.organization_member_role[],
      auth.uid(), 'work_order_created', 'Nueva orden de trabajo',
      'Se creo la orden ' || v_order.work_order_number || ' desde una solicitud interna.',
      'work_order', v_order.id, 'medium',
      pg_catalog.jsonb_build_object('work_order_number',v_order.work_order_number)
    );
  END IF;

  RETURN public.get_facility_management_work_order(_client_organization_id,v_order.id);
END
$function$;

REVOKE ALL ON FUNCTION public.create_facility_management_work_order_from_quote(uuid,uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.create_facility_management_internal_work_order(uuid,uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_facility_management_work_order_from_quote(uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_facility_management_internal_work_order(uuid,uuid)
  TO authenticated;
