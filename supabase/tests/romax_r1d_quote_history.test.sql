-- ROMAX R1-D: execute in a disposable/local Supabase stack ONLY.
-- All synthetic users, organizations and quotations are rolled back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(23);
CREATE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', coalesce(p_id::text,''), true)
$$;

INSERT INTO auth.users (id,email) VALUES
 ('d1100000-0000-0000-0000-000000000001','owner-a@r1d-qa.test'),
 ('d1100000-0000-0000-0000-000000000002','owner-b@r1d-qa.test'),
 ('d1100000-0000-0000-0000-000000000003','outsider@r1d-qa.test');

INSERT INTO public.organizations (id,name,organization_type) VALUES
 ('d1200000-0000-0000-0000-000000000001','R1D QA provider A','provider_company'),
 ('d1200000-0000-0000-0000-000000000002','R1D QA provider B','provider_company');

INSERT INTO public.organization_members (organization_id,user_id,role,is_active) VALUES
 ('d1200000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','owner',true),
 ('d1200000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000002','owner',true);

INSERT INTO public.commercial_clients (id,organization_id,business_name) VALUES
 ('d1300000-0000-0000-0000-000000000001','d1200000-0000-0000-0000-000000000001','A 1'),
 ('d1300000-0000-0000-0000-000000000002','d1200000-0000-0000-0000-000000000001','A 2'),
 ('d1300000-0000-0000-0000-000000000003','d1200000-0000-0000-0000-000000000002','B 1');

INSERT INTO public.commercial_client_sites (id,organization_id,commercial_client_id,site_name) VALUES
 ('d1400000-0000-0000-0000-000000000001','d1200000-0000-0000-0000-000000000001','d1300000-0000-0000-0000-000000000001','A 1 Site'),
 ('d1400000-0000-0000-0000-000000000002','d1200000-0000-0000-0000-000000000001','d1300000-0000-0000-0000-000000000002','A 2 Site'),
 ('d1400000-0000-0000-0000-000000000003','d1200000-0000-0000-0000-000000000002','d1300000-0000-0000-0000-000000000003','B 1 Site');

INSERT INTO public.commercial_quote_history
 (id,organization_id,commercial_client_id,commercial_site_id,reference_document,
  reference_filename,reference_review,service_title,currency_code,client_match_status,
  import_batch,import_source_key)
 VALUES
 ('d1500000-0000-0000-0000-000000000001','d1200000-0000-0000-0000-000000000001',
  'd1300000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000001',
  'RMX-2026-0212','RMX-2026-0212','match','Synthetic roof repair','PEN','matched','QA','qa-file-1'),
 ('d1500000-0000-0000-0000-000000000002','d1200000-0000-0000-0000-000000000002',
  'd1300000-0000-0000-0000-000000000003','d1400000-0000-0000-0000-000000000003',
  'RMX-2026-0212','RMX-2026-0212','match','Synthetic plumbing','PEN','matched','QA','qa-file-2');

INSERT INTO public.commercial_quote_history_documents
 (organization_id,history_id,source_provider,source_file_id,source_filename,mime_type,document_role)
 VALUES
 ('d1200000-0000-0000-0000-000000000001','d1500000-0000-0000-0000-000000000001',
 'google_drive','qa-drive-file-1','Synthetic A.pdf','application/pdf','primary_pdf'),
 ('d1200000-0000-0000-0000-000000000002','d1500000-0000-0000-0000-000000000002',
 'google_drive','qa-drive-file-2','Synthetic B.pdf','application/pdf','primary_pdf');

SELECT has_table('public','commercial_quote_history','history table exists');
SELECT has_table('public','commercial_quote_history_documents','history documents table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.commercial_quote_history'::regclass),'history RLS enabled');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.commercial_quote_history_documents'::regclass),'document RLS enabled');
SELECT ok(NOT has_table_privilege('anon','public.commercial_quote_history','SELECT'),'anonymous read denied');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history','INSERT'),'web history insertion denied');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history','UPDATE'),'web update denied');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history_documents','INSERT'),'web document insertion denied');
SELECT is((SELECT count(*) FROM public.commercial_quote_history WHERE reference_document='RMX-2026-0212'),2::bigint,'duplicate correlation number allowed');

SELECT throws_ok($$ INSERT INTO public.commercial_quote_history
  (organization_id,service_title,import_batch,import_source_key)
  VALUES ('d1200000-0000-0000-0000-000000000001','Duplicate source','QA','qa-file-1') $$,
 '23505',NULL,'duplicate source key denied');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history
  (organization_id,commercial_client_id,client_match_status,service_title,import_batch,import_source_key)
  VALUES ('d1200000-0000-0000-0000-000000000001',
  'd1300000-0000-0000-0000-000000000003','matched','Wrong-tenant customer','QA','qa-file-3') $$,
 '23503',NULL,'wrong tenant client denied');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history
  (organization_id,commercial_client_id,commercial_site_id,client_match_status,
   service_title,import_batch,import_source_key)
  VALUES ('d1200000-0000-0000-0000-000000000001',
  'd1300000-0000-0000-0000-000000000001',
  'd1400000-0000-0000-0000-000000000002','matched','Wrong-client site','QA','qa-file-4') $$,
 '23503',NULL,'wrong client site denied');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history
  (organization_id,commercial_site_id,service_title,import_batch,import_source_key)
  VALUES ('d1200000-0000-0000-0000-000000000001',
  'd1400000-0000-0000-0000-000000000001','Orphan site','QA','qa-file-5') $$,
 '23514',NULL,'site requires client');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history
  (organization_id,service_title,price_review,import_batch,import_source_key)
  VALUES ('d1200000-0000-0000-0000-000000000001','No price','verified','QA','qa-file-6') $$,
 '23514',NULL,'price cannot be verified with no amount');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_documents
  (organization_id,history_id,source_file_id,source_filename,mime_type)
  VALUES ('d1200000-0000-0000-0000-000000000001',
  'd1500000-0000-0000-0000-000000000002','qa-drive-file-3','Other.pdf','application/pdf') $$,
 '23503',NULL,'cannot attach quote document across tenant');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_documents
  (organization_id,history_id,source_file_id,source_filename,mime_type)
  VALUES ('d1200000-0000-0000-0000-000000000001',
  'd1500000-0000-0000-0000-000000000001','qa-drive-file-1','Same.pdf','application/pdf') $$,
 '23505',NULL,'same Drive source cannot duplicate');

SELECT is((SELECT commercial_status FROM public.commercial_quote_history WHERE id='d1500000-0000-0000-0000-000000000001'),'unverified'::text,'folder not proof of acceptance/sending');
SELECT is((SELECT price_review FROM public.commercial_quote_history WHERE id='d1500000-0000-0000-0000-000000000001'),'pending'::text,'amounts remain pending');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1100000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.commercial_quote_history),1::bigint,'provider A sees its quotation only');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_documents),1::bigint,'provider A sees its doc only');
SELECT pg_temp.as_user('d1100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.commercial_quote_history),1::bigint,'provider B sees its quotation only');
SELECT pg_temp.as_user('d1100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.commercial_quote_history),0::bigint,'outsider sees zero history');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_documents),0::bigint,'outsider sees zero documents');

SELECT * FROM finish();
ROLLBACK;
