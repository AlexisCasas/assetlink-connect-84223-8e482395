-- Operational in-app notifications. Reuses the existing
-- organization_notifications table/RLS/idempotency pattern from
-- 20260721184404_quote_notifications_tenant_flow.sql instead of building a
-- parallel system — that table already had exactly the shape this phase
-- needs (organization_id, actor_user_id, type, title, message,
-- entity_type/entity_id, is_read/read_at), just extended with a
-- recipient_member_id (for per-person targeting; NULL still means
-- "organization-wide broadcast", preserving every existing row's meaning
-- unchanged) and priority/metadata.
--
-- No email/WhatsApp/push, no scheduler/cron, no multi-channel templates,
-- no notification preferences — explicitly out of scope for this phase,
-- documented in docs/OPERATIONAL_NOTIFICATIONS.md.
--
-- Every new/changed function fully qualifies every column reference with
-- a short alias from the very first line (n/om/au/r/wo/woa/woat/woar) —
-- see 20260827170000_fix_work_order_activities_rpc_ambiguity.sql for the
-- class of bug this is deliberately avoiding.

-- =========================================================================
-- A) Extend organization_notifications. recipient_member_id NULL keeps the
-- exact pre-existing "organization-wide broadcast" behavior (quote_submitted/
-- approved/rejected, the original work_order_created) — nothing about
-- those rows or their visibility changes. A non-NULL recipient_member_id
-- targets exactly one member.
-- =========================================================================
ALTER TABLE public.organization_notifications
  ADD COLUMN IF NOT EXISTS recipient_member_id uuid NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS priority text NOT NULL DEFAULT 'medium',
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $$ BEGIN
  ALTER TABLE public.organization_notifications ADD CONSTRAINT organization_notifications_priority_check
    CHECK (priority IN ('low', 'medium', 'high', 'urgent'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_organization_notifications_recipient_member_id
  ON public.organization_notifications (recipient_member_id);

-- Idempotency for the new operational event types: two partial unique
-- indexes, one per "shape" of notification. A single index can't cover
-- both, because NULL never equals NULL for uniqueness purposes — a plain
-- UNIQUE(organization_id, recipient_member_id, type, entity_type, entity_id)
-- would let broadcast rows (recipient_member_id IS NULL) duplicate freely.
CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_notifications_broadcast_dedup
  ON public.organization_notifications (organization_id, type, entity_type, entity_id)
  WHERE recipient_member_id IS NULL AND entity_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_notifications_targeted_dedup
  ON public.organization_notifications (organization_id, recipient_member_id, type, entity_type, entity_id)
  WHERE recipient_member_id IS NOT NULL AND entity_id IS NOT NULL;

-- SELECT/UPDATE policies replaced (not just extended) so a member can no
-- longer read or mark-as-read a notification targeted at a different
-- member of their own organization. Broadcasts (recipient_member_id IS
-- NULL) remain visible to every member, exactly as before.
DROP POLICY IF EXISTS "organization members can read organization notifications" ON public.organization_notifications;
CREATE POLICY "organization members can read organization notifications"
  ON public.organization_notifications
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      (SELECT public.is_organization_member(organization_id))
      AND (
        recipient_member_id IS NULL
        OR EXISTS (
          SELECT 1 FROM public.organization_members om
          WHERE om.id = organization_notifications.recipient_member_id AND om.user_id = auth.uid()
        )
      )
    )
  );

DROP POLICY IF EXISTS "organization members can mark organization notifications read" ON public.organization_notifications;
CREATE POLICY "organization members can mark organization notifications read"
  ON public.organization_notifications
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (
      (SELECT public.is_organization_member(organization_id))
      AND (
        recipient_member_id IS NULL
        OR EXISTS (
          SELECT 1 FROM public.organization_members om
          WHERE om.id = organization_notifications.recipient_member_id AND om.user_id = auth.uid()
        )
      )
    )
  )
  WITH CHECK (
    (SELECT public.is_platform_admin())
    OR (
      (SELECT public.is_organization_member(organization_id))
      AND (
        recipient_member_id IS NULL
        OR EXISTS (
          SELECT 1 FROM public.organization_members om
          WHERE om.id = organization_notifications.recipient_member_id AND om.user_id = auth.uid()
        )
      )
    )
  );

