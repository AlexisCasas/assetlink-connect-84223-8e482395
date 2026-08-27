-- Operative activity level inside a work order: work_orders ->
-- work_order_activities -> technicians assigned per activity. Same rule as
-- the previous two phases — one operational entity, no separate module for
-- "internal activities" vs "external activities". An activity always hangs
-- off work_orders itself, so it applies identically regardless of whether
-- that OT came from an approved quote or a direct internal request.

-- =========================================================================
-- A) work_order_activities
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.work_order_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id uuid NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
  -- The activity's own operating organization, denormalized from
  -- work_orders.provider_organization_id at write time (and kept in sync by
  -- trg_work_order_activities_check_org below) — lets RLS/indexes filter
  -- directly on this table without joining work_orders on every query.
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  description text NOT NULL,
  estimated_hours numeric(8, 2) NULL,
  -- timestamptz, not a plain date: matches work_orders.scheduled_at/due_at
  -- from the previous phase and the project's established convention for
  -- every other operational date column (requests.deadline included) — no
  -- bare `date` column exists anywhere for an equivalent concept.
  due_at timestamptz NULL,
  status text NOT NULL DEFAULT 'pending',
  sequence integer NOT NULL DEFAULT 1,
  created_by_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT work_order_activities_description_check CHECK (TRIM(description) <> ''),
  CONSTRAINT work_order_activities_hours_check CHECK (estimated_hours IS NULL OR estimated_hours >= 0),
  CONSTRAINT work_order_activities_status_check CHECK (status IN ('pending', 'assigned', 'in_progress', 'completed')),
  CONSTRAINT work_order_activities_sequence_check CHECK (sequence > 0)
);

CREATE INDEX IF NOT EXISTS idx_work_order_activities_work_order_sequence
  ON public.work_order_activities (work_order_id, sequence);
CREATE INDEX IF NOT EXISTS idx_work_order_activities_organization_id
  ON public.work_order_activities (organization_id);
CREATE INDEX IF NOT EXISTS idx_work_order_activities_status
  ON public.work_order_activities (status);

DROP TRIGGER IF EXISTS trg_work_order_activities_updated_at ON public.work_order_activities;
CREATE TRIGGER trg_work_order_activities_updated_at
BEFORE UPDATE ON public.work_order_activities
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Consistency guard: organization_id must always equal the parent OT's
-- provider_organization_id (the "organización operadora" — for an internal
-- OT this already equals client_organization_id, same anchor used by
-- planner_member_id/assigned_member_id in the previous phase). SECURITY
-- INVOKER on purpose: only ever runs inside the SECURITY DEFINER RPCs below.
CREATE OR REPLACE FUNCTION public.check_work_order_activity_organization()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  operating_org uuid;
BEGIN
  SELECT provider_organization_id INTO operating_org
    FROM public.work_orders WHERE id = NEW.work_order_id;

  IF operating_org IS NULL THEN
    RAISE EXCEPTION 'work_order_id does not reference an existing work order';
  END IF;
  IF NEW.organization_id <> operating_org THEN
    RAISE EXCEPTION 'organization_id must match the work order operating organization';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_activities_check_org ON public.work_order_activities;
CREATE TRIGGER trg_work_order_activities_check_org
BEFORE INSERT OR UPDATE ON public.work_order_activities
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_activity_organization();

