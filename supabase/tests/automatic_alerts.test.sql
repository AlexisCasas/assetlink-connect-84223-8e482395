-- Fase 1 · Punto 8 — Alertas automáticas.
-- Se ejecuta con: supabase test db --local
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
CREATE EXTENSION IF NOT EXISTS dblink;
SELECT plan(70);

-- -------------------------------------------------------------------------
-- Fixture — Organización A: owner, admin, manager, technician, y un quinto
-- miembro (manager, "responsable") deliberadamente TAMBIÉN en el pool de
-- broadcast owner/admin/manager: así el mecanismo de dedup
-- (responsable + rol) se ejercita de verdad en cada alerta de preventivo,
-- en vez de asumirlo sin probarlo.
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('b1000000-0000-0000-0000-000000000001', 'owner-a@alerts.test'),
  ('b1000000-0000-0000-0000-000000000002', 'admin-a@alerts.test'),
  ('b1000000-0000-0000-0000-000000000003', 'manager-a@alerts.test'),
  ('b1000000-0000-0000-0000-000000000004', 'technician-a@alerts.test'),
  ('b1000000-0000-0000-0000-000000000005', 'responsible-a@alerts.test'),
  ('b1000000-0000-0000-0000-000000000006', 'responsible-inactive-a@alerts.test'),
  ('b1000000-0000-0000-0000-000000000007', 'owner-b@alerts.test');

INSERT INTO public.organizations (id, name, organization_type, status) VALUES
  ('b2000000-0000-0000-0000-00000000000a', 'Tenant A', 'client_company', 'active'),
  ('b2000000-0000-0000-0000-00000000000b', 'Tenant B', 'client_company', 'active'),
  ('b2000000-0000-0000-0000-00000000000c', 'Tenant Suspendido', 'client_company', 'active');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-000000000001', 'owner', true),
  ('b3000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-000000000002', 'admin', true),
  ('b3000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-000000000003', 'manager', true),
  ('b3000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-000000000004', 'technician', true),
  ('b3000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-000000000005', 'manager', true),
  ('b3000000-0000-0000-0000-000000000006', 'b2000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-000000000006', 'manager', false),
  ('b3000000-0000-0000-0000-000000000007', 'b2000000-0000-0000-0000-00000000000b', 'b1000000-0000-0000-0000-000000000007', 'owner', true),
  ('b3000000-0000-0000-0000-000000000008', 'b2000000-0000-0000-0000-00000000000c', 'b1000000-0000-0000-0000-000000000001', 'owner', true);

INSERT INTO public.assets (id, organization_id, name, node_type, status) VALUES
  ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'Asset A', 'equipment', 'active'),
  ('b4000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'Asset A archived', 'equipment', 'archived'),
  ('b4000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000c', 'Asset Suspended Org', 'equipment', 'active');

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;
CREATE FUNCTION pg_temp.notif_count(p_org uuid, p_type text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.organization_notifications WHERE organization_id = p_org AND type = p_type;
$$;
-- Every save_preventive_maintenance_plan / set_preventive_maintenance_plan_active
-- call requires can_manage_preventive_maintenance(): a real owner/admin/manager
-- JWT context, plus the organization being 'active'. Used only for fixture
-- setup — the generators themselves are exercised without any JWT.
CREATE FUNCTION pg_temp.as_owner_authenticated() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'b1000000-0000-0000-0000-000000000001', true);
END;
$$;

-- =========================================================================
-- 1. OT: due-soon / overdue / terminal
-- =========================================================================
INSERT INTO public.requests (id, request_number, description, asset, location, service_type, deadline, status, created_by, organization_id, asset_id, request_type) VALUES
  ('b5000000-0000-0000-0000-000000000001', 'WO-REQ-1', 'x', 'Asset A', 'Planta', 'preventivo', now() + interval '1 day', 'draft', 'x@x.test', 'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'internal'),
  ('b5000000-0000-0000-0000-000000000002', 'WO-REQ-2', 'x', 'Asset A', 'Planta', 'preventivo', now() + interval '1 day', 'draft', 'x@x.test', 'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'internal'),
  ('b5000000-0000-0000-0000-000000000003', 'WO-REQ-3', 'x', 'Asset A', 'Planta', 'preventivo', now() + interval '1 day', 'draft', 'x@x.test', 'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'internal'),
  ('b5000000-0000-0000-0000-000000000004', 'WO-REQ-4', 'x', 'Asset A', 'Planta', 'preventivo', now() + interval '1 day', 'draft', 'x@x.test', 'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'internal');

INSERT INTO public.work_orders (id, request_id, client_organization_id, provider_organization_id, status, title, asset_id, work_order_type, priority, due_at, assigned_member_id) VALUES
  ('b6000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'b2000000-0000-0000-0000-00000000000a', 'pending', 'OT due-soon', 'b4000000-0000-0000-0000-000000000001', 'internal', 'medium', now() + interval '2 hours', 'b3000000-0000-0000-0000-000000000004'),
  ('b6000000-0000-0000-0000-000000000002', 'b5000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'b2000000-0000-0000-0000-00000000000a', 'in_progress', 'OT overdue', 'b4000000-0000-0000-0000-000000000001', 'internal', 'medium', now() - interval '2 hours', 'b3000000-0000-0000-0000-000000000004'),
  ('b6000000-0000-0000-0000-000000000003', 'b5000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000a', 'b2000000-0000-0000-0000-00000000000a', 'completed', 'OT completed', 'b4000000-0000-0000-0000-000000000001', 'internal', 'medium', now() - interval '2 hours', NULL),
  ('b6000000-0000-0000-0000-000000000004', 'b5000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-00000000000a', 'b2000000-0000-0000-0000-00000000000a', 'closed', 'OT closed', 'b4000000-0000-0000-0000-000000000001', 'internal', 'medium', now() - interval '2 hours', NULL);

-- Broadcast pool for Tenant A (owner/admin/manager, active) = 4 people:
-- owner, admin, manager, and the manager who doubles as "responsible" in
-- the preventive tests below. Each due-soon/overdue OT notifies those 4
-- plus the assigned technician = 5 per event type.
SELECT is(public.generate_operational_due_notifications_internal(), 10,
  'OT internal generator: 5 recipients (4 broadcast + 1 assigned technician) x 2 non-terminal OTs (due-soon + overdue) = 10');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'work_order_due_soon'), 5::bigint, 'due-soon: 4 broadcast + assigned technician');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'work_order_overdue'), 5::bigint, 'overdue: 4 broadcast + assigned technician');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.organization_notifications WHERE entity_id = 'b6000000-0000-0000-0000-000000000003'), 'completed OT never alerts');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.organization_notifications WHERE entity_id = 'b6000000-0000-0000-0000-000000000004'), 'closed OT never alerts');

