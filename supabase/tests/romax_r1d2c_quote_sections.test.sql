-- ROMAX R1-D2C: disposable database only.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(16);
CREATE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claim.sub',coalesce(p_id::text,''),true)
$$;
INSERT INTO auth.users(id,email) VALUES
 ('e2100000-0000-0000-0000-000000000001','r1d2c-owner-a@test.invalid'),
 ('e2100000-0000-0000-0000-000000000002','r1d2c-owner-b@test.invalid'),
 ('e2100000-0000-0000-0000-000000000003','r1d2c-outsider@test.invalid');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('e2200000-0000-0000-0000-000000000001','QA R1-D2C Provider A','provider_company'),
 ('e2200000-0000-0000-0000-000000000002','QA R1-D2C Provider B','provider_company');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','owner',true),
 ('e2200000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000002','owner',true);
INSERT INTO public.commercial_quote_history(id,organization_id,service_title,import_batch,import_source_key) VALUES
 ('e2300000-0000-0000-0000-000000000001','e2200000-0000-0000-0000-000000000001','QA quote A synthetic','QA','r1d2c-a'),
 ('e2300000-0000-0000-0000-000000000002','e2200000-0000-0000-0000-000000000002','QA quote B synthetic','QA','r1d2c-b');
INSERT INTO public.commercial_quote_history_sections
 (organization_id,history_id,section_order,section_kind,original_heading,section_text,provenance)
 VALUES
 ('e2200000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001',1,'technical','2. ACLARACIONES TECNICAS','Synthetic technical work without unit pricing.','pdf_extracted_text'),
 ('e2200000-0000-0000-0000-000000000002','e2300000-0000-0000-0000-000000000002',1,'safety','3. SEGURIDAD','Synthetic EPP requirements.','pdf_extracted_text');
SELECT has_table('public','commercial_quote_history_sections','sections table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.commercial_quote_history_sections'::regclass),'sections RLS enabled');
SELECT ok(NOT has_table_privilege('anon','public.commercial_quote_history_sections','SELECT'),'anonymous denied');
SELECT ok(has_table_privilege('authenticated','public.commercial_quote_history_sections','SELECT'),'authenticated select granted');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history_sections','INSERT'),'browser cannot insert');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history_sections','UPDATE'),'browser cannot edit');
SELECT is((SELECT review_status FROM public.commercial_quote_history_sections WHERE section_kind='technical'),'extracted_unverified'::text,'status defaults to unverified');
SELECT is((SELECT source_page FROM public.commercial_quote_history_sections WHERE section_kind='technical'),NULL::integer,'unknown PDF page remains NULL');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_sections
 (organization_id,history_id,section_order,section_kind,original_heading,section_text)
 VALUES ('e2200000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000002',2,'technical','Bad tenant','Cross tenant content') $$,
 '23503',NULL,'cross-tenant section blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_sections
 (organization_id,history_id,section_order,section_kind,original_heading,section_text)
 VALUES ('e2200000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001',1,'technical','Duplicate','Duplicate section content') $$,
 '23505',NULL,'duplicate sequence blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_sections
 (organization_id,history_id,section_order,section_kind,original_heading,section_text)
 VALUES ('e2200000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001',2,'made_up_kind','Fake section','No valid type') $$,
 '23514',NULL,'invalid section kind blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_sections
 (organization_id,history_id,section_order,section_kind,original_heading,section_text,source_page)
 VALUES ('e2200000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001',2,'technical','Bad page','Unknown source page',0) $$,
 '23514',NULL,'invalid page blocked');
INSERT INTO public.commercial_quote_history_cost_components
 (organization_id,history_id,component_kind,amount,source_page,source_label)
 VALUES ('e2200000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001','net_total',100,NULL,'Synthetic net without confirmed page');
SELECT is((SELECT source_page FROM public.commercial_quote_history_cost_components
 WHERE source_label='Synthetic net without confirmed page'),NULL::integer,'unknown economic-summary page stays NULL');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_sections),1::bigint,'owner A sees own section only');
SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_sections),1::bigint,'owner B sees own section only');
SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_sections),0::bigint,'outsider sees no sections');
SELECT * FROM finish();
ROLLBACK;
