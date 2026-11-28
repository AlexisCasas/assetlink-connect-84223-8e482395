
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(31);
INSERT INTO auth.users(id,email) VALUES ('e4c10000-0000-4000-8000-000000000002','quarantine-owner@qa.invalid'),('e4c10000-0000-4000-8000-000000000003','quarantine-manager@qa.invalid');
INSERT INTO public.organizations(id,name,organization_type,status) VALUES ('e4c10000-0000-4000-8000-000000000001','Synthetic quarantine','provider_company','active');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES ('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000002','owner',true),('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000003','manager',true);
INSERT INTO public.romax_gmail_connections(organization_id,status,mailbox_email,refresh_ciphertext,connected_by,connected_at) VALUES ('e4c10000-0000-4000-8000-000000000001','connected','synthetic@example.test','synthetic-ciphertext','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z');
INSERT INTO public.romax_opportunities(id,organization_id,subject,source_system,source_thread_id,source_message_id) VALUES ('e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000001','Synthetic quarantine','gmail','thread-a','source-a'),('e4c10000-0000-4000-8000-000000000005','e4c10000-0000-4000-8000-000000000001','Other','gmail','thread-b','source-b');
INSERT INTO public.romax_opportunity_attachments(id,organization_id,opportunity_id,source_system,source_message_id,source_attachment_id,source_locator_kind,source_received_at,source_direction,discovered_by,filename,mime_type,size_bytes)
SELECT ('e4c10000-0000-4000-8000-0000000000'||lpad(n::text,2,'0'))::uuid,'e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','gmail','message-a','attachment-'||n,
  CASE WHEN n=16 THEN 'mime_part' ELSE 'attachment_id' END,'2026-01-01T00:00:00Z','incoming','e4c10000-0000-4000-8000-000000000002','test.pdf','application/pdf',
  CASE WHEN n BETWEEN 13 AND 15 THEN 10485760 ELSE 1024 END