-- =========================================================================
-- A2) work_order_activity_technicians (bridge, multiple technicians per
-- activity from the model even though the initial UI exposes a simple
-- checkbox list — see docs/WORK_ORDER_ACTIVITIES.md).
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.work_order_activity_technicians (
  activity_id uuid NOT NULL REFERENCES public.work_order_activities(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_work_order_activity_technicians_member_id
  ON public.work_order_activity_technicians (member_id);

-- Consistency guard, same pattern as assigned_member_id/planner_member_id:
-- the technician must belong to the activity's own organization_id, be
-- active, and hold the technician role. No cross-tenant technician can ever
-- be linked to an activity, at the database level, regardless of caller.
CREATE OR REPLACE FUNCTION public.check_work_order_activity_technician()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  activity_org uuid;
  member_org uuid;
  member_active boolean;
  member_role public.organization_member_role;
BEGIN
  SELECT organization_id INTO activity_org
    FROM public.work_order_activities WHERE id = NEW.activity_id;
  IF activity_org IS NULL THEN
    RAISE EXCEPTION 'activity_id does not reference an existing activity';
  END IF;

  SELECT organization_id, is_active, role INTO member_org, member_active, member_role
    FROM public.organization_members WHERE id = NEW.member_id;

  IF member_org IS NULL THEN
    RAISE EXCEPTION 'member_id does not reference an existing organization member';
  END IF;
  IF member_org <> activity_org THEN
    RAISE EXCEPTION 'member_id must belong to the activity operating organization';
  END IF;
  IF NOT member_active THEN
    RAISE EXCEPTION 'member_id must be an active member';
  END IF;
  IF member_role <> 'technician' THEN
    RAISE EXCEPTION 'member_id must have the technician role';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_activity_technicians_check ON public.work_order_activity_technicians;
CREATE TRIGGER trg_work_order_activity_technicians_check
BEFORE INSERT OR UPDATE ON public.work_order_activity_technicians
FOR EACH ROW EXECUTE FUNCTION public.check_work_order_activity_technician();

-- =========================================================================
-- RLS. Both tables use organization_id (activities) / the parent activity's
-- organization_id (bridge) as the tenant boundary — since organization_id
-- is always the OT's operating organization, this scopes activity
-- visibility to whoever executes that OT (the provider for an external OT;
-- the client itself for an internal one, since the two ids coincide there).
-- Deliberately narrower than work_orders' own SELECT policy (which also
-- lets the *other* side of an external OT — the client — read the OT row):
-- the line-by-line technician task breakdown is the operator's internal
-- execution detail, not something shared with the client by default. See
-- docs/WORK_ORDER_ACTIVITIES.md for the full rationale.
-- No INSERT/UPDATE/DELETE policy on either table — the RPCs below
-- (SECURITY DEFINER) remain the only write path.
-- =========================================================================
ALTER TABLE public.work_order_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_order_activity_technicians ENABLE ROW LEVEL SECURITY;

CREATE POLICY "operating organization members can view activities" ON public.work_order_activities
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

CREATE POLICY "operating organization members can view activity technicians" ON public.work_order_activity_technicians
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.work_order_activities activity
      WHERE activity.id = work_order_activity_technicians.activity_id
        AND (
          (SELECT public.is_platform_admin())
          OR (SELECT public.is_organization_member(activity.organization_id))
        )
    )
  );

GRANT SELECT ON TABLE public.work_order_activities TO authenticated;
GRANT SELECT ON TABLE public.work_order_activity_technicians TO authenticated;

