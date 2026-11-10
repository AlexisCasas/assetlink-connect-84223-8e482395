-- 9C.6-B1. All synthetic data is removed by ROLLBACK. Execute ONLY in local/isolated Supabase.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
-- Dynamic plan marker is substituted below.
SELECT plan(41);
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


-- Reuse proven synthetic fixtures from B1, then create one eligible internal OT.
UPDATE public.work_orders
SET status='pending'
WHERE id='f6a00000-0000-0000-0000-0000000000a3';
-- Signed-in FM manager without manage permission should still be read-only.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'B2 denies write if work_orders.manage missing');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES ('f6700000-0000-0000-0000-0000000000a1','work_orders.manage');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');

SELECT ok(has_function_privilege('authenticated','public.update_facility_management_internal_work_order_schedule(uuid,uuid,text,timestamptz,timestamptz,text,timestamptz,timestamptz)','EXECUTE'),'authenticated may invoke guarded RPC');

SELECT ok(NOT has_function_privilege('anon','public.update_facility_management_internal_work_order_schedule(uuid,uuid,text,timestamptz,timestamptz,text,timestamptz,timestamptz)','EXECUTE'),'anon cannot invoke the RPC');

SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='update_facility_management_internal_work_order_schedule' AND prosecdef AND proconfig @> ARRAY['search_path=""']::text[]),1,'RPC is SECURITY DEFINER with empty search_path');

SELECT is((public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL)->>'priority')::text,'high','Assigned manager can update priority on pending internal OT');

SELECT is((SELECT priority FROM public.work_orders WHERE id='f6a00000-0000-0000-0000-0000000000a3'),'high','Priority persisted');

SELECT is((SELECT count(*)::int FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning'),1,'Exactly one planning audit event created');

SELECT is((SELECT actor_user_id FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning' LIMIT 1),'f6100000-0000-0000-0000-000000000004'::uuid,'Audit attributes change to actual FM actor');

SELECT is((SELECT old_data->>'priority' FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning' LIMIT 1),'medium','Audit preserves old priority');

SELECT is((SELECT new_data->>'priority' FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning' LIMIT 1),'high','Audit preserves new priority');

SELECT ok((SELECT old_data FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning' LIMIT 1) ?& ARRAY['priority','scheduled_at','due_at'],'Audit captures all and only relevant fields');

SELECT ok(NOT ((SELECT new_data FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning' LIMIT 1) ? 'observations'),'Provider observations excluded from audit');

SELECT is((public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'high',NULL,NULL,'high',NULL,NULL)->>'priority'),'high','No-op request returns sanitized OT');

SELECT is((SELECT count(*)::int FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning'),1,'No-op did not duplicate audit');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'urgent',NULL,NULL) $sql$,'40001',NULL,'Stale expected priority rejected');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'high',NULL,NULL,'low',now()+interval '5 days',now()+interval '3 days') $sql$,'22023',NULL,'Start after due date rejected');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'high',NULL,NULL,'other',NULL,NULL) $sql$,'22023',NULL,'Invalid priority rejected');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'high',NULL,NULL,NULL,NULL,NULL) $sql$,'22023',NULL,'Null priority rejected');

SELECT is(((public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'high',NULL,NULL,'urgent',now()+interval '2 days',now()+interval '4 days'))->>'priority'),'urgent','Authorized dates and priority update accepted');

SELECT ok((SELECT scheduled_at=now()+interval '2 days' AND due_at=now()+interval '4 days' FROM public.work_orders WHERE id='f6a00000-0000-0000-0000-0000000000a3'),'Both dates persisted correctly');

SELECT is((SELECT count(*)::int FROM public.audit_logs WHERE record_id='f6a00000-0000-0000-0000-0000000000a3' AND action='facility_manager_internal_work_order_planning'),2,'Date change creates one additional audit');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',NULL,NULL,'low',NULL,NULL) $sql$,'40001',NULL,'Stale dates rejected even when priority matches');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a2'::uuid,'urgent',NULL,NULL,'low',NULL,NULL) $sql$,'42501',NULL,'External OT cannot be modified');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000b1'::uuid,'low',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Other client OT denied');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a4'::uuid,'low',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Draft-source internal OT denied');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000ff'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Unknown ID denied indistinguishably');

RESET ROLE;
UPDATE public.work_orders SET status='closed' WHERE id='f6a00000-0000-0000-0000-0000000000a3';
SET LOCAL ROLE authenticated; SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',now()+interval '2 days',now()+interval '4 days','low',NULL,NULL) $sql$,'42501',NULL,'Closed OT cannot be modified');

RESET ROLE;
UPDATE public.work_orders SET status='completed' WHERE id='f6a00000-0000-0000-0000-0000000000a3';
SET LOCAL ROLE authenticated; SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',now()+interval '2 days',now()+interval '4 days','low',NULL,NULL) $sql$,'42501',NULL,'Completed OT cannot be modified');

RESET ROLE;
UPDATE public.work_orders SET status='in_progress' WHERE id='f6a00000-0000-0000-0000-0000000000a3';
SET LOCAL ROLE authenticated; SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000005');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',NULL,NULL,'low',NULL,NULL) $sql$,'42501',NULL,'Requester role cannot manage even with grants');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000006');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',NULL,NULL,'low',NULL,NULL) $sql$,'42501',NULL,'Technician FM role cannot manage');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000008');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',NULL,NULL,'low',NULL,NULL) $sql$,'42501',NULL,'Unassigned manager cannot manage');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000009');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',NULL,NULL,'low',NULL,NULL) $sql$,'42501',NULL,'FM B manager cannot manage client A');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000002');

