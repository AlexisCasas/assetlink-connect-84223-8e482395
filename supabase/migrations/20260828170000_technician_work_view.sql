-- Technician operative view: "Mis órdenes de trabajo". No parallel OT
-- module — this reads work_orders + work_order_activities +
-- work_order_activity_technicians + work_order_materials exactly as they
-- already exist, scoped to the caller's own technician membership(s).
-- Every RPC below fully qualifies every column reference with a short
-- table alias (wo/woa/woat/wom/m/a/om/au) from the very first line — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the
-- 42702 bug this is deliberately avoiding.

-- =========================================================================
-- A) work_order_work_logs — a technician's "Registrar trabajo" entries.
-- Deliberately a real (small) table instead of appending free text into
-- work_orders.observations: it keeps author/timestamp/optional status
-- transition structured, and observations remains the planner's own
-- header field (untouched by technicians). Not a kardex, not a full audit
-- trail of every field change — just the technician's own work notes.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.work_order_work_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id uuid NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
  note text NOT NULL,
  status_from text NULL,
  status_to text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT work_order_work_logs_note_check CHECK (TRIM(note) <> '')
);

CREATE INDEX IF NOT EXISTS idx_work_order_work_logs_work_order_id ON public.work_order_work_logs (work_order_id);
CREATE INDEX IF NOT EXISTS idx_work_order_work_logs_organization_id ON public.work_order_work_logs (organization_id);
CREATE INDEX IF NOT EXISTS idx_work_order_work_logs_member_id ON public.work_order_work_logs (member_id);

-- Consistency guard: organization_id must equal the OT's own operating
-- organization (same anchor as work_order_activities/work_order_materials),
-- and the author must be an active technician of that organization.
CREATE OR REPLACE FUNCTION public.check_work_order_work_log_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_operating_org uuid;
  v_member_org uuid;
  v_member_active boolean;
  v_member_role public.organization_member_role;
BEGIN
  SELECT wo.provider_organization_id INTO v_operating_org FROM public.work_orders wo WHERE wo.id = NEW.work_order_id;
  IF v_operating_org IS NULL THEN
    RAISE EXCEPTION 'work_order_id does not reference an existing work order';
  END IF;
  IF NEW.organization_id <> v_operating_org THEN
    RAISE EXCEPTION 'organization_id must match the work order operating organization';
  END IF;

  SELECT om.organization_id, om.is_active, om.role INTO v_member_org, v_member_active, v_member_role
    FROM public.organization_members om WHERE om.id = NEW.member_id;
  IF v_member_org IS NULL THEN
    RAISE EXCEPTION 'member_id does not reference an existing organization member';
  END IF;
  IF v_member_org <> v_operating_org THEN
    RAISE EXCEPTION 'member_id must belong to the work order operating organization';
  END IF;
  IF NOT v_member_active THEN
    RAISE EXCEPTION 'member_id must be an active member';
  END IF;
  IF v_member_role <> 'technician' THEN
    RAISE EXCEPTION 'member_id must have the technician role';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_work_logs_check ON public.work_order_work_logs;
CREATE TRIGGER trg_work_order_work_logs_check
BEFORE INSERT OR UPDATE ON public.work_order_work_logs
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_work_log_consistency();

-- Same restrictive visibility as work_order_activities/work_order_materials
-- (operating organization only, not the other side of an external OT). No
-- INSERT/UPDATE/DELETE policy — technician_update_work_order_progress
-- (SECURITY DEFINER) is the only write path.
ALTER TABLE public.work_order_work_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "operating organization members can view work logs" ON public.work_order_work_logs
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

GRANT SELECT ON TABLE public.work_order_work_logs TO authenticated;