-- =========================================================================
-- 2. Inspecciones: before_due, múltiples umbrales, overdue, next cycle, timezone
-- =========================================================================
INSERT INTO public.checklist_templates (id, organization_id, name) VALUES
  ('b7000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'Template A');

INSERT INTO public.inspection_plans (id, organization_id, template_id, asset_id, title, next_due_at, responsible_member_id, is_active) VALUES
  ('b8000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'b7000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'Plan Multi-Threshold', now() + interval '3 days', 'b3000000-0000-0000-0000-000000000003', true),
  ('b8000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'b7000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'Plan Overdue', now() - interval '1 day', 'b3000000-0000-0000-0000-000000000003', true);

INSERT INTO public.inspection_plan_alert_rules (id, plan_id, organization_id, alert_type, days_before, is_active) VALUES
  ('b9000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'before_due', 7, true),
  ('b9000000-0000-0000-0000-000000000002', 'b8000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'before_due', 2, true),
  ('b9000000-0000-0000-0000-000000000003', 'b8000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'overdue', NULL, true);

-- Plan due in 3 days: only the 7-day-before rule has started (the 2-day
-- one has not yet), so exactly one threshold fires. responsible_member_id
-- here is the plain manager (b3...03), already counted in the broadcast —
-- dedup collapses it to 4 distinct recipients, same pool as the OT tests.
SELECT is(public.generate_inspection_due_notifications_internal(), 8,
  'inspection internal generator: 4 distinct recipients for the due plan (only the 7-day threshold has started; the 2-day one has not) + 4 for the overdue plan = 8');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'inspection_due_soon_future'), 4::bigint, 'exactly the 7-day threshold fired for 4 distinct recipients');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'inspection_overdue_future'), 4::bigint, 'overdue plan fired for 4 distinct recipients');

-- Next cycle: advancing next_due_at re-alerts (different synthetic entity_id).
UPDATE public.inspection_plans SET next_due_at = now() + interval '10 days' WHERE id = 'b8000000-0000-0000-0000-000000000002';
UPDATE public.inspection_plan_alert_rules SET alert_type = 'before_due', days_before = 10 WHERE id = 'b9000000-0000-0000-0000-000000000003';
SELECT is(public.generate_inspection_due_notifications_internal(), 4, 'next cycle (advanced next_due_at) re-alerts with a fresh synthetic entity_id (4 new distinct recipients)');
SELECT is((SELECT count(DISTINCT entity_id) FROM public.organization_notifications WHERE type = 'inspection_due_soon_future' AND entity_type = 'inspection_plan'), 2::bigint,
  'two distinct synthetic entity_ids so far (the original 7-day threshold, and the advanced 10-day-as-before_due cycle) — never colliding');

