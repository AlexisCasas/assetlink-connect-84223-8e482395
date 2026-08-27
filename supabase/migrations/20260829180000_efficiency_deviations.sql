-- Efficiency/deviation MVP indicators, computed live from data that already
-- exists (work_orders, work_order_activities.estimated_hours,
-- work_order_activity_reports.actual_hours) — no mirror tables, two RPCs
-- only:
--   get_efficiency_activity_metrics: one row per activity (planned vs.
--     actual vs. deviation).
--   get_efficiency_summary: one summary row (OT counts + hours totals),
--     internally reusing get_efficiency_activity_metrics for its hours
--     portion instead of recomputing the same aggregation twice.
--
-- No get_efficiency_grouped_metrics RPC: grouping by work_order/technician/
-- asset is done client-side over the same activity-metrics rows already
-- fetched for the table view — a third parameterized-grouping RPC would
-- duplicate the exact same safe-division logic for no real benefit at this
-- row volume. See docs/EFFICIENCY_DEVIATIONS.md.
--
-- These are operational counts, not a performance ranking: no query here
-- ever compares one technician's numbers against another's, and the
-- frontend never sorts/labels technicians by deviation.
--
-- Every reference qualified with a short alias from the first line
-- (wo/woa/woar/woat/om/au/a) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the class
-- of bug this is deliberately avoiding.

