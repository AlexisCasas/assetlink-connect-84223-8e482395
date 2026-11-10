-- One Facility | 9C.6-B2.2 D3 | isolated pgTAP; all fixture changes rolled back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(36);
CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $fn$
  SELECT set_config('request.jwt.claim.sub',coalesce(p_user::text,''),true);
$fn$;

INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
('b6100000-0000-0000-0000-000000000001','client@fm-create-qa.test','{}'),
('b6100000-0000-0000-0000-000000000002','owner@fm-create-qa.test','{}'),
('b6100000-0000-0000-0000-000000000003','admin@fm-create-qa.test','{}'),
('b6100000-0000-0000-0000-000000000004','manager@fm-create-qa.test','{}'),
('b6100000-0000-0000-0000-000000000005','requester@fm-create-qa.test','{}'),
('b6100000-0000-0000-0000-000000000006','unassigned@fm-create-qa.test','{}'),
('b6100000-0000-0000-0000-000000000007','outsider@fm-create-qa.test','{}'),
('b6100000-0000-0000-0000-000000000008','otherfm@fm-create-qa.test','{}');

INSERT INTO public.organizations(id,name,organization_type) VALUES
('b6200000-0000-0000-0000-0000000000a1','QA B22 Client A','client_company'),
('b6200000-0000-0000-0000-0000000000b1','QA B22 Client B','client_company'),
('b6200000-0000-0000-0000-0000000000fa','QA B22 FM A','facility_manager'),
('b6200000-0000-0000-0000-0000000000fb','QA B22 FM B','facility_manager'),
('b6200000-0000-0000-0000-0000000000c1','QA B22 Provider','provider_company');

INSERT INTO public.organization_members(id,organization_id,user_id,role,is_active) VALUES
('b6300000-0000-0000-0000-000000000001','b6200000-0000-0000-0000-0000000000a1','b6100000-0000-0000-0000-000000000001','owner',true),
('b6300000-0000-0000-0000-000000000002','b6200000-0000-0000-0000-0000000000fa','b6100000-0000-0000-0000-000000000002','owner',true),
('b6300000-0000-0000-0000-000000000003','b6200000-0000-0000-0000-0000000000fa','b6100000-0000-0000-0000-000000000003','admin',true),
('b6300000-0000-0000-0000-000000000004','b6200000-0000-0000-0000-0000000000fa','b6100000-0000-0000-0000-000000000004','manager',true),
('b6300000-0000-0000-0000-000000000005','b6200000-0000-0000-0000-0000000000fa','b6100000-0000-0000-0000-000000000005','requester',true),
('b6300000-0000-0000-0000-000000000006','b6200000-0000-0000-0000-0000000000fa','b6100000-0000-0000-0000-000000000006','manager',true),
('b6300000-0000-0000-0000-000000000008','b6200000-0000-0000-0000-0000000000fb','b6100000-0000-0000-0000-000000000008','manager',true);

INSERT INTO public.organization_relationships(id,source_organization_id,target_organization_id,relationship_type,status) VALUES
('b6700000-0000-0000-0000-0000000000a1','b6200000-0000-0000-0000-0000000000a1','b6200000-0000-0000-0000-0000000000fa','facility_management','pending'),
('b6700000-0000-0000-0000-0000000000b1','b6200000-0000-0000-0000-0000000000b1','b6200000-0000-0000-0000-0000000000fb','facility_management','pending');
UPDATE public.organization_relationships SET status='active' WHERE id IN
('b6700000-0000-0000-0000-0000000000a1','b6700000-0000-0000-0000-0000000000b1');

INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES
('b6700000-0000-0000-0000-0000000000a1','requests.view'),
('b6700000-0000-0000-0000-0000000000a1','work_orders.view'),
('b6700000-0000-0000-0000-0000000000a1','quotes.view'),
('b6700000-0000-0000-0000-0000000000b1','requests.view'),
('b6700000-0000-0000-0000-0000000000b1','work_orders.view'),
('b6700000-0000-0000-0000-0000000000b1','work_orders.manage');

INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id) VALUES
('b6700000-0000-0000-0000-0000000000a1','b6300000-0000-0000-0000-000000000002'),
('b6700000-0000-0000-0000-0000000000a1','b6300000-0000-0000-0000-000000000003'),
('b6700000-0000-0000-0000-0000000000a1','b6300000-0000-0000-0000-000000000004'),
('b6700000-0000-0000-0000-0000000000a1','b6300000-0000-0000-0000-000000000005'),
('b6700000-0000-0000-0000-0000000000b1','b6300000-0000-0000-0000-000000000008');