-- Timezone: the synthetic entity_id the FUNCTION actually produces must be
-- byte-identical regardless of the CALLER's ambient session TimeZone — a
-- real functional test, not a hand-recomputed hash (a timestamptz cast to
-- text always embeds the session's offset, e.g. "+00" vs "-05", so
-- comparing two such casts directly would always differ regardless of any
-- fix; what matters is that the function's own SET timezone = 'UTC'
-- shields its internal computation from whatever the caller's session is
-- set to). Fresh plan/rule, isolated from the rest of this section.
INSERT INTO public.inspection_plans (id, organization_id, template_id, asset_id, title, next_due_at, is_active) VALUES
  ('b8000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000a', 'b7000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 'Plan TZ Test', now() + interval '4 days', true);
INSERT INTO public.inspection_plan_alert_rules (id, plan_id, organization_id, alert_type, days_before, is_active) VALUES
  ('b9000000-0000-0000-0000-000000000004', 'b8000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000a', 'before_due', 5, true);

SET LOCAL TimeZone = 'UTC';
SELECT public.generate_inspection_due_notifications_internal() AS tz_utc_count \gset
SELECT entity_id AS tz_hash_utc FROM public.organization_notifications WHERE entity_type = 'inspection_plan' AND (metadata->>'plan_id')::uuid = 'b8000000-0000-0000-0000-000000000003' LIMIT 1 \gset
DELETE FROM public.organization_notifications WHERE entity_type = 'inspection_plan' AND (metadata->>'plan_id')::uuid = 'b8000000-0000-0000-0000-000000000003';

SET LOCAL TimeZone = 'America/Lima';
SELECT public.generate_inspection_due_notifications_internal() AS tz_lima_count \gset
SELECT entity_id AS tz_hash_lima FROM public.organization_notifications WHERE entity_type = 'inspection_plan' AND (metadata->>'plan_id')::uuid = 'b8000000-0000-0000-0000-000000000003' LIMIT 1 \gset

SELECT is(:'tz_hash_lima'::uuid, :'tz_hash_utc'::uuid,
  'calling the internal generator under session TimeZone=America/Lima produces the EXACT SAME synthetic entity_id as under TimeZone=UTC — the function''s own SET timezone = ''UTC'' works');
RESET TimeZone;

-- =========================================================================
-- 3. Preventivo: calendario, medidor, y todas las exclusiones
-- =========================================================================
INSERT INTO public.maintenance_cards (id, organization_id, code, name) VALUES
  ('ba000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'CARD-A', 'Card A'),
  ('ba000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000c', 'CARD-C', 'Card C');

SELECT pg_temp.as_owner_authenticated();
SET LOCAL ROLE authenticated;

-- 3.1 Calendar plan (active), due soon. responsible = manager b3...05
-- (also in the broadcast pool) -> exercises the dedup mechanism for real.
SELECT public.save_preventive_maintenance_plan(
  'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
  'calendar', 'medium', 'internal', 'b3000000-0000-0000-0000-000000000005', 3, 'monthly', NULL, NULL,
  now() + interval '2 days', NULL, NULL, NULL, NULL, NULL
);
-- 3.2 Calendar plan, INACTIVE — must never alert.
SELECT public.save_preventive_maintenance_plan(
  'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
  'calendar', 'medium', 'internal', 'b3000000-0000-0000-0000-000000000005', 3, 'monthly', NULL, NULL,
  now() + interval '1 hour', NULL, NULL, NULL, NULL, NULL
);
SELECT public.set_preventive_maintenance_plan_active(
  (SELECT id FROM public.preventive_maintenance_plans WHERE first_due_at = now() + interval '1 hour' AND asset_id = 'b4000000-0000-0000-0000-000000000001'),
  false, 'test: inactive plan must not alert'
);
-- 3.3 Calendar plan on an ARCHIVED asset — must never alert.
SELECT public.save_preventive_maintenance_plan(
  'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000002', 'ba000000-0000-0000-0000-000000000001',
  'calendar', 'medium', 'internal', 'b3000000-0000-0000-0000-000000000005', 3, 'monthly', NULL, NULL,
  now() + interval '1 hour', NULL, NULL, NULL, NULL, NULL
);
-- 3.4 Calendar plan for the "suspended organization" test — created WHILE
-- that organization is still active (can_manage_preventive_maintenance
-- requires an active organization to even create a plan), suspended
-- immediately afterward.
SELECT public.save_preventive_maintenance_plan(
  'b2000000-0000-0000-0000-00000000000c', 'b4000000-0000-0000-0000-000000000003', 'ba000000-0000-0000-0000-000000000002',
  'calendar', 'medium', 'internal', NULL, 3, 'monthly', NULL, NULL,
  now() + interval '1 hour', NULL, NULL, NULL, NULL, NULL
);
-- 3.5 Calendar plan, OVERDUE, with a responsible member that is INACTIVE
-- by the time the generator runs — the role broadcast (4 people) must
-- still fire; only the direct notify to the inactive responsible must not.
-- check_preventive_plan_consistency requires an ACTIVE owner/admin/manager
-- at ASSIGNMENT time, so b3...006 is reactivated just long enough to be
-- assigned, then deactivated again immediately (organization_members has
-- no direct UPDATE grant for authenticated since the Punto 6B hardening,
-- so this happens as postgres, outside the authenticated role context).
RESET ROLE;
UPDATE public.organization_members SET is_active = true WHERE id = 'b3000000-0000-0000-0000-000000000006';
SELECT pg_temp.as_owner_authenticated();
SET LOCAL ROLE authenticated;
SELECT public.save_preventive_maintenance_plan(
  'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
  'calendar', 'high', 'internal', 'b3000000-0000-0000-0000-000000000006', 3, 'monthly', NULL, NULL,
  now() - interval '2 days', NULL, NULL, NULL, NULL, NULL
);
RESET ROLE;
UPDATE public.organization_members SET is_active = false WHERE id = 'b3000000-0000-0000-0000-000000000006';
-- Suspend Tenant C AFTER its plan/occurrence already exist, as postgres
-- (bypasses RLS) — this is the realistic path: an organization suspended
-- after having active preventive plans.
UPDATE public.organizations SET status = 'suspended' WHERE id = 'b2000000-0000-0000-0000-00000000000c';

SELECT is(public.generate_preventive_due_notifications(), 8,
  'preventive calendar: 4 distinct recipients for the due plan (3.1) + 4 for the overdue plan (3.5, inactive responsible excluded from its own direct notify but still counted in the broadcast) = 8; inactive plan (3.2), archived asset (3.3) and suspended org (3.4) contribute 0');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'preventive_maintenance_due'), 4::bigint, 'calendar due: 4 distinct recipients (dedup collapses the responsible/manager overlap)');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'preventive_maintenance_overdue'), 4::bigint, 'calendar overdue: 4 distinct recipients from the broadcast; the inactive responsible member is excluded from receiving a SECOND (direct) notification, not just deduped');
