-- 9C.7-B2. All synthetic data is removed by ROLLBACK. Execute ONLY in local/isolated Supabase.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
-- Dynamic plan marker is substituted below.
SELECT plan(62);
CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text,''), true);
$$;

INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES
  ('c8100000-0000-0000-0000-000000000001','co@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000002','owner@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000003','admin@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000004','manager@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000005','requester@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000006','tech@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000007','viewer@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000008','unassigned@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000009','otherfm@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000010','outsider@fm-trends-qa.test','{}'),
  ('c8100000-0000-0000-0000-000000000011','provider@fm-trends-qa.test','{}');

INSERT INTO public.organizations (id,name,organization_type) VALUES
('c8200000-0000-0000-0000-0000000000a1','FM OT Client A','client_company'),
('c8200000-0000-0000-0000-0000000000b1','FM OT Client B','client_company'),
('c8200000-0000-0000-0000-0000000000fa','FM OT Manager A','facility_manager'),
('c8200000-0000-0000-0000-0000000000fb','FM OT Manager B','facility_manager'),
('c8200000-0000-0000-0000-0000000000c1','FM OT Provider','provider_company');

INSERT INTO public.organization_members (id,organization_id,user_id,role,is_active) VALUES
('c8300000-0000-0000-0000-000000000001','c8200000-0000-0000-0000-0000000000a1','c8100000-0000-0000-0000-000000000001','owner',true),
('c8300000-0000-0000-0000-000000000002','c8200000-0000-0000-0000-0000000000fa','c8100000-0000-0000-0000-000000000002','owner',true),
('c8300000-0000-0000-0000-000000000003','c8200000-0000-0000-0000-0000000000fa','c8100000-0000-0000-0000-000000000003','admin',true),
('c8300000-0000-0000-0000-000000000004','c8200000-0000-0000-0000-0000000000fa','c8100000-0000-0000-0000-000000000004','manager',true),
('c8300000-0000-0000-0000-000000000005','c8200000-0000-0000-0000-0000000000fa','c8100000-0000-0000-0000-000000000005','requester',true),
('c8300000-0000-0000-0000-000000000006','c8200000-0000-0000-0000-0000000000fa','c8100000-0000-0000-0000-000000000006','technician',true),
('c8300000-0000-0000-0000-000000000007','c8200000-0000-0000-0000-0000000000fa','c8100000-0000-0000-0000-000000000007','viewer',true),
('c8300000-0000-0000-0000-000000000008','c8200000-0000-0000-0000-0000000000fa','c8100000-0000-0000-0000-000000000008','manager',true),
('c8300000-0000-0000-0000-000000000009','c8200000-0000-0000-0000-0000000000fb','c8100000-0000-0000-0000-000000000009','manager',true),
('c8300000-0000-0000-0000-000000000010','c8200000-0000-0000-0000-0000000000c1','c8100000-0000-0000-0000-000000000011','owner',true);

INSERT INTO public.organization_relationships
(id,source_organization_id,target_organization_id,relationship_type,status) VALUES
('c8700000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000fa','facility_management','pending'),
('c8700000-0000-0000-0000-0000000000b1','c8200000-0000-0000-0000-0000000000b1','c8200000-0000-0000-0000-0000000000fb','facility_management','pending');
UPDATE public.organization_relationships SET status='active' WHERE id IN ('c8700000-0000-0000-0000-0000000000a1','c8700000-0000-0000-0000-0000000000b1');
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES
('c8700000-0000-0000-0000-0000000000a1','requests.view'),('c8700000-0000-0000-0000-0000000000a1','work_orders.view'),
('c8700000-0000-0000-0000-0000000000a1','quotes.view'),('c8700000-0000-0000-0000-0000000000a1','assets.view'),
('c8700000-0000-0000-0000-0000000000b1','requests.view'),('c8700000-0000-0000-0000-0000000000b1','work_orders.view');
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id) VALUES
('c8700000-0000-0000-0000-0000000000a1','c8300000-0000-0000-0000-000000000002'),
('c8700000-0000-0000-0000-0000000000a1','c8300000-0000-0000-0000-000000000003'),
('c8700000-0000-0000-0000-0000000000a1','c8300000-0000-0000-0000-000000000004'),
('c8700000-0000-0000-0000-0000000000a1','c8300000-0000-0000-0000-000000000005'),
('c8700000-0000-0000-0000-0000000000a1','c8300000-0000-0000-0000-000000000006'),
('c8700000-0000-0000-0000-0000000000a1','c8300000-0000-0000-0000-000000000007'),
('c8700000-0000-0000-0000-0000000000b1','c8300000-0000-0000-0000-000000000009');

