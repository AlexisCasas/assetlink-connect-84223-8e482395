-- 9C.6-B1. All synthetic data is removed by ROLLBACK. Execute ONLY in local/isolated Supabase.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
-- Dynamic plan marker is substituted below.
SELECT plan(51);
CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text,''), true);
$$;

INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES
  ('f6100000-0000-0000-0000-000000000001','co@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000002','owner@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000003','admin@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000004','manager@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000005','requester@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000006','tech@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000007','viewer@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000008','unassigned@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000009','otherfm@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000010','outsider@fm-workorder-qa.test','{}'),
  ('f6100000-0000-0000-0000-000000000011','provider@fm-workorder-qa.test','{}');

INSERT INTO public.organizations (id,name,organization_type) VALUES
('f6200000-0000-0000-0000-0000000000a1','FM OT Client A','client_company'),
('f6200000-0000-0000-0000-0000000000b1','FM OT Client B','client_company'),
('f6200000-0000-0000-0000-0000000000fa','FM OT Manager A','facility_manager'),
('f6200000-0000-0000-0000-0000000000fb','FM OT Manager B','facility_manager'),
('f6200000-0000-0000-0000-0000000000c1','FM OT Provider','provider_company');

INSERT INTO public.organization_members (id,organization_id,user_id,role,is_active) VALUES
('f6300000-0000-0000-0000-000000000001','f6200000-0000-0000-0000-0000000000a1','f6100000-0000-0000-0000-000000000001','owner',true),
('f6300000-0000-0000-0000-000000000002','f6200000-0000-0000-0000-0000000000fa','f6100000-0000-0000-0000-000000000002','owner',true),
('f6300000-0000-0000-0000-000000000003','f6200000-0000-0000-0000-0000000000fa','f6100000-0000-0000-0000-000000000003','admin',true),
('f6300000-0000-0000-0000-000000000004','f6200000-0000-0000-0000-0000000000fa','f6100000-0000-0000-0000-000000000004','manager',true),
('f6300000-0000-0000-0000-000000000005','f6200000-0000-0000-0000-0000000000fa','f6100000-0000-0000-0000-000000000005','requester',true),
('f6300000-0000-0000-0000-000000000006','f6200000-0000-0000-0000-0000000000fa','f6100000-0000-0000-0000-000000000006','technician',true),
('f6300000-0000-0000-0000-000000000007','f6200000-0000-0000-0000-0000000000fa','f6100000-0000-0000-0000-000000000007','viewer',true),
('f6300000-0000-0000-0000-000000000008','f6200000-0000-0000-0000-0000000000fa','f6100000-0000-0000-0000-000000000008','manager',true),
('f6300000-0000-0000-0000-000000000009','f6200000-0000-0000-0000-0000000000fb','f6100000-0000-0000-0000-000000000009','manager',true),
('f6300000-0000-0000-0000-000000000010','f6200000-0000-0000-0000-0000000000c1','f6100000-0000-0000-0000-000000000011','owner',true);

INSERT INTO public.organization_relationships
(id,source_organization_id,target_organization_id,relationship_type,status) VALUES
('f6700000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000fa','facility_management','pending'),
('f6700000-0000-0000-0000-0000000000b1','f6200000-0000-0000-0000-0000000000b1','f6200000-0000-0000-0000-0000000000fb','facility_management','pending');
UPDATE public.organization_relationships SET status='active' WHERE id IN ('f6700000-0000-0000-0000-0000000000a1','f6700000-0000-0000-0000-0000000000b1');
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES
('f6700000-0000-0000-0000-0000000000a1','requests.view'),('f6700000-0000-0000-0000-0000000000a1','work_orders.view'),
('f6700000-0000-0000-0000-0000000000a1','quotes.view'),('f6700000-0000-0000-0000-0000000000a1','assets.view'),
('f6700000-0000-0000-0000-0000000000b1','requests.view'),('f6700000-0000-0000-0000-0000000000b1','work_orders.view');
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id) VALUES
('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000002'),
('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000003'),
('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000004'),
('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000005'),
('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000006'),
('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000007'),
('f6700000-0000-0000-0000-0000000000b1','f6300000-0000-0000-0000-000000000009');

