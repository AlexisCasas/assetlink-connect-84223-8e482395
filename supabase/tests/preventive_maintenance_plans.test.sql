BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(90);

SELECT has_table('public', 'maintenance_cards', 'maintenance_cards exists');
SELECT has_table('public', 'maintenance_card_tasks', 'maintenance_card_tasks exists');
SELECT has_table('public', 'maintenance_card_materials', 'maintenance_card_materials exists');
SELECT has_table('public', 'asset_meters', 'asset_meters exists');
SELECT has_table('public', 'asset_meter_readings', 'asset_meter_readings exists');
SELECT has_table('public', 'preventive_maintenance_plans', 'preventive_maintenance_plans exists');
SELECT has_table('public', 'preventive_maintenance_occurrences', 'preventive_maintenance_occurrences exists');

INSERT INTO auth.users (id, email)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'owner@test.local'),
  ('10000000-0000-0000-0000-000000000002', 'viewer@test.local'),
  ('10000000-0000-0000-0000-000000000003', 'technician@test.local'),
  ('10000000-0000-0000-0000-000000000004', 'provider@test.local');
INSERT INTO public.organizations (id, name, organization_type)
VALUES
  ('20000000-0000-0000-0000-000000000001', 'Cliente A', 'client_company'),
  ('20000000-0000-0000-0000-000000000002', 'Cliente B', 'client_company'),
  ('20000000-0000-0000-0000-000000000003', 'Proveedor', 'provider_company');
INSERT INTO public.organization_members (id, organization_id, user_id, role)
VALUES
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'viewer'),
  ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'technician'),
  ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000004', 'owner');
INSERT INTO public.assets (id, organization_id, code, name)
VALUES
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'EQ-1', 'Equipo A'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'EQ-2', 'Equipo B'),
  ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'EQ-3', 'Equipo alterno');
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

SELECT lives_ok($$
  SELECT public.save_maintenance_card(
    '20000000-0000-0000-0000-000000000001', 'CARD-A', 'Ficha A', 'Alcance', 'General', 2,
    'Procedimiento', 'Seguridad',
    '[{"title":"Inspeccionar","estimated_hours":1,"is_required":true}]'::jsonb,
    '[{"description":"Lubricante","quantity":2,"unit":"L"}]'::jsonb, NULL
  )
$$, 'card header and children save atomically');
SELECT is((SELECT count(*) FROM public.maintenance_card_tasks), 1::bigint, 'card task saved exactly once');
SELECT ok(EXISTS (SELECT 1 FROM public.maintenance_card_materials WHERE material_id IS NULL), 'free material is stored with null material id');
SELECT throws_matching($$
  SELECT public.save_maintenance_card('20000000-0000-0000-0000-000000000001', 'card-a', 'Duplicada', NULL, NULL, NULL, NULL, NULL, '[]', '[]', NULL)
$$, '.*duplicate key.*', 'card code is case-insensitively unique per tenant');
SELECT lives_ok($$ INSERT INTO public.maintenance_cards (organization_id, code, name) VALUES ('20000000-0000-0000-0000-000000000002', 'CARD-A', 'Ficha otro tenant') $$, 'same card code is allowed in another tenant');
INSERT INTO public.warehouses (id, organization_id, name) VALUES ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'Almacén B');
INSERT INTO public.materials (id, organization_id, warehouse_id, code, name, unit)
VALUES ('51000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001', 'MAT-B', 'Material B', 'und');
SELECT throws_matching($$
  SELECT public.save_maintenance_card(
    '20000000-0000-0000-0000-000000000001', 'CARD-X', 'Cross', NULL, NULL, NULL, NULL, NULL, '[]',
    '[{"material_id":"51000000-0000-0000-0000-000000000001","description":"B","quantity":1,"unit":"und"}]', NULL
  )
$$, '.*belong to this organization.*', 'cross-tenant linked material is rejected');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.maintenance_cards WHERE code = 'CARD-X'), 'failed child validation rolls back card header');

