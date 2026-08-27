-- Fixes Postgres error 42702 (ambiguous_column) on get_work_order_activities
-- and hardens the other two activity RPCs against the same class of bug.
--
-- Root cause: get_work_order_activities declares RETURNS TABLE (id uuid,
-- work_order_id uuid, description text, estimated_hours numeric,
-- due_at timestamptz, status text, sequence integer, created_at timestamptz,
-- updated_at timestamptz, technicians jsonb). PL/pgSQL turns every one of
-- those into an implicit OUT variable visible by bare name inside the
-- function body. The function's very first query —
--   SELECT provider_organization_id INTO operating_org
--     FROM public.work_orders WHERE id = target_work_order_id;
-- — referenced the unqualified column `id`, which Postgres could not
-- resolve between public.work_orders.id and the OUT variable `id`: exactly
-- 42702. The rest of that function already qualified every column via the
-- `activity` alias, so this one bare reference was the only offender.
--
-- upsert_work_order_activity and delete_work_order_activity do not use
-- RETURNS TABLE (delete returns void, upsert returns a single
-- work_order_activities row), so they never had this specific OUT-variable
-- collision — audited line by line, no ambiguous reference found. They are
-- still replaced here with the same short table aliases and p_-prefixed
-- parameter names for consistency and to close off the same class of bug
-- permanently, as requested.
--
-- 20260827160000_work_order_activities.sql (already applied
-- local + remote) is intentionally left untouched — this is a corrective
-- migration on top of it, not an edit to the original.

-- =========================================================================
-- get_work_order_activities
-- Postgres refuses CREATE OR REPLACE FUNCTION when an input parameter is
-- renamed (SQLSTATE 42P13, "cannot change name of input parameter") even
-- though the type signature is unchanged — DROP first, same signature.
-- =========================================================================
DROP FUNCTION IF EXISTS public.get_work_order_activities(uuid);

