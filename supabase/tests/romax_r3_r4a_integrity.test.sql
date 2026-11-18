-- ROMAX R3/R4-A regression. LOCAL/DISPOSABLE DATABASE ONLY.
-- Every synthetic record and role claim is discarded by ROLLBACK.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(32);
CREATE FUNCTION pg_temp.romax_as_user(p_id uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub',coalesce(p_id::text,''),true);
$$;

INSERT INTO auth.users(id,email) VALUES
 ('c6100000-0000-0000-0000-000000000001','r3-owner@qa.invalid'),
 ('c6100000-0000-0000-0000-000000000002','r3-viewer@qa.invalid'),
 ('c6100000-0000-0000-0000-000000000003','r3-outsider@qa.invalid');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('c6200000-0000-0000-0000-0000000000a1','R3 QA provider A','provider_company'),
 ('c6200000-0000-0000-0000-0000000000b1','R3 QA provider B','provider_company');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES
 ('c6200000-0000-0000-0000-0000000000a1','c6100000-0000-0000-0000-000000000001','owner',true),
 ('c6200000-0000-0000-0000-0000000000a1','c6100000-0000-0000-0000-000000000002','viewer',true),
 ('c6200000-0000-0000-0000-0000000000b1','c6100000-0000-0000-0000-000000000003','owner',true);

SELECT has_table('public','romax_opportunities','opportunities table exists');
SELECT has_table('public','romax_opportunity_attachments','attachments table exists');
SELECT has_table('public','romax_opportunity_analyses','analyses table exists');
SELECT has_table('public','romax_opportunity_analysis_items','analysis items table exists');
SELECT ok(NOT has_table_privilege('anon','public.romax_opportunities','SELECT'), 'anonymous cannot read opportunities');
SELECT ok(NOT has_table_privilege('anon','public.romax_opportunity_analyses','SELECT'), 'anonymous cannot read analyses');
SELECT ok(NOT has_table_privilege('authenticated','public.romax_opportunity_analyses','DELETE'), 'no hard-delete of analyses');
SELECT ok(has_column_privilege('authenticated','public.romax_opportunities','status','UPDATE'),
  'authorized editor can update opportunity status');
SELECT ok(NOT has_column_privilege('authenticated','public.romax_opportunities','organization_id','UPDATE'),
  'editor cannot reassign opportunity tenant');
SELECT ok(has_column_privilege('authenticated','public.romax_opportunity_analyses','status','UPDATE'),
  'save RPC can supersede a previous analysis');
SELECT ok(NOT has_column_privilege('authenticated','public.romax_opportunity_analyses','created_by','UPDATE'),
  'editor cannot rewrite analysis creator');

SELECT ok(NOT has_function_privilege('anon','public.romax_save_opportunity_analysis_v1(uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE'), 'anonymous cannot call save RPC');
SELECT ok(has_function_privilege('authenticated','public.romax_save_opportunity_analysis_v1(uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE'), 'authenticated role can call guarded RPC');

SET LOCAL ROLE authenticated;
SELECT pg_temp.romax_as_user('c6100000-0000-0000-0000-000000000001');
INSERT INTO public.romax_opportunities(id,organization_id,subject,source_system)
VALUES ('c6300000-0000-0000-0000-000000000001','c6200000-0000-0000-0000-0000000000a1','R3 QA manual request','manual');

SELECT is(
 (SELECT created_by FROM public.romax_opportunities WHERE id='c6300000-0000-0000-0000-000000000001'),
 'c6100000-0000-0000-0000-000000000001'::uuid,
 'creator defaults to the actual authenticated actor'
);

SELECT lives_ok($save$
 SELECT * FROM public.romax_save_opportunity_analysis_v1(
  'c6300000-0000-0000-0000-000000000001',
  'Instalación eléctrica','Cableado',
  '["Confirmar medidas"]'::jsonb,'[]'::jsonb,'[]'::jsonb,
  '[{"item_type":"material","description":"Cable NH80","quantity":5,"unit_code":"M"},
    {"item_type":"labor","description":"Técnico","quantity":2,"unit_code":"HORA"}]'::jsonb
 )
$save$, 'owner saves version 1 and both items atomically');

