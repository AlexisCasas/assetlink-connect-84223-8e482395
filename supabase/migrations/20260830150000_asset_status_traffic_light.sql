-- Operational traffic light for assets/áreas/sedes — computed live from
-- real sources (work_orders, inspection_plans/inspection_runs/
-- inspection_run_answers, assets.status, assets.criticality), never a
-- mirror table and never a manually-set color. Two read-only RPCs:
--   get_asset_traffic_light: one row per asset, direct + roll-up color.
--   get_branch_traffic_light: one row per sede, aggregating the assets
--     tagged with that branch_id (client_branches is a separate table
--     from the assets parent_asset_id tree — a "sede" is never itself an
--     assets row in this codebase).
--
-- Every reference qualified with a short alias from the first line
-- (a/wo/ip/ir/ira/cb/om/au) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the
-- class of bug this is deliberately avoiding.

-- =========================================================================
-- A) get_asset_traffic_light
--
-- direct_color: computed purely from this asset's own sources (never from
-- descendants). rollup_color: the worst color among the asset itself and
-- every descendant (via a recursive ancestor/descendant closure over
-- assets.parent_asset_id) — for a leaf with no children, rollup = direct
-- automatically (the closure's only pair is the asset with itself).
--
-- Sources implemented, and why:
--   RED
--     - work_order_overdue: work_orders.asset_id = a.id, due_at < now(),
--       status NOT IN ('completed','closed') — same "overdue" definition
--       already used by generate_operational_due_notifications().
--     - inspection_overdue: inspection_plans targeting this asset
--       (asset_id OR area_asset_id), is_active, next_due_at < now().
--       Unconditional on alert rules existing — being overdue is a fact
--       about compliance, not about whether a reminder was configured.
--     - inspection_failed: the LATEST *completed* run per plan targeting
--       this asset has result = 'failed'. "Latest per plan", not "any run
--       ever failed" — a later passing run supersedes an earlier failure
--       (see docs/ASSET_TRAFFIC_LIGHT.md). The failing item question(s)
--       are pulled from inspection_run_answers (is_failure = true) into
--       the reason's own description — a single reason per run, not one
--       per failing answer ("no duplicar demasiado" per the task spec).
--     - asset_status = 'inactive': the closest real value this schema has
--       to "fuera de servicio" — assets.status has no literal
--       out_of_service value (only active/maintenance/inactive/archived,
--       see 20260826234732_assets_tenant_aware_foundation.sql). Documented
--       explicitly in docs/ASSET_TRAFFIC_LIGHT.md rather than invented.
--   AMBER
--     - work_order_due_soon: due_at within the next 24h, not completed/
--       closed — same 24h window generate_operational_due_notifications()
--       already uses (not a new invented threshold).
--     - inspection_due_soon: only if the plan has an ACTIVE before_due
--       alert rule whose window is currently open (now() within
--       days_before of next_due_at). No configured rule → no amber from
--       this source — never an invented default window.
--     - asset_status = 'maintenance': informational "needs attention",
--       not a failure — never escalated to red.
--   Deliberately NOT implemented: "criticality=critical + pending work →
--   amber" (explicitly optional in the task spec, "si no complica").
--   criticality is exposed as a plain output column for context only —
--   it never contributes to direct_color/rollup_color by itself. See
--   docs/ASSET_TRAFFIC_LIGHT.md.
--
-- Archived assets (status = 'archived') are excluded entirely — same
-- default-hidden behavior AssetTree already applies, see useAssets.ts's
-- filterArchived.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_asset_traffic_light(p_organization_id uuid)
RETURNS TABLE (
  asset_id uuid,
  organization_id uuid,
  branch_id uuid,
  parent_asset_id uuid,
  asset_name text,
  asset_code text,
  node_type text,
  status text,
  criticality text,
  direct_color text,
  rollup_color text,
  direct_severity integer,
  rollup_severity integer,
  direct_reasons jsonb,
  rollup_reasons jsonb,
  causing_asset_ids uuid[],
  updated_at timestamptz
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
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the traffic light for this organization';
  END IF;

  RETURN QUERY
  WITH RECURSIVE closure AS (
    -- Depth 0: every asset is its own ancestor/descendant.
    SELECT a.id AS ancestor_id, a.id AS descendant_id
    FROM public.assets a
    WHERE a.organization_id = p_organization_id AND a.status <> 'archived'
    UNION ALL
    SELECT c.ancestor_id, ch.id AS descendant_id
    FROM closure c
    INNER JOIN public.assets ch
      ON ch.parent_asset_id = c.descendant_id
     AND ch.organization_id = p_organization_id
     AND ch.status <> 'archived'
  ),
  base_assets AS (
    SELECT a.id, a.organization_id, a.branch_id, a.parent_asset_id, a.name, a.code, a.node_type, a.status, a.criticality, a.updated_at
    FROM public.assets a
    WHERE a.organization_id = p_organization_id AND a.status <> 'archived'
  ),
  reason_asset_status AS (
    SELECT
      ba.id AS asset_id,
      (CASE ba.status
        WHEN 'inactive' THEN jsonb_build_object(
          'severity', 'red', 'source_type', 'asset_status', 'source_table', 'assets', 'source_id', ba.id,
          'title', 'Activo fuera de servicio', 'description', 'El activo "' || ba.name || '" está marcado como inactivo.',
          'event_date', ba.updated_at, 'due_at', NULL, 'asset_id', ba.id, 'asset_name', ba.name
        )
        WHEN 'maintenance' THEN jsonb_build_object(
          'severity', 'amber', 'source_type', 'asset_status', 'source_table', 'assets', 'source_id', ba.id,
          'title', 'Activo en mantenimiento', 'description', 'El activo "' || ba.name || '" está en mantenimiento.',
          'event_date', ba.updated_at, 'due_at', NULL, 'asset_id', ba.id, 'asset_name', ba.name
        )
        ELSE NULL
      END) AS reason
    FROM base_assets ba
  ),
  reason_wo_overdue AS (
    SELECT
      ba.id AS asset_id,
      jsonb_build_object(
        'severity', 'red', 'source_type', 'work_order_overdue', 'source_table', 'work_orders', 'source_id', wo.id,
        'title', 'OT vencida', 'description', 'La orden de trabajo "' || wo.work_order_number || '" está vencida.',
        'event_date', wo.due_at, 'due_at', wo.due_at, 'asset_id', ba.id, 'asset_name', ba.name
      ) AS reason
    FROM base_assets ba
    INNER JOIN public.work_orders wo ON wo.asset_id = ba.id
    WHERE wo.due_at IS NOT NULL AND wo.due_at < now() AND wo.status NOT IN ('completed', 'closed')
  ),
  reason_wo_due_soon AS (
    SELECT
      ba.id AS asset_id,
      jsonb_build_object(
        'severity', 'amber', 'source_type', 'work_order_due_soon', 'source_table', 'work_orders', 'source_id', wo.id,
        'title', 'OT próxima a vencer', 'description', 'La orden de trabajo "' || wo.work_order_number || '" vence en menos de 24 horas.',
        'event_date', wo.due_at, 'due_at', wo.due_at, 'asset_id', ba.id, 'asset_name', ba.name
      ) AS reason
    FROM base_assets ba
    INNER JOIN public.work_orders wo ON wo.asset_id = ba.id
    WHERE wo.due_at IS NOT NULL AND wo.due_at >= now() AND wo.due_at <= now() + interval '24 hours'
      AND wo.status NOT IN ('completed', 'closed')
  ),
  reason_inspection_overdue AS (
    SELECT
      ba.id AS asset_id,
      jsonb_build_object(
        'severity', 'red', 'source_type', 'inspection_overdue', 'source_table', 'inspection_plans', 'source_id', ip.id,
        'title', 'Inspección vencida', 'description', 'La inspección "' || ip.title || '" está vencida.',
        'event_date', ip.next_due_at, 'due_at', ip.next_due_at, 'asset_id', ba.id, 'asset_name', ba.name
      ) AS reason
    FROM base_assets ba
    INNER JOIN public.inspection_plans ip ON (ip.asset_id = ba.id OR ip.area_asset_id = ba.id) AND ip.is_active
    WHERE ip.next_due_at IS NOT NULL AND ip.next_due_at < now()
  ),
  reason_inspection_due_soon AS (
    SELECT
      ba.id AS asset_id,
      jsonb_build_object(
        'severity', 'amber', 'source_type', 'inspection_due_soon', 'source_table', 'inspection_plans', 'source_id', ip.id,
        'title', 'Inspección próxima a vencer',
        'description', 'La inspección "' || ip.title || '" vence en ' || COALESCE(ipar.label, ipar.days_before || ' días') || '.',
        'event_date', ip.next_due_at, 'due_at', ip.next_due_at, 'asset_id', ba.id, 'asset_name', ba.name
      ) AS reason
    FROM base_assets ba
    INNER JOIN public.inspection_plans ip ON (ip.asset_id = ba.id OR ip.area_asset_id = ba.id) AND ip.is_active
    INNER JOIN public.inspection_plan_alert_rules ipar
      ON ipar.plan_id = ip.id AND ipar.is_active AND ipar.alert_type = 'before_due'
    WHERE ip.next_due_at IS NOT NULL
      AND now() >= (ip.next_due_at - make_interval(days => ipar.days_before))
      AND now() < ip.next_due_at
  ),
  latest_run_per_plan AS (
    SELECT ir.*, ROW_NUMBER() OVER (PARTITION BY ir.plan_id ORDER BY ir.completed_at DESC) AS rn
    FROM public.inspection_runs ir
    WHERE ir.organization_id = p_organization_id AND ir.status = 'completed' AND ir.plan_id IS NOT NULL
  ),
  reason_inspection_failed AS (
    SELECT
      ba.id AS asset_id,
      jsonb_build_object(
        'severity', 'red', 'source_type', 'inspection_failed', 'source_table', 'inspection_runs', 'source_id', lr.id,
        'title', 'Checklist con no conformidad',
        'description', 'La última ejecución de "' || ct.name || '" no cumple' || COALESCE(' (' || failing.items || ')', '') || '.',
        'event_date', lr.completed_at, 'due_at', NULL, 'asset_id', ba.id, 'asset_name', ba.name
      ) AS reason
    FROM base_assets ba
    INNER JOIN latest_run_per_plan lr ON (lr.asset_id = ba.id OR lr.area_asset_id = ba.id) AND lr.rn = 1 AND lr.result = 'failed'
    INNER JOIN public.checklist_templates ct ON ct.id = lr.template_id
    LEFT JOIN LATERAL (
      SELECT string_agg(DISTINCT ira.item_question, ', ') AS items
      FROM public.inspection_run_answers ira
      WHERE ira.run_id = lr.id AND ira.is_failure
    ) failing ON true
  ),
  -- Every branch below qualifies asset_id/reason with its source CTE's own
  -- alias — RETURNS TABLE below declares an OUT parameter also named
  -- asset_id, so a bare unqualified reference here would be ambiguous
  -- between that OUT parameter and the CTE column (42702), exactly the
  -- class of bug 20260827170000_fix_work_order_activities_rpc_ambiguity.sql
  -- exists to avoid.
  all_reasons AS (
    SELECT ras.asset_id, ras.reason FROM reason_asset_status ras WHERE ras.reason IS NOT NULL
    UNION ALL SELECT rwo.asset_id, rwo.reason FROM reason_wo_overdue rwo
    UNION ALL SELECT rwds.asset_id, rwds.reason FROM reason_wo_due_soon rwds
    UNION ALL SELECT rio.asset_id, rio.reason FROM reason_inspection_overdue rio
    UNION ALL SELECT rids.asset_id, rids.reason FROM reason_inspection_due_soon rids
    UNION ALL SELECT rif.asset_id, rif.reason FROM reason_inspection_failed rif
  ),
  direct AS (
    SELECT
      ba.id AS asset_id, ba.organization_id, ba.branch_id, ba.parent_asset_id, ba.name, ba.code, ba.node_type, ba.status, ba.criticality, ba.updated_at,
      COALESCE(jsonb_agg(ar.reason) FILTER (WHERE ar.reason IS NOT NULL), '[]'::jsonb) AS direct_reasons,
      COALESCE(MAX(CASE ar.reason->>'severity' WHEN 'red' THEN 2 WHEN 'amber' THEN 1 ELSE 0 END), 0) AS direct_severity
    FROM base_assets ba
    LEFT JOIN all_reasons ar ON ar.asset_id = ba.id
    GROUP BY ba.id, ba.organization_id, ba.branch_id, ba.parent_asset_id, ba.name, ba.code, ba.node_type, ba.status, ba.criticality, ba.updated_at
  ),
  rollup AS (
    SELECT
      c.ancestor_id AS asset_id,
      MAX(d.direct_severity) AS rollup_severity,
      COALESCE(jsonb_agg(elem.value) FILTER (WHERE elem.value IS NOT NULL), '[]'::jsonb) AS rollup_reasons,
      COALESCE(array_agg(DISTINCT c.descendant_id) FILTER (WHERE d.direct_severity > 0 AND c.descendant_id <> c.ancestor_id), ARRAY[]::uuid[]) AS causing_asset_ids
    FROM closure c
    INNER JOIN direct d ON d.asset_id = c.descendant_id
    LEFT JOIN LATERAL jsonb_array_elements(d.direct_reasons) AS elem(value) ON d.direct_severity > 0
    GROUP BY c.ancestor_id
  )
  SELECT
    dr.asset_id,
    dr.organization_id,
    dr.branch_id,
    dr.parent_asset_id,
    dr.name AS asset_name,
    dr.code AS asset_code,
    dr.node_type,
    dr.status,
    dr.criticality,
    (CASE dr.direct_severity WHEN 2 THEN 'red' WHEN 1 THEN 'amber' ELSE 'green' END) AS direct_color,
    (CASE ru.rollup_severity WHEN 2 THEN 'red' WHEN 1 THEN 'amber' ELSE 'green' END) AS rollup_color,
    dr.direct_severity,
    ru.rollup_severity,
    dr.direct_reasons,
    ru.rollup_reasons,
    ru.causing_asset_ids,
    dr.updated_at
  FROM direct dr
  INNER JOIN rollup ru ON ru.asset_id = dr.asset_id
  ORDER BY dr.name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_traffic_light(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_asset_traffic_light(uuid) TO authenticated;

-- =========================================================================
-- B) get_branch_traffic_light — a sede (client_branches) is never an
-- assets row in this codebase, so it cannot join the recursive closure
-- above; instead it aggregates the already-computed rollup of every asset
-- tagged with that branch_id, plus any purely sede-level inspection plan
-- (branch_id set, asset_id and area_asset_id both null — a plan that
-- targets the whole sede, not a specific asset/area). Composes
-- get_asset_traffic_light (materialized once via the CTE below) instead
-- of duplicating any reason-computation logic — same "call the other RPC"
-- pattern already used by get_efficiency_summary calling
-- get_efficiency_activity_metrics.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_branch_traffic_light(p_organization_id uuid)
RETURNS TABLE (
  branch_id uuid,
  branch_name text,
  rollup_color text,
  rollup_severity integer,
  causing_asset_ids uuid[],
  rollup_reasons jsonb
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
    OR public.is_organization_member(p_organization_id)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view the traffic light for this organization';
  END IF;

  RETURN QUERY
  WITH asset_rollup AS MATERIALIZED (
    SELECT atl.branch_id, atl.asset_id, atl.rollup_severity, atl.rollup_reasons
    FROM public.get_asset_traffic_light(p_organization_id) atl
    WHERE atl.branch_id IS NOT NULL
  ),
  branch_level_reasons AS (
    SELECT ip.branch_id, 2 AS severity, jsonb_build_object(
      'severity', 'red', 'source_type', 'inspection_overdue', 'source_table', 'inspection_plans', 'source_id', ip.id,
      'title', 'Inspección vencida', 'description', 'La inspección "' || ip.title || '" (sede) está vencida.',
      'event_date', ip.next_due_at, 'due_at', ip.next_due_at, 'asset_id', NULL, 'asset_name', NULL
    ) AS reason
    FROM public.inspection_plans ip
    WHERE ip.organization_id = p_organization_id AND ip.is_active
      AND ip.asset_id IS NULL AND ip.area_asset_id IS NULL AND ip.branch_id IS NOT NULL
      AND ip.next_due_at IS NOT NULL AND ip.next_due_at < now()

    UNION ALL

    SELECT ip.branch_id, 1 AS severity, jsonb_build_object(
      'severity', 'amber', 'source_type', 'inspection_due_soon', 'source_table', 'inspection_plans', 'source_id', ip.id,
      'title', 'Inspección próxima a vencer',
      'description', 'La inspección "' || ip.title || '" (sede) vence en ' || COALESCE(ipar.label, ipar.days_before || ' días') || '.',
      'event_date', ip.next_due_at, 'due_at', ip.next_due_at, 'asset_id', NULL, 'asset_name', NULL
    ) AS reason
    FROM public.inspection_plans ip
    INNER JOIN public.inspection_plan_alert_rules ipar
      ON ipar.plan_id = ip.id AND ipar.is_active AND ipar.alert_type = 'before_due'
    WHERE ip.organization_id = p_organization_id AND ip.is_active
      AND ip.asset_id IS NULL AND ip.area_asset_id IS NULL AND ip.branch_id IS NOT NULL
      AND ip.next_due_at IS NOT NULL
      AND now() >= (ip.next_due_at - make_interval(days => ipar.days_before))
      AND now() < ip.next_due_at
  ),
  branch_asset_agg AS (
    SELECT
      ar.branch_id,
      MAX(ar.rollup_severity) AS max_severity,
      COALESCE(array_agg(DISTINCT ar.asset_id) FILTER (WHERE ar.rollup_severity > 0), ARRAY[]::uuid[]) AS causing_asset_ids,
      COALESCE(jsonb_agg(DISTINCT elem.value) FILTER (WHERE elem.value IS NOT NULL), '[]'::jsonb) AS reasons
    FROM asset_rollup ar
    LEFT JOIN LATERAL jsonb_array_elements(ar.rollup_reasons) AS elem(value) ON ar.rollup_severity > 0
    GROUP BY ar.branch_id
  ),
  branch_level_agg AS (
    SELECT blr.branch_id, MAX(blr.severity) AS max_severity, jsonb_agg(blr.reason) AS reasons
    FROM branch_level_reasons blr
    GROUP BY blr.branch_id
  )
  SELECT
    cb.id AS branch_id,
    cb.name AS branch_name,
    (CASE GREATEST(COALESCE(baa.max_severity, 0), COALESCE(bla.max_severity, 0))
      WHEN 2 THEN 'red' WHEN 1 THEN 'amber' ELSE 'green' END) AS rollup_color,
    GREATEST(COALESCE(baa.max_severity, 0), COALESCE(bla.max_severity, 0)) AS rollup_severity,
    COALESCE(baa.causing_asset_ids, ARRAY[]::uuid[]) AS causing_asset_ids,
    (COALESCE(baa.reasons, '[]'::jsonb) || COALESCE(bla.reasons, '[]'::jsonb)) AS rollup_reasons
  FROM public.client_branches cb
  LEFT JOIN branch_asset_agg baa ON baa.branch_id = cb.id
  LEFT JOIN branch_level_agg bla ON bla.branch_id = cb.id
  WHERE cb.organization_id = p_organization_id AND cb.is_active
  ORDER BY cb.name;
END;
$$;

REVOKE ALL ON FUNCTION public.get_branch_traffic_light(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_branch_traffic_light(uuid) TO authenticated;
