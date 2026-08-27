-- Real dashboard metrics — one consolidated read RPC replacing the
-- hardcoded numbers in StatsCards.tsx (fake "Total Activos: 147" etc.,
-- never backed by a query). No new tables, no mirror data: every count is
-- computed live from the same sources the rest of the app already reads
-- from (assets, requests, work_orders, inspection_plans/_alert_rules), and
-- hours reuse get_efficiency_summary instead of recomputing that
-- aggregation a second time.
--
-- Every reference qualified with a short alias from the first line
-- (a/r/wo/ip/ipar) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the class
-- of bug this is deliberately avoiding. Every intermediate count is first
-- computed into a v_-prefixed local variable and only referenced by that
-- name in the final RETURN QUERY SELECT — since RETURNS TABLE here
-- declares OUT parameters with the exact same names as the metrics
-- themselves (total_assets, critical_assets, ...), a bare unqualified
-- reference to one of those names anywhere in the query body would be
-- ambiguous (42702) — the same mistake caught and fixed in
-- get_asset_traffic_light during the previous phase.
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_organization_id uuid)
RETURNS TABLE (
  total_assets integer,
  critical_assets integer,
  open_requests integer,
  open_work_orders integer,
  overdue_work_orders integer,
  upcoming_inspections integer,
  overdue_inspections integer,
  planned_hours numeric,
  actual_hours numeric,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_assets integer;
  v_critical_assets integer;
  v_open_requests integer;
  v_open_work_orders integer;
  v_overdue_work_orders integer;
  v_upcoming_inspections integer;
  v_overdue_inspections integer;
  v_planned_hours numeric;
  v_actual_hours numeric;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  -- Deliberately narrower than most other read RPCs in this codebase
  -- (which allow any active member, including technician) — this is an
  -- operational summary across the whole organization (open/overdue
  -- counts, aggregate hours), not a single asset's or a single plan's own
  -- data. Same owner/admin/manager-or-platform_admin gate already used
  -- for get_efficiency_summary and get_criticality_matrix's write side.
  -- See docs/REAL_DASHBOARD_METRICS.md for the explicit criterion.
  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to view dashboard metrics for this organization';
  END IF;

  -- 1) total_assets / 2) critical_assets — archived assets excluded, same
  -- default-hidden semantics AssetTree already applies (useAssets.ts's
  -- filterArchived) and the same exclusion get_asset_traffic_light uses.
  SELECT COUNT(*) INTO v_total_assets
  FROM public.assets a
  WHERE a.organization_id = p_organization_id AND a.status <> 'archived';

  SELECT COUNT(*) INTO v_critical_assets
  FROM public.assets a
  WHERE a.organization_id = p_organization_id AND a.status <> 'archived' AND a.criticality = 'critical';

  -- 3) open_requests — 'draft' excluded on purpose: a draft is not yet a
  -- submitted request (it is a separate concept in this app already —
  -- DraftList.tsx queries status = 'draft' as its own distinct view;
  -- RequestList.tsx's own "real" list only ever queries status = 'sent').
  -- 'completed'/'anulado' are the two real closed states (this schema has
  -- no literal 'cancelled'/'closed'/'rejected' value — 'anulado' is it).
  SELECT COUNT(*) INTO v_open_requests
  FROM public.requests r
  WHERE r.organization_id = p_organization_id AND r.status IN ('sent', 'quoted');

  -- 4) open_work_orders / 5) overdue_work_orders — same status set and
  -- due_at comparison already used by generate_operational_due_notifications().
  SELECT COUNT(*) INTO v_open_work_orders
  FROM public.work_orders wo
  WHERE wo.provider_organization_id = p_organization_id AND wo.status NOT IN ('completed', 'closed');

  SELECT COUNT(*) INTO v_overdue_work_orders
  FROM public.work_orders wo
  WHERE wo.provider_organization_id = p_organization_id
    AND wo.status NOT IN ('completed', 'closed')
    AND wo.due_at IS NOT NULL AND wo.due_at < now();

  -- 6) upcoming_inspections — only plans with an ACTIVE before_due alert
  -- rule whose window is currently open (same condition
  -- get_asset_traffic_light / generate_inspection_due_notifications use).
  -- No configured rule → never counted as "upcoming" — no invented
  -- window. COUNT(DISTINCT ip.id): a single plan can simultaneously match
  -- more than one rule (e.g. both a 90-day and a 60-day rule open at
  -- once) — it must still count as exactly one upcoming inspection.
  SELECT COUNT(DISTINCT ip.id) INTO v_upcoming_inspections
  FROM public.inspection_plans ip
  INNER JOIN public.inspection_plan_alert_rules ipar
    ON ipar.plan_id = ip.id AND ipar.is_active AND ipar.alert_type = 'before_due'
  WHERE ip.organization_id = p_organization_id AND ip.is_active
    AND ip.next_due_at IS NOT NULL
    AND now() >= (ip.next_due_at - make_interval(days => ipar.days_before))
    AND now() < ip.next_due_at;

  -- 7) overdue_inspections — unconditional on alert rules existing, same
  -- as get_asset_traffic_light's inspection_overdue reason: being overdue
  -- is a fact, independent of whether a reminder was configured.
  SELECT COUNT(*) INTO v_overdue_inspections
  FROM public.inspection_plans ip
  WHERE ip.organization_id = p_organization_id AND ip.is_active
    AND ip.next_due_at IS NOT NULL AND ip.next_due_at < now();

  -- 8) planned_hours / 9) actual_hours — delegates to get_efficiency_summary
  -- (same auth.uid(), so its own authorization check passes transparently
  -- for whoever already passed this one's) instead of recomputing the
  -- planned/actual aggregation a second time. All-time totals (no date
  -- range) — date filters are an explicit "próximos pasos" item.
  SELECT es.planned_hours_total, es.actual_hours_total
    INTO v_planned_hours, v_actual_hours
  FROM public.get_efficiency_summary(p_organization_id, NULL, NULL) es;

  RETURN QUERY
  SELECT
    v_total_assets,
    v_critical_assets,
    v_open_requests,
    v_open_work_orders,
    v_overdue_work_orders,
    v_upcoming_inspections,
    v_overdue_inspections,
    COALESCE(v_planned_hours, 0),
    COALESCE(v_actual_hours, 0),
    now();
END;
$$;

REVOKE ALL ON FUNCTION public.get_dashboard_metrics(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_dashboard_metrics(uuid) TO authenticated;
