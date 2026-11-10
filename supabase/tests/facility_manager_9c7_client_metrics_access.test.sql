-- 9C.6-B1. All synthetic data is removed by ROLLBACK. Execute ONLY in local/isolated Supabase.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
-- Dynamic plan marker is substituted below.
SELECT plan(59);
CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text,''), true);
$$;

INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES
  ('b7100000-0000-0000-0000-000000000001','co@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000002','owner@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000003','admin@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000004','manager@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000005','requester@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000006','tech@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000007','viewer@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000008','unassigned@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000009','otherfm@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000010','outsider@fm-metrics-qa.test','{}'),
  ('b7100000-0000-0000-0000-000000000011','provider@fm-metrics-qa.test','{}');

INSERT INTO public.organizations (id,name,organization_type) VALUES
('b7200000-0000-0000-0000-0000000000a1','FM OT Client A','client_company'),
('b7200000-0000-0000-0000-0000000000b1','FM OT Client B','client_company'),
('b7200000-0000-0000-0000-0000000000fa','FM OT Manager A','facility_manager'),
('b7200000-0000-0000-0000-0000000000fb','FM OT Manager B','facility_manager'),
('b7200000-0000-0000-0000-0000000000c1','FM OT Provider','provider_company');

INSERT INTO public.organization_members (id,organization_id,user_id,role,is_active) VALUES
('b7300000-0000-0000-0000-000000000001','b7200000-0000-0000-0000-0000000000a1','b7100000-0000-0000-0000-000000000001','owner',true),
('b7300000-0000-0000-0000-000000000002','b7200000-0000-0000-0000-0000000000fa','b7100000-0000-0000-0000-000000000002','owner',true),
('b7300000-0000-0000-0000-000000000003','b7200000-0000-0000-0000-0000000000fa','b7100000-0000-0000-0000-000000000003','admin',true),
('b7300000-0000-0000-0000-000000000004','b7200000-0000-0000-0000-0000000000fa','b7100000-0000-0000-0000-000000000004','manager',true),
('b7300000-0000-0000-0000-000000000005','b7200000-0000-0000-0000-0000000000fa','b7100000-0000-0000-0000-000000000005','requester',true),
('b7300000-0000-0000-0000-000000000006','b7200000-0000-0000-0000-0000000000fa','b7100000-0000-0000-0000-000000000006','technician',true),
('b7300000-0000-0000-0000-000000000007','b7200000-0000-0000-0000-0000000000fa','b7100000-0000-0000-0000-000000000007','viewer',true),
('b7300000-0000-0000-0000-000000000008','b7200000-0000-0000-0000-0000000000fa','b7100000-0000-0000-0000-000000000008','manager',true),
('b7300000-0000-0000-0000-000000000009','b7200000-0000-0000-0000-0000000000fb','b7100000-0000-0000-0000-000000000009','manager',true),
('b7300000-0000-0000-0000-000000000010','b7200000-0000-0000-0000-0000000000c1','b7100000-0000-0000-0000-000000000011','owner',true);

INSERT INTO public.organization_relationships
(id,source_organization_id,target_organization_id,relationship_type,status) VALUES
('b7700000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000fa','facility_management','pending'),
('b7700000-0000-0000-0000-0000000000b1','b7200000-0000-0000-0000-0000000000b1','b7200000-0000-0000-0000-0000000000fb','facility_management','pending');
UPDATE public.organization_relationships SET status='active' WHERE id IN ('b7700000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000b1');
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES
('b7700000-0000-0000-0000-0000000000a1','requests.view'),('b7700000-0000-0000-0000-0000000000a1','work_orders.view'),
('b7700000-0000-0000-0000-0000000000a1','quotes.view'),('b7700000-0000-0000-0000-0000000000a1','assets.view'),
('b7700000-0000-0000-0000-0000000000b1','requests.view'),('b7700000-0000-0000-0000-0000000000b1','work_orders.view');
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id) VALUES
('b7700000-0000-0000-0000-0000000000a1','b7300000-0000-0000-0000-000000000002'),
('b7700000-0000-0000-0000-0000000000a1','b7300000-0000-0000-0000-000000000003'),
('b7700000-0000-0000-0000-0000000000a1','b7300000-0000-0000-0000-000000000004'),
('b7700000-0000-0000-0000-0000000000a1','b7300000-0000-0000-0000-000000000005'),
('b7700000-0000-0000-0000-0000000000a1','b7300000-0000-0000-0000-000000000006'),
('b7700000-0000-0000-0000-0000000000a1','b7300000-0000-0000-0000-000000000007'),
('b7700000-0000-0000-0000-0000000000b1','b7300000-0000-0000-0000-000000000009');