-- =========================================================================
-- B1) create_notification_once: the single low-level insert, dedup-safe
-- against whichever of the two partial indexes above applies. Not granted
-- to authenticated — same "internal helper" pattern as the pre-existing
-- create_organization_notification (title/message/recipient are free-form
-- inputs here; exposing this directly would let any authenticated user
-- spam arbitrary notifications at arbitrary members).
-- =========================================================================
CREATE OR REPLACE FUNCTION public.create_notification_once(
  p_organization_id uuid,
  p_recipient_member_id uuid,
  p_actor_user_id uuid,
  p_type text,
  p_title text,
  p_message text,
  p_entity_type text,
  p_entity_id uuid,
  p_priority text DEFAULT 'medium',
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notification_id uuid;
BEGIN
  IF p_recipient_member_id IS NULL THEN
    INSERT INTO public.organization_notifications (
      organization_id, recipient_member_id, actor_user_id, type, title, message,
      entity_type, entity_id, priority, metadata
    ) VALUES (
      p_organization_id, NULL, p_actor_user_id, p_type, p_title, p_message,
      p_entity_type, p_entity_id, p_priority, p_metadata
    )
    ON CONFLICT (organization_id, type, entity_type, entity_id)
      WHERE recipient_member_id IS NULL AND entity_id IS NOT NULL
      DO NOTHING
    RETURNING id INTO v_notification_id;
  ELSE
    INSERT INTO public.organization_notifications (
      organization_id, recipient_member_id, actor_user_id, type, title, message,
      entity_type, entity_id, priority, metadata
    ) VALUES (
      p_organization_id, p_recipient_member_id, p_actor_user_id, p_type, p_title, p_message,
      p_entity_type, p_entity_id, p_priority, p_metadata
    )
    ON CONFLICT (organization_id, recipient_member_id, type, entity_type, entity_id)
      WHERE recipient_member_id IS NOT NULL AND entity_id IS NOT NULL
      DO NOTHING
    RETURNING id INTO v_notification_id;
  END IF;

  RETURN v_notification_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_notification_once(uuid, uuid, uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_notification_once(uuid, uuid, uuid, text, text, text, text, uuid, text, jsonb) FROM authenticated;

-- =========================================================================
-- B2) notify_role_members: one targeted notification per active member of
-- p_organization_id whose role is in p_roles. Deliberately NOT a single
-- broadcast row — a broadcast would be visible to every member of the
-- organization regardless of role (viewers/requesters/technicians
-- included), which is exactly what "no notificar a todos los viewers si
-- no corresponde" rules out. Each recipient's row is independently
-- idempotent via create_notification_once.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.notify_role_members(
  p_organization_id uuid,
  p_roles public.organization_member_role[],
  p_actor_user_id uuid,
  p_type text,
  p_title text,
  p_message text,
  p_entity_type text,
  p_entity_id uuid,
  p_priority text DEFAULT 'medium',
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  FOR v_member_id IN
    SELECT om.id FROM public.organization_members om
    WHERE om.organization_id = p_organization_id
      AND om.is_active
      AND om.role = ANY (p_roles)
  LOOP
    PERFORM public.create_notification_once(
      p_organization_id, v_member_id, p_actor_user_id, p_type, p_title, p_message,
      p_entity_type, p_entity_id, p_priority, p_metadata
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_role_members(uuid, public.organization_member_role[], uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_role_members(uuid, public.organization_member_role[], uuid, text, text, text, text, uuid, text, jsonb) FROM authenticated;

-- =========================================================================
-- B3) notify_member: single-recipient wrapper, resolves the member's own
-- organization_id so callers don't have to look it up separately.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.notify_member(
  p_member_id uuid,
  p_actor_user_id uuid,
  p_type text,
  p_title text,
  p_message text,
  p_entity_type text,
  p_entity_id uuid,
  p_priority text DEFAULT 'medium',
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organization_id uuid;
BEGIN
  SELECT om.organization_id INTO v_organization_id FROM public.organization_members om WHERE om.id = p_member_id;
  IF v_organization_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM public.create_notification_once(
    v_organization_id, p_member_id, p_actor_user_id, p_type, p_title, p_message,
    p_entity_type, p_entity_id, p_priority, p_metadata
  );
END;
$$;

REVOKE ALL ON FUNCTION public.notify_member(uuid, uuid, text, text, text, text, uuid, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_member(uuid, uuid, text, text, text, text, uuid, text, jsonb) FROM authenticated;

-- =========================================================================
-- C) Internal request created -> notify owner/admin/manager of the
-- requesting organization. Requests are inserted directly by the frontend
-- (no creation RPC exists for them), so this is a trigger, same pattern as
-- notify_quote_status_change. Fires once a request is actually sent
-- (status = 'sent'), whether that happens on INSERT (submit immediately)
-- or on UPDATE (a draft is later sent) — draft requests never notify.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.notify_internal_request_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.request_type = 'internal' AND NEW.organization_id IS NOT NULL AND (
    (TG_OP = 'INSERT' AND NEW.status = 'sent')
    OR (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'sent')
  ) THEN
    PERFORM public.notify_role_members(
      NEW.organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NEW.created_by_user_id,
      'internal_request_created',
      'Nueva solicitud interna',
      COALESCE(NEW.title, NEW.request_number) || ' fue enviada como solicitud interna.',
      'request',
      NEW.id,
      'medium',
      jsonb_build_object('request_number', NEW.request_number)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_internal_request_created ON public.requests;
CREATE TRIGGER trg_notify_internal_request_created
AFTER INSERT OR UPDATE OF status ON public.requests
FOR EACH ROW EXECUTE FUNCTION public.notify_internal_request_created();

REVOKE ALL ON FUNCTION public.notify_internal_request_created() FROM PUBLIC;

-- =========================================================================
-- D) Extend existing write RPCs with notification calls. Every one below
-- keeps its exact pre-existing signature (no parameter renamed), so a
-- plain CREATE OR REPLACE FUNCTION is enough — no DROP FUNCTION needed,
-- unlike a parameter rename (see the 42702 fix migration for why that
-- distinction matters).
-- =========================================================================

-- D1) create_work_order_from_quote: the pre-existing notification here was
-- a plain organization-wide broadcast to the whole provider organization.
-- Tightened to owner/admin/manager only, per this phase's explicit
-- recipient rule for "nueva OT" — the only behavior change in this
-- function. No assigned technician to notify here: this path never sets
-- assigned_member_id at creation time.
CREATE OR REPLACE FUNCTION public.create_work_order_from_quote(target_quote_id uuid)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_quote public.quotes%ROWTYPE;
  source_request public.requests%ROWTYPE;
  created_work_order public.work_orders%ROWTYPE;
  can_create boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT quote.* INTO source_quote
  FROM public.quotes quote
  WHERE quote.id = target_quote_id
  FOR UPDATE;

  IF source_quote.id IS NULL THEN
    RAISE EXCEPTION 'Quote not found';
  END IF;

  IF source_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'A work order can only be created from an approved quote';
  END IF;

  IF source_quote.provider_organization_id IS NULL THEN
    RAISE EXCEPTION 'Approved quote has no provider organization';
  END IF;

  SELECT request.* INTO source_request
  FROM public.requests request
  WHERE request.id = source_quote.request_id;

  IF source_request.id IS NULL OR source_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Quote request has no client organization';
  END IF;

  can_create := public.is_platform_admin()
    OR public.has_organization_role(
      source_request.organization_id,
      ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
    );

  IF NOT can_create THEN
    RAISE EXCEPTION 'Not authorized to create a work order for this quote';
  END IF;

  INSERT INTO public.work_orders (
    request_id,
    quote_id,
    client_organization_id,
    provider_organization_id,
    work_order_type,
    asset_id,
    priority,
    due_at,
    planner_member_id,
    status,
    title,
    description,
    total_amount,
    created_by_user_id
  ) VALUES (
    source_quote.request_id,
    source_quote.id,
    source_request.organization_id,
    source_quote.provider_organization_id,
    'external',
    source_request.asset_id,
    public.map_request_priority_to_work_order_priority(source_request.priority),
    source_request.deadline,
    public.resolve_caller_planner_member(source_quote.provider_organization_id),
    'pending',
    source_request.title,
    source_quote.description,
    source_quote.total_amount,
    auth.uid()
  )
  ON CONFLICT (quote_id) DO NOTHING
  RETURNING * INTO created_work_order;

  IF created_work_order.id IS NULL THEN
    SELECT work_order.* INTO created_work_order
    FROM public.work_orders work_order
    WHERE work_order.quote_id = source_quote.id;

    RETURN created_work_order;
  END IF;

  PERFORM public.notify_role_members(
    source_quote.provider_organization_id,
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
    auth.uid(),
    'work_order_created',
    'Nueva orden de trabajo',
    'Se creó la orden ' || created_work_order.work_order_number || ' a partir de una cotización aprobada.',
    'work_order',
    created_work_order.id,
    'medium',
    jsonb_build_object('work_order_number', created_work_order.work_order_number)
  );

  RETURN created_work_order;
END;
$$;

-- D2) create_internal_work_order_from_request: notifies owner/admin/manager
-- of the client organization ("nueva OT") and, if a technician was already
-- assigned at creation, also notifies that technician ("técnico asignado")
-- as a second, distinct event.
CREATE OR REPLACE FUNCTION public.create_internal_work_order_from_request(
  target_request_id uuid,
  target_assigned_member_id uuid DEFAULT NULL
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_request public.requests%ROWTYPE;
  existing_work_order public.work_orders%ROWTYPE;
  created_work_order public.work_orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO source_request FROM public.requests WHERE id = target_request_id;
  IF source_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  IF source_request.request_type <> 'internal' THEN
    RAISE EXCEPTION 'Only internal requests can generate a direct work order';
  END IF;

  IF source_request.organization_id IS NULL THEN
    RAISE EXCEPTION 'Request has no client organization';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations organization
    WHERE organization.id = source_request.organization_id
      AND organization.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Request organization is not active';
  END IF;

  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      source_request.organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to generate a work order for this request';
  END IF;

  SELECT * INTO existing_work_order
    FROM public.work_orders
    WHERE request_id = target_request_id AND quote_id IS NULL;

  IF existing_work_order.id IS NOT NULL THEN
    RETURN existing_work_order;
  END IF;

  INSERT INTO public.work_orders (
    request_id,
    quote_id,
    client_organization_id,
    provider_organization_id,
    work_order_type,
    asset_id,
    priority,
    due_at,
    planner_member_id,
    assigned_member_id,
    status,
    title,
    description,
    created_by_user_id
  ) VALUES (
    target_request_id,
    NULL,
    source_request.organization_id,
    source_request.organization_id,
    'internal',
    source_request.asset_id,
    public.map_request_priority_to_work_order_priority(source_request.priority),
    source_request.deadline,
    public.resolve_caller_planner_member(source_request.organization_id),
    target_assigned_member_id,
    CASE WHEN target_assigned_member_id IS NOT NULL THEN 'assigned' ELSE 'pending' END,
    source_request.title,
    source_request.description,
    auth.uid()
  )
  RETURNING * INTO created_work_order;

  PERFORM public.notify_role_members(
    source_request.organization_id,
    ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
    auth.uid(),
    'work_order_created',
    'Nueva orden de trabajo',
    'Se creó la orden ' || created_work_order.work_order_number || ' desde una solicitud interna.',
    'work_order',
    created_work_order.id,
    'medium',
    jsonb_build_object('work_order_number', created_work_order.work_order_number)
  );

  IF target_assigned_member_id IS NOT NULL THEN
    PERFORM public.notify_member(
      target_assigned_member_id,
      auth.uid(),
      'technician_assigned',
      'Te asignaron una orden de trabajo',
      'Te asignaron la orden ' || created_work_order.work_order_number || '.',
      'work_order',
      created_work_order.id,
      'medium',
      jsonb_build_object('work_order_number', created_work_order.work_order_number)
    );
  END IF;

  RETURN created_work_order;
END;
$$;

-- D3) update_work_order_operations: notifies the newly assigned technician
-- only when assigned_member_id actually changes to a non-null value —
-- never the previous technician, never on every save.
CREATE OR REPLACE FUNCTION public.update_work_order_operations(
  target_work_order_id uuid,
  target_planner_member_id uuid,
  target_assigned_member_id uuid,
  target_scheduled_at timestamptz,
  target_due_at timestamptz,
  target_priority text,
  target_status text,
  target_observations text
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_work_order public.work_orders%ROWTYPE;
  updated_work_order public.work_orders%ROWTYPE;
  v_previous_assigned_member_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO target_work_order FROM public.work_orders WHERE id = target_work_order_id;
  IF target_work_order.id IS NULL THEN
    RAISE EXCEPTION 'Work order not found';
  END IF;

  -- Only owner/admin/manager of the operating organization (provider_organization_id
  -- — for internal OTs this is the same organization as the client) or a
  -- platform admin may edit. Technicians can view but not edit in this phase.
  IF NOT (
    public.is_platform_admin()
    OR public.has_organization_role(
      target_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[]
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to edit this work order';
  END IF;

  IF target_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Invalid priority value';
  END IF;
  IF target_status NOT IN ('pending', 'assigned', 'in_progress', 'completed', 'closed') THEN
    RAISE EXCEPTION 'Invalid status value';
  END IF;

  v_previous_assigned_member_id := target_work_order.assigned_member_id;

  -- planner_member_id / assigned_member_id row consistency (organization,
  -- active, role) is enforced by trg_work_orders_check_planner and
  -- trg_work_orders_check_assigned_technician on this UPDATE.
  UPDATE public.work_orders
  SET planner_member_id = target_planner_member_id,
      assigned_member_id = target_assigned_member_id,
      scheduled_at = target_scheduled_at,
      due_at = target_due_at,
      priority = target_priority,
      status = target_status,
      observations = target_observations
  WHERE id = target_work_order_id
  RETURNING * INTO updated_work_order;

  IF target_assigned_member_id IS NOT NULL AND target_assigned_member_id IS DISTINCT FROM v_previous_assigned_member_id THEN
    PERFORM public.notify_member(
      target_assigned_member_id,
      auth.uid(),
      'technician_assigned',
      'Te asignaron una orden de trabajo',
      'Te asignaron la orden ' || updated_work_order.work_order_number || '.',
      'work_order',
      updated_work_order.id,
      'medium',
      jsonb_build_object('work_order_number', updated_work_order.work_order_number)
    );
  END IF;

  IF target_status = 'completed' AND target_work_order.status IS DISTINCT FROM 'completed' THEN
    PERFORM public.notify_role_members(
      updated_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      auth.uid(),
      'work_completed',
      'Trabajo completado',
      'La orden ' || updated_work_order.work_order_number || ' fue marcada como completada.',
      'work_order',
      updated_work_order.id,
      'medium',
      jsonb_build_object('work_order_number', updated_work_order.work_order_number)
    );
  END IF;

  RETURN updated_work_order;
END;
$$;

-- D4) assign_work_order_technician: still exists for backward compatibility
-- (the frontend now saves technician assignment through
-- update_work_order_operations instead), extended with the same
-- new-assignment-only notification rule.
CREATE OR REPLACE FUNCTION public.assign_work_order_technician(
  target_work_order_id uuid,
  target_member_id uuid
)
RETURNS public.work_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_work_order public.work_orders%ROWTYPE;
  updated_work_order public.work_orders%ROWTYPE;
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
    RAISE EXCEPTION 'Not authorized to assign a technician for this work order';
  END IF;

  UPDATE public.work_orders
  SET assigned_member_id = target_member_id,
      status = CASE
        WHEN target_member_id IS NOT NULL AND status = 'pending' THEN 'assigned'
        WHEN target_member_id IS NULL AND status = 'assigned' THEN 'pending'
        ELSE status
      END
  WHERE id = target_work_order_id
  RETURNING * INTO updated_work_order;

  IF target_member_id IS NOT NULL AND target_member_id IS DISTINCT FROM target_work_order.assigned_member_id THEN
    PERFORM public.notify_member(
      target_member_id,
      auth.uid(),
      'technician_assigned',
      'Te asignaron una orden de trabajo',
      'Te asignaron la orden ' || updated_work_order.work_order_number || '.',
      'work_order',
      updated_work_order.id,
      'medium',
      jsonb_build_object('work_order_number', updated_work_order.work_order_number)
    );
  END IF;

  RETURN updated_work_order;
END;
$$;

-- D5) upsert_work_order_activity: notifies every technician in the final
-- p_technician_member_ids set, on both create and update. No manual
-- old-vs-new diff needed — create_notification_once's own idempotency
-- (keyed on organization + recipient + type + entity_type + entity_id)
-- already guarantees a technician already notified for this exact
-- activity is silently skipped on a later call, so only genuinely new
-- assignments ever produce a visible notification.
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

      PERFORM public.notify_member(
        v_member_id,
        auth.uid(),
        'activity_assigned',
        'Te asignaron una actividad',
        'Te asignaron la actividad "' || v_saved_activity.description || '".',
        'activity',
        v_saved_activity.id,
        'medium',
        jsonb_build_object('work_order_number', v_work_order.work_order_number, 'activity_description', v_saved_activity.description)
      );
    END LOOP;
  END IF;

  RETURN v_saved_activity;
END;
$$;

-- D6) submit_activity_report: when a technician marks their own activity
-- report as completed, notifies owner/admin/manager of the operating
-- organization ("trabajo completado" at the activity level — distinct
-- from the OT-level one in update_work_order_operations).
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

    PERFORM public.notify_role_members(
      v_work_order.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      auth.uid(),
      'work_completed',
      'Trabajo completado',
      'Se completó la actividad "' || v_activity.description || '" de la orden ' || v_work_order.work_order_number || '.',
      'activity',
      p_activity_id,
      'medium',
      jsonb_build_object('work_order_number', v_work_order.work_order_number, 'activity_description', v_activity.description)
    );
  ELSIF p_final_status IN ('in_progress', 'blocked') THEN
    UPDATE public.work_order_activities woa SET status = 'in_progress' WHERE woa.id = p_activity_id;
  END IF;

  RETURN v_saved_report;
END;
$$;

-- D7) technician_update_work_order_progress: OT-level "trabajo completado"
-- notification when the technician themself finishes the whole OT.
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

    IF p_status = 'completed' THEN
      PERFORM public.notify_role_members(
        v_updated.provider_organization_id,
        ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
        auth.uid(),
        'work_completed',
        'Trabajo completado',
        'La orden ' || v_updated.work_order_number || ' fue marcada como completada.',
        'work_order',
        v_updated.id,
        'medium',
        jsonb_build_object('work_order_number', v_updated.work_order_number)
      );
    END IF;
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