SELECT is((SELECT max(version_number) FROM public.romax_opportunity_analyses),1,'first analysis version is 1');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analysis_items),2::bigint,'both analysis items persisted together');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses WHERE status='draft'),1::bigint,'first analysis is active draft');

SELECT lives_ok($save$
 SELECT * FROM public.romax_save_opportunity_analysis_v1(
  'c6300000-0000-0000-0000-000000000001',
  'Instalación eléctrica','Cableado actualizado',
  '[]'::jsonb,'[]'::jsonb,'[]'::jsonb,
  '[{"item_type":"material","description":"Cable NH80","quantity":8,"unit_code":"M"}]'::jsonb
 )
$save$, 'second analysis saved atomically');

SELECT is((SELECT max(version_number) FROM public.romax_opportunity_analyses),2,'second analysis gets version 2');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses WHERE status='superseded'),1::bigint,'previous version superseded');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses WHERE status='draft'),1::bigint,'one latest draft');

SELECT throws_ok($save$
 SELECT * FROM public.romax_save_opportunity_analysis_v1(
  'c6300000-0000-0000-0000-000000000001','Bad qty','Bad qty',
  '[]'::jsonb,'[]'::jsonb,'[]'::jsonb,
  '[{"item_type":"material","description":"Bad","quantity":-1,"unit_code":"M"}]'::jsonb
 )
$save$, '23514', NULL, 'bad item rolls back the entire save');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),2::bigint,'failed save left no partial version');

INSERT INTO public.romax_opportunity_attachments(
 organization_id, opportunity_id, source_system, source_message_id, source_attachment_id, filename
) VALUES
 ('c6200000-0000-0000-0000-0000000000a1','c6300000-0000-0000-0000-000000000001','gmail','msg-a','attachment-1','one.pdf'),
 ('c6200000-0000-0000-0000-0000000000a1','c6300000-0000-0000-0000-000000000001','gmail','msg-b','attachment-1','two.pdf');
SELECT is((SELECT count(*) FROM public.romax_opportunity_attachments),2::bigint,'Gmail attachment ID is scoped to message');
SELECT throws_ok($dupe$
 INSERT INTO public.romax_opportunity_attachments(
  organization_id,opportunity_id,source_system,source_message_id,source_attachment_id,filename
 ) VALUES (
  'c6200000-0000-0000-0000-0000000000a1','c6300000-0000-0000-0000-000000000001',
  'gmail','msg-a','attachment-1','duplicate.pdf'
 )
$dupe$,'23505',NULL,'same message and attachment cannot duplicate');

-- The BEFORE INSERT tenant-link guard rejects first (P0001) before CHECK.
SELECT throws_ok($invalid$
 INSERT INTO public.romax_opportunities(organization_id,subject,commercial_site_id)
 VALUES('c6200000-0000-0000-0000-0000000000a1','Invalid orphan site','c6400000-0000-0000-0000-000000000001')
$invalid$,'P0001',NULL,'site cannot be linked without client');

SELECT pg_temp.romax_as_user('c6100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.romax_opportunities),0::bigint,'viewer cannot read commercial opportunities');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),0::bigint,'viewer cannot read analyses');
SELECT throws_ok($denied$
 SELECT * FROM public.romax_save_opportunity_analysis_v1(
  'c6300000-0000-0000-0000-000000000001','Unauthorized',NULL,
  '[]'::jsonb,'[]'::jsonb,'[]'::jsonb,'[]'::jsonb
 )
$denied$,'42501',NULL,'viewer cannot save analyses');

SELECT pg_temp.romax_as_user('c6100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.romax_opportunities),0::bigint,'other tenant sees no opportunity');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),0::bigint,'other tenant sees no analyses');

SELECT * FROM finish();
ROLLBACK;