INSERT INTO public.assets(id,organization_id,code,name,node_type,status)
VALUES ('b7400000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000a1','A-OT-TEST','Equipo QA seguro','equipment','active');

INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes,quotes_closed)
VALUES
('b7800000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000a1','FM-OT-TEST-001','Cotizacion autorizada','Solicitud visible','Equipo QA','b7400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',1,false),
('b7800000-0000-0000-0000-0000000000a2','b7200000-0000-0000-0000-0000000000a1','FM-OT-TEST-002','Cotizacion bajo minimo','Solicitud restringida','Equipo QA','b7400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',2,false),
('b7800000-0000-0000-0000-0000000000a3','b7200000-0000-0000-0000-0000000000a1','FM-OT-TEST-003','Servicio interno','Solicitud interna','Equipo QA','b7400000-0000-0000-0000-0000000000a1','Lima','preventivo',now()+interval '10 days','sent','internal',false,'fixture',1,false),
('b7800000-0000-0000-0000-0000000000b1','b7200000-0000-0000-0000-0000000000b1','FM-OT-TEST-004','Cliente B','Servicio B','Activo B',NULL,'Lima','correctivo',now()+interval '10 days','sent','internal',false,'fixture',1,false);

INSERT INTO public.quotes
(id,request_id,provider_organization_id,created_by_user_id,amount,description,status,total_amount)
VALUES
('b7900000-0000-0000-0000-0000000000a1','b7800000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000c1','b7100000-0000-0000-0000-000000000011',1700,'Propuesta visible S/ 1700','approved',1700),
('b7900000-0000-0000-0000-0000000000a2','b7800000-0000-0000-0000-0000000000a2','b7200000-0000-0000-0000-0000000000c1','b7100000-0000-0000-0000-000000000011',1800,'Propuesta oculta S/ 1800','approved',1800);

INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id,observations)
VALUES
('b7a00000-0000-0000-0000-0000000000a1','b7800000-0000-0000-0000-0000000000a1','b7900000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000c1','external','completed','Trabajo externo autorizado S/ 1700','Descripción S/ 1700','high','OT-FM-001',1700,'b7400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('b7a00000-0000-0000-0000-0000000000a2','b7800000-0000-0000-0000-0000000000a2','b7900000-0000-0000-0000-0000000000a2','b7200000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000c1','external','pending','Oferta oculta S/ 1800','Descripción oculta S/ 1800','urgent','OT-FM-002',1800,'b7400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('b7a00000-0000-0000-0000-0000000000a3','b7800000-0000-0000-0000-0000000000a3',NULL,'b7200000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000a1','internal','closed','Trabajo interno','Descripción del cliente','medium','OT-FM-003',NULL,'b7400000-0000-0000-0000-0000000000a1','NOTA INTERNA DE OPERADOR'),
('b7a00000-0000-0000-0000-0000000000b1','b7800000-0000-0000-0000-0000000000b1',NULL,'b7200000-0000-0000-0000-0000000000b1','b7200000-0000-0000-0000-0000000000b1','internal','pending','Trabajo de otro cliente','Privado B','low','OT-FM-004',NULL,NULL,'PRIVADO B');

-- Deliberately invalid source state: must not appear through delegated OT RPCs.
INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes)
VALUES ('b7800000-0000-0000-0000-0000000000a4','b7200000-0000-0000-0000-0000000000a1',
'FM-OT-TEST-005','Borrador oculto','Solo borrador','Equipo QA','b7400000-0000-0000-0000-0000000000a1',
'Lima','correctivo',now()+interval '10 days','draft','internal',false,'fixture',1);
INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id)
VALUES ('b7a00000-0000-0000-0000-0000000000a4',
'b7800000-0000-0000-0000-0000000000a4',NULL,
'b7200000-0000-0000-0000-0000000000a1','b7200000-0000-0000-0000-0000000000a1',
'internal','pending','No publicar','Borrador privado','low','OT-FM-DRAFT',NULL,'b7400000-0000-0000-0000-0000000000a1');


-- 9C.7-B1: approved D1-D7, ONLY on disposable Supabase, all rows ROLLBACK.
-- No reports.view initially; do not equate domain view grants with report access.
SELECT is((SELECT count(*)::integer FROM pg_proc
 WHERE pronamespace='public'::regnamespace
   AND proname='get_facility_management_client_metrics'),1,
 'B1 new RPC is installed exactly once');
