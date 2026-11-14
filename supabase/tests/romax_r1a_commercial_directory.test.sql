-- R1-A QA. LOCAL/DISPOSABLE DATABASE ONLY; never run on production.
-- Test fixtures are synthetic; transaction rolls back automatically.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(16);
CREATE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claim.sub', coalesce(p_id::text,''), true);
$$;

INSERT INTO auth.users (id,email) VALUES
 ('a1100000-0000-0000-0000-000000000001','a-owner@r1a-qa.test'),
 ('a1100000-0000-0000-0000-000000000002','b-owner@r1a-qa.test'),
 ('a1100000-0000-0000-0000-000000000003','a-viewer@r1a-qa.test'),
 ('a1100000-0000-0000-0000-000000000004','outsider@r1a-qa.test');
INSERT INTO public.organizations (id,name,organization_type) VALUES
 ('a1200000-0000-0000-0000-000000000001','R1A QA Provider A','provider_company'),
 ('a1200000-0000-0000-0000-000000000002','R1A QA Provider B','provider_company');
INSERT INTO public.organization_members (organization_id,user_id,role,is_active) VALUES
 ('a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','owner',true),
 ('a1200000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002','owner',true),
 ('a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000003','viewer',true);
INSERT INTO public.commercial_clients (id,organization_id,business_name) VALUES
 ('a1300000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001','Client A1'),
 ('a1300000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-000000000002','Client B'),
 ('a1300000-0000-0000-0000-000000000003','a1200000-0000-0000-0000-000000000001','Client A2');
INSERT INTO public.commercial_client_sites (id,organization_id,commercial_client_id,site_name) VALUES
 ('a1400000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001','A1 Site');

SELECT has_table('public','commercial_clients','clients table');
SELECT has_table('public','commercial_client_sites','sites table');
SELECT has_table('public','commercial_client_contacts','contacts table');
SELECT ok(NOT has_table_privilege('anon','public.commercial_clients','SELECT'),'anon cannot read');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_clients','DELETE'),'no hard delete');
SELECT ok(NOT has_column_privilege('authenticated','public.commercial_clients','organization_id','UPDATE'),'tenant immutable');
SELECT ok(NOT has_column_privilege('authenticated','public.commercial_clients','linked_client_organization_id','UPDATE'),'hybrid link service only');
SELECT throws_ok($$ INSERT INTO public.commercial_client_sites (organization_id,commercial_client_id,site_name)
 VALUES ('a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000002','cross tenant') $$,
 '23503',NULL,'cross-tenant site FK');
SELECT throws_ok($$ INSERT INTO public.commercial_client_contacts (organization_id,commercial_client_id,commercial_site_id,full_name)
 VALUES ('a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000003','a1400000-0000-0000-0000-000000000001','wrong customer') $$,
 '23503',NULL,'site/client mismatch FK');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a1100000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.commercial_clients),2::bigint,'owner A only sees its customers');
SELECT lives_ok($$INSERT INTO public.commercial_client_contacts
 (organization_id, commercial_client_id, full_name) VALUES
 ('a1200000-0000-0000-0000-000000000001','a1300000-0000-0000-0000-000000000001','Contact A')$$,'owner A can add contact');
SELECT pg_temp.as_user('a1100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.commercial_clients),2::bigint,'viewer A sees A customers');
SELECT throws_ok($$INSERT INTO public.commercial_clients (organization_id,business_name)
 VALUES ('a1200000-0000-0000-0000-000000000001','not allowed')$$,
 '42501',NULL,'viewer cannot insert');
SELECT pg_temp.as_user('a1100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.commercial_clients),1::bigint,'owner B isolated');
SELECT pg_temp.as_user('a1100000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.commercial_clients),0::bigint,'outsider sees nothing');
SELECT is((SELECT count(*) FROM public.commercial_client_sites),0::bigint,'outsider cannot see sites');
SELECT * FROM finish();
ROLLBACK;
