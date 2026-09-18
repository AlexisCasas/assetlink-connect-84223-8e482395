CREATE EXTENSION IF NOT EXISTS pgtap;
CREATE EXTENSION IF NOT EXISTS dblink;
SELECT plan(9);

DELETE FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001';
DELETE FROM public.work_orders WHERE client_organization_id = '21000000-0000-0000-0000-000000000001';
DELETE FROM public.requests WHERE organization_id = '21000000-0000-0000-0000-000000000001';
DELETE FROM public.preventive_maintenance_plans WHERE organization_id = '21000000-0000-0000-0000-000000000001';
DELETE FROM public.maintenance_cards WHERE organization_id = '21000000-0000-0000-0000-000000000001';
DELETE FROM public.assets WHERE organization_id = '21000000-0000-0000-0000-000000000001';
DELETE FROM public.organization_members WHERE organization_id = '21000000-0000-0000-0000-000000000001';
DELETE FROM public.organizations WHERE id = '21000000-0000-0000-0000-000000000001';
DELETE FROM auth.users WHERE id = '11000000-0000-0000-0000-000000000001';

INSERT INTO auth.users (id, email) VALUES ('11000000-0000-0000-0000-000000000001', 'race@test.local');
INSERT INTO public.organizations (id, name, organization_type) VALUES ('21000000-0000-0000-0000-000000000001', 'Cliente Race', 'client_company');
INSERT INTO public.organization_members (id, organization_id, user_id, role)
VALUES ('31000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001', 'owner');
INSERT INTO public.assets (id, organization_id, code, name)
VALUES ('41000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'RACE-1', 'Equipo Race');
SELECT set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000001', false);
SELECT public.save_maintenance_card(
  '21000000-0000-0000-0000-000000000001', 'RACE-CARD', 'Ficha Race', NULL, NULL, 1,
  NULL, NULL, '[]'::jsonb, '[]'::jsonb, NULL
);
SELECT public.save_preventive_maintenance_plan(
  '21000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000001',
  (SELECT id FROM public.maintenance_cards WHERE code = 'RACE-CARD'), 'calendar', 'medium', 'internal',
  '31000000-0000-0000-0000-000000000001', 5, 'weekly', NULL, NULL,
  now() + interval '1 day', NULL, NULL, NULL, NULL, NULL
);
INSERT INTO public.requests (
  id, request_number, description, asset, location, service_type, deadline, status,
  created_by, organization_id, asset_id, request_type
)
SELECT request_creation_id, 'MP-RACE', 'Race', 'Equipo Race', 'Planta', 'preventivo', now() + interval '1 day',
  'draft', 'race@test.local', organization_id, asset_id, 'internal'
FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001';

SELECT dblink_connect('pm_c1', 'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres');
SELECT dblink_connect('pm_c2', 'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres');
SELECT dblink_send_query('pm_c1', format(
  $sql$WITH authn AS MATERIALIZED (SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',false))
  SELECT (public.plan_preventive_maintenance_occurrence('%s','%s')).status::text FROM authn$sql$,
  (SELECT id FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001'),
  (SELECT request_creation_id FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001')
));
SELECT dblink_send_query('pm_c2', format(
  $sql$WITH authn AS MATERIALIZED (SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',false))
  SELECT (public.plan_preventive_maintenance_occurrence('%s','%s')).status::text FROM authn$sql$,
  (SELECT id FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001'),
  (SELECT request_creation_id FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001')
));
SELECT is((SELECT status FROM dblink_get_result('pm_c1') AS t(status text)), 'planned', 'first concurrent planner succeeds');
SELECT is((SELECT status FROM dblink_get_result('pm_c2') AS t(status text)), 'planned', 'second concurrent planner is idempotent');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001' AND status = 'planned'), 1::bigint, 'concurrent planning leaves one planned occurrence');
SELECT is((SELECT count(*) FROM public.asset_events WHERE organization_id = '21000000-0000-0000-0000-000000000001' AND event_type = 'preventive_maintenance_planned'), 1::bigint, 'concurrent planning emits one event');

SELECT dblink_disconnect('pm_c1');
SELECT dblink_disconnect('pm_c2');
SELECT dblink_connect('pm_c1', 'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres');
SELECT dblink_connect('pm_c2', 'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres');

INSERT INTO public.work_orders (
  request_id, client_organization_id, provider_organization_id, status, title, asset_id, work_order_type, priority
)
SELECT id, organization_id, organization_id, 'pending', 'OT Race', asset_id, 'internal', 'medium'
FROM public.requests WHERE request_number = 'MP-RACE';
SELECT ok(EXISTS (SELECT 1 FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001' AND work_order_id IS NOT NULL), 'work order attached before terminal race');

SELECT dblink_send_query('pm_c1', $sql$WITH authn AS MATERIALIZED (SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',false))
  UPDATE public.work_orders SET status = 'completed' FROM authn WHERE title = 'OT Race' RETURNING id::text$sql$);
SELECT dblink_send_query('pm_c2', $sql$WITH authn AS MATERIALIZED (SELECT set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',false))
  UPDATE public.work_orders SET status = 'completed' FROM authn WHERE title = 'OT Race' RETURNING id::text$sql$);
SELECT ok((SELECT id FROM dblink_get_result('pm_c1') AS t(id text)) IS NOT NULL, 'first terminal transition succeeds');
SELECT ok((SELECT id FROM dblink_get_result('pm_c2') AS t(id text)) IS NOT NULL, 'second terminal transition safely replays');
SELECT is((SELECT count(*) FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001'), 2::bigint, 'terminal race creates exactly one next occurrence');
SELECT is(
  (SELECT due_at FROM public.preventive_maintenance_occurrences WHERE organization_id = '21000000-0000-0000-0000-000000000001' AND status = 'open'),
  (SELECT completed_at + interval '1 week' FROM public.work_orders WHERE title = 'OT Race'),
  'completed calendar cadence starts from completion time'
);

SELECT dblink_disconnect('pm_c1');
SELECT dblink_disconnect('pm_c2');
SELECT * FROM finish();
