-- 9C.8-B1: local/disposable Supabase ONLY. Never execute against Cloud.
-- Two clients, two FM organizations, three relationships, dual-FM membership.
-- All synthetic identities, records and grants are discarded with ROLLBACK.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(43);
CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text,''), true);
$$;
INSERT INTO auth.users(id,email) VALUES
 ('e9100000-0000-0000-0000-000000000001','clientOwner@9c8-qa.test'),
 ('e9100000-0000-0000-0000-000000000002','fm1Manager@9c8-qa.test'),
 ('e9100000-0000-0000-0000-000000000003','fm1Unassigned@9c8-qa.test'),
 ('e9100000-0000-0000-0000-000000000004','fm2Manager@9c8-qa.test'),
 ('e9100000-0000-0000-0000-000000000005','dual@9c8-qa.test'),
 ('e9100000-0000-0000-0000-000000000006','requester@9c8-qa.test'),
 ('e9100000-0000-0000-0000-000000000007','outsider@9c8-qa.test'),
 ('e9100000-0000-0000-0000-000000000008','clientBOwner@9c8-qa.test');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('e9200000-0000-0000-0000-0000000000a1','9C8 Client A','client_company'),
 ('e9200000-0000-0000-0000-0000000000b1','9C8 Client B','client_company'),
 ('e9200000-0000-0000-0000-0000000000f1','9C8 FM A','facility_manager'),
 ('e9200000-0000-0000-0000-0000000000f2','9C8 FM B','facility_manager');
INSERT INTO public.organization_members(id,organization_id,user_id,role,is_active) VALUES
 ('e9300000-0000-0000-0000-000000000001','e9200000-0000-0000-0000-0000000000a1','e9100000-0000-0000-0000-000000000001','owner',true),
 ('e9300000-0000-0000-0000-000000000002','e9200000-0000-0000-0000-0000000000f1','e9100000-0000-0000-0000-000000000002','manager',true),
 ('e9300000-0000-0000-0000-000000000003','e9200000-0000-0000-0000-0000000000f1','e9100000-0000-0000-0000-000000000003','owner',true),
 ('e9300000-0000-0000-0000-000000000004','e9200000-0000-0000-0000-0000000000f2','e9100000-0000-0000-0000-000000000004','manager',true),
 ('e9300000-0000-0000-0000-000000000005','e9200000-0000-0000-0000-0000000000f1','e9100000-0000-0000-0000-000000000005','manager',true),
 ('e9300000-0000-0000-0000-000000000006','e9200000-0000-0000-0000-0000000000f2','e9100000-0000-0000-0000-000000000005','manager',true),
 ('e9300000-0000-0000-0000-000000000007','e9200000-0000-0000-0000-0000000000f1','e9100000-0000-0000-0000-000000000006','requester',true),
 ('e9300000-0000-0000-0000-000000000008','e9200000-0000-0000-0000-0000000000b1','e9100000-0000-0000-0000-000000000008','owner',true);
INSERT INTO public.organization_relationships
 (id,source_organization_id,target_organization_id,relationship_type,status) VALUES
 ('e9700000-0000-0000-0000-0000000000a1','e9200000-0000-0000-0000-0000000000a1','e9200000-0000-0000-0000-0000000000f1','facility_management','pending'),
 ('e9700000-0000-0000-0000-0000000000a2','e9200000-0000-0000-0000-0000000000a1','e9200000-0000-0000-0000-0000000000f2','facility_management','pending'),
 ('e9700000-0000-0000-0000-0000000000b2','e9200000-0000-0000-0000-0000000000b1','e9200000-0000-0000-0000-0000000000f2','facility_management','pending');
UPDATE public.organization_relationships SET status='active'
 WHERE id IN ('e9700000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid);
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES
 ('e9700000-0000-0000-0000-0000000000a1','reports.view'),('e9700000-0000-0000-0000-0000000000a1','requests.view'),
 ('e9700000-0000-0000-0000-0000000000a1','work_orders.view'),('e9700000-0000-0000-0000-0000000000a1','assets.view'),
 ('e9700000-0000-0000-0000-0000000000a2','reports.view'),('e9700000-0000-0000-0000-0000000000a2','requests.view'),('e9700000-0000-0000-0000-0000000000a2','work_orders.view'),
 ('e9700000-0000-0000-0000-0000000000b2','reports.view'),('e9700000-0000-0000-0000-0000000000b2','requests.view'),('e9700000-0000-0000-0000-0000000000b2','work_orders.view');
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id) VALUES
 ('e9700000-0000-0000-0000-0000000000a1','e9300000-0000-0000-0000-000000000002'),
 ('e9700000-0000-0000-0000-0000000000a1','e9300000-0000-0000-0000-000000000005'),
 ('e9700000-0000-0000-0000-0000000000a1','e9300000-0000-0000-0000-000000000007'),
 ('e9700000-0000-0000-0000-0000000000a2','e9300000-0000-0000-0000-000000000004'),
 ('e9700000-0000-0000-0000-0000000000b2','e9300000-0000-0000-0000-000000000004'),
 ('e9700000-0000-0000-0000-0000000000b2','e9300000-0000-0000-0000-000000000006');