INSERT INTO public.assets(id,organization_id,code,name,node_type,status)
VALUES ('c8400000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000a1','A-OT-TEST','Equipo QA seguro','equipment','active');

INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes,quotes_closed)
VALUES
('c8800000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000a1','FM-OT-TEST-001','Cotizacion autorizada','Solicitud visible','Equipo QA','c8400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',1,false),
('c8800000-0000-0000-0000-0000000000a2','c8200000-0000-0000-0000-0000000000a1','FM-OT-TEST-002','Cotizacion bajo minimo','Solicitud restringida','Equipo QA','c8400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',2,false),
('c8800000-0000-0000-0000-0000000000a3','c8200000-0000-0000-0000-0000000000a1','FM-OT-TEST-003','Servicio interno','Solicitud interna','Equipo QA','c8400000-0000-0000-0000-0000000000a1','Lima','preventivo',now()+interval '10 days','sent','internal',false,'fixture',1,false),
('c8800000-0000-0000-0000-0000000000b1','c8200000-0000-0000-0000-0000000000b1','FM-OT-TEST-004','Cliente B','Servicio B','Activo B',NULL,'Lima','correctivo',now()+interval '10 days','sent','internal',false,'fixture',1,false);

INSERT INTO public.quotes
(id,request_id,provider_organization_id,created_by_user_id,amount,description,status,total_amount)
VALUES
('c8900000-0000-0000-0000-0000000000a1','c8800000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000c1','c8100000-0000-0000-0000-000000000011',1700,'Propuesta visible S/ 1700','approved',1700),
('c8900000-0000-0000-0000-0000000000a2','c8800000-0000-0000-0000-0000000000a2','c8200000-0000-0000-0000-0000000000c1','c8100000-0000-0000-0000-000000000011',1800,'Propuesta oculta S/ 1800','approved',1800);

INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id,observations)
VALUES
('c8a00000-0000-0000-0000-0000000000a1','c8800000-0000-0000-0000-0000000000a1','c8900000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000c1','external','completed','Trabajo externo autorizado S/ 1700','Descripción S/ 1700','high','OT-FM-001',1700,'c8400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('c8a00000-0000-0000-0000-0000000000a2','c8800000-0000-0000-0000-0000000000a2','c8900000-0000-0000-0000-0000000000a2','c8200000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000c1','external','pending','Oferta oculta S/ 1800','Descripción oculta S/ 1800','urgent','OT-FM-002',1800,'c8400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('c8a00000-0000-0000-0000-0000000000a3','c8800000-0000-0000-0000-0000000000a3',NULL,'c8200000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000a1','internal','closed','Trabajo interno','Descripción del cliente','medium','OT-FM-003',NULL,'c8400000-0000-0000-0000-0000000000a1','NOTA INTERNA DE OPERADOR'),
('c8a00000-0000-0000-0000-0000000000b1','c8800000-0000-0000-0000-0000000000b1',NULL,'c8200000-0000-0000-0000-0000000000b1','c8200000-0000-0000-0000-0000000000b1','internal','pending','Trabajo de otro cliente','Privado B','low','OT-FM-004',NULL,NULL,'PRIVADO B');

-- Deliberately invalid source state: must not appear through delegated OT RPCs.
INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes)
VALUES ('c8800000-0000-0000-0000-0000000000a4','c8200000-0000-0000-0000-0000000000a1',
'FM-OT-TEST-005','Borrador oculto','Solo borrador','Equipo QA','c8400000-0000-0000-0000-0000000000a1',
'Lima','correctivo',now()+interval '10 days','draft','internal',false,'fixture',1);
INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id)
VALUES ('c8a00000-0000-0000-0000-0000000000a4',
'c8800000-0000-0000-0000-0000000000a4',NULL,
'c8200000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000a1',
'internal','pending','No publicar','Borrador privado','low','OT-FM-DRAFT',NULL,'c8400000-0000-0000-0000-0000000000a1');