INSERT INTO public.assets(id,organization_id,code,name,node_type,status)
VALUES ('f6400000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000a1','A-OT-TEST','Equipo QA seguro','equipment','active');

INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes,quotes_closed)
VALUES
('f6800000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000a1','FM-OT-TEST-001','Cotizacion autorizada','Solicitud visible','Equipo QA','f6400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',1,false),
('f6800000-0000-0000-0000-0000000000a2','f6200000-0000-0000-0000-0000000000a1','FM-OT-TEST-002','Cotizacion bajo minimo','Solicitud restringida','Equipo QA','f6400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',2,false),
('f6800000-0000-0000-0000-0000000000a3','f6200000-0000-0000-0000-0000000000a1','FM-OT-TEST-003','Servicio interno','Solicitud interna','Equipo QA','f6400000-0000-0000-0000-0000000000a1','Lima','preventivo',now()+interval '10 days','sent','internal',false,'fixture',1,false),
('f6800000-0000-0000-0000-0000000000b1','f6200000-0000-0000-0000-0000000000b1','FM-OT-TEST-004','Cliente B','Servicio B','Activo B',NULL,'Lima','correctivo',now()+interval '10 days','sent','internal',false,'fixture',1,false);

INSERT INTO public.quotes
(id,request_id,provider_organization_id,created_by_user_id,amount,description,status,total_amount)
VALUES
('f6900000-0000-0000-0000-0000000000a1','f6800000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000c1','f6100000-0000-0000-0000-000000000011',1700,'Propuesta visible S/ 1700','approved',1700),
('f6900000-0000-0000-0000-0000000000a2','f6800000-0000-0000-0000-0000000000a2','f6200000-0000-0000-0000-0000000000c1','f6100000-0000-0000-0000-000000000011',1800,'Propuesta oculta S/ 1800','approved',1800);

INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id,observations)
VALUES
('f6a00000-0000-0000-0000-0000000000a1','f6800000-0000-0000-0000-0000000000a1','f6900000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000c1','external','completed','Trabajo externo autorizado S/ 1700','Descripción S/ 1700','high','OT-FM-001',1700,'f6400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('f6a00000-0000-0000-0000-0000000000a2','f6800000-0000-0000-0000-0000000000a2','f6900000-0000-0000-0000-0000000000a2','f6200000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000c1','external','pending','Oferta oculta S/ 1800','Descripción oculta S/ 1800','urgent','OT-FM-002',1800,'f6400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('f6a00000-0000-0000-0000-0000000000a3','f6800000-0000-0000-0000-0000000000a3',NULL,'f6200000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000a1','internal','closed','Trabajo interno','Descripción del cliente','medium','OT-FM-003',NULL,'f6400000-0000-0000-0000-0000000000a1','NOTA INTERNA DE OPERADOR'),
('f6a00000-0000-0000-0000-0000000000b1','f6800000-0000-0000-0000-0000000000b1',NULL,'f6200000-0000-0000-0000-0000000000b1','f6200000-0000-0000-0000-0000000000b1','internal','pending','Trabajo de otro cliente','Privado B','low','OT-FM-004',NULL,NULL,'PRIVADO B');

-- Deliberately invalid source state: must not appear through delegated OT RPCs.
INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes)
VALUES ('f6800000-0000-0000-0000-0000000000a4','f6200000-0000-0000-0000-0000000000a1',
'FM-OT-TEST-005','Borrador oculto','Solo borrador','Equipo QA','f6400000-0000-0000-0000-0000000000a1',
'Lima','correctivo',now()+interval '10 days','draft','internal',false,'fixture',1);
INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id)
VALUES ('f6a00000-0000-0000-0000-0000000000a4',
'f6800000-0000-0000-0000-0000000000a4',NULL,
'f6200000-0000-0000-0000-0000000000a1','f6200000-0000-0000-0000-0000000000a1',
'internal','pending','No publicar','Borrador privado','low','OT-FM-DRAFT',NULL,'f6400000-0000-0000-0000-0000000000a1');