SELECT is((public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'urgent',now()+interval '2 days',now()+interval '4 days','high',now()+interval '2 days',now()+interval '4 days')->>'priority'),'high','Assigned owner may manage with grant');

SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000003');

SELECT is((public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'high',now()+interval '2 days',now()+interval '4 days','medium',now()+interval '2 days',now()+interval '4 days')->>'priority'),'medium','Assigned admin may manage with grant');

RESET ROLE;
DELETE FROM public.facility_management_permissions WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND permission='requests.view';
SET LOCAL ROLE authenticated; SELECT pg_temp.as_user('f6100000-0000-0000-0000-000000000004');

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Revoked requests.view denies management');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES ('f6700000-0000-0000-0000-0000000000a1','requests.view');
DELETE FROM public.facility_management_permissions WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND permission='work_orders.view';
SET LOCAL ROLE authenticated;

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Revoked work_orders.view denies management');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES ('f6700000-0000-0000-0000-0000000000a1','work_orders.view');
DELETE FROM public.facility_management_permissions WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND permission='work_orders.manage';
SET LOCAL ROLE authenticated;

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Revoked work_orders.manage denies management');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES ('f6700000-0000-0000-0000-0000000000a1','work_orders.manage');
UPDATE public.organization_relationships SET status='suspended' WHERE id='f6700000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Suspended FM relationship denies management');

RESET ROLE;
UPDATE public.organization_relationships SET status='active' WHERE id='f6700000-0000-0000-0000-0000000000a1';
DELETE FROM public.facility_management_relationship_members WHERE relationship_id='f6700000-0000-0000-0000-0000000000a1' AND organization_member_id='f6300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'FM member unassignment denies management');

RESET ROLE;
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id) VALUES ('f6700000-0000-0000-0000-0000000000a1','f6300000-0000-0000-0000-000000000004');
UPDATE public.organization_members SET is_active=false WHERE id='f6300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Inactive FM membership denies management');

RESET ROLE;
UPDATE public.organization_members SET is_active=true WHERE id='f6300000-0000-0000-0000-000000000004';
UPDATE public.organizations SET status='suspended' WHERE id='f6200000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;

SELECT throws_ok($sql$ SELECT public.update_facility_management_internal_work_order_schedule('f6200000-0000-0000-0000-0000000000a1'::uuid,'f6a00000-0000-0000-0000-0000000000a3'::uuid,'medium',NULL,NULL,'high',NULL,NULL) $sql$,'42501',NULL,'Inactive client denies management');

SELECT * FROM finish();
ROLLBACK;