-- =========================================================================
-- B) resolve_asset_path: internal helper only — deliberately NOT granted
-- to `authenticated`. It resolves an asset's hierarchical name path
-- bypassing RLS (SECURITY DEFINER), which is safe only because it is never
-- callable directly by a frontend user; it is only ever invoked from
-- inside another SECURITY DEFINER function already scoped to auth.uid()
-- (get_my_technician_work_orders below). A function's owner can always
-- call functions it owns regardless of grants, which is exactly the
-- mechanism this relies on — REVOKE ALL FROM PUBLIC with no GRANT to
-- authenticated at all, on purpose.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.resolve_asset_path(p_asset_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH RECURSIVE ancestry AS (
    SELECT a.id, a.name, a.parent_asset_id, 0 AS depth
    FROM public.assets a
    WHERE a.id = p_asset_id
    UNION ALL
    SELECT parent.id, parent.name, parent.parent_asset_id, ancestry.depth + 1
    FROM public.assets parent
    INNER JOIN ancestry ON ancestry.parent_asset_id = parent.id
  )
  SELECT string_agg(ancestry.name, ' › ' ORDER BY ancestry.depth DESC) FROM ancestry;
$$;

REVOKE ALL ON FUNCTION public.resolve_asset_path(uuid) FROM PUBLIC;

-- =========================================================================
-- C) get_my_technician_work_orders: no organization parameter on purpose
-- — it resolves purely from auth.uid(), returning the caller's own work
-- across every organization where they hold an active technician
-- membership (there is no input to spoof another user's or organization's
-- work). A work order is included when the caller is its principal
-- assigned_member_id OR is linked to at least one of its activities via
-- work_order_activity_technicians. "activities" in the payload mirrors
-- that same rule per row: if the caller is linked to specific activities,
-- only those are returned; if the caller is the OT's principal technician
-- and the OT has no per-activity technician assignments at all, every
-- activity of that OT is returned (they are its sole executor).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_my_technician_work_orders()
RETURNS TABLE (
  id uuid,
  work_order_number text,
  work_order_type text,
  title text,
  status text,
  priority text,
  scheduled_at timestamptz,
  due_at timestamptz,
  asset_id uuid,
  asset_name text,
  asset_path text,
  location text,
  organization_id uuid,
  request_id uuid,
  activities jsonb,
  materials jsonb
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

  RETURN QUERY
  WITH my_memberships AS (
    SELECT om.id AS member_id, om.organization_id AS org_id
    FROM public.organization_members om
    WHERE om.user_id = auth.uid() AND om.is_active AND om.role = 'technician'
  ),
  my_work_orders AS (
    SELECT wo.*, mm.member_id AS my_member_id
    FROM public.work_orders wo
    INNER JOIN my_memberships mm ON mm.org_id = wo.provider_organization_id
    WHERE wo.assigned_member_id = mm.member_id
       OR EXISTS (
         SELECT 1
         FROM public.work_order_activities woa
         INNER JOIN public.work_order_activity_technicians woat ON woat.activity_id = woa.id
         WHERE woa.work_order_id = wo.id AND woat.member_id = mm.member_id
       )
  )
  SELECT
    mwo.id,
    mwo.work_order_number,
    mwo.work_order_type,
    mwo.title,
    mwo.status,
    mwo.priority,
    mwo.scheduled_at,
    mwo.due_at,
    mwo.asset_id,
    a.name,
    public.resolve_asset_path(mwo.asset_id),
    COALESCE(a.location_text, cb.name),
    mwo.provider_organization_id,
    mwo.request_id,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', woa.id,
          'description', woa.description,
          'estimated_hours', woa.estimated_hours,
          'status', woa.status,
          'sequence', woa.sequence,
          'due_at', woa.due_at
        )
        ORDER BY woa.sequence
      )
      FROM public.work_order_activities woa
      WHERE woa.work_order_id = mwo.id
        AND (
          EXISTS (
            SELECT 1 FROM public.work_order_activity_technicians woat
            WHERE woat.activity_id = woa.id AND woat.member_id = mwo.my_member_id
          )
          OR (
            mwo.assigned_member_id = mwo.my_member_id
            AND NOT EXISTS (
              SELECT 1
              FROM public.work_order_activities woa2
              INNER JOIN public.work_order_activity_technicians woat2 ON woat2.activity_id = woa2.id
              WHERE woa2.work_order_id = mwo.id
            )
          )
        )
    ), '[]'::jsonb) AS activities,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', wom.id,
          'material_code', m.code,
          'material_name', m.name,
          'material_unit', m.unit,
          'planned_quantity', wom.planned_quantity,
          'used_quantity', wom.used_quantity,
          'current_stock', m.stock,
          'warning_status', CASE
            WHEN m.stock = 0 AND wom.planned_quantity > 0 THEN 'no_stock'
            WHEN m.stock < wom.planned_quantity THEN 'insufficient_stock'
            ELSE 'ok'
          END
        )
      )
      FROM public.work_order_materials wom
      INNER JOIN public.materials m ON m.id = wom.material_id
      WHERE wom.work_order_id = mwo.id
    ), '[]'::jsonb) AS materials
  FROM my_work_orders mwo
  LEFT JOIN public.assets a ON a.id = mwo.asset_id
  LEFT JOIN public.client_branches cb ON cb.id = a.branch_id
  ORDER BY mwo.due_at ASC NULLS LAST, mwo.scheduled_at ASC NULLS LAST, mwo.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_technician_work_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_technician_work_orders() TO authenticated;