-- 9C.7-B2 isolated pgTAP: repeat existing 9C.7-B1 fixtures in an
-- independent ROLLBACK. This suite NEVER writes to Supabase Cloud.
SELECT ok((SELECT prosecdef AND provolatile='s' AND
  proconfig @> ARRAY['search_path=""'::text] AND
  proconfig @> ARRAY['statement_timeout=5s'::text]
  FROM pg_proc WHERE oid='public.get_facility_management_client_trends(uuid,uuid,date,date,text)'::regprocedure),
 'New trends RPC is STABLE SECURITY DEFINER with strict search_path and timeout');
SELECT ok(NOT has_function_privilege('anon',
 'public.get_facility_management_client_trends(uuid,uuid,date,date,text)','EXECUTE'),
 'anon cannot execute trend RPC');
SELECT ok(NOT has_function_privilege('service_role',
 'public.get_facility_management_client_trends(uuid,uuid,date,date,text)','EXECUTE'),
 'service_role is not granted trends execution');
SELECT ok(has_function_privilege('authenticated',
 'public.get_facility_management_client_trends(uuid,uuid,date,date,text)','EXECUTE'),
 'Authenticated may invoke but must pass all server-side gates');
SELECT ok((SELECT count(*)=0 FROM pg_policies WHERE schemaname='public'
 AND tablename='work_orders' AND qual ILIKE '%get_facility_management_client_trends%'),
 'No work_orders RLS policy broadened by B2');

-- Dates straddle the 05:00Z midnight boundary of America/Lima (UTC-05).
-- Draft source work_order a4 is excluded; draft request a4 is a CREATED request.
UPDATE public.requests
 SET created_at = CASE id
 WHEN 'c8800000-0000-0000-0000-0000000000a1' THEN '2026-09-01 04:59:59+00'::timestamptz
 WHEN 'c8800000-0000-0000-0000-0000000000a2' THEN '2026-09-01 05:00:00+00'::timestamptz
 WHEN 'c8800000-0000-0000-0000-0000000000a3' THEN '2026-09-02 05:00:00+00'::timestamptz
 WHEN 'c8800000-0000-0000-0000-0000000000a4' THEN '2026-09-02 05:00:00+00'::timestamptz
 ELSE created_at END
 WHERE id IN (
 'c8800000-0000-0000-0000-0000000000a1','c8800000-0000-0000-0000-0000000000a2',
 'c8800000-0000-0000-0000-0000000000a3','c8800000-0000-0000-0000-0000000000a4'
 );
UPDATE public.requests SET created_at='2026-09-01 05:00:00+00'::timestamptz
 WHERE id='c8800000-0000-0000-0000-0000000000b1';
UPDATE public.work_orders SET
 created_at = CASE id
 WHEN 'c8a00000-0000-0000-0000-0000000000a1' THEN '2026-09-01 04:59:59+00'::timestamptz
 WHEN 'c8a00000-0000-0000-0000-0000000000a2' THEN '2026-09-01 05:00:00+00'::timestamptz
 WHEN 'c8a00000-0000-0000-0000-0000000000a3' THEN '2026-09-02 05:00:00+00'::timestamptz
 WHEN 'c8a00000-0000-0000-0000-0000000000a4' THEN '2026-09-01 05:00:00+00'::timestamptz
 ELSE created_at END,
 completed_at = CASE id
 WHEN 'c8a00000-0000-0000-0000-0000000000a1' THEN '2026-09-01 05:00:00+00'::timestamptz
 WHEN 'c8a00000-0000-0000-0000-0000000000a3' THEN '2026-09-03 04:59:59+00'::timestamptz
 ELSE completed_at END
 WHERE id IN (
 'c8a00000-0000-0000-0000-0000000000a1','c8a00000-0000-0000-0000-0000000000a2',
 'c8a00000-0000-0000-0000-0000000000a3','c8a00000-0000-0000-0000-0000000000a4');