-- =========================================================================
-- A) get_efficiency_activity_metrics
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_efficiency_activity_metrics(
  p_organization_id uuid,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  activity_id uuid,
  work_order_id uuid,
  work_order_number text,
  work_order_status text,
  asset_id uuid,
  asset_name text,
  technician_member_id uuid,
  technician_name text,
  activity_description text,
  activity_status text,
  planned_hours numeric,
  actual_hours numeric,
  deviation_hours numeric,
  deviation_percent numeric,
  reports_count integer,
  first_started_at timestamptz,
  last_finished_at timestamptz,
  period_date date
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
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to view efficiency metrics for this organization';
  END IF;

  RETURN QUERY
  WITH metrics AS (
    SELECT
      woa.id AS activity_id,
      wo.id AS work_order_id,
      wo.work_order_number AS work_order_number,
      wo.status AS work_order_status,
      wo.asset_id AS asset_id,
      a.name AS asset_name,
      tech.member_id AS technician_member_id,
      tech.name AS technician_name,
      woa.description AS activity_description,
      woa.status AS activity_status,
      woa.estimated_hours AS planned_hours,
      COALESCE(rep.actual_hours_sum, 0) AS actual_hours,
      COALESCE(rep.actual_hours_sum, 0) - COALESCE(woa.estimated_hours, 0) AS deviation_hours,
      CASE
        WHEN woa.estimated_hours IS NULL OR woa.estimated_hours = 0 THEN NULL
        ELSE ROUND(((COALESCE(rep.actual_hours_sum, 0) - woa.estimated_hours) / woa.estimated_hours) * 100, 2)
      END AS deviation_percent,
      COALESCE(rep.reports_count, 0)::integer AS reports_count,
      rep.first_started_at AS first_started_at,
      rep.last_finished_at AS last_finished_at,
      COALESCE(rep.last_finished_at::date, wo.due_at::date, wo.created_at::date) AS period_date
    FROM public.work_order_activities woa
    INNER JOIN public.work_orders wo ON wo.id = woa.work_order_id
    LEFT JOIN public.assets a ON a.id = wo.asset_id
    LEFT JOIN LATERAL (
      SELECT
        SUM(woar.actual_hours) AS actual_hours_sum,
        COUNT(*) AS reports_count,
        MIN(woar.started_at) AS first_started_at,
        MAX(woar.finished_at) AS last_finished_at
      FROM public.work_order_activity_reports woar
      WHERE woar.activity_id = woa.id
    ) rep ON true
    -- The activity's primary technician if one was set per-activity,
    -- otherwise the OT's own principal technician — same fallback rule
    -- already used by get_my_technician_work_orders for "whose work is
    -- this". A plain LEFT JOIN, so an activity with neither still returns
    -- its row with technician_member_id/technician_name both NULL.
    LEFT JOIN LATERAL (
      SELECT om.id AS member_id,
        COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS name
      FROM public.organization_members om
      INNER JOIN auth.users au ON au.id = om.user_id
      WHERE om.id = COALESCE(
        (SELECT woat.member_id FROM public.work_order_activity_technicians woat
          WHERE woat.activity_id = woa.id AND woat.is_primary = true LIMIT 1),
        wo.assigned_member_id
      )
    ) tech ON true
    WHERE wo.provider_organization_id = p_organization_id
  )
  SELECT
    metrics.activity_id,
    metrics.work_order_id,
    metrics.work_order_number,
    metrics.work_order_status,
    metrics.asset_id,
    metrics.asset_name,
    metrics.technician_member_id,
    metrics.technician_name,
    metrics.activity_description,
    metrics.activity_status,
    metrics.planned_hours,
    metrics.actual_hours,
    metrics.deviation_hours,
    metrics.deviation_percent,
    metrics.reports_count,
    metrics.first_started_at,
    metrics.last_finished_at,
    metrics.period_date
  FROM metrics
  WHERE (p_start_date IS NULL OR metrics.period_date >= p_start_date)
    AND (p_end_date IS NULL OR metrics.period_date <= p_end_date)
  ORDER BY metrics.period_date DESC NULLS LAST, metrics.work_order_number, metrics.activity_description;
END;
$$;

REVOKE ALL ON FUNCTION public.get_efficiency_activity_metrics(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_efficiency_activity_metrics(uuid, date, date) TO authenticated;

-- =========================================================================
-- B) get_efficiency_summary — reuses get_efficiency_activity_metrics for
-- the hours/activities portion (same auth.uid(), so its own authorization
-- check passes transparently for whoever already passed this one's) rather
-- than recomputing the same planned/actual/deviation aggregation a second
-- time. OT counts (completed/pending/overdue) are computed separately,
-- period-filtered by the same COALESCE(due_at, created_at) anchor used for
-- an activity's own period_date.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_efficiency_summary(
  p_organization_id uuid,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  completed_work_orders integer,
  pending_work_orders integer,
  overdue_work_orders integer,
  planned_hours_total numeric,
  actual_hours_total numeric,
  deviation_hours_total numeric,
  deviation_percent_total numeric,
  activities_count integer,
  reported_activities_count integer
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
    OR public.has_organization_role(p_organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[])
  ) THEN
    RAISE EXCEPTION 'Not authorized to view efficiency metrics for this organization';
  END IF;

  RETURN QUERY
  WITH activity_metrics AS (
    SELECT * FROM public.get_efficiency_activity_metrics(p_organization_id, p_start_date, p_end_date)
  ),
  activity_totals AS (
    SELECT
      COALESCE(SUM(activity_metrics.planned_hours), 0) AS planned_sum,
      COALESCE(SUM(activity_metrics.actual_hours), 0) AS actual_sum,
      COUNT(*) AS activities_count,
      COUNT(*) FILTER (WHERE activity_metrics.reports_count > 0) AS reported_count
    FROM activity_metrics
  ),
  wo_period AS (
    SELECT
      wo.id AS id,
      wo.status AS status,
      wo.due_at AS due_at,
      COALESCE(wo.due_at::date, wo.created_at::date) AS wo_period_date
    FROM public.work_orders wo
    WHERE wo.provider_organization_id = p_organization_id
  ),
  wo_totals AS (
    SELECT
      COUNT(*) FILTER (WHERE wo_period.status IN ('completed', 'closed')) AS completed_count,
      COUNT(*) FILTER (WHERE wo_period.status NOT IN ('completed', 'closed')) AS pending_count,
      COUNT(*) FILTER (
        WHERE wo_period.status NOT IN ('completed', 'closed')
          AND wo_period.due_at IS NOT NULL
          AND wo_period.due_at < now()
      ) AS overdue_count
    FROM wo_period
    WHERE (p_start_date IS NULL OR wo_period.wo_period_date >= p_start_date)
      AND (p_end_date IS NULL OR wo_period.wo_period_date <= p_end_date)
  )
  SELECT
    wo_totals.completed_count::integer,
    wo_totals.pending_count::integer,
    wo_totals.overdue_count::integer,
    activity_totals.planned_sum,
    activity_totals.actual_sum,
    activity_totals.actual_sum - activity_totals.planned_sum,
    CASE
      WHEN activity_totals.planned_sum = 0 THEN NULL
      ELSE ROUND(((activity_totals.actual_sum - activity_totals.planned_sum) / activity_totals.planned_sum) * 100, 2)
    END,
    activity_totals.activities_count::integer,
    activity_totals.reported_count::integer
  FROM activity_totals, wo_totals;
END;
$$;

REVOKE ALL ON FUNCTION public.get_efficiency_summary(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_efficiency_summary(uuid, date, date) TO authenticated;
