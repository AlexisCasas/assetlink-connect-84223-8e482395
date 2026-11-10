-- One Facility | D4: FM client-side followups QA, disposable Supabase ONLY.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
-- Dynamic plan marker is substituted below.
SELECT plan(43);
CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text,''), true);
$$;

INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES
  ('d6100000-0000-0000-0000-000000000001','co@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000002','owner@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000003','admin@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000004','manager@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000005','requester@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000006','tech@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000007','viewer@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000008','unassigned@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000009','otherfm@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000010','outsider@fm-workorder-qa.test','{}'),
  ('d6100000-0000-0000-0000-000000000011','provider@fm-workorder-qa.test','{}');

INSERT INTO public.organizations (id,name,organization_type) VALUES
('d6200000-0000-0000-0000-0000000000a1','FM OT Client A','client_company'),
('d6200000-0000-0000-0000-0000000000b1','FM OT Client B','client_company'),
('d6200000-0000-0000-0000-0000000000fa','FM OT Manager A','facility_manager'),
('d6200000-0000-0000-0000-0000000000fb','FM OT Manager B','facility_manager'),
('d6200000-0000-0000-0000-0000000000c1','FM OT Provider','provider_company');

INSERT INTO public.organization_members (id,organization_id,user_id,role,is_active) VALUES
('d6300000-0000-0000-0000-000000000001','d6200000-0000-0000-0000-0000000000a1','d6100000-0000-0000-0000-000000000001','owner',true),
('d6300000-0000-0000-0000-000000000002','d6200000-0000-0000-0000-0000000000fa','d6100000-0000-0000-0000-000000000002','owner',true),
('d6300000-0000-0000-0000-000000000003','d6200000-0000-0000-0000-0000000000fa','d6100000-0000-0000-0000-000000000003','admin',true),
('d6300000-0000-0000-0000-000000000004','d6200000-0000-0000-0000-0000000000fa','d6100000-0000-0000-0000-000000000004','manager',true),
('d6300000-0000-0000-0000-000000000005','d6200000-0000-0000-0000-0000000000fa','d6100000-0000-0000-0000-000000000005','requester',true),
('d6300000-0000-0000-0000-000000000006','d6200000-0000-0000-0000-0000000000fa','d6100000-0000-0000-0000-000000000006','technician',true),
('d6300000-0000-0000-0000-000000000007','d6200000-0000-0000-0000-0000000000fa','d6100000-0000-0000-0000-000000000007','viewer',true),
('d6300000-0000-0000-0000-000000000008','d6200000-0000-0000-0000-0000000000fa','d6100000-0000-0000-0000-000000000008','manager',true),
('d6300000-0000-0000-0000-000000000009','d6200000-0000-0000-0000-0000000000fb','d6100000-0000-0000-0000-000000000009','manager',true),
('d6300000-0000-0000-0000-000000000010','d6200000-0000-0000-0000-0000000000c1','d6100000-0000-0000-0000-000000000011','owner',true);

INSERT INTO public.organization_relationships
(id,source_organization_id,target_organization_id,relationship_type,status) VALUES
('d6700000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000fa','facility_management','pending'),
('d6700000-0000-0000-0000-0000000000b1','d6200000-0000-0000-0000-0000000000b1','d6200000-0000-0000-0000-0000000000fb','facility_management','pending');
UPDATE public.organization_relationships SET status='active' WHERE id IN ('d6700000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000b1');
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES
('d6700000-0000-0000-0000-0000000000a1','requests.view'),('d6700000-0000-0000-0000-0000000000a1','work_orders.view'),
('d6700000-0000-0000-0000-0000000000a1','quotes.view'),('d6700000-0000-0000-0000-0000000000a1','assets.view'),
('d6700000-0000-0000-0000-0000000000b1','requests.view'),('d6700000-0000-0000-0000-0000000000b1','work_orders.view');
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id) VALUES
('d6700000-0000-0000-0000-0000000000a1','d6300000-0000-0000-0000-000000000002'),
('d6700000-0000-0000-0000-0000000000a1','d6300000-0000-0000-0000-000000000003'),
('d6700000-0000-0000-0000-0000000000a1','d6300000-0000-0000-0000-000000000004'),
('d6700000-0000-0000-0000-0000000000a1','d6300000-0000-0000-0000-000000000005'),
('d6700000-0000-0000-0000-0000000000a1','d6300000-0000-0000-0000-000000000006'),
('d6700000-0000-0000-0000-0000000000a1','d6300000-0000-0000-0000-000000000007'),
('d6700000-0000-0000-0000-0000000000b1','d6300000-0000-0000-0000-000000000009');

