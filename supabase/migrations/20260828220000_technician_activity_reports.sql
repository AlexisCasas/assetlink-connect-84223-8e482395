-- Technician real-execution reporting per activity: planned (estimated_hours
-- on work_order_activities) vs actual (started_at/finished_at reported
-- here). Extends work_order_activities — does not replace it, and is not a
-- parallel OT module: every report hangs off an existing activity/work
-- order. No stock deduction, no kardex, no costing, no mandatory
-- stopwatch (manual Desde/Hasta is the only required input).
--
-- Every RPC fully qualifies every column reference with a short table
-- alias from the very first line (wo/woa/woat/wom/m/r/rm/ev/om/au) — see
-- 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the class
-- of bug (42702 ambiguous_column from RETURNS TABLE OUT variables) this is
-- deliberately avoiding.
--
-- Evidence scope decision: no new Supabase Storage bucket/upload flow in
-- this phase. work_order_activity_report_evidences is schema-ready for
-- real files (file_path/mime_type/size_bytes columns exist and are
-- exactly what a future upload integration would fill), but for now only
-- metadata (file_name, an optional pasted file_url, notes) is collected —
-- explicitly authorized by the task's own fallback ("si no está listo,
-- implementar evidencia como registro metadata/link manual") and listed
-- as a documented pendiente. See docs/TECHNICIAN_ACTIVITY_REPORTS.md.

-- =========================================================================
-- A1) work_order_activity_reports
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.work_order_activity_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id uuid NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
  activity_id uuid NOT NULL REFERENCES public.work_order_activities(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL,
  finished_at timestamptz NOT NULL,
  -- Not a GENERATED column: `finished_at - started_at` on two timestamptz
  -- values is only STABLE in Postgres' catalog (not IMMUTABLE), which
  -- GENERATED ALWAYS AS requires — table creation fails otherwise. Computed
  -- instead by trg_work_order_activity_reports_compute_hours below, which
  -- always overwrites whatever value was passed in, so it can never drift
  -- from started_at/finished_at.
  actual_hours numeric(8, 2) NOT NULL DEFAULT 0,
  observations text NULL,
  final_status text NOT NULL DEFAULT 'completed',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT work_order_activity_reports_time_check CHECK (finished_at >= started_at),
  CONSTRAINT work_order_activity_reports_hours_check CHECK (actual_hours >= 0),
  CONSTRAINT work_order_activity_reports_observations_check CHECK (observations IS NULL OR TRIM(observations) <> ''),
  CONSTRAINT work_order_activity_reports_status_check CHECK (final_status IN ('pending', 'in_progress', 'completed', 'blocked'))
);

CREATE INDEX IF NOT EXISTS idx_work_order_activity_reports_work_order_id ON public.work_order_activity_reports (work_order_id);
CREATE INDEX IF NOT EXISTS idx_work_order_activity_reports_activity_id ON public.work_order_activity_reports (activity_id);
CREATE INDEX IF NOT EXISTS idx_work_order_activity_reports_member_id ON public.work_order_activity_reports (member_id);
CREATE INDEX IF NOT EXISTS idx_work_order_activity_reports_organization_id ON public.work_order_activity_reports (organization_id);
CREATE INDEX IF NOT EXISTS idx_work_order_activity_reports_started_at ON public.work_order_activity_reports (started_at);

CREATE OR REPLACE FUNCTION public.compute_work_order_activity_report_hours()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.actual_hours := ROUND(EXTRACT(EPOCH FROM (NEW.finished_at - NEW.started_at)) / 3600.0, 2);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_activity_reports_compute_hours ON public.work_order_activity_reports;
CREATE TRIGGER trg_work_order_activity_reports_compute_hours
BEFORE INSERT OR UPDATE ON public.work_order_activity_reports
FOR EACH ROW EXECUTE FUNCTION public.compute_work_order_activity_report_hours();