SELECT is((SELECT count(*) FROM public.organization_notifications WHERE organization_id = 'b2000000-0000-0000-0000-00000000000c'), 0::bigint, 'suspended organization: zero alerts even though its plan/occurrence exist');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.organization_notifications WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000006'), 'the inactive responsible member never received a notification of any kind');

-- 3.6 Meter plan: due, overdue, no-reading (baseline reading voided after
-- plan creation, leaving zero effective readings).
INSERT INTO public.asset_meters (id, organization_id, asset_id, name, unit) VALUES
  ('bb000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'Horómetro', 'horas'),
  ('bb000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'Horómetro sin lectura efectiva', 'horas');

INSERT INTO public.asset_meter_readings (id, meter_id, value, recorded_at) VALUES
  ('bc000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 100, now() - interval '10 days'),
  ('bc000000-0000-0000-0000-000000000005', 'bb000000-0000-0000-0000-000000000002', 0, now() - interval '10 days');

SELECT pg_temp.as_owner_authenticated();
SET LOCAL ROLE authenticated;
-- due_meter_value = baseline(100) + interval_value(100) = 200; lead=10 ->
-- due window [190,200].
SELECT public.save_preventive_maintenance_plan(
  'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
  'meter', 'urgent', 'internal', NULL, 0, NULL, NULL, NULL,
  NULL, 'bb000000-0000-0000-0000-000000000001', 100, 'bc000000-0000-0000-0000-000000000001', 10
);
-- "no effective reading" plan: has a valid baseline at creation time, then
-- that baseline gets voided directly below, leaving the meter with zero
-- effective readings for the generator to evaluate.
SELECT public.save_preventive_maintenance_plan(
  'b2000000-0000-0000-0000-00000000000a', 'b4000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
  'meter', 'medium', 'internal', NULL, 0, NULL, NULL, NULL,
  NULL, 'bb000000-0000-0000-0000-000000000002', 10, 'bc000000-0000-0000-0000-000000000005', 5
);
RESET ROLE;
UPDATE public.asset_meter_readings SET voided_at = now(), void_reason = 'test: force no effective reading' WHERE id = 'bc000000-0000-0000-0000-000000000005';

-- A newer, VOIDED reading of 195 must be ignored; the latest EFFECTIVE
-- reading (190) is what actually falls in the due window [190,200].
INSERT INTO public.asset_meter_readings (id, meter_id, value, recorded_at, voided_at, void_reason) VALUES
  ('bc000000-0000-0000-0000-000000000002', 'bb000000-0000-0000-0000-000000000001', 195, now() - interval '1 hour', now(), 'test void');
INSERT INTO public.asset_meter_readings (id, meter_id, value, recorded_at) VALUES
  ('bc000000-0000-0000-0000-000000000003', 'bb000000-0000-0000-0000-000000000001', 190, now() - interval '2 hours');

SELECT is(public.generate_preventive_due_notifications(), 4,
  'meter due: the latest EFFECTIVE reading (190; the newer but voided 195 is ignored) falls in [190,200] -> 4 distinct recipients; the no-effective-reading meter plan contributes 0');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'preventive_maintenance_due'), 8::bigint, '4 calendar-due (already deduped, unchanged) + 4 new meter-due');
SELECT is((SELECT count(*) FROM public.organization_notifications n JOIN public.preventive_maintenance_plans p ON p.id = (n.metadata->>'plan_id')::uuid WHERE p.meter_id = 'bb000000-0000-0000-0000-000000000002'), 0::bigint,
  'the meter plan with zero effective readings (voided baseline) never alerts — a voided reading correctly behaves as "no reading" for this purpose');

-- Meter overdue: record a reading past due_meter_value.
INSERT INTO public.asset_meter_readings (id, meter_id, value, recorded_at) VALUES
  ('bc000000-0000-0000-0000-000000000004', 'bb000000-0000-0000-0000-000000000001', 250, now());
SELECT is(public.generate_preventive_due_notifications(), 4, 'meter overdue: crossing due_meter_value fires the overdue type for 4 distinct recipients (the due-type alert for this same occurrence stays deduped, unaffected)');
SELECT is(pg_temp.notif_count('b2000000-0000-0000-0000-00000000000a', 'preventive_maintenance_overdue'), 8::bigint, '4 calendar-overdue + 4 meter-overdue');

-- Terminal occurrence: cancelling it must stop it from alerting again.
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences WHERE plan_id = (SELECT id FROM public.preventive_maintenance_plans WHERE meter_id = 'bb000000-0000-0000-0000-000000000001')), 'open', 'sanity: the meter occurrence is still open before we terminate it');
UPDATE public.preventive_maintenance_occurrences SET status = 'cancelled', cancelled_at = now(), cancel_reason = 'test'
WHERE plan_id = (SELECT id FROM public.preventive_maintenance_plans WHERE meter_id = 'bb000000-0000-0000-0000-000000000001') AND status = 'open';
SELECT (SELECT count(*) FROM public.organization_notifications) AS n_before_cancel_check \gset
SELECT public.generate_preventive_due_notifications() AS discard_count \gset
SELECT is((SELECT count(*) FROM public.organization_notifications), :n_before_cancel_check::bigint, 'a cancelled occurrence produces zero new alerts on the next run (terminal occurrences are excluded by status IN (open, planned))');