INSERT INTO public.assets(id,organization_id,code,name,node_type,status) VALUES
('b6400000-0000-0000-0000-0000000000a1','b6200000-0000-0000-0000-0000000000a1','B22-QA','Equipo QA B22','equipment','active');

INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,asset_id,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes,quotes_closed)
VALUES
('b6800000-0000-0000-0000-0000000000a1','b6200000-0000-0000-0000-0000000000a1','B22-INT-01','Interna autorizada','Servicio interno QA','Equipo','b6400000-0000-0000-0000-0000000000a1','Lima','preventivo',now()+interval '10 days','sent','internal',false,'fixture',1,false),
('b6800000-0000-0000-0000-0000000000a2','b6200000-0000-0000-0000-0000000000a1','B22-INT-DRAFT','Interna borrador','No crear','Equipo','b6400000-0000-0000-0000-0000000000a1','Lima','preventivo',now()+interval '10 days','draft','internal',false,'fixture',1,false),
('b6800000-0000-0000-0000-0000000000a3','b6200000-0000-0000-0000-0000000000a1','B22-EXT-01','Externa costo S/ 1700','Externa sensible','Equipo','b6400000-0000-0000-0000-0000000000a1','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',3,false),
('b6800000-0000-0000-0000-0000000000b1','b6200000-0000-0000-0000-0000000000b1','B22-INT-B','Otro cliente','Privada B','Equipo',NULL,'Lima','correctivo',now()+interval '10 days','sent','internal',false,'fixture',1,false);

INSERT INTO public.quotes(id,request_id,provider_organization_id,amount,description,status,total_amount)
VALUES
('b6900000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a3','b6200000-0000-0000-0000-0000000000c1',1700,'Descripcion sensible S/ 1700','approved',1700),
('b6900000-0000-0000-0000-0000000000a2','b6800000-0000-0000-0000-0000000000a3','b6200000-0000-0000-0000-0000000000c1',1500,'Oferta no aprobada','submitted',1500);

SELECT ok((SELECT bool_and(p.prosecdef AND p.proconfig @> ARRAY['search_path=""'::text])
  FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
    AND p.proname IN ('create_facility_management_internal_work_order','create_facility_management_work_order_from_quote')),
  'Both FM creation functions are SECURITY DEFINER with empty search_path');
SELECT ok((SELECT bool_and(NOT has_function_privilege('anon',p.oid,'EXECUTE')
  AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
  AND has_function_privilege('authenticated',p.oid,'EXECUTE'))
  FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
    AND p.proname IN ('create_facility_management_internal_work_order','create_facility_management_work_order_from_quote')),
  'Creation RPC ACL allows authenticated only');
SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace='public'::regnamespace
  AND proname IN ('create_facility_management_internal_work_order','create_facility_management_work_order_from_quote')),2,
  'Exactly two new public creation functions');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Without manage grant internal creation is denied');
SELECT throws_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Without manage grant quote creation is denied');

RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES ('b6700000-0000-0000-0000-0000000000a1','work_orders.manage');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT lives_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,
  'Assigned FM manager can create an internal OT');
SELECT lives_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,
  'Repeated internal creation is idempotent');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.work_orders WHERE request_id='b6800000-0000-0000-0000-0000000000a1'),1,
  'Internal request created exactly one OT');
SELECT is((SELECT status FROM public.work_orders WHERE request_id='b6800000-0000-0000-0000-0000000000a1'),'pending',
  'New internal OT starts pending');
SELECT ok((SELECT planner_member_id IS NULL AND assigned_member_id IS NULL
 AND client_organization_id=provider_organization_id AND work_order_type='internal' AND quote_id IS NULL
 FROM public.work_orders WHERE request_id='b6800000-0000-0000-0000-0000000000a1'),
 'Internal OT has no impersonated planner/technician and is client-operated');
SELECT is((SELECT count(*)::int FROM public.audit_logs WHERE action='facility_manager_internal_work_order_created'
 AND organization_id='b6200000-0000-0000-0000-0000000000a1'),1,
 'Internal idempotency creates exactly one audit');
