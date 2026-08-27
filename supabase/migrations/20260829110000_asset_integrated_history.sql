-- Consolidated asset history: "¿Qué le ha pasado a este activo?" — a single
-- read RPC that stitches together the asset's own manual/structural events
-- (asset_events) with everything already recorded operationally elsewhere
-- (requests, work_orders, work_order_activities, technician reports,
-- materials used, evidences). No new module, no mirror table: every row
-- comes straight from its real source table at read time.
--
-- No schema change to asset_events in this migration — it already carries
-- event_type/description/payload (used as this timeline's `metadata`), and
-- useAssets.ts already logs 'created'/'updated'/'archived'/'restored' on
-- every asset mutation. Turning it into a mirror of every operational
-- table would be exactly the "espejo gigante" the task says not to build.
--
-- Every reference is qualified with a short alias from the very first
-- line (a/ae/r/wo/woa/woar/woarm/woare/om/au/m) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the class
-- of bug (42702 ambiguous_column from RETURNS TABLE OUT variables) this is
-- deliberately avoiding; this function's own `id`/`status`/`description`
-- output columns make that risk very real here. Every branch also
-- explicitly `AS`-aliases every output column: for a UNION ALL, the outer
-- ORDER BY resolves against the *first* branch's column names at the SQL
-- level (before PL/pgSQL positionally assigns the result to the
-- RETURNS TABLE parameters), so leaving columns unaliased would make
-- `ORDER BY event_date` fail to resolve.

CREATE OR REPLACE FUNCTION public.get_asset_integrated_history(p_asset_id uuid)
RETURNS TABLE (
  id text,
  event_type text,
  event_label text,
  event_date timestamptz,
  actor_name text,
  actor_email text,
  source_table text,
  source_id uuid,
  title text,
  description text,
  status text,
  metadata jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_asset_org uuid;
  v_is_owner_or_platform_admin boolean;
  v_is_operating_provider boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT a.organization_id INTO v_asset_org FROM public.assets a WHERE a.id = p_asset_id;
  IF v_asset_org IS NULL THEN
    RAISE EXCEPTION 'Asset not found';
  END IF;

  v_is_owner_or_platform_admin := public.is_platform_admin() OR public.is_organization_member(v_asset_org);

  -- A provider organization that executed at least one work order on this
  -- asset can see that work order's own chain, even when it isn't the
  -- asset's owning organization — checked again per-row below, this is
  -- just the top-level "does the caller belong here at all" gate.
  v_is_operating_provider := EXISTS (
    SELECT 1 FROM public.work_orders wo
    WHERE wo.asset_id = p_asset_id AND public.is_organization_member(wo.provider_organization_id)
  );

  IF NOT (v_is_owner_or_platform_admin OR v_is_operating_provider) THEN
    RAISE EXCEPTION 'Not authorized to view this asset history';
  END IF;

  RETURN QUERY

  -- 1) Asset creation, sourced from assets itself — but only as a fallback
  -- when no asset_events 'created' row exists for it (the normal case
  -- already has one, via useAssets.ts's logEvent on create; this only
  -- covers a row whose event-log insert silently failed). Never emitted
  -- alongside the asset_events version — that would be exactly the
  -- duplication the task says to avoid.
  SELECT
    'asset-created-' || a.id::text AS id,
    'asset_created'::text AS event_type,
    'Creación del activo'::text AS event_label,
    a.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'assets'::text AS source_table,
    a.id AS source_id,
    'Activo creado: ' || a.name AS title,
    a.description AS description,
    a.status::text AS status,
    jsonb_build_object('node_type', a.node_type, 'code', a.code) AS metadata
  FROM public.assets a
  LEFT JOIN auth.users au ON au.id = a.created_by_user_id
  WHERE a.id = p_asset_id
    AND v_is_owner_or_platform_admin
    AND NOT EXISTS (
      SELECT 1 FROM public.asset_events ae WHERE ae.asset_id = a.id AND ae.event_type = 'created'
    )

  UNION ALL

  -- 2) Manual/structural events already logged on the asset itself
  -- (created/updated/archived/restored, or any future event_type — this
  -- table is deliberately generic, see check_asset_child_organization).
  SELECT
    'asset-event-' || ae.id::text AS id,
    'asset_event'::text AS event_type,
    (CASE ae.event_type
      WHEN 'created' THEN 'Activo creado'
      WHEN 'updated' THEN 'Activo actualizado'
      WHEN 'archived' THEN 'Activo archivado'
      WHEN 'restored' THEN 'Activo restaurado'
      ELSE INITCAP(REPLACE(ae.event_type, '_', ' '))
    END)::text AS event_label,
    ae.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'asset_events'::text AS source_table,
    ae.id AS source_id,
    (CASE ae.event_type
      WHEN 'created' THEN 'Activo creado'
      WHEN 'updated' THEN 'Activo actualizado'
      WHEN 'archived' THEN 'Activo archivado'
      WHEN 'restored' THEN 'Activo restaurado'
      ELSE INITCAP(REPLACE(ae.event_type, '_', ' '))
    END)::text AS title,
    ae.description AS description,
    NULL::text AS status,
    ae.payload AS metadata
  FROM public.asset_events ae
  LEFT JOIN auth.users au ON au.id = ae.created_by_user_id
  WHERE ae.asset_id = p_asset_id
    AND v_is_owner_or_platform_admin

  UNION ALL

  -- 3) Requests linked to this asset. Owner/platform_admin only — a
  -- provider working one resulting OT does not need the original request
  -- record itself; the OT already carries the title/description it needs.
  SELECT
    'request-' || r.id::text AS id,
    'request_created'::text AS event_type,
    'Solicitud creada'::text AS event_label,
    r.created_at AS event_date,
    r.created_by_name AS actor_name,
    r.created_by_email AS actor_email,
    'requests'::text AS source_table,
    r.id AS source_id,
    COALESCE(r.title, r.request_number) AS title,
    r.description AS description,
    r.status::text AS status,
    jsonb_build_object('request_number', r.request_number, 'request_type', r.request_type, 'priority', r.priority) AS metadata
  FROM public.requests r
  WHERE r.asset_id = p_asset_id
    AND v_is_owner_or_platform_admin

  UNION ALL

  -- 4) Work orders linked to this asset. Visible to the asset owner
  -- (always) and to whichever provider organization actually operates
  -- that specific work order (never to an unrelated provider on the same
  -- asset). Only one item per OT (its creation) — there is no stored
  -- history of status transitions to source a separate "work_order_status"
  -- item from; the current status is already this item's own `status`.
  SELECT
    'work-order-' || wo.id::text AS id,
    'work_order_created'::text AS event_type,
    'Orden de trabajo generada'::text AS event_label,
    wo.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_orders'::text AS source_table,
    wo.id AS source_id,
    wo.work_order_number || COALESCE(' — ' || wo.title, '') AS title,
    wo.description AS description,
    wo.status AS status,
    jsonb_build_object('work_order_number', wo.work_order_number, 'work_order_type', wo.work_order_type, 'priority', wo.priority) AS metadata
  FROM public.work_orders wo
  LEFT JOIN auth.users au ON au.id = wo.created_by_user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  -- 5) Activities of those work orders. Same reasoning as work orders for
  -- not sourcing a separate "activity_completed" item: work_order_activities
  -- has no completed_at, and its mutable `status`/`updated_at` do not
  -- reliably mark a single completion moment — the technician_report items
  -- below (sourced from real started_at/finished_at) already carry that.
  SELECT
    'activity-' || woa.id::text AS id,
    'activity_created'::text AS event_type,
    'Actividad registrada'::text AS event_label,
    woa.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activities'::text AS source_table,
    woa.id AS source_id,
    woa.description AS title,
    NULL::text AS description,
    woa.status AS status,
    jsonb_build_object('estimated_hours', woa.estimated_hours, 'sequence', woa.sequence, 'work_order_number', wo.work_order_number) AS metadata
  FROM public.work_order_activities woa
  INNER JOIN public.work_orders wo ON wo.id = woa.work_order_id
  LEFT JOIN auth.users au ON au.id = woa.created_by_user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  -- 6) Technician reports (the real intervention record: what happened,
  -- who did it, when, how long it actually took).
  SELECT
    'report-' || woar.id::text AS id,
    'technician_report'::text AS event_type,
    'Intervención de técnico'::text AS event_label,
    woar.started_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_reports'::text AS source_table,
    woar.id AS source_id,
    woa.description AS title,
    woar.observations AS description,
    woar.final_status AS status,
    jsonb_build_object(
      'work_order_number', wo.work_order_number,
      'activity_description', woa.description,
      'started_at', woar.started_at,
      'finished_at', woar.finished_at,
      'actual_hours', woar.actual_hours,
      'estimated_hours', woa.estimated_hours
    ) AS metadata
  FROM public.work_order_activity_reports woar
  INNER JOIN public.work_order_activities woa ON woa.id = woar.activity_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  -- 7) Materials used per report. Only what was used is exposed
  -- (code/name/quantity/unit) — never the provider's live stock or
  -- warehouse, which is internal inventory posture, not "what happened to
  -- this asset".
  SELECT
    'report-material-' || woarm.id::text AS id,
    'material_used'::text AS event_type,
    'Material utilizado'::text AS event_label,
    woarm.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_report_materials'::text AS source_table,
    woarm.id AS source_id,
    m.code || ' — ' || m.name AS title,
    woarm.notes AS description,
    NULL::text AS status,
    jsonb_build_object('quantity_used', woarm.quantity_used, 'unit', woarm.unit, 'material_code', m.code, 'material_name', m.name) AS metadata
  FROM public.work_order_activity_report_materials woarm
  INNER JOIN public.work_order_activity_reports woar ON woar.id = woarm.report_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.materials m ON m.id = woarm.material_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  UNION ALL

  -- 8) Evidences per report. Metadata only in this phase (no real file
  -- upload yet, see docs/TECHNICIAN_ACTIVITY_REPORTS.md) — file_path is
  -- intentionally not exposed here even once uploads exist, only the
  -- fields useful to a timeline viewer.
  SELECT
    'report-evidence-' || woare.id::text AS id,
    'evidence_added'::text AS event_type,
    'Evidencia registrada'::text AS event_label,
    woare.created_at AS event_date,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS actor_name,
    au.email::text AS actor_email,
    'work_order_activity_report_evidences'::text AS source_table,
    woare.id AS source_id,
    woare.file_name AS title,
    woare.notes AS description,
    NULL::text AS status,
    jsonb_build_object('file_name', woare.file_name, 'file_url', woare.file_url, 'mime_type', woare.mime_type) AS metadata
  FROM public.work_order_activity_report_evidences woare
  INNER JOIN public.work_order_activity_reports woar ON woar.id = woare.report_id
  INNER JOIN public.work_orders wo ON wo.id = woar.work_order_id
  INNER JOIN public.organization_members om ON om.id = woar.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wo.asset_id = p_asset_id
    AND (v_is_owner_or_platform_admin OR public.is_organization_member(wo.provider_organization_id))

  ORDER BY event_date DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_asset_integrated_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_asset_integrated_history(uuid) TO authenticated;
