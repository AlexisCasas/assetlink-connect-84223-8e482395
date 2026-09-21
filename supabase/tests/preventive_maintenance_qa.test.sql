BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(81);

INSERT INTO auth.users (id, email)
VALUES
  ('12000000-0000-0000-0000-000000000001', 'qa-owner@test.local'),
  ('12000000-0000-0000-0000-000000000002', 'qa-manager@test.local'),
  ('12000000-0000-0000-0000-000000000003', 'qa-technician@test.local'),
  ('12000000-0000-0000-0000-000000000004', 'qa-requester@test.local'),
  ('12000000-0000-0000-0000-000000000005', 'qa-viewer@test.local'),
  ('12000000-0000-0000-0000-000000000006', 'qa-provider@test.local');

INSERT INTO public.organizations (id, name, organization_type)
VALUES
  ('22000000-0000-0000-0000-000000000001', 'QA Cliente A', 'client_company'),
  ('22000000-0000-0000-0000-000000000002', 'QA Cliente B', 'client_company'),
  ('22000000-0000-0000-0000-000000000003', 'QA Proveedor', 'provider_company');

INSERT INTO public.organization_members (id, organization_id, user_id, role)
VALUES
  ('32000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000001', 'owner'),
  ('32000000-0000-0000-0000-000000000002', '22000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000002', 'manager'),
  ('32000000-0000-0000-0000-000000000003', '22000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000003', 'technician'),
  ('32000000-0000-0000-0000-000000000004', '22000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000004', 'requester'),
  ('32000000-0000-0000-0000-000000000005', '22000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000005', 'viewer'),
  ('32000000-0000-0000-0000-000000000006', '22000000-0000-0000-0000-000000000003', '12000000-0000-0000-0000-000000000006', 'owner');

INSERT INTO public.assets (id, organization_id, code, name)
VALUES
  ('42000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', 'QA-A', 'Unidad QA A'),
  ('42000000-0000-0000-0000-000000000002', '22000000-0000-0000-0000-000000000002', 'QA-B', 'Unidad QA B'),
  ('42000000-0000-0000-0000-000000000003', '22000000-0000-0000-0000-000000000001', 'QA-12', 'Unidad QA-12 aislada');