SELECT lives_ok($$
  SELECT public.create_asset_meter(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
    'Horómetro', 'h', 100, now() + interval '1 day', 'base future'
  )
$$, 'meter and initial reading created');
SELECT is((SELECT count(*) FROM public.asset_events WHERE event_type = 'meter_reading_recorded'), 1::bigint, 'initial reading creates one event');
SELECT throws_matching($$
  SELECT public.record_asset_meter_reading(
    (SELECT id FROM public.asset_meters WHERE name = 'Horómetro'), 90, now() + interval '2 days', NULL
  )
$$, '.*lower than the previous.*', 'decreasing reading is rejected');
SELECT lives_ok($$
  SELECT public.correct_asset_meter_reading(
    (SELECT id FROM public.asset_meter_readings WHERE value = 100 AND voided_at IS NULL), 110, 'captura incorrecta', NULL
  )
$$, 'correction creates a replacement');
SELECT ok(EXISTS (SELECT 1 FROM public.asset_meter_readings WHERE value = 100 AND voided_at IS NOT NULL), 'original reading is retained and voided');
SELECT ok(EXISTS (SELECT 1 FROM public.asset_meter_readings replacement JOIN public.asset_meter_readings original ON original.id = replacement.supersedes_reading_id WHERE replacement.value = 110 AND original.value = 100), 'replacement links to original');
SELECT throws_matching($$
  SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Horómetro'), 130, now(), 'incompatible history')
$$, '.*higher than the next.*', 'historical reading must fit its next neighbor');
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
SELECT lives_ok($$
  SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Horómetro'), 120, now() + interval '2 days', 'técnico')
$$, 'technician can record a reading');
SELECT lives_ok($$ SELECT public.get_maintenance_cards('20000000-0000-0000-0000-000000000001', true) $$, 'technician can read preventive cards');
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
SELECT public.create_asset_meter(
  '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
  'Ciclos viejo', 'ciclos', 500, now(), 'antes del reset'
);
SELECT lives_ok($$
  SELECT public.replace_asset_meter((SELECT id FROM public.asset_meters WHERE name = 'Ciclos viejo'), 'Ciclos nuevo', 'ciclos', 0, now(), 'reemplazo físico', NULL)
$$, 'meter replacement supports a new initial value');
SELECT ok(EXISTS (
  SELECT 1 FROM public.asset_meters newer JOIN public.asset_meters older ON older.id = newer.replaces_meter_id
  WHERE newer.name = 'Ciclos nuevo' AND NOT older.is_active AND EXISTS (SELECT 1 FROM public.asset_meter_readings WHERE meter_id = older.id AND value = 500)
), 'meter replacement preserves old meter history');

SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-A' AND organization_id = '20000000-0000-0000-0000-000000000001'), 'calendar', 'medium', 'internal',
    '30000000-0000-0000-0000-000000000001', 7, 'monthly', NULL, NULL,
    '2030-01-15 10:00:00+00', NULL, NULL, NULL, NULL, NULL
  )