-- =========================================================================
-- 4. Aislamiento por tenant
-- =========================================================================
SELECT is((SELECT count(*) FROM public.organization_notifications WHERE organization_id = 'b2000000-0000-0000-0000-00000000000b'), 0::bigint, 'Tenant B has zero notifications from any generator run so far');

-- =========================================================================
-- 5. Concurrencia: 10 corridas simultáneas -> 0 duplicados, lock demostrado
--
-- DELIBERADAMENTE antes de cualquier llamada directa a
-- run_automatic_alert_generation() dentro de esta misma transacción de
-- prueba: pg_try_advisory_xact_lock es reentrante para la MISMA
-- transacción/sesión (una segunda llamada en la misma transacción vuelve a
-- adquirirlo trivialmente, nunca compite consigo misma), pero SÍ bloquea a
-- cualquier OTRA sesión mientras la transacción que lo tomó siga abierta.
-- Como todo este archivo vive en un único BEGIN/ROLLBACK, si primero
-- llamáramos al wrapper directamente aquí (sesión actual) y DESPUÉS
-- lanzáramos las 10 conexiones dblink (sesiones nuevas), las 10
-- externas encontrarían el lock ya tomado por esta transacción — que
-- nunca hace COMMIT hasta el final del archivo — y las 10 quedarían
-- "already_running" sin excepción. Verificado empíricamente: ese fue
-- exactamente el primer resultado obtenido con el orden invertido.
-- =========================================================================
-- automatic_alert_runs se llena vía conexiones dblink reales (sesiones
-- aparte que hacen su propio COMMIT), así que esas filas sobreviven al
-- ROLLBACK final de este archivo. Si esta suite se corre más de una vez
-- contra la misma base local sin `db reset` de por medio, la tabla puede
-- traer filas de corridas anteriores: por eso la sección 7 mide un DELTA
-- desde esta marca de tiempo, nunca un conteo absoluto.
SELECT clock_timestamp() AS alert_runs_watermark \gset
SELECT (SELECT count(*) FROM public.organization_notifications) AS n_before_concurrency \gset
DO $$
DECLARE i integer; BEGIN
  FOR i IN 1..10 LOOP
    PERFORM dblink_connect('alerts_c' || i, 'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres');
    PERFORM dblink_send_query('alerts_c' || i, 'SELECT public.run_automatic_alert_generation()');
  END LOOP;