SELECT ok((SELECT prosecdef AND provolatile='s' AND
 proconfig @> ARRAY['search_path=""'::text]
 FROM pg_proc WHERE oid='public.get_facility_management_client_metrics(uuid,uuid)'::regprocedure),
 'RPC is stable SECURITY DEFINER with empty search_path');
SELECT ok(NOT has_function_privilege('anon',
 'public.get_facility_management_client_metrics(uuid,uuid)','EXECUTE'),
 'anon cannot call B1 RPC');
SELECT ok(NOT has_function_privilege('service_role',
 'public.get_facility_management_client_metrics(uuid,uuid)','EXECUTE'),
 'service_role has no direct B1 RPC grant');
SELECT ok(has_function_privilege('authenticated',
 'public.get_facility_management_client_metrics(uuid,uuid)','EXECUTE'),
 'Only authenticated can invoke B1 public interface');
SELECT ok((SELECT COUNT(*)=0 FROM pg_policies
 WHERE schemaname='public' AND tablename='work_orders'
   AND (qual ILIKE '%reports.view%' OR qual ILIKE '%facility_management_client_metrics%')),
 'Existing OT RLS policies are not broadened for reporting');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'FM manager with domain grants but WITHOUT reports.view is denied');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000001');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Direct client owner does not inherit delegated reporting permission');
RESET ROLE;

INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('b7700000-0000-0000-0000-0000000000a1','reports.view');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->>'total')::integer,3,'Eligible OT count excludes draft-sourced OT');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->>'open')::integer,1,'Only pending/assigned/in_progress are open');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->>'overdue_open')::integer,0,'No due_at means no overdue OT');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->'by_status'->>'pending')::integer,1,'Pending status counted');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->'by_status'->>'completed')::integer,1,'Completed status counted');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->'by_status'->>'closed')::integer,1,'Closed status counted');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->'by_type'->>'internal')::integer,1,'Internal orders counted by client');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->'by_type'->>'external')::integer,2,'External orders counted by client');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'requests'->>'open')::integer,3,'Sent and quoted requests only, excludes draft');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'assets'->>'active')::integer,1,'One active asset');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'assets'->>'critical')::integer,0,'Authorized zero is literal zero, not unavailable');
SELECT ok((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'availability'->>'work_orders')='true','Explicit availability flag for authorized OT');
SELECT ok((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'availability'->>'assets')='true','Explicit availability flag for authorized assets');
SELECT is(pg_catalog.jsonb_typeof(public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'as_of'),'string','Single as_of timestamp provided');
SELECT ok(public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')::text
 !~ '1700|1800|total_amount|quote_id|provider_organization_id|activity|technician|notes|user_id|work_order_number|SECRETO PROVEEDOR',
 'Aggregate DTO does not leak amounts, quote IDs or private provider operations');

SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000002');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->>'total')::integer,3,'Assigned FM owner can read');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000003');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->>'total')::integer,3,'Assigned FM admin can read');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000005');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Requester cannot view manager-only metrics despite reports grant');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000006');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Technician cannot view manager-only metrics');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000007');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Viewer cannot view manager-only metrics');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000008');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Unassigned FM manager denied');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000010');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Unrelated outsider denied');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000011');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Provider owner denied');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000009');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000b1',
  'b7700000-0000-0000-0000-0000000000b1') $q$,
 '42501',NULL,'Second FM without reports grant denied');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000b1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Swapped client UUID cannot enumerate report');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000b1') $q$,
 '42501',NULL,'Other-client relationship ID denied');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000ff') $q$,
 '42501',NULL,'Unknown relationship hidden with same 42501');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  NULL,'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Null client denied without enumeration');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',NULL) $q$,
 '42501',NULL,'Null relationship denied');
SELECT throws_ok($q$ SELECT * FROM public.get_dashboard_metrics(
 'b7200000-0000-0000-0000-0000000000a1') $q$,
 'P0001',NULL,'Existing direct-organization dashboard remains inaccessible to FM-only member');
RESET ROLE;

-- A second FM relationship for SAME client must not inherit another FM grant.
INSERT INTO public.organization_relationships(
 id,source_organization_id,target_organization_id,relationship_type,status
) VALUES(
 'b7700000-0000-0000-0000-0000000000c1',
 'b7200000-0000-0000-0000-0000000000a1',
 'b7200000-0000-0000-0000-0000000000fb',
 'facility_management','pending');
UPDATE public.organization_relationships SET status='active'
 WHERE id='b7700000-0000-0000-0000-0000000000c1';