$$, 'calendar plan creates');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences WHERE plan_id = (SELECT id FROM public.preventive_maintenance_plans WHERE trigger_type = 'calendar' AND organization_id = '20000000-0000-0000-0000-000000000001')), 1::bigint, 'plan creation creates exactly occurrence one');
SELECT is((SELECT scope_snapshot #>> '{card,name}' FROM public.preventive_maintenance_occurrences WHERE organization_id = '20000000-0000-0000-0000-000000000001'), 'Ficha A', 'occurrence freezes card name');
SELECT is((SELECT scope_snapshot->>'due_at' FROM public.preventive_maintenance_occurrences WHERE organization_id = '20000000-0000-0000-0000-000000000001'), '2030-01-15T10:00:00+00:00', 'snapshot includes the due value');
SELECT lives_ok($$
  SELECT public.save_maintenance_card(
    '20000000-0000-0000-0000-000000000001', 'CARD-A', 'Ficha A editada', NULL, NULL, 3, NULL, NULL,
    '[{"title":"Nueva tarea"}]', '[]', (SELECT id FROM public.maintenance_cards WHERE organization_id = '20000000-0000-0000-0000-000000000001' AND code = 'CARD-A')
  )
$$, 'card can be edited after occurrence snapshot');
SELECT is((SELECT scope_snapshot #>> '{card,name}' FROM public.preventive_maintenance_occurrences WHERE organization_id = '20000000-0000-0000-0000-000000000001'), 'Ficha A', 'editing card does not rewrite occurrence snapshot');
CREATE TEMP TABLE test_due AS SELECT id, due_at FROM public.preventive_maintenance_occurrences WHERE plan_id = (SELECT id FROM public.preventive_maintenance_plans WHERE trigger_type = 'calendar' AND organization_id = '20000000-0000-0000-0000-000000000001');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-A' AND organization_id = '20000000-0000-0000-0000-000000000001'), 'calendar', 'high', 'external',
    NULL, 14, 'monthly', NULL, NULL, '2031-01-15 10:00:00+00', NULL, NULL, NULL, NULL,
    (SELECT id FROM public.preventive_maintenance_plans WHERE trigger_type = 'calendar' AND organization_id = '20000000-0000-0000-0000-000000000001')
  )
$$, 'plan mutable fields edit');
SELECT is((SELECT due_at FROM public.preventive_maintenance_occurrences WHERE id = (SELECT id FROM test_due)), (SELECT due_at FROM test_due), 'editing plan does not move current cycle');
SELECT throws_matching($$ SELECT public.set_maintenance_card_active((SELECT id FROM public.maintenance_cards WHERE code = 'CARD-A' AND organization_id = '20000000-0000-0000-0000-000000000001'), false) $$, '.*active preventive.*', 'active plan blocks card deactivation');
SELECT lives_ok($$ SELECT public.skip_preventive_maintenance_occurrence((SELECT id FROM test_due), 'parada de planta reprogramada') $$, 'open cycle can be skipped');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences WHERE plan_id = (SELECT plan_id FROM public.preventive_maintenance_occurrences WHERE id = (SELECT id FROM test_due))), 2::bigint, 'skip creates exactly one next cycle');
SELECT is(
  (SELECT due_at FROM public.preventive_maintenance_occurrences WHERE status = 'open' AND plan_id = (SELECT plan_id FROM public.preventive_maintenance_occurrences WHERE id = (SELECT id FROM test_due))),
  (SELECT due_at + interval '1 month' FROM test_due),
  'skipped calendar cadence uses old due date'
);
SELECT lives_ok($$ SELECT public.skip_preventive_maintenance_occurrence((SELECT id FROM test_due), 'retry') $$, 'skip retry is idempotent');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences WHERE plan_id = (SELECT plan_id FROM public.preventive_maintenance_occurrences WHERE id = (SELECT id FROM test_due))), 2::bigint, 'skip retry creates no duplicate');
SELECT throws_matching($$
  INSERT INTO public.preventive_maintenance_occurrences (organization_id, plan_id, asset_id, sequence, due_at, scope_snapshot)
  SELECT organization_id, plan_id, asset_id, 99, due_at + interval '1 month', '{"schema_version":1}'
  FROM public.preventive_maintenance_occurrences WHERE plan_id = (SELECT plan_id FROM public.preventive_maintenance_occurrences WHERE id = (SELECT id FROM test_due)) AND status = 'open'
$$, '.*uq_preventive_occurrences_one_current.*', 'database permits only one open or planned occurrence per plan');
SELECT throws_matching($$ UPDATE public.preventive_maintenance_occurrences SET scope_snapshot = '{}' WHERE id = (SELECT id FROM test_due) $$, '.*immutable.*', 'occurrence scope snapshot is immutable');

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
SELECT lives_ok($$ SELECT public.get_maintenance_cards('20000000-0000-0000-0000-000000000001', true) $$, 'viewer can read its tenant preventive cards');
SELECT throws_matching($$
  SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Horómetro'), 120, now() + interval '2 days', NULL)
$$, '.*Not authorized.*', 'viewer cannot record a meter reading');
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
SELECT throws_matching($$ SELECT public.get_maintenance_cards('20000000-0000-0000-0000-000000000001', true) $$, '.*Not authorized.*', 'provider cannot read client preventive domain');
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