END $$;
DO $$
DECLARE i integer; v_result text; v_skipped integer := 0; v_ok integer := 0; BEGIN
  FOR i IN 1..10 LOOP
    SELECT result INTO v_result FROM dblink_get_result('alerts_c' || i) AS t(result text);
    IF v_result::jsonb ? 'skipped' THEN v_skipped := v_skipped + 1; ELSE v_ok := v_ok + 1; END IF;
    PERFORM dblink_disconnect('alerts_c' || i);
  END LOOP;
  PERFORM set_config('pgtap.concurrency_ok', v_ok::text, false);
  PERFORM set_config('pgtap.concurrency_skipped', v_skipped::text, false);
END $$;
SELECT ok(current_setting('pgtap.concurrency_ok')::integer >= 1, 'at least one of the 10 concurrent runs actually executed');
-- NOTA: NO afirmamos aquí "al menos una de las 10 quedó skipped". Es una
-- carrera real entre 10 conexiones async: si no llegan a solaparse en el
-- tiempo (sistema rápido/poco cargado), las 10 pueden ganar el lock en
-- secuencia sin contienda real, sin que eso indique ningún defecto. Verificado
-- empíricamente: en corridas repetidas de esta misma suite, el reparto ok/
-- skipped varía. La prueba 5b de abajo demuestra el bloqueo del lock de forma
-- determinística (sin azar), que es la evidencia real de que funciona.
SELECT is((current_setting('pgtap.concurrency_ok')::integer + current_setting('pgtap.concurrency_skipped')::integer), 10, 'all 10 concurrent invocations accounted for (ran or skipped)');
SELECT is((SELECT count(*) FROM public.organization_notifications), :n_before_concurrency::bigint, '10 concurrent runs produced ZERO additional notification rows (full dedup, even under real concurrency)');

-- =========================================================================
-- 5b. Prueba determinística (sin azar) de que el lock realmente bloquea:
-- una sesión externa (dblink) toma el advisory lock y lo mantiene abierto
-- (BEGIN sin COMMIT en esa conexión nombrada); esta sesión de prueba llama
-- al wrapper directamente y DEBE recibir skipped, siempre, sin depender de
-- ningún solapamiento temporal. Luego la sesión externa libera el lock
-- (ROLLBACK) y una nueva llamada debe ejecutarse con normalidad.
--
-- Se ejecuta DESPUÉS del bloque de 10 conexiones de arriba (no antes): la
-- llamada final "unblocked_result" adquiere el lock en ESTA sesión/
-- transacción y lo mantiene hasta el ROLLBACK final del archivo (ver nota
-- de reentrancia al inicio de la sección 5) — si esto corriera antes de las
-- 10 conexiones externas, las 10 encontrarían el lock ya tomado por esta
-- misma transacción y quedarían skipped sin excepción, igual que el bug ya
-- documentado más arriba.
-- =========================================================================
SELECT dblink_connect('alerts_lockholder', 'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres');
SELECT dblink_exec('alerts_lockholder', 'BEGIN');
SELECT locked AS lockholder_locked FROM dblink('alerts_lockholder', 'SELECT pg_try_advisory_xact_lock(728471001)') AS t(locked boolean) \gset
SELECT ok(:'lockholder_locked'::boolean, 'test setup: the external dblink session successfully acquired the advisory lock');
SELECT run_automatic_alert_generation() AS blocked_result \gset
SELECT ok((:'blocked_result'::jsonb ? 'skipped'), 'while an external session holds the advisory lock, the wrapper deterministically reports skipped (no timing race)');
SELECT dblink_exec('alerts_lockholder', 'ROLLBACK');
SELECT dblink_disconnect('alerts_lockholder');
SELECT run_automatic_alert_generation() AS unblocked_result \gset
SELECT ok(NOT (:'unblocked_result'::jsonb ? 'skipped'), 'once the external session releases the lock, the wrapper executes normally again');

-- =========================================================================
-- 6. Deduplicación: 2 corridas consecutivas del wrapper no duplican nada
-- (ahora en ESTA sesión/transacción — ya no compite con nada externo)
-- =========================================================================
SELECT (SELECT count(*) FROM public.organization_notifications) AS n_before \gset
SELECT run_automatic_alert_generation() AS run1_result \gset
SELECT run_automatic_alert_generation() AS run2_result \gset
SELECT is((SELECT count(*) FROM public.organization_notifications), :n_before::bigint, 'running the wrapper twice in a row inserts zero additional rows (full dedup)');
SELECT ok((:'run1_result'::jsonb -> 'generators' -> 'operational' ->> 'status') = 'ok', 'run1: operational generator reports status ok');
SELECT ok((:'run2_result'::jsonb -> 'generators' -> 'preventive' ->> 'status') = 'ok', 'run2: preventive generator reports status ok');