INSERT INTO public.assets(id,organization_id,code,name,node_type,status)
VALUES ('d6400000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000a1','A-OT-TEST','Equipo QA seguro','equipment','active');

INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes,quotes_closed)
VALUES
('d6800000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000a1','FM-OT-TEST-001','Cotizacion autorizada','Solicitud visible','Equipo QA','d6400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',1,false),
('d6800000-0000-0000-0000-0000000000a2','d6200000-0000-0000-0000-0000000000a1','FM-OT-TEST-002','Cotizacion bajo minimo','Solicitud restringida','Equipo QA','d6400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',2,false),
('d6800000-0000-0000-0000-0000000000a3','d6200000-0000-0000-0000-0000000000a1','FM-OT-TEST-003','Servicio interno','Solicitud interna','Equipo QA','d6400000-0000-0000-0000-0000000000a1','Lima','preventivo',now()+interval '10 days','sent','internal',false,'fixture',1,false),
('d6800000-0000-0000-0000-0000000000b1','d6200000-0000-0000-0000-0000000000b1','FM-OT-TEST-004','Cliente B','Servicio B','Activo B',NULL,'Lima','correctivo',now()+interval '10 days','sent','internal',false,'fixture',1,false);

INSERT INTO public.quotes
(id,request_id,provider_organization_id,created_by_user_id,amount,description,status,total_amount)
VALUES
('d6900000-0000-0000-0000-0000000000a1','d6800000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000c1','d6100000-0000-0000-0000-000000000011',1700,'Propuesta visible S/ 1700','approved',1700),
('d6900000-0000-0000-0000-0000000000a2','d6800000-0000-0000-0000-0000000000a2','d6200000-0000-0000-0000-0000000000c1','d6100000-0000-0000-0000-000000000011',1800,'Propuesta oculta S/ 1800','approved',1800);

INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id,observations)
VALUES
('d6a00000-0000-0000-0000-0000000000a1','d6800000-0000-0000-0000-0000000000a1','d6900000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000c1','external','completed','Trabajo externo autorizado S/ 1700','Descripción S/ 1700','high','OT-FM-001',1700,'d6400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('d6a00000-0000-0000-0000-0000000000a2','d6800000-0000-0000-0000-0000000000a2','d6900000-0000-0000-0000-0000000000a2','d6200000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000c1','external','pending','Oferta oculta S/ 1800','Descripción oculta S/ 1800','urgent','OT-FM-002',1800,'d6400000-0000-0000-0000-0000000000a1','SECRETO PROVEEDOR'),
('d6a00000-0000-0000-0000-0000000000a3','d6800000-0000-0000-0000-0000000000a3',NULL,'d6200000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000a1','internal','closed','Trabajo interno','Descripción del cliente','medium','OT-FM-003',NULL,'d6400000-0000-0000-0000-0000000000a1','NOTA INTERNA DE OPERADOR'),
('d6a00000-0000-0000-0000-0000000000b1','d6800000-0000-0000-0000-0000000000b1',NULL,'d6200000-0000-0000-0000-0000000000b1','d6200000-0000-0000-0000-0000000000b1','internal','pending','Trabajo de otro cliente','Privado B','low','OT-FM-004',NULL,NULL,'PRIVADO B');

-- Deliberately invalid source state: must not appear through delegated OT RPCs.
INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes)
VALUES ('d6800000-0000-0000-0000-0000000000a4','d6200000-0000-0000-0000-0000000000a1',
'FM-OT-TEST-005','Borrador oculto','Solo borrador','Equipo QA','d6400000-0000-0000-0000-0000000000a1',
'Lima','correctivo',now()+interval '10 days','draft','internal',false,'fixture',1);
INSERT INTO public.work_orders
(id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,total_amount,asset_id)
VALUES ('d6a00000-0000-0000-0000-0000000000a4',
'd6800000-0000-0000-0000-0000000000a4',NULL,
'd6200000-0000-0000-0000-0000000000a1','d6200000-0000-0000-0000-0000000000a1',
'internal','pending','No publicar','Borrador privado','low','OT-FM-DRAFT',NULL,'d6400000-0000-0000-0000-0000000000a1');


-- Secondary FM relationship for SAME client: notes must never leak between
-- separately assigned FM providers even if both can view the same OT.
INSERT INTO public.organization_relationships(id,source_organization_id,target_organization_id,relationship_type,status)
VALUES ('d6700000-0000-0000-0000-0000000000c1',
        'd6200000-0000-0000-0000-0000000000a1',
        'd6200000-0000-0000-0000-0000000000fb',
        'facility_management','pending');