DROP TRIGGER IF EXISTS trg_work_order_activity_reports_updated_at ON public.work_order_activity_reports;
CREATE TRIGGER trg_work_order_activity_reports_updated_at
BEFORE UPDATE ON public.work_order_activity_reports
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: activity_id belongs to work_order_id; organization_id
-- matches both the work order's and the activity's own operating
-- organization; member_id is an active technician of that organization,
-- assigned to the activity itself or the OT's principal technician.
CREATE OR REPLACE FUNCTION public.check_work_order_activity_report_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_activity_work_order_id uuid;
  v_activity_org uuid;
  v_operating_org uuid;
  v_wo_assigned_member_id uuid;
  v_member_org uuid;
  v_member_active boolean;
  v_member_role public.organization_member_role;
  v_is_assigned boolean;
BEGIN
  SELECT woa.work_order_id, woa.organization_id INTO v_activity_work_order_id, v_activity_org
    FROM public.work_order_activities woa WHERE woa.id = NEW.activity_id;
  IF v_activity_work_order_id IS NULL THEN
    RAISE EXCEPTION 'activity_id does not reference an existing activity';
  END IF;
  IF v_activity_work_order_id <> NEW.work_order_id THEN
    RAISE EXCEPTION 'activity_id must belong to work_order_id';
  END IF;

  SELECT wo.provider_organization_id, wo.assigned_member_id INTO v_operating_org, v_wo_assigned_member_id
    FROM public.work_orders wo WHERE wo.id = NEW.work_order_id;
  IF v_operating_org IS NULL THEN
    RAISE EXCEPTION 'work_order_id does not reference an existing work order';
  END IF;
  IF NEW.organization_id <> v_operating_org OR v_activity_org <> v_operating_org THEN
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

  v_is_assigned := v_wo_assigned_member_id = NEW.member_id
    OR EXISTS (
      SELECT 1 FROM public.work_order_activity_technicians woat
      WHERE woat.activity_id = NEW.activity_id AND woat.member_id = NEW.member_id
    );
  IF NOT v_is_assigned THEN
    RAISE EXCEPTION 'member_id must be assigned to this activity or be the work order principal technician';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_activity_reports_check ON public.work_order_activity_reports;
CREATE TRIGGER trg_work_order_activity_reports_check
BEFORE INSERT OR UPDATE ON public.work_order_activity_reports
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_activity_report_consistency();

-- =========================================================================
-- A2) work_order_activity_report_materials — recorded for reporting only.
-- Never touches materials.stock (no deduction, no kardex, no blocking).
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.work_order_activity_report_materials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.work_order_activity_reports(id) ON DELETE CASCADE,
  work_order_material_id uuid NULL REFERENCES public.work_order_materials(id) ON DELETE SET NULL,
  material_id uuid NOT NULL REFERENCES public.materials(id) ON DELETE RESTRICT,
  quantity_used numeric(12, 2) NOT NULL DEFAULT 0,
  unit text NOT NULL,
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT work_order_activity_report_materials_qty_check CHECK (quantity_used >= 0)
);

CREATE INDEX IF NOT EXISTS idx_work_order_activity_report_materials_report_id ON public.work_order_activity_report_materials (report_id);
CREATE INDEX IF NOT EXISTS idx_work_order_activity_report_materials_material_id ON public.work_order_activity_report_materials (material_id);

CREATE OR REPLACE FUNCTION public.check_activity_report_material_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_report_org uuid;
  v_report_work_order_id uuid;
  v_material_org uuid;
  v_wom_work_order_id uuid;
BEGIN
  SELECT r.organization_id, r.work_order_id INTO v_report_org, v_report_work_order_id
    FROM public.work_order_activity_reports r WHERE r.id = NEW.report_id;
  IF v_report_org IS NULL THEN
    RAISE EXCEPTION 'report_id does not reference an existing report';
  END IF;

  SELECT m.organization_id INTO v_material_org FROM public.materials m WHERE m.id = NEW.material_id;
  IF v_material_org IS NULL THEN
    RAISE EXCEPTION 'material_id does not reference an existing material';
  END IF;
  IF v_material_org <> v_report_org THEN
    RAISE EXCEPTION 'material_id must belong to the report organization';
  END IF;

  IF NEW.work_order_material_id IS NOT NULL THEN
    SELECT wom.work_order_id INTO v_wom_work_order_id
      FROM public.work_order_materials wom WHERE wom.id = NEW.work_order_material_id;
    IF v_wom_work_order_id IS NULL OR v_wom_work_order_id <> v_report_work_order_id THEN
      RAISE EXCEPTION 'work_order_material_id must belong to the same work order as the report';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_activity_report_materials_check ON public.work_order_activity_report_materials;