-- =========================================================================
-- E) generate_operational_due_notifications: no external cron/scheduler in
-- this phase — called from the frontend on notification-center load,
-- Dashboard load, and WorkOrdersList load (see
-- docs/OPERATIONAL_NOTIFICATIONS.md). Idempotent: repeated calls for a
-- work order that is still due-soon/overdue never create a second row for
-- the same recipient (create_notification_once's own dedup). Granted to
-- authenticated — unlike the helpers above, this function takes no
-- free-form input at all (no title/message/recipient the caller controls),
-- it only ever notifies the *correct* recipients of whichever work orders
-- actually qualify, so exposing it directly cannot be abused to spam
-- anyone.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.generate_operational_due_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wo record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  FOR v_wo IN
    SELECT wo.id, wo.work_order_number, wo.provider_organization_id, wo.assigned_member_id
    FROM public.work_orders wo
    WHERE wo.due_at IS NOT NULL
      AND wo.status NOT IN ('completed', 'closed')
      AND wo.due_at >= now()
      AND wo.due_at <= now() + interval '24 hours'
  LOOP
    PERFORM public.notify_role_members(
      v_wo.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL,
      'work_order_due_soon',
      'OT próxima a vencer',
      'La orden ' || v_wo.work_order_number || ' vence en menos de 24 horas.',
      'work_order',
      v_wo.id,
      'high',
      jsonb_build_object('work_order_number', v_wo.work_order_number)
    );
    IF v_wo.assigned_member_id IS NOT NULL THEN
      PERFORM public.notify_member(
        v_wo.assigned_member_id,
        NULL,
        'work_order_due_soon',
        'OT próxima a vencer',
        'La orden ' || v_wo.work_order_number || ' vence en menos de 24 horas.',
        'work_order',
        v_wo.id,
        'high',
        jsonb_build_object('work_order_number', v_wo.work_order_number)
      );
    END IF;
  END LOOP;

  FOR v_wo IN
    SELECT wo.id, wo.work_order_number, wo.provider_organization_id, wo.assigned_member_id
    FROM public.work_orders wo
    WHERE wo.due_at IS NOT NULL
      AND wo.status NOT IN ('completed', 'closed')
      AND wo.due_at < now()
  LOOP
    PERFORM public.notify_role_members(
      v_wo.provider_organization_id,
      ARRAY['owner', 'admin', 'manager']::public.organization_member_role[],
      NULL,
      'work_order_overdue',
      'OT vencida',
      'La orden ' || v_wo.work_order_number || ' está vencida.',
      'work_order',
      v_wo.id,
      'urgent',
      jsonb_build_object('work_order_number', v_wo.work_order_number)
    );
    IF v_wo.assigned_member_id IS NOT NULL THEN
      PERFORM public.notify_member(
        v_wo.assigned_member_id,
        NULL,
        'work_order_overdue',
        'OT vencida',
        'La orden ' || v_wo.work_order_number || ' está vencida.',
        'work_order',
        v_wo.id,
        'urgent',
        jsonb_build_object('work_order_number', v_wo.work_order_number)
      );
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.generate_operational_due_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_operational_due_notifications() TO authenticated;