UPDATE public.work_orders SET created_at='2026-09-01 05:00:00+00'::timestamptz
 WHERE id='c8a00000-0000-0000-0000-0000000000b1';

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Assigned FM manager without reports.view denied');
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000001');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Direct client owner does not inherit report access');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('c8700000-0000-0000-0000-0000000000a1','reports.view');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT is(pg_catalog.jsonb_array_length(public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'),3,
 'Inclusive 3-day OT series has no gaps');
SELECT is(pg_catalog.jsonb_array_length(public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'requests'->'daily'),3,
 'Inclusive 3-day requests series has no gaps');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'date'),'2026-08-31',
 'UTC 04:59:59 falls on Aug 31 in Peru');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->1->>'date'),'2026-09-01',
 'UTC 05:00 falls on Sep 1 in Peru');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'created')::integer,1,
 'Aug31 created at UTC 04:59:59 included');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'completed')::integer,0,
 'Aug31 has zero completed');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->1->>'created')::integer,1,
 'Sep1 created at local midnight included');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->1->>'completed')::integer,1,
 'Sep1 completion sourced from completed_at');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->2->>'created')::integer,1,
 'Sep2 created counted');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->2->>'completed')::integer,1,
 'Sep2 completion at local 23:59:59 counted');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'requests'->'daily'->0->>'created')::integer,1,
 'Aug31 request count');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'requests'->'daily'->1->>'created')::integer,1,
 'Sep1 request count');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'requests'->'daily'->2->>'created')::integer,2,
 'Sep2 counts two created requests including draft');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->>'time_zone'),'America/Lima',
 'Explicit report timezone returned');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->>'start_date'),'2026-08-31',
 'Inclusive start date returned');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->>'end_date'),'2026-09-02',
 'Inclusive end date returned');
SELECT is(pg_catalog.jsonb_typeof(public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'as_of'),'string',
 'As-of timestamp is supplied');
SELECT ok(public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)::text !~ '1700|1800|total_amount|provider_organization_id|technician|idempotency|notes|SECRETO PROVEEDOR|work_order_number',
 'DTO contains no amounts/provider/technician/private fields');
SELECT is(pg_catalog.jsonb_array_length(public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-10-01'::date,'2026-10-02'::date,'America/Lima'::text)->'work_orders'->'daily'),2,
 'Authorized empty range is a complete two-day series');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-10-01'::date,'2026-10-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'created')::integer,0,
 'Authorized empty day is numeric zero');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-10-01'::date,'2026-10-02'::date,'America/Lima'::text)->'requests'->'daily'->1->>'created')::integer,0,
 'Authorized empty request day is numeric zero');
SELECT is(pg_catalog.jsonb_array_length(public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2025-09-01'::date,'2026-09-01'::date,'America/Lima'::text)->'work_orders'->'daily'),366,
 '366 inclusive days accepted');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2025-08-31'::date,'2026-09-01'::date,'America/Lima'::text) $tr$,
 '22023',NULL,'367 inclusive days rejected');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-09-02'::date,'2026-08-31'::date,'America/Lima'::text) $tr$,
 '22023',NULL,'Reversed date range rejected');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'UTC'::text) $tr$,
 '22023',NULL,'Unapproved UTC zone rejected');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,NULL,'2026-09-02'::date,'America/Lima') $tr$,
 '22023',NULL,'Missing start date rejected');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,NULL,'America/Lima') $tr$,
 '22023',NULL,'Missing end date rejected');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,NULL) $tr$,
 '22023',NULL,'Missing zone rejected');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'infinity'::date,'infinity'::date,'America/Lima'::text) $tr$,
 '22023',NULL,'Nonfinite dates rejected');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-08-31'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'created')::integer,1,
 'Start and end same day supported');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-09-01'::date,'2026-09-01'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'completed')::integer,1,
 'Date filtering uses local midnight inclusive/exclusive boundaries');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000b1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'UTC'::text) $tr$,
 '42501',NULL,'Client UUID swapped cannot enumerate trends');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000b1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Relationship from another client denied');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000ff'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Unknown relationship hidden');
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000008');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Unassigned FM manager denied');
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000005');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Requester role denied');
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000011');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Provider owner denied');
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000002');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'created')::integer,1,
 'Assigned FM owner permitted');
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000003');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'created')::integer,1,
 'Assigned FM admin permitted');