CREATE TRIGGER trg_activity_report_materials_check
BEFORE INSERT OR UPDATE ON public.work_order_activity_report_materials
FOR EACH ROW EXECUTE FUNCTION public.check_activity_report_material_consistency();

-- =========================================================================
-- A3) work_order_activity_report_evidences — metadata only in this phase
-- (see the file header comment). No consistency trigger needed beyond the
-- FK to report_id: it carries no independent organization_id, so it can
-- never point cross-tenant on its own.
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.work_order_activity_report_evidences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id uuid NOT NULL REFERENCES public.work_order_activity_reports(id) ON DELETE CASCADE,
  file_name text NOT NULL,
  file_url text NULL,
  file_path text NULL,
  mime_type text NULL,
  size_bytes bigint NULL,
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT work_order_activity_report_evidences_name_check CHECK (TRIM(file_name) <> '')
);

CREATE INDEX IF NOT EXISTS idx_work_order_activity_report_evidences_report_id ON public.work_order_activity_report_evidences (report_id);

-- =========================================================================
-- RLS. Same restrictive-visibility family as work_order_activities/
-- work_order_materials/work_order_work_logs (operating organization only),
-- but with one extra distinction requested explicitly: within that
-- organization, a technician sees only their own reports; owner/admin/
-- manager/platform_admin see all of them. No INSERT/UPDATE/DELETE policy
-- on any of the three tables — submit_activity_report (SECURITY DEFINER)
-- is the only write path.
-- =========================================================================
ALTER TABLE public.work_order_activity_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_order_activity_report_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_order_activity_report_evidences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "planners see all reports, technicians see their own" ON public.work_order_activity_reports
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]))
    OR EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.id = work_order_activity_reports.member_id AND om.user_id = auth.uid()
    )
  );

CREATE POLICY "planners see all report materials, technicians see their own" ON public.work_order_activity_report_materials
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.work_order_activity_reports r
      WHERE r.id = work_order_activity_report_materials.report_id
        AND (
          (SELECT public.is_platform_admin())
          OR (SELECT public.has_organization_role(r.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]))
          OR EXISTS (SELECT 1 FROM public.organization_members om WHERE om.id = r.member_id AND om.user_id = auth.uid())
        )
    )
  );

CREATE POLICY "planners see all report evidences, technicians see their own" ON public.work_order_activity_report_evidences
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.work_order_activity_reports r
      WHERE r.id = work_order_activity_report_evidences.report_id
        AND (
          (SELECT public.is_platform_admin())
          OR (SELECT public.has_organization_role(r.organization_id, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]))
          OR EXISTS (SELECT 1 FROM public.organization_members om WHERE om.id = r.member_id AND om.user_id = auth.uid())
        )
    )
  );

GRANT SELECT ON TABLE public.work_order_activity_reports TO authenticated;
GRANT SELECT ON TABLE public.work_order_activity_report_materials TO authenticated;
GRANT SELECT ON TABLE public.work_order_activity_report_evidences TO authenticated;