SELECT is((SELECT actor_user_id FROM public.audit_logs WHERE action='facility_manager_internal_work_order_created'
 LIMIT 1),'b6100000-0000-0000-0000-000000000004'::uuid,'Internal audit preserves actual FM actor');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000002');
SELECT lives_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1') $qa$,
  'Assigned FM owner creates external OT from approved quote');
SELECT lives_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1') $qa$,
  'Repeated external creation is idempotent');
SELECT is((public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1')->>'title'),'Orden externa',
 'Confidential external title remains masked until quote visibility threshold');
SELECT ok((public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1')->>'total_amount') IS NULL,
 'External amount remains masked even when approved');
SELECT ok((public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1')->>'description') IS NULL,
 'External free-text description remains masked');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.work_orders WHERE quote_id='b6900000-0000-0000-0000-0000000000a1'),1,
 'Approved quote created exactly one OT');
SELECT is((SELECT count(*)::int FROM public.audit_logs WHERE action='facility_manager_work_order_created_from_quote'),1,
 'External idempotency creates exactly one audit');
SELECT ok((SELECT planner_member_id IS NULL AND assigned_member_id IS NULL AND status='pending'
 AND work_order_type='external' AND provider_organization_id='b6200000-0000-0000-0000-0000000000c1'
 FROM public.work_orders WHERE quote_id='b6900000-0000-0000-0000-0000000000a1'),
 'External FM creation does not impersonate an operator');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a2') $qa$,'42501',NULL,'Draft internal request denied');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a3') $qa$,'42501',NULL,'External request denied on internal route');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000b1') $qa$,'42501',NULL,'Cross-client internal request denied');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000ff') $qa$,'42501',NULL,'Unknown request denied indistinguishably');
SELECT throws_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a2') $qa$,'42501',NULL,'Nonapproved quote denied');
SELECT throws_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000ff') $qa$,'42501',NULL,'Unknown quote denied indistinguishably');

SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000005');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Requester role cannot create internal OT');
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000006');
SELECT throws_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Unassigned manager cannot create external OT');
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000007');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Outsider cannot create OT');
SELECT pg_temp.as_user(NULL::uuid);
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Authenticated role with no identity denied');

RESET ROLE;
DELETE FROM public.facility_management_permissions
WHERE relationship_id='b6700000-0000-0000-0000-0000000000a1'
 AND permission='quotes.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Quote grant revocation blocks creation even if OT exists');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES ('b6700000-0000-0000-0000-0000000000a1','quotes.view');
DELETE FROM public.facility_management_permissions
WHERE relationship_id='b6700000-0000-0000-0000-0000000000a1'
 AND permission='requests.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Request grant revocation blocks internal creation');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES ('b6700000-0000-0000-0000-0000000000a1','requests.view');
DELETE FROM public.facility_management_permissions
WHERE relationship_id='b6700000-0000-0000-0000-0000000000a1'
 AND permission='work_orders.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Work-order view revocation blocks internal creation');
RESET ROLE;
INSERT INTO public.facility_management_permissions(relationship_id,permission)
VALUES ('b6700000-0000-0000-0000-0000000000a1','work_orders.view');

UPDATE public.organization_relationships SET status='suspended'
WHERE id='b6700000-0000-0000-0000-0000000000a1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.create_facility_management_internal_work_order('b6200000-0000-0000-0000-0000000000a1','b6800000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Suspended relationship blocks creation');
RESET ROLE;
UPDATE public.organization_relationships SET status='active'
WHERE id='b6700000-0000-0000-0000-0000000000a1';
UPDATE public.organization_members SET is_active=false
WHERE id='b6300000-0000-0000-0000-000000000004';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b6100000-0000-0000-0000-000000000004');
SELECT throws_ok($qa$ SELECT public.create_facility_management_work_order_from_quote('b6200000-0000-0000-0000-0000000000a1','b6900000-0000-0000-0000-0000000000a1') $qa$,'42501',NULL,'Inactive FM membership blocks creation');

RESET ROLE;
SELECT ok(NOT EXISTS (
 SELECT 1 FROM public.audit_logs a WHERE a.action IN
 ('facility_manager_work_order_created_from_quote','facility_manager_internal_work_order_created')
 AND (a.new_data ? 'total_amount' OR a.new_data ? 'description' OR a.new_data ? 'provider_organization_id')
), 'Audit payload never contains economic or operator private data');
SELECT * FROM finish();
ROLLBACK;