-- =========================================================================
-- D) technician_update_work_order_progress: the only status transitions a
-- technician may perform (pending/assigned -> in_progress,
-- in_progress -> completed — never `closed`, that stays planner/admin-only
-- via update_work_order_operations), plus an optional work-log note. A
-- status change, a note, or both may be given — at least one is required.
-- Never touches planner, assigned_member_id, dates, priority, or materials.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.technician_update_work_order_progress(
  p_work_order_id uuid,
  p_status text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_work_order public.work_orders%ROWTYPE;
  v_member_id uuid;
  v_is_assigned boolean;
  v_current_status text;
  v_updated public.work_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wo.* INTO v_work_order FROM public.work_orders wo WHERE wo.id = p_work_order_id;
  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  SELECT om.id INTO v_member_id
    FROM public.organization_members om
    WHERE om.organization_id = v_work_order.provider_organization_id
      AND om.user_id = auth.uid()
      AND om.is_active
      AND om.role = 'technician';

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized: caller is not an active technician of the operating organization';
  END IF;

  v_is_assigned := v_work_order.assigned_member_id = v_member_id
    OR EXISTS (
      SELECT 1
      FROM public.work_order_activities woa
      INNER JOIN public.work_order_activity_technicians woat ON woat.activity_id = woa.id
      WHERE woa.work_order_id = p_work_order_id AND woat.member_id = v_member_id
    );

  IF NOT v_is_assigned THEN
    RAISE EXCEPTION 'Not authorized: this work order is not assigned to the caller';
  END IF;

  v_current_status := v_work_order.status;

  IF p_status IS NOT NULL THEN
    IF NOT (
      (v_current_status IN ('pending', 'assigned') AND p_status = 'in_progress')
      OR (v_current_status = 'in_progress' AND p_status = 'completed')
    ) THEN
      RAISE EXCEPTION 'Technicians can only move pending/assigned work orders to in_progress, or in_progress work orders to completed';
    END IF;

    UPDATE public.work_orders wo
    SET status = p_status
    WHERE wo.id = p_work_order_id
    RETURNING wo.* INTO v_updated;
  ELSE
    v_updated := v_work_order;
  END IF;

  IF p_notes IS NOT NULL AND TRIM(p_notes) <> '' THEN
    INSERT INTO public.work_order_work_logs (work_order_id, organization_id, member_id, note, status_from, status_to)
    VALUES (
      p_work_order_id,
      v_work_order.provider_organization_id,
      v_member_id,
      TRIM(p_notes),
      CASE WHEN p_status IS NOT NULL THEN v_current_status ELSE NULL END,
      CASE WHEN p_status IS NOT NULL THEN p_status ELSE NULL END
    );
  ELSIF p_status IS NULL THEN
    RAISE EXCEPTION 'Provide a status change, a note, or both';
  END IF;

  RETURN v_updated;
END;
$$;

REVOKE ALL ON FUNCTION public.technician_update_work_order_progress(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.technician_update_work_order_progress(uuid, text, text) TO authenticated;

-- =========================================================================
-- E) get_work_order_work_logs: read-only history, shown in
-- WorkOrderDetailDialog to whoever can already view operating details
-- (planner/admin/technician of the operating organization) — otherwise a
-- technician's "Registrar trabajo" notes would be visible to nobody but
-- themselves, defeating their purpose.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_work_order_work_logs(p_work_order_id uuid)
RETURNS TABLE (
  id uuid,
  note text,
  status_from text,
  status_to text,
  member_name text,
  member_email text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_operating_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wo.provider_organization_id INTO v_operating_org FROM public.work_orders wo WHERE wo.id = p_work_order_id;
  IF v_operating_org IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(v_operating_org)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view work logs for this work order';
  END IF;

  RETURN QUERY
  SELECT
    wowl.id,
    wowl.note,
    wowl.status_from,
    wowl.status_to,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)),
    au.email::text,
    wowl.created_at
  FROM public.work_order_work_logs wowl
  INNER JOIN public.organization_members om ON om.id = wowl.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE wowl.work_order_id = p_work_order_id
  ORDER BY wowl.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_work_order_work_logs(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_work_order_work_logs(uuid) TO authenticated;
