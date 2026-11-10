-- One Facility | 9C.6-B2.1 | Delegated coordination of INTERNAL OT.
-- No change to work_orders RLS, existing operator RPCs or other facilities.
-- Application must only call this RPC after explicit client delegation.
-- The RPC updates exactly priority/scheduled_at/due_at, with a guarded
-- snapshot precondition, row lock, and one minimal audit entry per change.

DO $preflight$
BEGIN
  IF to_regprocedure(
    'public.has_facility_management_operational_access_all(uuid,public.facility_management_permission[],public.organization_member_role[])'
  ) IS NULL OR to_regprocedure(
    'public.get_facility_management_work_order(uuid,uuid)'
  ) IS NULL OR to_regclass('public.audit_logs') IS NULL THEN
    RAISE EXCEPTION '9C.6-B2.1 requires existing FM grants, B1 read RPC and audit_logs';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.update_facility_management_internal_work_order_schedule(
  _client_organization_id uuid,
  _work_order_id uuid,
  _expected_priority text,
  _expected_scheduled_at timestamptz,
  _expected_due_at timestamptz,
  _priority text,
  _scheduled_at timestamptz,
  _due_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO ''
SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_old public.work_orders%ROWTYPE;
  v_updated public.work_orders%ROWTYPE;
BEGIN
  -- Explicit FM role, active client/FM/relationship, active assignment,
  -- and three grants on ONE relationship. Never infer provider membership.
  IF auth.uid() IS NULL
     OR NOT public.has_facility_management_operational_access_all(
       _client_organization_id,
       ARRAY[
         'requests.view',
         'work_orders.view',
         'work_orders.manage'
       ]::public.facility_management_permission[],
       ARRAY['owner','admin','manager']::public.organization_member_role[]
     )
  THEN
    RAISE EXCEPTION 'Not authorized to manage this work order'
      USING ERRCODE = '42501';
  END IF;

  IF _priority IS NULL
     OR _priority NOT IN ('low','medium','high','urgent')
     OR _expected_priority IS NULL
     OR _expected_priority NOT IN ('low','medium','high','urgent')
     OR (_scheduled_at IS NOT NULL AND _due_at IS NOT NULL
         AND _scheduled_at > _due_at)
  THEN
    RAISE EXCEPTION 'Invalid work order planning values'
      USING ERRCODE = '22023';
  END IF;

  -- Only a customer's INTERNAL and nonterminal OT with a valid source
  -- request may be edited. The lock serializes delegated coordination.
  SELECT wo.* INTO v_old
  FROM public.work_orders wo
  WHERE wo.id = _work_order_id
    AND wo.client_organization_id = _client_organization_id
    AND wo.provider_organization_id = _client_organization_id
    AND wo.work_order_type = 'internal'
    AND wo.quote_id IS NULL
    AND wo.status IN ('pending','assigned','in_progress')
    AND EXISTS (
      SELECT 1
      FROM public.requests r
      WHERE r.id = wo.request_id
        AND r.organization_id = _client_organization_id
        AND r.status NOT IN ('draft','anulado')
    )
  FOR UPDATE OF wo;

  IF NOT FOUND THEN
    -- Identical response for missing, external, terminal and foreign OTs.
    RAISE EXCEPTION 'Not authorized to manage this work order'
      USING ERRCODE = '42501';
  END IF;

  -- Fail closed if the relationship was revoked while waiting for the OT.
  IF NOT public.has_facility_management_operational_access_all(
    _client_organization_id,
    ARRAY[
      'requests.view',
      'work_orders.view',
      'work_orders.manage'
    ]::public.facility_management_permission[],
    ARRAY['owner','admin','manager']::public.organization_member_role[]
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage this work order'
      USING ERRCODE = '42501';
  END IF;

  -- Typed compare-and-swap across ALL editable fields. This also detects
  -- stale values when updated_at has coarse transaction timestamps.
  IF v_old.priority IS DISTINCT FROM _expected_priority
     OR v_old.scheduled_at IS DISTINCT FROM _expected_scheduled_at
     OR v_old.due_at IS DISTINCT FROM _expected_due_at
  THEN
    RAISE EXCEPTION 'Work order planning changed; reload before saving'
      USING ERRCODE = '40001';
  END IF;

  -- Idempotent no-op: no UPDATE, no trigger effects, no audit entry.
  IF v_old.priority IS NOT DISTINCT FROM _priority
     AND v_old.scheduled_at IS NOT DISTINCT FROM _scheduled_at
     AND v_old.due_at IS NOT DISTINCT FROM _due_at
  THEN
    RETURN public.get_facility_management_work_order(
      _client_organization_id,_work_order_id
    );
  END IF;

  UPDATE public.work_orders wo
  SET priority = _priority,
      scheduled_at = _scheduled_at,
      due_at = _due_at
  WHERE wo.id = v_old.id
    AND wo.client_organization_id = _client_organization_id
    AND wo.status IN ('pending','assigned','in_progress')
  RETURNING wo.* INTO v_updated;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Work order planning changed; reload before saving'
      USING ERRCODE = '40001';
  END IF;

  -- One audit event contains only the three authorized fields, not
  -- provider identifiers, member data or free-text observations.
  INSERT INTO public.audit_logs (
    organization_id,
    actor_user_id,
    table_name,
    record_id,
    action,
    old_data,
    new_data
  )
  VALUES (
    _client_organization_id,
    auth.uid(),
    'work_orders',
    v_old.id,
    'facility_manager_internal_work_order_planning',
    pg_catalog.jsonb_build_object(
      'priority', v_old.priority,
      'scheduled_at', v_old.scheduled_at,
      'due_at', v_old.due_at
    ),
    pg_catalog.jsonb_build_object(
      'priority', v_updated.priority,
      'scheduled_at', v_updated.scheduled_at,
      'due_at', v_updated.due_at
    )
  );

  -- B1 sanitizes returned fields, even when writing as SECURITY DEFINER.
  RETURN public.get_facility_management_work_order(
    _client_organization_id,_work_order_id
  );
END;
$function$;

-- Revoke default PUBLIC execute and any broad API access. Authenticated
-- receives ONLY this narrowly authorized entrypoint; no direct table grants.
REVOKE ALL ON FUNCTION public.update_facility_management_internal_work_order_schedule(
  uuid,uuid,text,timestamptz,timestamptz,text,timestamptz,timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_facility_management_internal_work_order_schedule(
  uuid,uuid,text,timestamptz,timestamptz,text,timestamptz,timestamptz
) TO authenticated;