FROM generate_series(10,16) n;
CREATE TEMP TABLE qa_claims(name text primary key,v jsonb);
GRANT ALL ON qa_claims TO service_role;
SELECT ok((SELECT NOT public AND file_size_limit=10485760 FROM storage.buckets WHERE id='romax-request-attachments'),'bucket private and bounded');
SELECT ok(EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='romax_docs_storage_deny_client' AND permissive='RESTRICTIVE'),'restrictive storage gate');
SELECT ok(NOT has_table_privilege('service_role','romax_docs_private.download_attempts','SELECT'),'attempt state private');
SELECT ok(NOT has_function_privilege('authenticated','public.romax_claim_attachment_downloads(uuid,uuid,uuid,timestamptz,uuid[])','EXECUTE'),'claim service-only');
SELECT ok(NOT has_function_privilege('authenticated','public.romax_finish_attachment_download(uuid,uuid,uuid,timestamptz,uuid,uuid,text,bigint,text)','EXECUTE'),'finish service-only');
SET LOCAL ROLE service_role;
SELECT throws_ok($q$SELECT public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000003','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000010']::uuid[])$q$,'42501',NULL,'manager cannot reserve');
SELECT throws_ok($q$SELECT public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000005','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000010']::uuid[])$q$,'22023',NULL,'wrong opportunity denied');
SELECT throws_ok($q$SELECT public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000010','e4c10000-0000-4000-8000-000000000010']::uuid[])$q$,'22023',NULL,'duplicate selection denied');
SELECT throws_ok($q$SELECT public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000010','e4c10000-0000-4000-8000-000000000011','e4c10000-0000-4000-8000-000000000012','e4c10000-0000-4000-8000-000000000013','e4c10000-0000-4000-8000-000000000014','e4c10000-0000-4000-8000-000000000015']::uuid[])$q$,'22023',NULL,'six selected denied');
SELECT throws_ok($q$SELECT public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000013','e4c10000-0000-4000-8000-000000000014','e4c10000-0000-4000-8000-000000000015']::uuid[])$q$,'22023',NULL,'batch over 25 MiB denied');
SELECT throws_ok($q$SELECT public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000016']::uuid[])$q$,'22023',NULL,'inline part deferred');
INSERT INTO qa_claims VALUES('first',public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000010']::uuid[]));
SELECT is((SELECT jsonb_array_length(v->'claims') FROM qa_claims WHERE name='first'),1,'one attempt claimed');
SELECT is((SELECT availability_status FROM public.romax_opportunity_attachments WHERE id='e4c10000-0000-4000-8000-000000000010'),'queued','reserved state');
SELECT throws_ok($q$SELECT public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000010','e4c10000-0000-4000-8000-000000000011']::uuid[])$q$,'40001',NULL,'active lease prevents duplicate and partial batch');
SELECT is((SELECT availability_status FROM public.romax_opportunity_attachments WHERE id='e4c10000-0000-4000-8000-000000000011'),'metadata_only','unrelated document unchanged');
SELECT throws_ok($q$SELECT public.romax_finish_attachment_download('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','e4c10000-0000-4000-8000-000000000010',(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='first'),'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1024,NULL)$q$,'22023',NULL,'no object cannot finalize');
RESET ROLE;
-- Synthetic Storage metadata fixture only; no real bytes or uploads in SQL tests.
INSERT INTO storage.objects(bucket_id,name,metadata) SELECT 'romax-request-attachments',v->'claims'->0->>'path',jsonb_build_object('size',1024) FROM qa_claims WHERE name='first';
SET LOCAL ROLE service_role;
SELECT is((public.romax_finish_attachment_download('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','e4c10000-0000-4000-8000-000000000010',(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='first'),'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1024,NULL))->>'status','quarantined','object metadata confirmed quarantine');
SELECT is((public.romax_finish_attachment_download('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','e4c10000-0000-4000-8000-000000000010',(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='first'),'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1024,NULL))->>'unchanged','true','exact successful finish replay');
SELECT throws_ok($q$SELECT public.romax_finish_attachment_download('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','e4c10000-0000-4000-8000-000000000010',(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='first'),'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',1024,NULL)$q$,'40001',NULL,'changed hash replay denied');
SELECT is((SELECT scan_status FROM public.romax_opportunity_attachments WHERE id='e4c10000-0000-4000-8000-000000000010'),'pending','scanner pending');
SELECT is((SELECT storage_path FROM public.romax_opportunity_attachments WHERE id='e4c10000-0000-4000-8000-000000000010'),NULL::text,'canonical path never published');
SELECT is((public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000010']::uuid[]))->>'skipped','1','already quarantined is not re-downloaded');
INSERT INTO qa_claims VALUES('old',public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000011']::uuid[]));
RESET ROLE;
UPDATE romax_docs_private.download_attempts SET lease_until=clock_timestamp()-interval '1 second' WHERE id=(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='old');
SET LOCAL ROLE service_role;
INSERT INTO qa_claims VALUES('retry',public.romax_claim_attachment_downloads('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c10000-0000-4000-8000-000000000011']::uuid[]));
SELECT ok((SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='old')<>(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='retry'),'retry has fresh fencing token');
SELECT throws_ok($q$SELECT public.romax_finish_attachment_download('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','e4c10000-0000-4000-8000-000000000011',(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='old'),NULL,NULL,'remote_error')$q$,'40001',NULL,'stale attempt cannot finish');
SELECT is((public.romax_finish_attachment_download('e4c10000-0000-4000-8000-000000000001','e4c10000-0000-4000-8000-000000000004','e4c10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','e4c10000-0000-4000-8000-000000000011',(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='retry'),NULL,NULL,'storage_uncertain'))->>'status','failed','uncertain upload recorded');
SELECT is((SELECT availability_status FROM public.romax_opportunity_attachments WHERE id='e4c10000-0000-4000-8000-000000000011'),'failed','no release after failure');
RESET ROLE;
SELECT is((SELECT state FROM romax_docs_private.download_attempts WHERE id=(SELECT (v->'claims'->0->>'attempt')::uuid FROM qa_claims WHERE name='old')), 'expired','expired attempt retained for reconciliation');
SELECT is((SELECT count(*) FROM public.romax_opportunity_attachments WHERE organization_id='e4c10000-0000-4000-8000-000000000001' AND availability_status='available'),0::bigint,'no release in 4C.1');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','e4c10000-0000-4000-8000-000000000002',true);
SELECT is((SELECT count(*) FROM storage.objects WHERE bucket_id='romax-request-attachments'),0::bigint,'owner cannot list quarantined object');
SELECT throws_ok($q$INSERT INTO storage.objects(bucket_id,name) VALUES ('romax-request-attachments','forged')$q$,'42501',NULL,'owner cannot write bucket');
RESET ROLE;
SELECT is((SELECT count(*) FROM romax_docs_private.attachment_events WHERE organization_id='e4c10000-0000-4000-8000-000000000001' AND attachment_id='e4c10000-0000-4000-8000-000000000010' AND next_state='quarantined'),1::bigint,'successful replay does not duplicate audit');
SELECT * FROM finish();
ROLLBACK;