INSERT INTO public.facility_management_relationship_members
 (relationship_id,organization_member_id)
 VALUES('b7700000-0000-0000-0000-0000000000c1','b7300000-0000-0000-0000-000000000009');
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('b7700000-0000-0000-0000-0000000000c1','reports.view'),
      ('b7700000-0000-0000-0000-0000000000c1','assets.view');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000009');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000c1')
 ->'assets'->>'active')::integer,1,'Second FM gets own authorized asset count');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000c1')
 ->'work_orders')::text,'null','Second FM without domain grants gets null OT (not zero)');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000c1')
 ->'requests')::text,'null','Second FM without requests.view gets null requests');
SELECT ok((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000c1')
 ->'availability'->>'work_orders')='false',
 'Second FM availability marks missing domain');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Second FM cannot exploit first FM relationship for same client');
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000c1') $q$,
 '42501',NULL,'First FM cannot exploit second FM relation for same client');
RESET ROLE;

-- Domain permissions are independent and dynamically revoked.
DELETE FROM public.facility_management_permissions
 WHERE relationship_id='b7700000-0000-0000-0000-0000000000a1'
   AND permission='requests.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'requests')::text,'null','Missing requests.view returns null requests, not zero');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders')::text,'null','work_orders.view alone cannot expose OT without requests.view');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'assets'->>'active')::integer,1,'Asset view remains independently authorized');
RESET ROLE;

INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('b7700000-0000-0000-0000-0000000000a1','requests.view');
DELETE FROM public.facility_management_permissions
 WHERE relationship_id='b7700000-0000-0000-0000-0000000000a1'
   AND permission='assets.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'assets')::text,'null','Missing assets.view hides all asset counts');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'requests'->>'open')::integer,3,'Request metric remains visible when assets revoked');
RESET ROLE;

INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('b7700000-0000-0000-0000-0000000000a1','assets.view');
DELETE FROM public.facility_management_permissions
 WHERE relationship_id='b7700000-0000-0000-0000-0000000000a1'
   AND permission='work_orders.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders')::text,'null','Missing work_orders.view hides OT counts');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'requests'->>'open')::integer,3,'Requests remain available if only OT view is revoked');
RESET ROLE;

INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('b7700000-0000-0000-0000-0000000000a1','work_orders.view');
DELETE FROM public.facility_management_permissions
 WHERE relationship_id='b7700000-0000-0000-0000-0000000000a1'
   AND permission='reports.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Revoked reports.view blocks ALL metrics immediately');
RESET ROLE;

INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('b7700000-0000-0000-0000-0000000000a1','reports.view');
UPDATE public.organization_relationships SET status='suspended'
 WHERE id='b7700000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Suspended relationship blocks report');
RESET ROLE;

UPDATE public.organization_relationships SET status='active'
 WHERE id='b7700000-0000-0000-0000-0000000000a1';
DELETE FROM public.facility_management_relationship_members
 WHERE relationship_id='b7700000-0000-0000-0000-0000000000a1'
 AND organization_member_id='b7300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Unassigned manager blocked');
RESET ROLE;

INSERT INTO public.facility_management_relationship_members
 (relationship_id,organization_member_id)
VALUES('b7700000-0000-0000-0000-0000000000a1','b7300000-0000-0000-0000-000000000004');
UPDATE public.organization_members SET is_active=false
 WHERE id='b7300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Inactive assigned membership blocked');
RESET ROLE;

UPDATE public.organization_members SET is_active=true
 WHERE id='b7300000-0000-0000-0000-000000000004';
UPDATE public.organizations SET status='suspended'
 WHERE id='b7200000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Suspended client blocked');
RESET ROLE;

UPDATE public.organizations SET status='active'
 WHERE id='b7200000-0000-0000-0000-0000000000a1';
UPDATE public.organizations SET status='suspended'
 WHERE id='b7200000-0000-0000-0000-0000000000fa';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Suspended FM organization blocked');
RESET ROLE;

UPDATE public.organizations SET status='active'
 WHERE id='b7200000-0000-0000-0000-0000000000fa';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b7100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_metrics(
 'b7200000-0000-0000-0000-0000000000a1','b7700000-0000-0000-0000-0000000000a1')
 ->'work_orders'->>'total')::integer,3,'Reporting is restored only after all gates restored');
SELECT pg_temp.as_user(NULL);
SELECT throws_ok($q$ SELECT public.get_facility_management_client_metrics(
  'b7200000-0000-0000-0000-0000000000a1',
  'b7700000-0000-0000-0000-0000000000a1') $q$,
 '42501',NULL,'Authenticated DB role without auth.uid blocked');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