INSERT INTO public.warehouses (id, organization_id, name)
VALUES ('52000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', 'QA Almacén');
INSERT INTO public.materials (id, organization_id, warehouse_id, code, name, unit)
VALUES
  ('62000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 'FILTRO', 'Filtro aceite', 'und'),
  ('62000000-0000-0000-0000-000000000002', '22000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 'ACEITE', 'Aceite 15W40', 'L');
INSERT INTO public.maintenance_cards (id, organization_id, code, name)
VALUES ('72000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000002', 'QA-B-CARD', 'Ficha privada cliente B');

SELECT set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000001', true);

SELECT lives_ok($$
  SELECT public.save_maintenance_card(
    '22000000-0000-0000-0000-000000000001', 'MP-5000', 'Mantenimiento 5,000 km',
    'Servicio preventivo de 5,000 km', 'Vehículos', 4.5,
    'Seguir procedimiento del fabricante', 'Bloquear y señalizar el equipo',
    '[{"title":"Cambio de aceite"},{"title":"Cambio de filtro"},{"title":"Revisión de frenos"}]'::jsonb,
    '[{"material_id":"62000000-0000-0000-0000-000000000001","description":"Filtro aceite","quantity":1,"unit":"und"},{"material_id":"62000000-0000-0000-0000-000000000002","description":"Aceite 15W40","quantity":5,"unit":"L"}]'::jsonb,
    NULL
  )
$$, 'QA card with exact tasks and materials saves atomically');
SELECT is((SELECT count(*) FROM public.maintenance_card_tasks), 3::bigint, 'QA card has three tasks');
SELECT is((SELECT count(*) FROM public.maintenance_card_materials), 2::bigint, 'QA card has two materials');

SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000'), 'calendar', 'medium', 'internal',
    '32000000-0000-0000-0000-000000000002', 30, 'annual', NULL, NULL,
    '2030-01-15 10:00:00+00', NULL, NULL, NULL, NULL, NULL
  )
$$, 'annual calendar plan creates');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences WHERE organization_id = '22000000-0000-0000-0000-000000000001'), 1::bigint, 'annual plan creates exactly one occurrence');
SELECT is((SELECT scope_snapshot #>> '{card,code}' FROM public.preventive_maintenance_occurrences WHERE organization_id = '22000000-0000-0000-0000-000000000001'), 'MP-5000', 'snapshot freezes card code');
SELECT is((SELECT scope_snapshot #>> '{card,procedure_notes}' FROM public.preventive_maintenance_occurrences WHERE organization_id = '22000000-0000-0000-0000-000000000001'), 'Seguir procedimiento del fabricante', 'snapshot freezes procedure notes');
SELECT is((SELECT jsonb_array_length(scope_snapshot #> '{card,tasks}') FROM public.preventive_maintenance_occurrences WHERE organization_id = '22000000-0000-0000-0000-000000000001'), 3, 'snapshot freezes all tasks');
SELECT is((SELECT (material->>'quantity')::numeric FROM public.preventive_maintenance_occurrences o CROSS JOIN LATERAL jsonb_array_elements(o.scope_snapshot #> '{card,materials}') material WHERE o.organization_id = '22000000-0000-0000-0000-000000000001' AND material->>'code' = 'ACEITE'), 5::numeric, 'snapshot freezes five liters of oil');

SELECT lives_ok($$
  SELECT public.save_maintenance_card(
    '22000000-0000-0000-0000-000000000001', 'MP-5000', 'Mantenimiento 5,000 km',
    'Servicio preventivo de 5,000 km', 'Vehículos', 4.5,
    'Seguir procedimiento del fabricante', 'Bloquear y señalizar el equipo',
    '[{"title":"Cambio de aceite"},{"title":"Cambio de filtro"},{"title":"Revisión de frenos"}]'::jsonb,
    '[{"material_id":"62000000-0000-0000-0000-000000000001","description":"Filtro aceite","quantity":1,"unit":"und"},{"material_id":"62000000-0000-0000-0000-000000000002","description":"Aceite 15W40","quantity":6,"unit":"L"}]'::jsonb,
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000')
  )
$$, 'live card changes oil quantity to six liters');
SELECT is((SELECT quantity FROM public.maintenance_card_materials WHERE material_id = '62000000-0000-0000-0000-000000000002'), 6::numeric, 'live card exposes six liters');
SELECT is((SELECT (material->>'quantity')::numeric FROM public.preventive_maintenance_occurrences o CROSS JOIN LATERAL jsonb_array_elements(o.scope_snapshot #> '{card,materials}') material WHERE o.organization_id = '22000000-0000-0000-0000-000000000001' AND material->>'code' = 'ACEITE'), 5::numeric, 'historical occurrence remains at five liters');
SELECT throws_matching($$ SELECT public.skip_preventive_maintenance_occurrence((SELECT id FROM public.preventive_maintenance_occurrences WHERE organization_id = '22000000-0000-0000-0000-000000000001'), '') $$, '.*reason is required.*', 'skip without a reason fails');
SELECT lives_ok($$ SELECT public.skip_preventive_maintenance_occurrence((SELECT id FROM public.preventive_maintenance_occurrences WHERE organization_id = '22000000-0000-0000-0000-000000000001'), 'QA snapshot next cycle') $$, 'annual occurrence can be skipped');
SELECT is((SELECT (material->>'quantity')::numeric FROM public.preventive_maintenance_occurrences o CROSS JOIN LATERAL jsonb_array_elements(o.scope_snapshot #> '{card,materials}') material WHERE o.organization_id = '22000000-0000-0000-0000-000000000001' AND o.status = 'open' AND material->>'code' = 'ACEITE'), 6::numeric, 'future occurrence uses six liters');
SELECT is((SELECT due_at FROM public.preventive_maintenance_occurrences WHERE organization_id = '22000000-0000-0000-0000-000000000001' AND status = 'open'), '2031-01-15 10:00:00+00'::timestamptz, 'annual skip preserves cadence from old due date');

INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
)
SELECT o.request_creation_id, 'QA-CALENDAR-CLOSED', 'Preventivo anual', 'Unidad QA A', 'QA',
  'preventivo', now() + interval '3 days', 'draft', 'qa-owner@test.local', o.organization_id,
  p.asset_id, 'internal'
FROM public.preventive_maintenance_occurrences o
JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
WHERE p.frequency = 'annual' AND o.status = 'open';
SELECT lives_ok($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'annual' AND o.status = 'open'),
    (SELECT id FROM public.requests WHERE request_number = 'QA-CALENDAR-CLOSED')
  )
$$, 'annual calendar occurrence links to its durable request');
INSERT INTO public.work_orders (
  request_id, client_organization_id, provider_organization_id, status,
  title, asset_id, work_order_type, priority
)
SELECT r.id, r.organization_id, r.organization_id, 'pending', 'QA OT calendar direct closed',
  r.asset_id, 'internal', 'medium'
FROM public.requests r WHERE r.request_number = 'QA-CALENDAR-CLOSED';
SELECT lives_ok($$ UPDATE public.work_orders SET status = 'closed' WHERE title = 'QA OT calendar direct closed' $$, 'direct closed is a terminal preventive transition');
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA OT calendar direct closed')), 'completed', 'direct closed completes the linked occurrence');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'annual' AND o.status IN ('open', 'planned')), 1::bigint, 'direct closed creates exactly one current annual occurrence');

SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000'), 'calendar', 'medium', 'internal',
    NULL, 15, 'custom', 45, 'days', now() + interval '10 days', NULL, NULL, NULL, NULL, NULL
  )
$$, 'custom forty-five-day plan creates');
SELECT is((
  SELECT item->>'timing_status' FROM jsonb_array_elements(public.get_preventive_maintenance_plans('22000000-0000-0000-0000-000000000001')) item
  WHERE item->>'frequency' = 'custom'
), 'due', 'calendar timing is due inside its lead window');

SELECT lives_ok($$
  SELECT public.create_asset_meter(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
    'Odómetro', 'km', 40000, now() - interval '3 hours', 'QA baseline'
  )
$$, 'generic odometer creates with a real baseline');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000'), 'meter', 'medium', 'internal',
    NULL, 0, NULL, NULL, NULL, NULL, (SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 5000,
    (SELECT id FROM public.asset_meter_readings WHERE value = 40000), 500, NULL
  )
$$, 'five-thousand-unit meter plan creates');
SELECT is((SELECT due_meter_value FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter'), 45000::numeric, 'first meter occurrence is due at 45000');
SELECT lives_ok($$ SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 44780, now() - interval '2 hours', NULL) $$, '44780 reading records');
SELECT is((SELECT item->>'timing_status' FROM jsonb_array_elements(public.get_preventive_maintenance_plans('22000000-0000-0000-0000-000000000001')) item WHERE item->>'trigger_type' = 'meter'), 'due', '44780 is due, not overdue');
SELECT is((SELECT (item->>'meter_remaining_value')::numeric FROM jsonb_array_elements(public.get_preventive_maintenance_plans('22000000-0000-0000-0000-000000000001')) item WHERE item->>'trigger_type' = 'meter'), 220::numeric, 'meter read model reports 220 remaining units');
SELECT lives_ok($$ SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 45000, now() - interval '1 hour', NULL) $$, 'exact due reading records');
SELECT is((SELECT item->>'timing_status' FROM jsonb_array_elements(public.get_preventive_maintenance_plans('22000000-0000-0000-0000-000000000001')) item WHERE item->>'trigger_type' = 'meter'), 'due', 'exact meter threshold remains due');
SELECT lives_ok($$ SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 45050, now() - interval '2 minutes', NULL) $$, 'overdue reading records');
SELECT is((SELECT item->>'timing_status' FROM jsonb_array_elements(public.get_preventive_maintenance_plans('22000000-0000-0000-0000-000000000001')) item WHERE item->>'trigger_type' = 'meter'), 'overdue', 'value above threshold is overdue');
INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
)
SELECT o.request_creation_id, 'QA-METER-50180', 'Preventivo por odómetro', 'Unidad QA A', 'QA',
  'preventivo', now() + interval '3 days', 'draft', 'qa-owner@test.local', o.organization_id,
  p.asset_id, 'internal'
FROM public.preventive_maintenance_occurrences o
JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
WHERE p.trigger_type = 'meter' AND o.status = 'open';
SELECT lives_ok($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND o.status = 'open'),
    (SELECT id FROM public.requests WHERE request_number = 'QA-METER-50180')
  )
$$, 'meter occurrence links to its durable request');
SELECT lives_ok($$
  SELECT public.record_asset_meter_reading(
    (SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 45180,
    (SELECT planned_at FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND o.status = 'planned'),
    'QA completion'
  )
$$, '45180 completion reading records at the planned occurrence time');
INSERT INTO public.work_orders (
  request_id, client_organization_id, provider_organization_id, status,
  title, asset_id, work_order_type, priority
)
SELECT r.id, r.organization_id, r.organization_id, 'pending', 'QA OT meter 50180',
  r.asset_id, 'internal', 'medium'
FROM public.requests r WHERE r.request_number = 'QA-METER-50180';
SELECT lives_ok($$ UPDATE public.work_orders SET status = 'completed' WHERE title = 'QA OT meter 50180' $$, 'meter work order completes with the effective reading');
SELECT is((SELECT due_meter_value FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND o.status = 'open'), 50180::numeric, 'next meter occurrence is due at 50180');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.trigger_type = 'meter' AND o.status IN ('open', 'planned')), 1::bigint, 'meter completion leaves exactly one current occurrence');

SELECT lives_ok($$
  SELECT public.create_asset_meter(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000003',
    'QA-12 Medidor', 'km', 100, now() - interval '1 day', 'baseline QA-12'
  )
$$, 'QA-12 creates an isolated meter with only its baseline reading');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000003',
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000'), 'meter', 'medium', 'internal',
    NULL, 0, NULL, NULL, NULL, NULL,
    (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor'), 50,
    (SELECT r.id FROM public.asset_meter_readings r JOIN public.asset_meters m ON m.id = r.meter_id WHERE m.name = 'QA-12 Medidor'), 10, NULL
  )
$$, 'QA-12 creates a meter plan from the isolated baseline');
INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
)
SELECT o.request_creation_id, 'QA-12-BASELINE-ONLY', 'Preventivo QA-12', 'Unidad QA-12 aislada', 'QA',
  'preventivo', now() + interval '3 days', 'draft', 'qa-owner@test.local', o.organization_id,
  o.asset_id, 'internal'
FROM public.preventive_maintenance_occurrences o
JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
WHERE p.meter_id = (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor');
SELECT lives_ok($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.meter_id = (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor')),
    (SELECT id FROM public.requests WHERE request_number = 'QA-12-BASELINE-ONLY')
  )
$$, 'QA-12 links the planned occurrence without an operational reading');
INSERT INTO public.work_orders (
  request_id, client_organization_id, provider_organization_id, status,
  title, asset_id, work_order_type, priority
)
SELECT r.id, r.organization_id, r.organization_id, 'pending', 'QA-12 baseline-only OT',
  r.asset_id, 'internal', 'medium'
FROM public.requests r WHERE r.request_number = 'QA-12-BASELINE-ONLY';
SELECT throws_matching($$ UPDATE public.work_orders SET status = 'completed' WHERE title = 'QA-12 baseline-only OT' $$, '.*Registra una lectura actual del medidor QA-12 Medidor antes de completar este mantenimiento preventivo.*', 'QA-12 rejects a baseline recorded before the occurrence was planned');
SELECT is((SELECT count(*) FROM public.asset_meter_readings r JOIN public.asset_meters m ON m.id = r.meter_id WHERE m.name = 'QA-12 Medidor' AND r.voided_at IS NULL), 1::bigint, 'QA-12 has no operational reading beyond its baseline');
SELECT is((SELECT status FROM public.work_orders WHERE title = 'QA-12 baseline-only OT'), 'pending', 'failed completed transition rolls the work order back');
SELECT is((SELECT completed_at FROM public.work_orders WHERE title = 'QA-12 baseline-only OT'), NULL::timestamptz, 'failed completed transition does not persist completed_at');
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')), 'planned', 'failed completed transition leaves the occurrence planned');
SELECT is((SELECT completion_meter_reading_id FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')), NULL::uuid, 'failed completed transition leaves completion reading null');
SELECT is((SELECT completion_meter_value FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')), NULL::numeric, 'failed completed transition leaves completion value null');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.meter_id = (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor') AND o.status = 'open'), 0::bigint, 'failed completed transition creates no next occurrence');
SELECT throws_matching($$ UPDATE public.work_orders SET status = 'closed' WHERE title = 'QA-12 baseline-only OT' $$, '.*Registra una lectura actual del medidor QA-12 Medidor.*', 'QA-12 protects the closed terminal transition too');
SELECT lives_ok($$
  SELECT public.record_asset_meter_reading(
    (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor'), 110,
    (SELECT planned_at + interval '2 seconds' FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')),
    'lectura futura QA-12'
  )
$$, 'QA-12 records a reading after the proposed completion timestamp');
SELECT throws_matching($$
  UPDATE public.work_orders SET status = 'completed', completed_at = (
    SELECT planned_at + interval '1 second' FROM public.preventive_maintenance_occurrences
    WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')
  ) WHERE title = 'QA-12 baseline-only OT'
$$, '.*Registra una lectura actual del medidor QA-12 Medidor.*', 'QA-12 rejects a future-only reading');
SELECT lives_ok($$
  SELECT public.record_asset_meter_reading(
    (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor'), 101,
    (SELECT planned_at FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')),
    'lectura exacta QA-12'
  )
$$, 'QA-12 accepts a reading exactly at planned_at');
SELECT lives_ok($$
  SELECT public.record_asset_meter_reading(
    (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor'), 105,
    (SELECT planned_at + interval '500 milliseconds' FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')),
    'lectura posterior válida QA-12'
  )
$$, 'QA-12 accepts a reading after planned_at');
SELECT lives_ok($$
  SELECT public.record_asset_meter_reading(
    (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor'), 110,
    (SELECT planned_at + interval '750 milliseconds' FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')),
    'lectura posterior anulada QA-12'
  )
$$, 'QA-12 records a later candidate reading');
SELECT lives_ok($$
  UPDATE public.asset_meter_readings SET voided_at = now(), void_reason = 'QA lectura anulada'
  WHERE meter_id = (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor') AND value = 110
$$, 'QA-12 voids the latest candidate reading');
SELECT lives_ok($$
  UPDATE public.work_orders SET status = 'completed', completed_at = (
    SELECT planned_at + interval '1 second' FROM public.preventive_maintenance_occurrences
    WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')
  ) WHERE title = 'QA-12 baseline-only OT'
$$, 'QA-12 completes with a reading in the planned-to-completed window');
SELECT is(
  (SELECT completion_meter_reading_id FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')),
  (SELECT id FROM public.asset_meter_readings WHERE meter_id = (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor') AND value = 105 AND voided_at IS NULL),
  'QA-12 selects the latest effective reading at or before completion'
);
SELECT is((SELECT completion_meter_value FROM public.preventive_maintenance_occurrences WHERE work_order_id = (SELECT id FROM public.work_orders WHERE title = 'QA-12 baseline-only OT')), 105::numeric, 'QA-12 persists the selected completion value');
SELECT is((SELECT due_meter_value FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.meter_id = (SELECT id FROM public.asset_meters WHERE name = 'QA-12 Medidor') AND o.status = 'open'), 155::numeric, 'QA-12 creates the next cycle from the selected completion value');

SELECT lives_ok($$
  SELECT public.correct_asset_meter_reading((SELECT id FROM public.asset_meter_readings WHERE value = 40000 AND voided_at IS NULL), 40100, 'QA baseline correction', NULL)
$$, 'baseline reading can be corrected after plan creation');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000'), 'meter', 'high', 'external',
    NULL, 0, NULL, NULL, NULL, NULL, (SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 5000,
    (SELECT id FROM public.asset_meter_readings WHERE value = 40000), 500,
    (SELECT id FROM public.preventive_maintenance_plans WHERE trigger_type = 'meter' AND asset_id = '42000000-0000-0000-0000-000000000001')
  )
$$, 'corrected historical baseline does not block mutable plan edits');
SELECT is((SELECT baseline_value FROM public.preventive_maintenance_plans WHERE trigger_type = 'meter' AND asset_id = '42000000-0000-0000-0000-000000000001'), 40000::numeric, 'plan baseline remains immutable after correction');

SELECT lives_ok($$ SELECT public.set_preventive_maintenance_plan_active((SELECT id FROM public.preventive_maintenance_plans WHERE frequency = 'custom'), false, 'QA deactivate') $$, 'open custom plan deactivates');
SELECT is((SELECT status FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'custom'), 'cancelled', 'deactivation preserves occurrence as cancelled history');
SELECT lives_ok($$ SELECT public.set_preventive_maintenance_plan_active((SELECT id FROM public.preventive_maintenance_plans WHERE frequency = 'custom'), true, NULL) $$, 'custom plan reactivates');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'custom' AND o.status IN ('open', 'planned')), 1::bigint, 'reactivation leaves exactly one current occurrence');

SELECT set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000002', true);
SELECT lives_ok($$
  SELECT public.save_maintenance_card(
    '22000000-0000-0000-0000-000000000001', 'QA-MANAGER', 'Ficha del manager', NULL, NULL, 1,
    NULL, NULL, '[]'::jsonb, '[]'::jsonb, NULL
  )
$$, 'manager can manage maintenance cards');
SELECT lives_ok($$ SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 45200, now() + interval '1 minute', 'manager') $$, 'manager can record a meter reading');
SELECT lives_ok($$
  SELECT public.save_preventive_maintenance_plan(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000'), 'calendar', 'medium', 'internal',
    NULL, 7, 'weekly', NULL, NULL, now() + interval '7 days', NULL, NULL, NULL, NULL, NULL
  )
$$, 'manager can manage preventive plans');
INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
)
SELECT o.request_creation_id, 'QA-MANAGER-PLAN', 'Preventivo semanal', 'Unidad QA A', 'QA',
  'preventivo', now() + interval '3 days', 'draft', 'qa-manager@test.local', o.organization_id,
  p.asset_id, 'internal'
FROM public.preventive_maintenance_occurrences o
JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id
WHERE p.frequency = 'weekly'
  AND p.created_by_user_id = '12000000-0000-0000-0000-000000000002'
  AND o.status = 'open';
SELECT lives_ok($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'weekly' AND p.created_by_user_id = '12000000-0000-0000-0000-000000000002' AND o.status = 'open'),
    (SELECT id FROM public.requests WHERE request_number = 'QA-MANAGER-PLAN')
  )
$$, 'manager can plan a preventive occurrence');
SELECT lives_ok($$
  SELECT public.skip_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'annual' AND o.status = 'open'),
    'QA manager skip'
  )
$$, 'manager can skip a preventive occurrence');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'annual' AND o.status = 'open'), 1::bigint, 'manager skip leaves exactly one current annual occurrence');

SELECT set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000003', true);
SELECT lives_ok($$ SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 45300, now() + interval '2 minutes', 'technician') $$, 'technician can record a meter reading');
SELECT throws_matching($$
  SELECT public.save_maintenance_card('22000000-0000-0000-0000-000000000001', 'QA-TECH', 'No autorizada', NULL, NULL, NULL, NULL, NULL, '[]', '[]', NULL)
$$, '.*Not authorized.*', 'technician cannot manage maintenance cards');
SELECT throws_matching($$
  SELECT public.save_preventive_maintenance_plan(
    '22000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001',
    (SELECT id FROM public.maintenance_cards WHERE code = 'MP-5000'), 'calendar', 'medium', 'internal',
    NULL, 1, 'weekly', NULL, NULL, now(), NULL, NULL, NULL, NULL, NULL
  )
$$, '.*Not authorized.*', 'technician cannot manage preventive plans');
SELECT throws_matching($$
  SELECT public.plan_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'annual' AND o.status = 'open'),
    (SELECT o.request_creation_id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'annual' AND o.status = 'open')
  )
$$, '.*Not authorized.*', 'technician cannot plan preventive occurrences');
SELECT throws_matching($$
  SELECT public.skip_preventive_maintenance_occurrence(
    (SELECT o.id FROM public.preventive_maintenance_occurrences o JOIN public.preventive_maintenance_plans p ON p.id = o.plan_id WHERE p.frequency = 'annual' AND o.status = 'open'),
    'technician skip'
  )
$$, '.*Not authorized.*', 'technician cannot skip preventive occurrences');

SELECT set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000004', true);
SELECT throws_matching($$ SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 45400, now() + interval '3 minutes', 'requester') $$, '.*Not authorized.*', 'requester cannot record meter readings');
SELECT set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000005', true);
SELECT throws_matching($$ SELECT public.record_asset_meter_reading((SELECT id FROM public.asset_meters WHERE name = 'Odómetro'), 45400, now() + interval '3 minutes', 'viewer') $$, '.*Not authorized.*', 'viewer cannot record meter readings');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000001', true);
SELECT is((SELECT count(*) FROM public.maintenance_cards WHERE organization_id = '22000000-0000-0000-0000-000000000002'), 0::bigint, 'RLS hides client B cards from client A even by UUID');
SELECT set_config('request.jwt.claim.sub', '12000000-0000-0000-0000-000000000006', true);
SELECT is((SELECT count(*) FROM public.maintenance_cards WHERE organization_id = '22000000-0000-0000-0000-000000000001'), 0::bigint, 'RLS hides client preventive cards from provider members');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
