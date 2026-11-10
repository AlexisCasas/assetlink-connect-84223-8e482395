-- One Facility | 9C.7-B1: delegated client-level KPI snapshot.
-- Contract: 9C.7-A2 D1-D7, approved 2026-11-10.
-- No new table, RLS policy, data writes, grant of reports.view, or changes to
-- the existing direct-organization dashboard. New RPC is read-only.
-- Migration filename was generated with Supabase CLI 2.79.0 migration new.

DO $preflight$
BEGIN
  IF to_regclass('public.organization_relationships') IS NULL
    OR to_regclass('public.facility_management_permissions') IS NULL
    OR to_regclass('public.facility_management_relationship_members') IS NULL
    OR to_regclass('public.work_orders') IS NULL
    OR to_regclass('public.requests') IS NULL
    OR to_regclass('public.assets') IS NULL
    OR to_regprocedure('public.get_facility_management_work_orders(uuid,text,integer,integer)') IS NULL
  THEN
    RAISE EXCEPTION '9C.7-B1 requires previously deployed 9C.6 delegated reads and FM authorization tables';
  END IF;
END $preflight$;

CREATE OR REPLACE FUNCTION public.get_facility_management_client_metrics(
  _client_organization_id uuid,
  _relationship_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
SET statement_timeout TO '5s'
AS $function$
DECLARE
  v_authorized boolean := false;
  v_can_requests boolean := false;
  v_can_work_orders boolean := false;
  v_can_assets boolean := false;
  v_as_of timestamptz := pg_catalog.statement_timestamp();
  v_work_orders jsonb := NULL;
  v_requests jsonb := NULL;
  v_assets jsonb := NULL;
BEGIN
  -- Same explicit FM relationship and client, with a live assigned manager.
  -- Reports grant MUST belong to this exact relationship, not any FM of
  -- the client. No platform_admin shortcut or client/proxy membership.
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_relationships rel
    JOIN public.organizations client
      ON client.id=rel.source_organization_id
      AND client.organization_type='client_company'
      AND client.status='active'
    JOIN public.organizations fm
      ON fm.id=rel.target_organization_id
      AND fm.organization_type='facility_manager'
      AND fm.status='active'
    JOIN public.organization_members member
      ON member.organization_id=fm.id
      AND member.user_id=auth.uid()
      AND member.is_active
      AND member.role IN ('owner','admin','manager')
    JOIN public.facility_management_relationship_members assigned
      ON assigned.relationship_id=rel.id
      AND assigned.organization_member_id=member.id
    JOIN public.facility_management_permissions grant_reports
      ON grant_reports.relationship_id=rel.id
      AND grant_reports.permission='reports.view'
    WHERE rel.id=_relationship_id
      AND rel.source_organization_id=_client_organization_id
      AND rel.relationship_type='facility_management'
      AND rel.status='active'
      AND auth.uid() IS NOT NULL
  ) INTO v_authorized;

  IF NOT v_authorized THEN
    -- Deliberately identical for absent, foreign, suspended, or unassigned
    -- relationships: an attacker cannot enumerate clients via error details.
    RAISE EXCEPTION 'Not authorized to view delegated client metrics'
      USING ERRCODE='42501';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.facility_management_permissions p
    WHERE p.relationship_id=_relationship_id
      AND p.permission='requests.view'
  ) INTO v_can_requests;
  SELECT (
    v_can_requests AND EXISTS(
      SELECT 1 FROM public.facility_management_permissions p
      WHERE p.relationship_id=_relationship_id
        AND p.permission='work_orders.view'
    )
  ) INTO v_can_work_orders;
  SELECT EXISTS(
    SELECT 1 FROM public.facility_management_permissions p
    WHERE p.relationship_id=_relationship_id
      AND p.permission='assets.view'
  ) INTO v_can_assets;

  IF v_can_work_orders THEN
    -- Exactly the same client and non-draft/non-annulled request eligibility
    -- as 9C.6-B1, NOT the provider-organization dashboard definition.
    SELECT pg_catalog.jsonb_build_object(
      'total',COUNT(*)::integer,
      'open',COUNT(*) FILTER (
        WHERE wo.status IN ('pending','assigned','in_progress'))::integer,
      'overdue_open',COUNT(*) FILTER (
        WHERE wo.status IN ('pending','assigned','in_progress')
          AND wo.due_at IS NOT NULL AND wo.due_at < v_as_of)::integer,
      'by_status',pg_catalog.jsonb_build_object(
        'pending',COUNT(*) FILTER (WHERE wo.status='pending')::integer,
        'assigned',COUNT(*) FILTER (WHERE wo.status='assigned')::integer,
        'in_progress',COUNT(*) FILTER (WHERE wo.status='in_progress')::integer,
        'completed',COUNT(*) FILTER (WHERE wo.status='completed')::integer,
        'closed',COUNT(*) FILTER (WHERE wo.status='closed')::integer
      ),
      'by_type',pg_catalog.jsonb_build_object(
        'internal',COUNT(*) FILTER (WHERE wo.work_order_type='internal')::integer,
        'external',COUNT(*) FILTER (WHERE wo.work_order_type='external')::integer
      )
    ) INTO v_work_orders
    FROM public.work_orders wo
    WHERE wo.client_organization_id=_client_organization_id
      AND EXISTS (
        SELECT 1 FROM public.requests r
        WHERE r.id=wo.request_id
          AND r.organization_id=_client_organization_id
          AND r.status NOT IN ('draft','anulado')
      );
  END IF;

  IF v_can_requests THEN
    SELECT pg_catalog.jsonb_build_object(
      'open',COUNT(*) FILTER (WHERE r.status IN ('sent','quoted'))::integer
    ) INTO v_requests
    FROM public.requests r
    WHERE r.organization_id=_client_organization_id;
  END IF;

  IF v_can_assets THEN
    SELECT pg_catalog.jsonb_build_object(
      'active',COUNT(*)::integer,
      'critical',COUNT(*) FILTER (WHERE a.criticality='critical')::integer
    ) INTO v_assets
    FROM public.assets a
    WHERE a.organization_id=_client_organization_id
      AND a.status<>'archived';
  END IF;

  -- Null means permission unavailable, not zero records. Never return
  -- financial fields, operator actions, provider IDs, notes, or row data.
  RETURN pg_catalog.jsonb_build_object(
    'as_of',v_as_of,
    'availability',pg_catalog.jsonb_build_object(
      'work_orders',v_can_work_orders,
      'requests',v_can_requests,
      'assets',v_can_assets
    ),
    'work_orders',v_work_orders,
    'requests',v_requests,
    'assets',v_assets
  );
END
$function$;

-- Explicit ACL: no implicit EXECUTE for PUBLIC/anon/service_role.
-- authenticated may CALL but must pass every relation/role/grant check above.
REVOKE ALL ON FUNCTION public.get_facility_management_client_metrics(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_facility_management_client_metrics(uuid,uuid)
  TO authenticated;