UPDATE public.organization_relationships SET status='active'
WHERE id='d6700000-0000-0000-0000-0000000000c1';
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES
 ('d6700000-0000-0000-0000-0000000000c1','requests.view'),
 ('d6700000-0000-0000-0000-0000000000c1','work_orders.view'),
 ('d6700000-0000-0000-0000-0000000000c1','work_orders.manage');
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id)
VALUES ('d6700000-0000-0000-0000-0000000000c1','d6300000-0000-0000-0000-000000000009');

SELECT ok((SELECT relrowsecurity AND relforcerowsecurity
  FROM pg_class WHERE oid='public.facility_management_work_order_followups'::regclass),
  'Notes table has both RLS and FORCE RLS enabled');
SELECT ok(NOT has_table_privilege('authenticated','public.facility_management_work_order_followups','SELECT')
  AND NOT has_table_privilege('anon','public.facility_management_work_order_followups','SELECT')
  AND NOT has_table_privilege('authenticated','public.facility_management_work_order_followups','INSERT')
  AND NOT has_table_privilege('service_role','public.facility_management_work_order_followups','SELECT'),
  'No API role can directly SELECT or INSERT FM notes');
SELECT ok((SELECT bool_and(p.prosecdef AND p.proconfig @> ARRAY['search_path=""'::text])
  FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
  AND p.proname IN ('has_facility_management_followup_relation_access',
   'get_facility_management_work_order_followups',
   'add_facility_management_work_order_followup')),
  'All three D4 SQL entrypoints use SECURITY DEFINER and empty search_path');
SELECT ok(has_function_privilege('authenticated',
  'public.get_facility_management_work_order_followups(uuid,uuid,uuid,integer,integer)','EXECUTE')
  AND NOT has_function_privilege('anon',
  'public.get_facility_management_work_order_followups(uuid,uuid,uuid,integer,integer)','EXECUTE')
  AND NOT has_function_privilege('authenticated',
  'public.add_facility_management_work_order_followup(uuid,uuid,uuid,text,uuid)','EXECUTE')
  AND NOT has_function_privilege('service_role',
  'public.add_facility_management_work_order_followup(uuid,uuid,uuid,text,uuid)','EXECUTE'),
  'Read callable by authenticated only; staged write RPC blocked');
SELECT ok(NOT has_function_privilege('authenticated',
  'public.has_facility_management_followup_relation_access(uuid,uuid,public.facility_management_permission[],public.organization_member_role[])','EXECUTE'),
  'Internal authorization helper is not exposed to authenticated');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->>'total')::int,0,
 'Read permitted without work_orders.manage, initially empty');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','test',
 'd6b00000-0000-0000-0000-000000000001') $qa$,'42501',NULL,
 'Staged D4 write RPC is not executable');

SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000005');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->>'total')::int,0,
 'Assigned requester may read, never write');

SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000008');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,
 'Unassigned FM manager denied read');

SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000011');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,
 'Provider member cannot read client-side FM followups');

SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a3') $qa$,'42501',NULL,
 'Internal OT rejected by external follow-up reader');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000b1') $qa$,'42501',NULL,
 'Other client OT rejected');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000c1',
 'd6a00000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,
 'Relationship owned by another FM is rejected');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1',0,0) $qa$,'22023',NULL,
 'Invalid read pagination rejected');

RESET ROLE;
-- All ACL elevation below happens ONLY within this rolled-back pgTAP fixture.
GRANT EXECUTE ON FUNCTION public.add_facility_management_work_order_followup(uuid,uuid,uuid,text,uuid) TO authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','Sin permiso',
 'd6b00000-0000-0000-0000-000000000001') $qa$,'42501',NULL,
 'Manager without work_orders.manage cannot write');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('d6700000-0000-0000-0000-0000000000a1','work_orders.manage');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT lives_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','  Seguimiento cliente A  ',
 'd6b00000-0000-0000-0000-000000000001') $qa$,
 'Assigned FM manager adds a note to external OT');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->>'total')::int,1,
 'One note visible after creation');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->'items'->0->>'body'),
 'Seguimiento cliente A','Text trimmed and rendered only in scoped note DTO');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->'items'->0->>'authored_by_me'),
 'true','Author gets authored_by_me, not raw actor ID');
SELECT ok(NOT (public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->'items'->0 ? 'author_user_id'),
 'Read DTO does not expose author user ID');