-- =========================================================================
-- 7. automatic_alert_runs: cada corrida queda registrada
-- =========================================================================
SELECT is((SELECT count(*) FROM public.automatic_alert_runs WHERE finished_at >= :'alert_runs_watermark'::timestamptz), (current_setting('pgtap.concurrency_ok')::integer + 3)::bigint,
  'automatic_alert_runs has one row per SUCCESSFUL run so far: however many of the 10 concurrent calls actually executed, plus the unblocked_result call from 5b, plus the 2 sequential ones just above (skipped runs never insert a row)');
SELECT ok((SELECT bool_and(had_errors = false) FROM public.automatic_alert_runs WHERE finished_at >= :'alert_runs_watermark'::timestamptz), 'none of the successful runs so far reported had_errors (nothing was broken yet)');

-- =========================================================================
-- 8. Aislamiento de errores por generador (el wrapper no se detiene)
-- =========================================================================
SAVEPOINT before_forced_failure;
ALTER TABLE public.checklist_templates RENAME TO checklist_templates_hidden_for_test;
SELECT run_automatic_alert_generation() AS failure_result \gset
SELECT ok((:'failure_result'::jsonb -> 'generators' -> 'inspection' ->> 'status') = 'error', 'with checklist_templates hidden, the inspection generator specifically reports status=error');
SELECT ok((:'failure_result'::jsonb -> 'generators' -> 'inspection' ->> 'sqlstate') IS NOT NULL, 'the error result includes a SQLSTATE');
SELECT ok((:'failure_result'::jsonb -> 'generators' -> 'operational' ->> 'status') = 'ok', 'operational generator is UNAFFECTED by the inspection failure (isolation works)');
SELECT ok((:'failure_result'::jsonb -> 'generators' -> 'preventive' ->> 'status') = 'ok', 'preventive generator is UNAFFECTED by the inspection failure (isolation works)');
-- created_at/started_at both use now(), frozen for the whole test
-- transaction — ORDER BY that would tie across every run. finished_at
-- comes from clock_timestamp() (real wall-clock time, strictly increasing
-- even within one transaction), so it is what actually identifies "the
-- most recent run".
SELECT is((SELECT had_errors FROM public.automatic_alert_runs ORDER BY finished_at DESC LIMIT 1), true, 'the run with a forced failure is recorded with had_errors = true');
SELECT ok(NOT ((:'failure_result')::text ILIKE '%SELECT%FROM%'), 'the stored error message is not a raw SQL query dump');
ROLLBACK TO SAVEPOINT before_forced_failure;

-- =========================================================================
-- 9. Hardening organization_notifications
-- =========================================================================
-- Two independent layers, tested separately: (1) the trigger's own logic —
-- exercised here as `postgres` (full table grant, RLS bypassed, but NOT
-- platform_admin since there is no auth.uid() at all) so the GRANT layer
-- cannot mask whether the TRIGGER itself still rejects these fields; (2)
-- the column-level GRANT, exercised below as `authenticated` — the real
-- PostgREST-equivalent path, which now rejects these same columns before
-- the trigger even runs (belt AND suspenders, per the project's existing
-- "no confiar solo en GRANT" convention).
SELECT throws_ok(
  $$ UPDATE public.organization_notifications SET recipient_member_id = NULL WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004' $$,
  'P0001', 'Organization notifications can only be marked as read', 'TRIGGER layer (as postgres, full grant): rejects recipient_member_id -> NULL');
SELECT throws_ok(
  $$ UPDATE public.organization_notifications SET priority = 'low' WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004' $$,
  'P0001', 'Organization notifications can only be marked as read', 'TRIGGER layer (as postgres, full grant): rejects altering priority');
SELECT throws_ok(
  $$ UPDATE public.organization_notifications SET metadata = '{"forged":true}'::jsonb WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004' $$,
  'P0001', 'Organization notifications can only be marked as read', 'TRIGGER layer (as postgres, full grant): rejects altering metadata');

SELECT pg_temp.as_user('b1000000-0000-0000-0000-000000000004'); -- technician, has a targeted notification from the OT tests
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ UPDATE public.organization_notifications SET recipient_member_id = NULL WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004' $$,
  '42501', NULL, 'GRANT layer (as authenticated, real PostgREST path): recipient_member_id has no column UPDATE grant at all');
SELECT throws_ok(
  $$ UPDATE public.organization_notifications SET priority = 'low' WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004' $$,
  '42501', NULL, 'GRANT layer (as authenticated): priority has no column UPDATE grant at all');
SELECT throws_ok(
  $$ UPDATE public.organization_notifications SET metadata = '{"forged":true}'::jsonb WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004' $$,
  '42501', NULL, 'GRANT layer (as authenticated): metadata has no column UPDATE grant at all');
SELECT lives_ok(
  $$ UPDATE public.organization_notifications SET is_read = true WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004' $$,
  'marking as read still works after the hardening');