-- =========================================================================
-- B1) get_activity_report_form_data: everything the report form needs in
-- one call — the activity, its work order, its assigned technicians, the
-- OT's available materials (to pick "material utilizado" from), and the
-- caller's own previous reports for this activity (multiple reports per
-- activity are allowed — see submit_activity_report below).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_activity_report_form_data(p_activity_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_work_order_id uuid;
  v_operating_org uuid;
  v_caller_member_id uuid;
  v_is_assigned boolean;
  v_is_planner boolean;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT woa.work_order_id INTO v_work_order_id FROM public.work_order_activities woa WHERE woa.id = p_activity_id;
  IF v_work_order_id IS NULL THEN
    RAISE EXCEPTION 'Activity not found';
  END IF;

  SELECT wo.provider_organization_id INTO v_operating_org FROM public.work_orders wo WHERE wo.id = v_work_order_id;

  SELECT om.id INTO v_caller_member_id
    FROM public.organization_members om
    WHERE om.organization_id = v_operating_org AND om.user_id = auth.uid() AND om.is_active;

  v_is_planner := public.is_platform_admin()
    OR public.has_organization_role(v_operating_org, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]);

  v_is_assigned := v_caller_member_id IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.work_orders wo WHERE wo.id = v_work_order_id AND wo.assigned_member_id = v_caller_member_id)
    OR EXISTS (SELECT 1 FROM public.work_order_activity_technicians woat WHERE woat.activity_id = p_activity_id AND woat.member_id = v_caller_member_id)
  );

  IF NOT (v_is_planner OR v_is_assigned) THEN
    RAISE EXCEPTION 'Not authorized to view this activity report form';
  END IF;

  SELECT jsonb_build_object(
    'activity', (
      SELECT jsonb_build_object(
        'id', woa.id, 'description', woa.description, 'estimated_hours', woa.estimated_hours,
        'status', woa.status, 'sequence', woa.sequence, 'due_at', woa.due_at
      )
      FROM public.work_order_activities woa WHERE woa.id = p_activity_id
    ),
    'work_order', (
      SELECT jsonb_build_object(
        'id', wo.id, 'work_order_number', wo.work_order_number, 'title', wo.title, 'status', wo.status
      )
      FROM public.work_orders wo WHERE wo.id = v_work_order_id
    ),
    'assigned_technicians', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', om.id,
        'name', COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)),
        'email', au.email
      ))
      FROM public.work_order_activity_technicians woat
      INNER JOIN public.organization_members om ON om.id = woat.member_id
      INNER JOIN auth.users au ON au.id = om.user_id
      WHERE woat.activity_id = p_activity_id
    ), '[]'::jsonb),
    'available_materials', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'work_order_material_id', wom.id,
        'material_id', wom.material_id,
        'code', m.code,
        'name', m.name,
        'unit', m.unit,
        'planned_quantity', wom.planned_quantity,
        'used_quantity', wom.used_quantity,
        'current_stock', m.stock
      ))
      FROM public.work_order_materials wom
      INNER JOIN public.materials m ON m.id = wom.material_id
      WHERE wom.work_order_id = v_work_order_id
    ), '[]'::jsonb),
    'my_previous_reports', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', r.id, 'started_at', r.started_at, 'finished_at', r.finished_at, 'actual_hours', r.actual_hours,
        'observations', r.observations, 'final_status', r.final_status, 'created_at', r.created_at
      ) ORDER BY r.started_at DESC)
      FROM public.work_order_activity_reports r
      WHERE r.activity_id = p_activity_id AND r.member_id = v_caller_member_id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_activity_report_form_data(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_activity_report_form_data(uuid) TO authenticated;

-- =========================================================================
-- B2) submit_activity_report: the only write path for all three tables.
-- Multiple reports per activity are explicitly allowed (a technician
-- working a second shift on the same activity submits a second report —
-- see docs/TECHNICIAN_ACTIVITY_REPORTS.md) — there is no uniqueness
-- constraint preventing it and this RPC always INSERTs, never upserts.
-- final_status drives work_order_activities.status:
--   completed  -> activity status = 'completed'
--   in_progress or blocked -> activity status = 'in_progress' ('blocked' is
--     not added to work_order_activities' status CHECK in this phase —
--     mapped to in_progress on purpose, see docs)
--   pending -> activity status left untouched (a log-only report)
-- Never touches materials.stock, never closes the work order itself.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.submit_activity_report(
  p_activity_id uuid,
  p_started_at timestamptz,
  p_finished_at timestamptz,
  p_observations text DEFAULT NULL,
  p_final_status text DEFAULT 'completed',
  p_materials jsonb DEFAULT '[]'::jsonb,
  p_evidences jsonb DEFAULT '[]'::jsonb
)
RETURNS public.work_order_activity_reports
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity public.work_order_activities%ROWTYPE;
  v_work_order public.work_orders%ROWTYPE;
  v_member_id uuid;
  v_is_assigned boolean;
  v_saved_report public.work_order_activity_reports%ROWTYPE;
  v_material_item jsonb;
  v_evidence_item jsonb;
  v_material_id uuid;
  v_wom_id uuid;
  v_material_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT woa.* INTO v_activity FROM public.work_order_activities woa WHERE woa.id = p_activity_id;
  IF v_activity.id IS NULL THEN
    RAISE EXCEPTION 'Activity not found';
  END IF;

  SELECT wo.* INTO v_work_order FROM public.work_orders wo WHERE wo.id = v_activity.work_order_id;
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
      SELECT 1 FROM public.work_order_activity_technicians woat
      WHERE woat.activity_id = p_activity_id AND woat.member_id = v_member_id
    );

  IF NOT v_is_assigned THEN
    RAISE EXCEPTION 'Not authorized: this activity is not assigned to the caller';
  END IF;

  IF p_started_at IS NULL OR p_finished_at IS NULL THEN
    RAISE EXCEPTION 'started_at and finished_at are required';
  END IF;
  IF p_finished_at < p_started_at THEN
    RAISE EXCEPTION 'finished_at must not be before started_at';
  END IF;
  IF p_final_status NOT IN ('pending', 'in_progress', 'completed', 'blocked') THEN
    RAISE EXCEPTION 'Invalid final_status value';
  END IF;

  INSERT INTO public.work_order_activity_reports (
    work_order_id, activity_id, organization_id, member_id, started_at, finished_at, observations, final_status
  ) VALUES (
    v_activity.work_order_id, p_activity_id, v_work_order.provider_organization_id, v_member_id,
    p_started_at, p_finished_at, NULLIF(TRIM(COALESCE(p_observations, '')), ''), p_final_status
  )
  RETURNING * INTO v_saved_report;

  IF p_materials IS NOT NULL THEN
    FOR v_material_item IN SELECT * FROM jsonb_array_elements(p_materials) LOOP
      v_material_id := (v_material_item->>'material_id')::uuid;
      v_wom_id := NULLIF(v_material_item->>'work_order_material_id', '')::uuid;

      SELECT m.organization_id INTO v_material_org FROM public.materials m WHERE m.id = v_material_id;
      IF v_material_org IS NULL OR v_material_org <> v_work_order.provider_organization_id THEN
        RAISE EXCEPTION 'material_id % must belong to the work order operating organization', v_material_id;
      END IF;

      INSERT INTO public.work_order_activity_report_materials (
        report_id, work_order_material_id, material_id, quantity_used, unit, notes
      ) VALUES (
        v_saved_report.id,
        v_wom_id,
        v_material_id,
        COALESCE((v_material_item->>'quantity_used')::numeric, 0),
        COALESCE(NULLIF(v_material_item->>'unit', ''), (SELECT m2.unit FROM public.materials m2 WHERE m2.id = v_material_id)),
        NULLIF(v_material_item->>'notes', '')
      );
    END LOOP;
  END IF;

  IF p_evidences IS NOT NULL THEN
    FOR v_evidence_item IN SELECT * FROM jsonb_array_elements(p_evidences) LOOP
      INSERT INTO public.work_order_activity_report_evidences (
        report_id, file_name, file_url, file_path, mime_type, size_bytes, notes
      ) VALUES (
        v_saved_report.id,
        v_evidence_item->>'file_name',
        NULLIF(v_evidence_item->>'file_url', ''),
        NULLIF(v_evidence_item->>'file_path', ''),
        NULLIF(v_evidence_item->>'mime_type', ''),
        NULLIF(v_evidence_item->>'size_bytes', '')::bigint,
        NULLIF(v_evidence_item->>'notes', '')
      );
    END LOOP;
  END IF;

  IF p_final_status = 'completed' THEN
    UPDATE public.work_order_activities woa SET status = 'completed' WHERE woa.id = p_activity_id;
  ELSIF p_final_status IN ('in_progress', 'blocked') THEN
    UPDATE public.work_order_activities woa SET status = 'in_progress' WHERE woa.id = p_activity_id;
  END IF;

  RETURN v_saved_report;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_activity_report(uuid, timestamptz, timestamptz, text, text, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_activity_report(uuid, timestamptz, timestamptz, text, text, jsonb, jsonb) TO authenticated;

-- =========================================================================
-- B3) get_activity_reports_for_work_order: every report of an OT, with
-- estimated vs actual hours already diffed server-side (planificación vs
-- ejecución real is the whole point of this phase). Same visibility split
-- as the RLS policies above, re-implemented here because SECURITY DEFINER
-- bypasses RLS.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_activity_reports_for_work_order(p_work_order_id uuid)
RETURNS TABLE (
  id uuid,
  activity_id uuid,
  activity_description text,
  estimated_hours numeric,
  member_id uuid,
  technician_name text,
  technician_email text,
  started_at timestamptz,
  finished_at timestamptz,
  actual_hours numeric,
  hours_difference numeric,
  observations text,
  final_status text,
  materials jsonb,
  evidences jsonb,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_operating_org uuid;
  v_caller_member_id uuid;
  v_is_planner boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wo.provider_organization_id INTO v_operating_org FROM public.work_orders wo WHERE wo.id = p_work_order_id;
  IF v_operating_org IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  v_is_planner := public.is_platform_admin()
    OR public.has_organization_role(v_operating_org, ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]);

  SELECT om.id INTO v_caller_member_id
    FROM public.organization_members om
    WHERE om.organization_id = v_operating_org AND om.user_id = auth.uid() AND om.is_active;

  IF NOT (v_is_planner OR v_caller_member_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Not authorized to view reports for this work order';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.activity_id,
    woa.description,
    woa.estimated_hours,
    r.member_id,
    COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)),
    au.email::text,
    r.started_at,
    r.finished_at,
    r.actual_hours,
    r.actual_hours - COALESCE(woa.estimated_hours, 0),
    r.observations,
    r.final_status,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', rm.id, 'material_code', m.code, 'material_name', m.name,
        'unit', rm.unit, 'quantity_used', rm.quantity_used, 'notes', rm.notes
      ))
      FROM public.work_order_activity_report_materials rm
      INNER JOIN public.materials m ON m.id = rm.material_id
      WHERE rm.report_id = r.id
    ), '[]'::jsonb),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ev.id, 'file_name', ev.file_name, 'file_url', ev.file_url,
        'file_path', ev.file_path, 'mime_type', ev.mime_type, 'size_bytes', ev.size_bytes, 'notes', ev.notes
      ))
      FROM public.work_order_activity_report_evidences ev
      WHERE ev.report_id = r.id
    ), '[]'::jsonb),
    r.created_at
  FROM public.work_order_activity_reports r
  INNER JOIN public.work_order_activities woa ON woa.id = r.activity_id
  INNER JOIN public.organization_members om ON om.id = r.member_id
  INNER JOIN auth.users au ON au.id = om.user_id
  WHERE r.work_order_id = p_work_order_id
    AND (v_is_planner OR r.member_id = v_caller_member_id)
  ORDER BY woa.sequence, r.started_at;