SELECT lives_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','Seguimiento cliente A',
 'd6b00000-0000-0000-0000-000000000001') $qa$,
 'Exact idempotent retry accepted');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','Texto distinto mismo key',
 'd6b00000-0000-0000-0000-000000000001') $qa$,'22023',NULL,
 'Reused key with different content rejected');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','   ',
 'd6b00000-0000-0000-0000-000000000002') $qa$,'22023',NULL,
 'Blank follow-up rejected');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1',repeat('x',2001),
 'd6b00000-0000-0000-0000-000000000002') $qa$,'22023',NULL,
 'Over 2000 characters rejected');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a3','Interna no',
 'd6b00000-0000-0000-0000-000000000003') $qa$,'42501',NULL,
 'Cannot add follow-up to internal OT');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000b1','Foreign OT',
 'd6b00000-0000-0000-0000-000000000004') $qa$,'42501',NULL,
 'Cannot add follow-up to foreign OT');

SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000005');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','Requester denied',
 'd6b00000-0000-0000-0000-000000000005') $qa$,'42501',NULL,
 'Requester may read but may not write');

SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000008');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','Unassigned denied',
 'd6b00000-0000-0000-0000-000000000006') $qa$,'42501',NULL,
 'Unassigned manager cannot write');

RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.facility_management_work_order_followups),1,
 'Idempotent create yielded exactly one note');
SELECT is((SELECT count(*)::int FROM public.audit_logs WHERE action='facility_manager_external_work_order_followup_created'),1,
 'Idempotent create yielded exactly one audit');
SELECT ok(NOT EXISTS (
 SELECT 1 FROM public.audit_logs
 WHERE action='facility_manager_external_work_order_followup_created'
  AND (new_data ? 'body' OR new_data ? 'text' OR new_data::text like '%Seguimiento cliente A%')
), 'Audit metadata contains no free-text note body');
SELECT is((SELECT author_user_id FROM public.facility_management_work_order_followups LIMIT 1),
 'd6100000-0000-0000-0000-000000000004'::uuid,
 'Real actor preserved in separate table for audit');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000009');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000c1',
 'd6a00000-0000-0000-0000-0000000000a1')->>'total')::int,0,
 'Second authorized FM relationship cannot read first FM note');
SELECT lives_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000c1',
 'd6a00000-0000-0000-0000-0000000000a1','Otra relacion FM',
 'd6b00000-0000-0000-0000-000000000007') $qa$,
 'Second FM relationship creates its own isolated follow-up');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000c1',
 'd6a00000-0000-0000-0000-0000000000a1')->>'total')::int,1,
 'Second FM reads exactly its own note');
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->>'total')::int,1,
 'First FM cannot see second relationship note');

RESET ROLE;
DELETE FROM public.facility_management_permissions
WHERE relationship_id='d6700000-0000-0000-0000-0000000000a1' AND permission='work_orders.manage';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.add_facility_management_work_order_followup(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1','Revoked write',
 'd6b00000-0000-0000-0000-000000000008') $qa$,'42501',NULL,
 'Revoking work_orders.manage blocks future writes');
SELECT is((public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1')->>'total')::int,1,
 'Read remains possible after write grant revoked');
RESET ROLE;
DELETE FROM public.facility_management_permissions
WHERE relationship_id='d6700000-0000-0000-0000-0000000000a1' AND permission='work_orders.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,
 'Revoking work_orders.view blocks read even for historic notes');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES('d6700000-0000-0000-0000-0000000000a1','work_orders.view');
UPDATE public.organization_relationships SET status='suspended'
WHERE id='d6700000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,
 'Suspended relationship removes note visibility');
RESET ROLE;
UPDATE public.organization_relationships SET status='active'
WHERE id='d6700000-0000-0000-0000-0000000000a1';
UPDATE public.organization_members SET is_active=false
WHERE id='d6300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.get_facility_management_work_order_followups(
 'd6200000-0000-0000-0000-0000000000a1','d6700000-0000-0000-0000-0000000000a1',
 'd6a00000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,
 'Inactive FM member denied reading historic notes');

RESET ROLE;
SELECT ok((SELECT bool_and(wo.observations='SECRETO PROVEEDOR')
  FROM public.work_orders wo WHERE wo.id IN (
   'd6a00000-0000-0000-0000-0000000000a1','d6a00000-0000-0000-0000-0000000000a2')),
 'Provider observations are untouched');
SELECT is((SELECT count(*)::int FROM public.facility_management_work_order_followups),2,
 'Exactly one client follow-up per FM relation, no duplicates');
SELECT * FROM finish();
ROLLBACK;