SELECT ok((SELECT bool_and(is_read) FROM public.organization_notifications WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004'), 'is_read actually persisted');
SELECT ok((SELECT bool_and(read_at IS NOT NULL) FROM public.organization_notifications WHERE recipient_member_id = 'b3000000-0000-0000-0000-000000000004'), 'read_at was set automatically');
RESET ROLE;

-- Column-level grant check (independent of RLS/trigger).
SELECT ok(has_column_privilege('authenticated', 'public.organization_notifications', 'is_read', 'UPDATE'), 'authenticated can UPDATE is_read (column grant)');
SELECT ok(has_column_privilege('authenticated', 'public.organization_notifications', 'read_at', 'UPDATE'), 'authenticated can UPDATE read_at (column grant)');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organization_notifications', 'priority', 'UPDATE'), 'authenticated has NO column grant to UPDATE priority');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organization_notifications', 'recipient_member_id', 'UPDATE'), 'authenticated has NO column grant to UPDATE recipient_member_id');
SELECT ok(NOT has_column_privilege('authenticated', 'public.organization_notifications', 'metadata', 'UPDATE'), 'authenticated has NO column grant to UPDATE metadata');

-- =========================================================================
-- 10. notify_member respeta membership inactiva (aplica globalmente)
-- =========================================================================
SELECT is((SELECT public.notify_member_counted('b3000000-0000-0000-0000-000000000006', NULL, 'work_order_due_soon', 't', 'm', 'work_order', gen_random_uuid(), 'medium', '{}'::jsonb)), 0,
  'notify_member_counted (and therefore notify_member) is a no-op for an inactive membership');

-- =========================================================================
-- 11. Grants: PUBLIC/anon/authenticated no pueden invocar las piezas internas
-- =========================================================================
SELECT ok(NOT has_function_privilege('authenticated', 'public.run_automatic_alert_generation()', 'EXECUTE'), 'authenticated cannot EXECUTE run_automatic_alert_generation');
SELECT ok(NOT has_function_privilege('anon', 'public.run_automatic_alert_generation()', 'EXECUTE'), 'anon cannot EXECUTE run_automatic_alert_generation');
SELECT ok(NOT has_function_privilege('authenticated', 'public.generate_operational_due_notifications_internal()', 'EXECUTE'), 'authenticated cannot EXECUTE the internal OT generator');
SELECT ok(NOT has_function_privilege('authenticated', 'public.generate_inspection_due_notifications_internal()', 'EXECUTE'), 'authenticated cannot EXECUTE the internal inspection generator');
SELECT ok(NOT has_function_privilege('authenticated', 'public.generate_preventive_due_notifications()', 'EXECUTE'), 'authenticated cannot EXECUTE the preventive generator');
SELECT ok(NOT has_function_privilege('authenticated', 'public.notify_member_counted(uuid,uuid,text,text,text,text,uuid,text,jsonb)', 'EXECUTE'), 'authenticated cannot EXECUTE notify_member_counted');
SELECT ok(NOT has_function_privilege('authenticated', 'public.cleanup_automatic_alert_history()', 'EXECUTE'), 'authenticated cannot EXECUTE cleanup_automatic_alert_history');

-- Hardening final del rollout: los generadores públicos legacy ya no son
-- ejecutables por authenticated. La generación depende del wrapper backend
-- ejecutado por pg_cron.
SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.generate_operational_due_notifications()',
    'EXECUTE'
  ),
  'authenticated cannot EXECUTE the legacy operational notification generator after rollout hardening'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.generate_inspection_due_notifications()',
    'EXECUTE'
  ),
  'authenticated cannot EXECUTE the legacy inspection notification generator after rollout hardening'
);
-- automatic_alert_runs: sin acceso para clientes.
SELECT ok(NOT has_table_privilege('authenticated', 'public.automatic_alert_runs', 'SELECT'), 'authenticated cannot read automatic_alert_runs');
SELECT ok(NOT has_table_privilege('anon', 'public.automatic_alert_runs', 'SELECT'), 'anon cannot read automatic_alert_runs');

-- Índice parcial para las consultas de due-soon/overdue del generador de OT
-- (agregado tras confirmar con EXPLAIN real sobre 100k filas sintéticas que
-- mejora el plan; ver comentario en la migración junto a su CREATE INDEX).
SELECT ok(EXISTS (
  SELECT 1 FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'work_orders' AND indexname = 'idx_work_orders_due_at_active'
), 'the partial index on work_orders(due_at) for non-terminal statuses exists');

-- =========================================================================
-- 12. Cron jobs
-- =========================================================================
SELECT ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'automatic-alert-generation' AND active AND schedule = '5 * * * *'), 'the hourly automatic-alert-generation cron job exists and is active');
SELECT ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'automatic-alert-history-cleanup' AND active), 'the daily automatic-alert-history-cleanup cron job exists and is active');

SELECT * FROM finish();
ROLLBACK;
