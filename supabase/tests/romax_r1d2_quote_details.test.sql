-- R1-D2 quote line items: run only in a disposable Supabase database.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(24);
CREATE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claim.sub',coalesce(p_id::text,''),true)
$$;
INSERT INTO auth.users(id,email) VALUES
 ('e1100000-0000-0000-0000-000000000001','r1d2-owner-a@test.invalid'),
 ('e1100000-0000-0000-0000-000000000002','r1d2-owner-b@test.invalid'),
 ('e1100000-0000-0000-0000-000000000003','r1d2-outsider@test.invalid');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('e1200000-0000-0000-0000-000000000001','QA R1-D2 Provider A','provider_company'),
 ('e1200000-0000-0000-0000-000000000002','QA R1-D2 Provider B','provider_company');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES
 ('e1200000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','owner',true),
 ('e1200000-0000-0000-0000-000000000002','e1100000-0000-0000-0000-000000000002','owner',true);
INSERT INTO public.commercial_quote_history(id,organization_id,service_title,import_batch,import_source_key) VALUES
 ('e1300000-0000-0000-0000-000000000001','e1200000-0000-0000-0000-000000000001','Synthetic quote A','QA','qa-r1d2-1'),
 ('e1300000-0000-0000-0000-000000000002','e1200000-0000-0000-0000-000000000002','Synthetic quote B','QA','qa-r1d2-2');
INSERT INTO public.commercial_quote_history_line_items
 (organization_id,history_id,section_kind,line_order,description,unit_label,quantity,unit_price,line_total,currency_code,source_page) VALUES
 ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000001','service',1,'Synthetic welding','UND',10,null,null,'PEN',1),
 ('e1200000-0000-0000-0000-000000000002','e1300000-0000-0000-0000-000000000002','material',1,'Synthetic wheels','UND',10,65,650,'PEN',1);
INSERT INTO public.commercial_quote_history_cost_components
 (organization_id,history_id,component_kind,amount,currency_code,source_page,source_label) VALUES
 ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000001','labor',650,'PEN',2,'Labor'),
 ('e1200000-0000-0000-0000-000000000002','e1300000-0000-0000-0000-000000000002','materials',850,'PEN',2,'Materials');
INSERT INTO public.commercial_quote_history_source_extracts
 (organization_id,history_id,source_text) VALUES
 ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000001','Synthetic source text A'),
 ('e1200000-0000-0000-0000-000000000002','e1300000-0000-0000-0000-000000000002','Synthetic source text B');

SELECT has_table('public','commercial_quote_history_line_items','line items table exists');
SELECT has_table('public','commercial_quote_history_cost_components','cost components table exists');
SELECT has_table('public','commercial_quote_history_source_extracts','source extracts table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.commercial_quote_history_line_items'::regclass),'lines RLS active');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.commercial_quote_history_cost_components'::regclass),'costs RLS active');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.commercial_quote_history_source_extracts'::regclass),'raw texts RLS active');
SELECT ok(NOT has_table_privilege('anon','public.commercial_quote_history_line_items','SELECT'),'no anonymous lines');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history_line_items','INSERT'),'web cannot create lines');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history_cost_components','UPDATE'),'web cannot change prices');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_quote_history_source_extracts','INSERT'),'web cannot inject AI context');
SELECT is((SELECT review_status FROM public.commercial_quote_history_line_items WHERE description='Synthetic welding'),'extracted_unverified'::text,'line price not automatically approved');
SELECT is((SELECT review_status FROM public.commercial_quote_history_cost_components WHERE source_label='Labor'),'extracted_unverified'::text,'summary price not approved');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_line_items
  (organization_id,history_id,section_kind,line_order,description,source_page)
  VALUES ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000002','service',2,'Cross tenant',1) $$,
 '23503',NULL,'cross-tenant line blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_cost_components
 (organization_id,history_id,component_kind,amount,source_page,source_label)
 VALUES ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000002','labor',50,1,'Cross') $$,
 '23503',NULL,'cross-tenant summary blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_source_extracts
 (organization_id,history_id,source_text)
 VALUES ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000002','Cross text') $$,
 '23503',NULL,'cross-tenant raw text blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_line_items
 (organization_id,history_id,section_kind,line_order,description,source_page)
 VALUES ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000001','service',1,'Duplicate',1) $$,
 '23505',NULL,'duplicate line identity blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_quote_history_line_items
 (organization_id,history_id,section_kind,line_order,description,quantity,source_page)
 VALUES ('e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000001','service',2,'Negative qty',-1,1) $$,
 '23514',NULL,'negative quantity blocked');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e1100000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_line_items),1::bigint,'owner A sees own line only');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_cost_components),1::bigint,'owner A sees own summary only');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_source_extracts),1::bigint,'owner A sees own text only');
SELECT pg_temp.as_user('e1100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_line_items),1::bigint,'owner B sees own line only');
SELECT pg_temp.as_user('e1100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_line_items),0::bigint,'outsider lines hidden');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_cost_components),0::bigint,'outsider costs hidden');
SELECT is((SELECT count(*) FROM public.commercial_quote_history_source_extracts),0::bigint,'outsider raw text hidden');

SELECT * FROM finish();
ROLLBACK;