SELECT throws_matching($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-A' AND organization_id = '20000000-0000-0000-0000-000000000001'), 'meter', 'medium', 'internal', NULL, 0,
    NULL, NULL, NULL, NULL, (SELECT id FROM public.asset_meters WHERE name = 'Horómetro'), 50,
    (SELECT id FROM public.asset_meter_readings WHERE value = 110 AND voided_at IS NULL), 50, NULL
  )
$$, '.*violates check constraint.*', 'meter lead equal to interval is rejected');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'CARD-A' AND organization_id = '20000000-0000-0000-0000-000000000001'), 'meter', 'medium', 'internal', NULL, 0,
    NULL, NULL, NULL, NULL, (SELECT id FROM public.asset_meters WHERE name = 'Horómetro'), 50,
    (SELECT id FROM public.asset_meter_readings WHERE value = 110 AND voided_at IS NULL), 10, NULL
  )
$$, 'valid meter plan creates');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'), 1::bigint, 'meter plan has exactly one first occurrence');

INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
)
SELECT o.request_creation_id, 'MP-TEST-1', 'Preventivo', 'Equipo A', 'Planta', 'preventivo', now() + interval '3 days', 'draft',
  'owner@test.local', o.organization_id, '40000000-0000-0000-0000-000000000003', 'internal'
FROM public.preventive_maintenance_occurrences o
JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001';
SELECT throws_matching($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'),
    (SELECT id FROM public.requests WHERE request_number = 'MP-TEST-1')
  )
$$, '.*tenant, asset and service type.*', 'request with another asset is rejected after persistence');
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'), 'open', 'failed linking leaves occurrence open for retry');
UPDATE public.requests SET asset_id = '40000000-0000-0000-0000-000000000001', service_type = 'correctivo' WHERE request_number = 'MP-TEST-1';
SELECT throws_matching($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'),
    (SELECT id FROM public.requests WHERE request_number = 'MP-TEST-1')
  )
$$, '.*tenant, asset and service type.*', 'non-preventive request is rejected');
UPDATE public.requests SET service_type = 'preventivo' WHERE request_number = 'MP-TEST-1';
SELECT lives_ok($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'),
    (SELECT o.request_creation_id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001')
  )
$$, 'request with exact creation id links');
SELECT lives_ok($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'),
    (SELECT id FROM public.requests WHERE request_number = 'MP-TEST-1')
  )
$$, 'same occurrence and request link is idempotent');
SELECT is((SELECT request_id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'), (SELECT id FROM public.requests WHERE request_number = 'MP-TEST-1'), 'durable request creation id is reused after link failures');
INSERT INTO public.work_orders (
  request_id, client_organization_id, provider_organization_id, status,
  title, asset_id, work_order_type, priority
)
SELECT r.id, r.organization_id, r.organization_id, 'pending', 'OT preventiva', r.asset_id, 'internal', 'medium'
FROM public.requests r WHERE r.request_number = 'MP-TEST-1';
SELECT ok(EXISTS (SELECT 1 FROM public.preventive_maintenance_occurrences WHERE work_order_id IS NOT NULL AND status = 'planned'), 'work order insert attaches to planned occurrence');
SELECT lives_ok($$ UPDATE public.work_orders SET status = 'in_progress' WHERE title = 'OT preventiva' $$, 'first in-progress transition succeeds');
CREATE TEMP TABLE test_work_order_times AS SELECT id, started_at, completed_at FROM public.work_orders WHERE title = 'OT preventiva';
SELECT ok((SELECT started_at IS NOT NULL FROM test_work_order_times), 'first in-progress transition fixes started_at');
UPDATE public.work_orders SET status = 'pending' WHERE title = 'OT preventiva';
UPDATE public.work_orders SET status = 'in_progress' WHERE title = 'OT preventiva';
SELECT is((SELECT started_at FROM public.work_orders WHERE title = 'OT preventiva'), (SELECT started_at FROM test_work_order_times), 'started_at is never reset on later transitions');
SELECT throws_matching($$
  UPDATE public.work_orders SET status = 'completed', completed_at = now() WHERE title = 'OT preventiva'
$$, '.*Registra una lectura actual del medidor Horómetro.*', 'meter maintenance cannot complete without effective reading and names the meter');
SELECT ok((SELECT status <> 'completed' AND completed_at IS NULL FROM public.work_orders WHERE title = 'OT preventiva'), 'failed preventive completion rolls back work-order status and timestamp');
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'OT preventiva')), 'planned', 'failed preventive completion leaves the occurrence planned');
SELECT is((SELECT completion_meter_reading_id FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'OT preventiva')), NULL::uuid, 'failed preventive completion stores no meter reading');
SELECT is((SELECT completion_meter_value FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'OT preventiva')), NULL::numeric, 'failed preventive completion stores no meter value');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences WHERE plan_id = (SELECT plan_id FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'OT preventiva'))), 1::bigint, 'failed preventive completion creates no next occurrence');
SELECT lives_ok($$
  SELECT public.record_asset_meter_reading(
    (SELECT id FROM public.asset_meters WHERE name = 'Horómetro'),
    105,
    (SELECT planned_at FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'OT preventiva')),
    'cierre'
  )