INSERT INTO public.requests
 (id,organization_id,request_number,title,description,asset,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes,quotes_closed,created_at)
 VALUES
 ('e9800000-0000-0000-0000-0000000000a1','e9200000-0000-0000-0000-0000000000a1','9C8-REQ-A','9C8 A','QA isolated A','Equipo A','Lima','correctivo','2026-10-01','sent','internal',false,'fixture',1,false,'2026-09-01 13:00:00+00'),
 ('e9800000-0000-0000-0000-0000000000b1','e9200000-0000-0000-0000-0000000000b1','9C8-REQ-B','9C8 B','QA isolated B','Equipo B','Lima','correctivo','2026-10-01','sent','internal',false,'fixture',1,false,'2026-09-01 13:00:00+00');
INSERT INTO public.work_orders
 (id,request_id,quote_id,client_organization_id,provider_organization_id,work_order_type,status,title,description,priority,work_order_number,created_at)
 VALUES
 ('e9a00000-0000-0000-0000-0000000000a1','e9800000-0000-0000-0000-0000000000a1',NULL,'e9200000-0000-0000-0000-0000000000a1','e9200000-0000-0000-0000-0000000000a1','internal','pending','9C8 OT A','A only','medium','OT-9C8-A','2026-09-01 13:00:00+00'),
 ('e9a00000-0000-0000-0000-0000000000b1','e9800000-0000-0000-0000-0000000000b1',NULL,'e9200000-0000-0000-0000-0000000000b1','e9200000-0000-0000-0000-0000000000b1','internal','pending','9C8 OT B','B only','medium','OT-9C8-B','2026-09-01 13:00:00+00');