END;
$$;

REVOKE ALL ON FUNCTION public.get_activity_reports_for_work_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_activity_reports_for_work_order(uuid) TO authenticated;

-- =========================================================================
-- C) get_my_technician_work_orders extended with reported-hours totals.
-- 20260828170000_technician_work_view.sql (this function's original
-- definition) is already merged/deployed — left untouched. This is a
-- plain CREATE OR REPLACE with the identical signature and RETURNS TABLE
-- column list (no parameter rename, no column list change), so no DROP
-- FUNCTION is required here, unlike the 42702 fix migration: only the
-- jsonb payload built *inside* the `activities` column changes, adding
-- `actual_hours_total` (sum of the caller's own reports for that
-- activity) and `reports_count`, so "Mis órdenes" can show planned vs.
-- reported hours without a second round trip per activity.
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
          'due_at', woa.due_at,
          'actual_hours_total', (
            SELECT COALESCE(SUM(r.actual_hours), 0)
            FROM public.work_order_activity_reports r
            WHERE r.activity_id = woa.id AND r.member_id = mwo.my_member_id
          ),
          'reports_count', (
            SELECT COUNT(*)
            FROM public.work_order_activity_reports r
            WHERE r.activity_id = woa.id AND r.member_id = mwo.my_member_id
          )
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