$$, 'completion reading recorded exactly at the planned occurrence is valid');
SELECT lives_ok($$ UPDATE public.work_orders SET status = 'completed', completed_at = now() WHERE title = 'OT preventiva' $$, 'terminal transition completes occurrence');
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'OT preventiva')), 'completed', 'occurrence is completed atomically');
SELECT is(
  (SELECT due_meter_value FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001' AND o.status = 'open'),
  155::numeric,
  'next meter cycle uses completion reading plus interval'
);
UPDATE test_work_order_times SET completed_at = (SELECT completed_at FROM public.work_orders WHERE title = 'OT preventiva');
SELECT lives_ok($$ UPDATE public.work_orders SET status = 'closed' WHERE title = 'OT preventiva' $$, 'completed to closed is safe');
SELECT is((SELECT completed_at FROM public.work_orders WHERE title = 'OT preventiva'), (SELECT completed_at FROM test_work_order_times), 'completed_at is fixed only once');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'), 2::bigint, 'completed to closed creates no duplicate cycle');
INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
) VALUES (
  '91000000-0000-0000-0000-000000000001', 'NORMAL-OT-1', 'Correctivo normal', 'Equipo A', 'Planta',
  'correctivo', now() + interval '1 day', 'sent', 'owner@test.local',
  '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'internal'
);
INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
) VALUES (
  '91000000-0000-0000-0000-000000000002', 'NORMAL-OT-2', 'Correctivo alterno', 'Equipo A', 'Planta',
  'correctivo', now() + interval '1 day', 'sent', 'owner@test.local',
  '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'internal'
);
INSERT INTO public.work_orders (
  request_id, client_organization_id, provider_organization_id, status, title, asset_id, work_order_type, priority
) VALUES (
  '91000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001', 'pending', 'OT normal no preventiva',
  '40000000-0000-0000-0000-000000000001', 'internal', 'medium'
);
SELECT lives_ok($$ UPDATE public.work_orders SET status = 'completed' WHERE title = 'OT normal no preventiva' $$, 'normal non-preventive work order still completes');
SELECT is((SELECT status FROM public.work_orders WHERE title = 'OT normal no preventiva'), 'completed', 'normal work order keeps its terminal state');
SELECT is((SELECT count(*) FROM public.asset_events WHERE organization_id = '20000000-0000-0000-0000-000000000001' AND event_type = 'preventive_maintenance_completed'), 1::bigint, 'normal work order emits no preventive completion event');
SELECT throws_matching($$
  UPDATE public.work_orders SET request_id = '91000000-0000-0000-0000-000000000002' WHERE title = 'OT preventiva'
$$, '.*request must match.*', 'an attached preventive work order cannot switch to another request');
SELECT throws_matching($$
  INSERT INTO public.work_orders (request_id, client_organization_id, provider_organization_id, status, title, asset_id, work_order_type, priority)
  SELECT request_id, client_organization_id, provider_organization_id, 'pending', 'OT duplicada', asset_id, 'internal', 'medium'
  FROM public.work_orders WHERE title = 'OT preventiva'
$$, '.*uq_work_orders_internal_request.*', 'internal work order is unique per request');
SELECT ok((SELECT indexdef LIKE '%WHERE (quote_id IS NULL)%' FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_work_orders_internal_request'), 'internal uniqueness index excludes external quote work orders');
UPDATE public.work_orders SET status = 'in_progress' WHERE title = 'OT preventiva';
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'OT preventiva')), 'completed', 'work-order regression never reopens a terminal occurrence');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001'), 2::bigint, 'work-order regression does not remove next cycle');
SELECT lives_ok($$
  SELECT public.skip_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001' AND o.status = 'open'),
    'ciclo por medidor omitido'
  )