-- ACL: a connected authenticated user still needs valid server-side relationship/role/grants.
SELECT ok(NOT has_function_privilege('anon','public.get_facility_management_client_metrics(uuid,uuid)','EXECUTE'), 'anonymous cannot execute KPI RPC');
SELECT ok(NOT has_function_privilege('anon','public.get_facility_management_client_trends(uuid,uuid,date,date,text)','EXECUTE'), 'anonymous cannot execute trends RPC');
SELECT ok(has_function_privilege('authenticated','public.get_facility_management_client_metrics(uuid,uuid)','EXECUTE'), 'authenticated RPC privilege exists, subject to internal checks');
SELECT ok(has_function_privilege('authenticated','public.get_facility_management_client_trends(uuid,uuid,date,date,text)','EXECUTE'), 'trends RPC privilege exists, subject to internal checks');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()),1::bigint,'FM A manager lists only one assigned relationship');
SELECT is((SELECT relationship_id FROM public.get_my_facility_management_clients()),'e9700000-0000-0000-0000-0000000000a1'::uuid,'FM A manager sees only A-FM A');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid)->'work_orders'->>'total')::int,1,'FM A manager sees one OT only for client A');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid)->'requests'->>'open')::int,1,'FM A manager sees one open request only for client A');
SELECT is((public.get_facility_management_client_trends('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid,'2026-09-01'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'created')::int,1,'FM A manager sees only client A created OT event');
SELECT is((public.get_facility_management_work_orders('e9200000-0000-0000-0000-0000000000a1'::uuid)->>'total')::int,1,'FM A manager reads only client A OT listing');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid) $denied$, '42501', NULL, 'FM A identity cannot borrow FM B relationship for same client');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid) $denied$, '42501', NULL, 'FM A identity cannot access B by borrowing FM B relationship');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid) $denied$, '42501', NULL, 'Mismatched client and relationship rejected');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_trends('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid,'2026-09-01'::date,'2026-09-02'::date,'America/Lima'::text) $denied$, '42501', NULL, 'FM A identity cannot read trends through FM B relationship');
SELECT throws_ok($denied$ SELECT public.get_facility_management_work_orders('e9200000-0000-0000-0000-0000000000b1'::uuid) $denied$, '42501', NULL, 'FM A identity cannot list the other client's orders');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()),2::bigint,'FM B manager sees its two assigned client relationships');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid)->'work_orders'->>'total')::int,1,'FM B manager sees its client A OT through own relationship');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid)->'work_orders'->>'total')::int,1,'FM B manager sees its client B OT through own relationship');
SELECT is((public.get_facility_management_client_trends('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid,'2026-09-01'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders'->'daily'->0->>'created')::int,1,'FM B trends count only client B event');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid) $denied$, '42501', NULL, 'FM B manager cannot substitute FM A relation');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000005');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()),2::bigint,'dual FM user sees only assigned relationships, not every own organization');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid)->'work_orders'->>'total')::int,1,'dual user sees client A via FM A');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid)->'work_orders'->>'total')::int,1,'dual user sees client B via FM B');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid) $denied$, '42501', NULL, 'dual user cannot borrow unassigned A-FM B relation');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()),0::bigint,'unassigned FM owner has no operating clients');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid) $denied$, '42501', NULL, 'FM owner unassigned to relationship denied even with reports grant');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000006');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()),1::bigint,'requester assignment is visible to own user');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid) $denied$, '42501', NULL, 'assigned requester cannot use manager-only reports');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000007');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()),0::bigint,'outsider sees no operating clients');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid) $denied$, '42501', NULL, 'outsider denied KPI');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000001');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid) $denied$, '42501', NULL, 'client owner not assigned to FM cannot use delegated report RPC');
-- Atomic revocation tests are within this isolated transaction only.
RESET ROLE;
DELETE FROM public.facility_management_permissions WHERE relationship_id='e9700000-0000-0000-0000-0000000000a1'::uuid AND permission='reports.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000002');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid) $denied$, '42501', NULL, 'reports.view revocation immediately denies KPI for FM A');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_trends('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a1'::uuid,'2026-09-01'::date,'2026-09-02'::date,'America/Lima'::text) $denied$, '42501', NULL, 'reports.view revocation immediately denies trends for FM A');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid)->'work_orders'->>'total')::int,1,'revoking FM A must not revoke independent FM B relationship');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000005');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid)->'work_orders'->>'total')::int,1,'revoking one FM relationship does not affect another client grant');
RESET ROLE;
DELETE FROM public.facility_management_permissions WHERE relationship_id='e9700000-0000-0000-0000-0000000000b2'::uuid AND permission='requests.view';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000004');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid)->'requests')::text,'null','without requests.view own client B request section becomes null');
SELECT is((public.get_facility_management_client_trends('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid,'2026-09-01'::date,'2026-09-02'::date,'America/Lima'::text)->'work_orders')::text,'null','without requests.view own client B OT trends become null');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid)->'work_orders'->>'total')::int,1,'client A via FM B unaffected by client B domain revocation');
RESET ROLE;
UPDATE public.organization_members SET is_active=false WHERE id='e9300000-0000-0000-0000-000000000004'::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000004');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid) $denied$, '42501', NULL, 'inactive FM B manager membership blocks KPI even if granted');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000005');
SELECT is((public.get_facility_management_client_metrics('e9200000-0000-0000-0000-0000000000b1'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid)->'availability'->>'work_orders'),'false','dual FM user retains client B relationship but request grant remains revoked');
RESET ROLE;
UPDATE public.organization_relationships SET status='suspended' WHERE id='e9700000-0000-0000-0000-0000000000a2'::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000005');
SELECT throws_ok($denied$ SELECT public.get_facility_management_client_trends('e9200000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid,'2026-09-01'::date,'2026-09-02'::date,'America/Lima'::text) $denied$, '42501', NULL, 'suspended alternative FM relation cannot be borrowed for trends');
SELECT pg_temp.as_user('e9100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.get_my_facility_management_clients()),1::bigint,'independent active FM A assignment remains even if reports permission revoked');
RESET ROLE;
SELECT ok((SELECT count(*) FROM public.facility_management_permissions WHERE permission='reports.view' AND relationship_id IN ('e9700000-0000-0000-0000-0000000000a1'::uuid,'e9700000-0000-0000-0000-0000000000a2'::uuid,'e9700000-0000-0000-0000-0000000000b2'::uuid))=2, 'only the targeted synthetic report grant was revoked');
SELECT * FROM finish();
ROLLBACK;