RESET ROLE;

-- A second FM for the same client has a separate permission scope.
INSERT INTO public.organization_relationships
(id,source_organization_id,target_organization_id,relationship_type,status)
VALUES('c8700000-0000-0000-0000-0000000000c1','c8200000-0000-0000-0000-0000000000a1','c8200000-0000-0000-0000-0000000000fb',
 'facility_management','pending');
UPDATE public.organization_relationships SET status='active' WHERE id='c8700000-0000-0000-0000-0000000000c1';
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id)
VALUES('c8700000-0000-0000-0000-0000000000c1','c8300000-0000-0000-0000-000000000009');
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('c8700000-0000-0000-0000-0000000000c1','reports.view'),('c8700000-0000-0000-0000-0000000000c1','requests.view');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000009');
SELECT ok((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000c1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'availability'->>'requests')='true',
 'Second FM can view authorized requests for the same client');
SELECT ok((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000c1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'availability'->>'work_orders')='false',
 'Second FM without work_orders.view lacks order trends');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000c1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders')::text,'null',
 'No domain grant returns null, not zero');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000c1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'requests'->'daily'->2->>'created')::integer,2,
 'Second FM request-only trend still accurate');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Second FM cannot use first relationship ID');
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000c1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'First FM cannot use second relationship ID');
RESET ROLE;
DELETE FROM public.facility_management_permissions
WHERE relationship_id='c8700000-0000-0000-0000-0000000000a1' AND permission='work_orders.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders')::text,'null',
 'Work orders hidden immediately on domain grant revocation');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'requests'->'daily'->0->>'created')::integer,1,
 'Requests remain authorized after work_orders.view revoked');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('c8700000-0000-0000-0000-0000000000a1','work_orders.view');
DELETE FROM public.facility_management_permissions
WHERE relationship_id='c8700000-0000-0000-0000-0000000000a1' AND permission='requests.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'requests')::text,'null',
 'Request section null when requests.view revoked');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders')::text,'null',
 'OT trends additionally require requests.view');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('c8700000-0000-0000-0000-0000000000a1','requests.view');
DELETE FROM public.facility_management_permissions
WHERE relationship_id='c8700000-0000-0000-0000-0000000000a1' AND permission='reports.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Reports revocation immediately denies every trend');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('c8700000-0000-0000-0000-0000000000a1','reports.view');
UPDATE public.organization_relationships SET status='suspended' WHERE id='c8700000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Suspended FM-client relationship denied');
RESET ROLE;
UPDATE public.organization_relationships SET status='active' WHERE id='c8700000-0000-0000-0000-0000000000a1';
UPDATE public.organizations SET status='suspended' WHERE id='c8200000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Suspended client denied');
RESET ROLE;
UPDATE public.organizations SET status='active' WHERE id='c8200000-0000-0000-0000-0000000000a1';
UPDATE public.organization_members SET is_active=false
WHERE id='c8300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Inactive assigned manager denied');
RESET ROLE;
UPDATE public.organization_members SET is_active=true
WHERE id='c8300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('c8100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->1->>'created')::integer,1,
 'Authorized access restored after all gates restored');
SELECT pg_temp.as_user(NULL);
SELECT throws_ok($tr$ SELECT public.get_facility_management_client_trends('c8200000-0000-0000-0000-0000000000a1'::uuid,'c8700000-0000-0000-0000-0000000000a1'::uuid,'2026-08-31'::date,'2026-09-02'::date,'America/Lima'::text) $tr$,
 '42501',NULL,'Authenticated database role without auth.uid denied');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