$$, 'meter occurrence can be skipped');
SELECT is(
  (SELECT due_meter_value FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND p.organization_id = '20000000-0000-0000-0000-000000000001' AND o.status = 'open'),
  205::numeric,
  'skipped meter cadence uses old due value plus interval'
);

SELECT throws_matching($$ SELECT public.get_maintenance_cards('20000000-0000-0000-0000-000000000002', true) $$, '.*Not authorized.*', 'tenant-scoped read rejects another organization');
SELECT throws_matching($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT id FROM public.preventive_maintenance_occurrences WHERE status = 'open' AND organization_id = '20000000-0000-0000-0000-000000000001' LIMIT 1),
    '99999999-9999-9999-9999-999999999999'
  )
$$, '.*request id must equal.*', 'request id must be occurrence creation id');
SELECT ok(has_table_privilege('authenticated', 'public.maintenance_cards', 'SELECT'), 'authenticated receives explicit SELECT grant');
SELECT ok(NOT has_table_privilege('authenticated', 'public.maintenance_cards', 'INSERT'), 'authenticated has no direct INSERT grant');
SELECT ok(has_function_privilege('authenticated', 'public.record_asset_meter_reading(uuid,numeric,timestamptz,text)', 'EXECUTE'), 'reading RPC is executable by authenticated');
SELECT is((SELECT count(*) FROM public.asset_events WHERE organization_id = '20000000-0000-0000-0000-000000000001' AND event_type = 'preventive_maintenance_completed'), 1::bigint, 'completion emits exactly one asset event');
SELECT is((SELECT count(*) FROM public.asset_events WHERE organization_id = '20000000-0000-0000-0000-000000000001' AND event_type = 'preventive_maintenance_skipped'), 2::bigint, 'each skip emits exactly one asset event');
SELECT is(
  (SELECT count(*)
   FROM public.get_asset_integrated_history('40000000-0000-0000-0000-000000000001') h
   JOIN public.asset_events e
     ON h.source_table = 'asset_events'
    AND e.id = h.source_id
   WHERE e.event_type IN ('preventive_plan_created', 'meter_reading_recorded', 'preventive_maintenance_planned', 'preventive_maintenance_completed', 'preventive_maintenance_skipped')),
  (SELECT count(*) FROM public.asset_events e WHERE e.asset_id = '40000000-0000-0000-0000-000000000001' AND e.event_type IN ('preventive_plan_created', 'meter_reading_recorded', 'preventive_maintenance_planned', 'preventive_maintenance_completed', 'preventive_maintenance_skipped')),
  'integrated history represents each preventive asset event exactly once'
);
SELECT ok(NOT EXISTS (
  SELECT 1 FROM (
    SELECT h.event_date, lead(h.event_date) OVER (ORDER BY h.event_date DESC) AS next_date
    FROM public.get_asset_integrated_history('40000000-0000-0000-0000-000000000001') h
  ) ordered WHERE ordered.next_date > ordered.event_date
), 'integrated asset history remains reverse chronological');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM public.organization_notifications n
  WHERE n.organization_id = '20000000-0000-0000-0000-000000000001'
    AND n.type IN ('preventive_maintenance_planned', 'preventive_maintenance_completed', 'preventive_maintenance_skipped')
  GROUP BY n.recipient_member_id, n.type, n.entity_type, n.entity_id
  HAVING count(*) > 1
), 'preventive notifications are idempotent per recipient, event and occurrence');

SELECT * FROM finish();
ROLLBACK;