-- =========================================================================
-- B1) get_work_order_activities: activities + their technicians (resolved
-- name/email, same auth.users join pattern as get_assignable_technicians),
-- as a single call so the frontend never has to stitch two queries
-- together. Authorization matches the RLS policy above (operating
-- organization or platform admin) rather than work_orders' own broader
-- SELECT policy — see the RLS comment above for why.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_work_order_activities(target_work_order_id uuid)
RETURNS TABLE (
  id uuid,
  work_order_id uuid,
  description text,
  estimated_hours numeric,
  due_at timestamptz,
  status text,
  sequence integer,
  created_at timestamptz,
  updated_at timestamptz,
  technicians jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  operating_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT provider_organization_id INTO operating_org
    FROM public.work_orders WHERE id = target_work_order_id;

  IF operating_org IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(operating_org)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view activities for this work order';
  END IF;

  RETURN QUERY
  SELECT
    activity.id,
    activity.work_order_id,
    activity.description,
    activity.estimated_hours,
    activity.due_at,
    activity.status,
    activity.sequence,
    activity.created_at,
    activity.updated_at,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'member_id', technician_row.member_id,
            'name', technician_row.name,
            'email', technician_row.email,
            'is_primary', technician_row.is_primary
          )
          ORDER BY technician_row.is_primary DESC, technician_row.name
        )
        FROM (
          SELECT
            link.member_id,
            link.is_primary,
            COALESCE(NULLIF(TRIM(user_account.raw_user_meta_data->>'name'), ''), split_part(user_account.email, '@', 1)) AS name,
            user_account.email::text AS email
          FROM public.work_order_activity_technicians link
          INNER JOIN public.organization_members member ON member.id = link.member_id
          INNER JOIN auth.users user_account ON user_account.id = member.user_id
          WHERE link.activity_id = activity.id
        ) technician_row
      ),
      '[]'::jsonb
    ) AS technicians
  FROM public.work_order_activities activity
  WHERE activity.work_order_id = target_work_order_id
  ORDER BY activity.sequence, activity.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.get_work_order_activities(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_work_order_activities(uuid) TO authenticated;

-- =========================================================================
-- B2) upsert_work_order_activity: single create-or-update entry point.
-- target_activity_id NULL creates a new activity; non-null updates it (must
-- already belong to target_work_order_id). Full-replace technician set
-- (target_member_ids), same convention as update_work_order_operations —
-- the frontend always sends the complete desired list, not a delta. The
-- first id in target_member_ids becomes is_primary — the initial UI has no
-- separate "pick a primary" control, see docs/WORK_ORDER_ACTIVITIES.md §7.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.upsert_work_order_activity(
  target_work_order_id uuid,
  target_description text,
  target_activity_id uuid DEFAULT NULL,
  target_estimated_hours numeric DEFAULT NULL,
  target_due_at timestamptz DEFAULT NULL,
  target_status text DEFAULT 'pending',
  target_sequence integer DEFAULT NULL,
  target_member_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS public.work_order_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_work_order public.work_orders%ROWTYPE;
  existing_activity public.work_order_activities%ROWTYPE;
  saved_activity public.work_order_activities%ROWTYPE;
  resolved_sequence integer;
  next_sequence integer;
  primary_member_id uuid;
  member_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO target_work_order FROM public.work_orders WHERE id = target_work_order_id;
  IF target_work_order.id IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      target_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage activities for this work order';
  END IF;

  IF target_description IS NULL OR TRIM(target_description) = '' THEN
    RAISE EXCEPTION 'description is required';
  END IF;
  IF target_estimated_hours IS NOT NULL AND target_estimated_hours < 0 THEN
    RAISE EXCEPTION 'estimated_hours must be >= 0';
  END IF;
  IF target_status NOT IN ('pending', 'assigned', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'Invalid status value';
  END IF;

  -- Row consistency (organization, active, technician role) for each member
  -- is enforced again by trg_work_order_activity_technicians_check below;
  -- this pass exists only so a bad id fails with one clear error before any
  -- row is written, instead of failing mid-way through the technician loop.
  IF target_member_ids IS NOT NULL THEN
    FOREACH member_id IN ARRAY target_member_ids LOOP
      IF NOT EXISTS (
        SELECT 1 FROM public.organization_members member
        WHERE member.id = member_id
          AND member.organization_id = target_work_order.provider_organization_id
          AND member.is_active
          AND member.role = 'technician'
      ) THEN
        RAISE EXCEPTION 'Technician % is not an active technician of the operating organization', member_id;
      END IF;
    END LOOP;
  END IF;

  IF target_activity_id IS NOT NULL THEN
    SELECT * INTO existing_activity FROM public.work_order_activities WHERE id = target_activity_id;
    IF existing_activity.id IS NULL OR existing_activity.work_order_id <> target_work_order_id THEN
      RAISE EXCEPTION 'Activity not found for this work order';
    END IF;

    resolved_sequence := COALESCE(target_sequence, existing_activity.sequence);

    UPDATE public.work_order_activities
    SET description = TRIM(target_description),
        estimated_hours = target_estimated_hours,
        due_at = target_due_at,
        status = target_status,
        sequence = resolved_sequence
    WHERE id = target_activity_id
    RETURNING * INTO saved_activity;
  ELSE
    SELECT COALESCE(MAX(sequence), 0) + 1 INTO next_sequence
      FROM public.work_order_activities WHERE work_order_id = target_work_order_id;
    resolved_sequence := COALESCE(target_sequence, next_sequence);

    INSERT INTO public.work_order_activities (
      work_order_id, organization_id, description, estimated_hours, due_at, status, sequence, created_by_user_id
    ) VALUES (
      target_work_order_id, target_work_order.provider_organization_id, TRIM(target_description),
      target_estimated_hours, target_due_at, target_status, resolved_sequence, auth.uid()
    )
    RETURNING * INTO saved_activity;
  END IF;

  DELETE FROM public.work_order_activity_technicians WHERE activity_id = saved_activity.id;
  IF target_member_ids IS NOT NULL AND array_length(target_member_ids, 1) > 0 THEN
    primary_member_id := target_member_ids[1];
    FOREACH member_id IN ARRAY target_member_ids LOOP
      INSERT INTO public.work_order_activity_technicians (activity_id, member_id, is_primary)
      VALUES (saved_activity.id, member_id, member_id = primary_member_id)
      ON CONFLICT (activity_id, member_id) DO NOTHING;
    END LOOP;
  END IF;

  RETURN saved_activity;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_work_order_activity(uuid, text, uuid, numeric, timestamptz, text, integer, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_work_order_activity(uuid, text, uuid, numeric, timestamptz, text, integer, uuid[]) TO authenticated;

-- =========================================================================
-- B3) delete_work_order_activity: bridge rows cascade automatically
-- (ON DELETE CASCADE on work_order_activity_technicians.activity_id).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.delete_work_order_activity(target_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_activity public.work_order_activities%ROWTYPE;
  target_work_order public.work_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO target_activity FROM public.work_order_activities WHERE id = target_activity_id;
  IF target_activity.id IS NULL THEN
    RAISE EXCEPTION 'Activity not found';
  END IF;

  SELECT * INTO target_work_order FROM public.work_orders WHERE id = target_activity.work_order_id;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      target_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to delete this activity';
  END IF;

  DELETE FROM public.work_order_activities WHERE id = target_activity_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_work_order_activity(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_work_order_activity(uuid) TO authenticated;