-- Security and schema invariant checks run as test owner before switching roles.

SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
('can_view_work_orders_as_facility_manager','can_view_facility_management_work_order_price',
'facility_management_work_order_read_payload','get_facility_management_work_orders',
'get_facility_management_work_order')),5,'9C.6-B1 registers exactly five functions');

SELECT ok((SELECT bool_and(prosecdef AND proconfig @> ARRAY['search_path=""'::text])
FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
('get_facility_management_work_orders','get_facility_management_work_order')),
'Public read RPCs are SECURITY DEFINER and have empty search_path');

SELECT ok((SELECT bool_and(NOT has_function_privilege('anon',oid,'EXECUTE')
AND has_function_privilege('authenticated',oid,'EXECUTE'))
FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
('get_facility_management_work_orders','get_facility_management_work_order')),
'Only authenticated can call the public read RPCs');

SELECT ok((SELECT bool_and(NOT has_function_privilege('authenticated',oid,'EXECUTE')
AND NOT has_function_privilege('anon',oid,'EXECUTE'))
FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
('can_view_work_orders_as_facility_manager','can_view_facility_management_work_order_price','facility_management_work_order_read_payload')),
'Internal helpers are not executable by client roles');

SELECT ok((SELECT bool_and(coalesce(qual,'') NOT ILIKE '%facility_management%') FROM pg_policies
WHERE schemaname='public' AND tablename IN
('work_orders','work_order_activities','work_order_materials','work_order_activity_reports')),
'9C.6-B1 does not widen existing RLS policies');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');

SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') ->> 'total')::int,3,'Manager sees 3 own-client orders');

SELECT is(jsonb_array_length(public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1')->'items'),3,'Manager list returns 3 items');

SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1','pending')->>'total')::int,1,'Status filter pending returns one order');

SELECT is(jsonb_array_length(public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1',NULL,1,0)->'items'),1,'Bounded pagination returns one item');

SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1',NULL,1,2)->>'total')::int,3,'Pagination preserves total');

SELECT is(jsonb_array_length(public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1',NULL,1,3)->'items'),0,'Offset past last result yields empty page');

SELECT is((public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a1')->>'total_amount')::numeric,1700::numeric,'Approved quote with min met exposes authorized amount');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a2')->>'total_amount',NULL::text,'Hidden quote never exposes amount');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a2')->>'title','Orden externa','Free text title masked while price hidden');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a2')->>'description',NULL::text,'Free text description masked while price hidden');

SELECT ok(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a2')::text !~ '(1700|1800|SECRETO PROVEEDOR)','No amounts or provider observations leak in hidden payload');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a1')->>'asset_label','Equipo QA seguro','Asset label shown only with assets.view');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a3')->>'title','Trabajo interno','Internal order readable');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a3')->>'total_amount',NULL::text,'Internal order does not reveal unrelated quote money');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a3')->>'can_manage','false','B1 never grants write controls');

SELECT ok(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a1')::text !~ 'SECRETO PROVEEDOR|PRIVADO B|provider_organization_id|assigned_member_id|planner_member_id|created_by_user_id|quote_id|observations|work_order_materials|activity_reports|work_order_work_logs','No provider IDs, private logs, or internal descriptions');

SELECT throws_ok($$ SELECT public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000b1') $$,'42501',NULL,'Cross-client order ID denied');

SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000ff') $qa$,'42501',NULL,'Unknown order ID denied indistinguishably');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a4') $qa$,
'42501',NULL,'OT sourced from a draft request is not visible even with same client');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000b1') $$,'42501',NULL,'Manager A cannot list client B');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1','invalid-status') $$,'22023',NULL,'Invalid status is rejected');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1',NULL,101,0) $$,'22023',NULL,'Excessive limit is rejected');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1',NULL,0,0) $$,'22023',NULL,'Zero limit is rejected');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1',NULL,50,-1) $$,'22023',NULL,'Negative offset is rejected');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000002');

SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1')->>'total')::int,3,'Assigned owner may read OT with both grants');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000003');

SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1')->>'total')::int,3,'Assigned admin may read OT with both grants');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000005');

SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1')->>'total')::int,3,'Assigned requester may read OT with both grants');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000006');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'tech cannot read delegated OT');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000007');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'viewer cannot read delegated OT');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000008');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'unassigned cannot read delegated OT');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000010');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'outsider cannot read delegated OT');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000009');

SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000b1')->>'total')::int,1,'Assigned FM B sees only its own client');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'FM B cannot cross into client A');

SELECT pg_temp.as_user(NULL);

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'Authenticated role without auth.uid is denied');

RESET ROLE;
DELETE FROM public.facility_management_permissions
WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND permission='work_orders.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'Revoking work_orders.view immediately denies access');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES('f6700000-0000-0000-0000-0000000000a1','work_orders.view');
DELETE FROM public.facility_management_permissions
WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND permission='requests.view';
SET LOCAL ROLE authenticated;

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'work_orders.view without requests.view is insufficient');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES('f6700000-0000-0000-0000-0000000000a1','requests.view');
DELETE FROM public.facility_management_permissions
WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND permission='quotes.view';
SET LOCAL ROLE authenticated;

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a1')->>'total_amount',NULL::text,'Without quotes.view approved amount becomes null');

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a1')->>'title','Orden externa','Without quotes.view externally supplied title is masked');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES('f6700000-0000-0000-0000-0000000000a1','quotes.view');
DELETE FROM public.facility_management_permissions
WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND permission='assets.view';
SET LOCAL ROLE authenticated;

SELECT is(public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a3')->>'asset_label',NULL::text,'Without assets.view asset label is null');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES('f6700000-0000-0000-0000-0000000000a1','assets.view');
UPDATE public.requests SET quotes_closed=true WHERE id='f6800000-0000-0000-0000-0000000000a2';
SET LOCAL ROLE authenticated;

SELECT is((public.get_facility_management_work_order('f6200000-0000-0000-0000-0000000000a1','f6a00000-0000-0000-0000-0000000000a2')->>'total_amount')::numeric,1800::numeric,'Closing quote submission reveals price under min as in 9C.5');

RESET ROLE;
UPDATE public.requests SET quotes_closed=false WHERE id='f6800000-0000-0000-0000-0000000000a2';
UPDATE public.organization_relationships SET status='suspended' WHERE id='f6700000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'Suspended relation immediately denies access');

RESET ROLE;
UPDATE public.organization_relationships SET status='active' WHERE id='f6700000-0000-0000-0000-0000000000a1';
DELETE FROM public.facility_management_relationship_members
WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND organization_member_id='f6300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'Unassigning manager immediately denies access');

RESET ROLE;
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id)
VALUES('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000004');
UPDATE public.organization_members SET is_active=false WHERE id='f6300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'Inactive FM membership denies access');

RESET ROLE;
UPDATE public.organization_members SET is_active=true WHERE id='f6300000-0000-0000-0000-000000000004';
UPDATE public.organizations SET status='suspended' WHERE id='f6200000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;

SELECT throws_ok($$ SELECT public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1') $$,'42501',NULL,'Suspended client denies delegated access');

RESET ROLE;
-- Strict ACL variant: no direct work-order / quote / request / asset SELECT.
REVOKE SELECT ON public.work_orders, public.quotes, public.requests, public.assets FROM authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_work_orders('f6200000-0000-0000-0000-0000000000a1')->>'total')::int,
3,'Guarded RPC works without raw SELECT privileges');
SELECT throws_ok($qa$ SELECT * FROM public.work_orders LIMIT 1 $qa$,
'42501',NULL,'Raw work_orders SELECT is denied under strict ACL');

SELECT * FROM finish();
ROLLBACK;