CREATE OR REPLACE FUNCTION public.get_work_order_activities(p_work_order_id uuid)
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
  v_operating_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wo.provider_organization_id INTO v_operating_org
    FROM public.work_orders wo
    WHERE wo.id = p_work_order_id;

  IF v_operating_org IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.is_organization_member(v_operating_org)
  ) THEN
    RAISE EXCEPTION 'Not authorized to view activities for this work order';
  END IF;

  RETURN QUERY
  SELECT
    woa.id,
    woa.work_order_id,
    woa.description,
    woa.estimated_hours,
    woa.due_at,
    woa.status,
    woa.sequence,
    woa.created_at,
    woa.updated_at,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'member_id', tech.member_id,
            'name', tech.name,
            'email', tech.email,
            'is_primary', tech.is_primary
          )
          ORDER BY tech.is_primary DESC, tech.name
        )
        FROM (
          SELECT
            woat.member_id,
            woat.is_primary,
            COALESCE(NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''), split_part(au.email, '@', 1)) AS name,
            au.email::text AS email
          FROM public.work_order_activity_technicians woat
          INNER JOIN public.organization_members om ON om.id = woat.member_id
          INNER JOIN auth.users au ON au.id = om.user_id
          WHERE woat.activity_id = woa.id
        ) tech
      ),
      '[]'::jsonb
    ) AS technicians
  FROM public.work_order_activities woa
  WHERE woa.work_order_id = p_work_order_id
  ORDER BY woa.sequence, woa.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.get_work_order_activities(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_work_order_activities(uuid) TO authenticated;

-- =========================================================================
-- upsert_work_order_activity (renamed parameters, same DROP-first reason)
-- =========================================================================
DROP FUNCTION IF EXISTS public.upsert_work_order_activity(uuid, text, uuid, numeric, timestamptz, text, integer, uuid[]);

CREATE OR REPLACE FUNCTION public.upsert_work_order_activity(
  p_work_order_id uuid,
  p_description text,
  p_activity_id uuid DEFAULT NULL,
  p_estimated_hours numeric DEFAULT NULL,
  p_due_at timestamptz DEFAULT NULL,
  p_status text DEFAULT 'pending',
  p_sequence integer DEFAULT NULL,
  p_technician_member_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS public.work_order_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_work_order public.work_orders%ROWTYPE;
  v_existing_activity public.work_order_activities%ROWTYPE;
  v_saved_activity public.work_order_activities%ROWTYPE;
  v_resolved_sequence integer;
  v_next_sequence integer;
  v_primary_member_id uuid;
  v_member_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT wo.* INTO v_work_order FROM public.work_orders wo WHERE wo.id = p_work_order_id;
  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      v_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to manage activities for this work order';
  END IF;

  IF p_description IS NULL OR TRIM(p_description) = '' THEN
    RAISE EXCEPTION 'description is required';
  END IF;
  IF p_estimated_hours IS NOT NULL AND p_estimated_hours < 0 THEN
    RAISE EXCEPTION 'estimated_hours must be >= 0';
  END IF;
  IF p_status NOT IN ('pending', 'assigned', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'Invalid status value';
  END IF;

  -- Row consistency (organization, active, technician role) for each member
  -- is enforced again by trg_work_order_activity_technicians_check below;
  -- this pass exists only so a bad id fails with one clear error before any
  -- row is written, instead of failing mid-way through the technician loop.
  IF p_technician_member_ids IS NOT NULL THEN
    FOREACH v_member_id IN ARRAY p_technician_member_ids LOOP
      IF NOT EXISTS (
        SELECT 1 FROM public.organization_members om
        WHERE om.id = v_member_id
          AND om.organization_id = v_work_order.provider_organization_id
          AND om.is_active
          AND om.role = 'technician'
      ) THEN
        RAISE EXCEPTION 'Technician % is not an active technician of the operating organization', v_member_id;
      END IF;
    END LOOP;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT woa.* INTO v_existing_activity FROM public.work_order_activities woa WHERE woa.id = p_activity_id;
    IF v_existing_activity.id IS NULL OR v_existing_activity.work_order_id <> p_work_order_id THEN
      RAISE EXCEPTION 'Activity not found for this work order';
    END IF;

    v_resolved_sequence := COALESCE(p_sequence, v_existing_activity.sequence);

    UPDATE public.work_order_activities woa
    SET description = TRIM(p_description),
        estimated_hours = p_estimated_hours,
        due_at = p_due_at,
        status = p_status,
        sequence = v_resolved_sequence
    WHERE woa.id = p_activity_id
    RETURNING woa.* INTO v_saved_activity;
  ELSE
    SELECT COALESCE(MAX(woa.sequence), 0) + 1 INTO v_next_sequence
      FROM public.work_order_activities woa WHERE woa.work_order_id = p_work_order_id;
    v_resolved_sequence := COALESCE(p_sequence, v_next_sequence);

    INSERT INTO public.work_order_activities AS woa (
      work_order_id, organization_id, description, estimated_hours, due_at, status, sequence, created_by_user_id
    ) VALUES (
      p_work_order_id, v_work_order.provider_organization_id, TRIM(p_description),
      p_estimated_hours, p_due_at, p_status, v_resolved_sequence, auth.uid()
    )
    RETURNING woa.* INTO v_saved_activity;
  END IF;

  DELETE FROM public.work_order_activity_technicians woat WHERE woat.activity_id = v_saved_activity.id;
  IF p_technician_member_ids IS NOT NULL AND array_length(p_technician_member_ids, 1) > 0 THEN
    v_primary_member_id := p_technician_member_ids[1];
    FOREACH v_member_id IN ARRAY p_technician_member_ids LOOP
      INSERT INTO public.work_order_activity_technicians AS woat (activity_id, member_id, is_primary)
      VALUES (v_saved_activity.id, v_member_id, v_member_id = v_primary_member_id)
      ON CONFLICT (activity_id, member_id) DO NOTHING;
    END LOOP;
  END IF;

  RETURN v_saved_activity;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_work_order_activity(uuid, text, uuid, numeric, timestamptz, text, integer, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_work_order_activity(uuid, text, uuid, numeric, timestamptz, text, integer, uuid[]) TO authenticated;

-- =========================================================================
-- delete_work_order_activity (renamed parameter, same DROP-first reason)
-- =========================================================================
DROP FUNCTION IF EXISTS public.delete_work_order_activity(uuid);

CREATE OR REPLACE FUNCTION public.delete_work_order_activity(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity public.work_order_activities%ROWTYPE;
  v_work_order public.work_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT woa.* INTO v_activity FROM public.work_order_activities woa WHERE woa.id = p_activity_id;
  IF v_activity.id IS NULL THEN
    RAISE EXCEPTION 'Activity not found';
  END IF;

  SELECT wo.* INTO v_work_order FROM public.work_orders wo WHERE wo.id = v_activity.work_order_id;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      v_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to delete this activity';
  END IF;

  DELETE FROM public.work_order_activities woa WHERE woa.id = p_activity_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_work_order_activity(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_work_order_activity(uuid) TO authenticated;
