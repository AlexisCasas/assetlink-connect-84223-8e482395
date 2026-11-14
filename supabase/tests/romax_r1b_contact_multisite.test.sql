-- R1-B QA: disposable/local Supabase database only.
-- Creates only synthetic fixtures inside a transaction, rolled back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(19);
CREATE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', coalesce(p_id::text,''), true)
$$;

INSERT INTO auth.users (id,email) VALUES
 ('b1100000-0000-0000-0000-000000000001','b1owner@r1b-qa.test'),
 ('b1100000-0000-0000-0000-000000000002','b2owner@r1b-qa.test'),
 ('b1100000-0000-0000-0000-000000000003','b1viewer@r1b-qa.test'),
 ('b1100000-0000-0000-0000-000000000004','outsider@r1b-qa.test');

INSERT INTO public.organizations (id,name,organization_type) VALUES
 ('b1200000-0000-0000-0000-000000000001','QA R1-B Provider A','provider_company'),
 ('b1200000-0000-0000-0000-000000000002','QA R1-B Provider B','provider_company');

INSERT INTO public.organization_members (organization_id,user_id,role,is_active) VALUES
 ('b1200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','owner',true),
 ('b1200000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000002','owner',true),
 ('b1200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000003','viewer',true);

INSERT INTO public.commercial_clients (id,organization_id,business_name) VALUES
 ('b1300000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','A client 1'),
 ('b1300000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-000000000001','A client 2'),
 ('b1300000-0000-0000-0000-000000000003','b1200000-0000-0000-0000-000000000002','B client 1');

INSERT INTO public.commercial_client_sites (id,organization_id,commercial_client_id,site_name) VALUES
 ('b1400000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','A site 1'),
 ('b1400000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','A site 2'),
 ('b1400000-0000-0000-0000-000000000003','b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000002','A other client site'),
 ('b1400000-0000-0000-0000-000000000004','b1200000-0000-0000-0000-000000000002','b1300000-0000-0000-0000-000000000003','B site 1');

INSERT INTO public.commercial_client_contacts
 (id,organization_id,commercial_client_id,full_name) VALUES
 ('b1500000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','Contact A1'),
 ('b1500000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000002','Contact A2'),
 ('b1500000-0000-0000-0000-000000000003','b1200000-0000-0000-0000-000000000002','b1300000-0000-0000-0000-000000000003','Contact B1');

INSERT INTO public.commercial_client_contact_sites
 (organization_id,commercial_client_id,commercial_contact_id,commercial_site_id) VALUES
 ('b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1500000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001'),
 ('b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1500000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000002'),
 ('b1200000-0000-0000-0000-000000000002','b1300000-0000-0000-0000-000000000003','b1500000-0000-0000-0000-000000000003','b1400000-0000-0000-0000-000000000004');

SELECT has_table('public','commercial_client_contact_sites','multisite link table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.commercial_client_contact_sites'::regclass),'multisite RLS enabled');
SELECT ok(NOT has_table_privilege('anon','public.commercial_client_contact_sites','SELECT'),'anonymous cannot read');
SELECT ok(NOT has_table_privilege('anon','public.commercial_client_contact_sites','INSERT'),'anonymous cannot insert');
SELECT ok(NOT has_table_privilege('authenticated','public.commercial_client_contact_sites','UPDATE'),'links are immutable');
SELECT ok(has_table_privilege('authenticated','public.commercial_client_contact_sites','DELETE'),'browser role allowed to remove owned links');
SELECT ok(NOT has_column_privilege('authenticated','public.commercial_client_contact_sites','organization_id','UPDATE'),'link tenant immutable');

SELECT throws_ok($$ INSERT INTO public.commercial_client_contact_sites
  (organization_id,commercial_client_id,commercial_contact_id,commercial_site_id) VALUES
  ('b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1500000-0000-0000-0000-000000000003','b1400000-0000-0000-0000-000000000001') $$,
  '23503',NULL,'foreign tenant contact blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_client_contact_sites
  (organization_id,commercial_client_id,commercial_contact_id,commercial_site_id) VALUES
  ('b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1500000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000003') $$,
  '23503',NULL,'other commercial client site blocked');
SELECT throws_ok($$ INSERT INTO public.commercial_client_contact_sites
  (organization_id,commercial_client_id,commercial_contact_id,commercial_site_id) VALUES
  ('b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1500000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001') $$,
  '23505',NULL,'duplicate contact site link blocked');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b1100000-0000-0000-0000-000000000001');
SELECT is((SELECT count(*) FROM public.commercial_client_contact_sites),2::bigint,'provider A reads only its two links');
SELECT lives_ok($$ INSERT INTO public.commercial_client_contact_sites
 (organization_id,commercial_client_id,commercial_contact_id,commercial_site_id) VALUES
 ('b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000002','b1500000-0000-0000-0000-000000000002','b1400000-0000-0000-0000-000000000003') $$,
 'owner A may add a valid link');
SELECT is((SELECT count(*) FROM public.commercial_client_contact_sites),3::bigint,'owner A sees three links');
SELECT throws_ok($$ INSERT INTO public.commercial_client_contact_sites
 (organization_id,commercial_client_id,commercial_contact_id,commercial_site_id) VALUES
 ('b1200000-0000-0000-0000-000000000002','b1300000-0000-0000-0000-000000000003','b1500000-0000-0000-0000-000000000003','b1400000-0000-0000-0000-000000000004') $$,
 '42501',NULL,'owner A cannot write for B');

SELECT pg_temp.as_user('b1100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.commercial_client_contact_sites),3::bigint,'viewer A can read links');
SELECT throws_ok($$ INSERT INTO public.commercial_client_contact_sites
 (organization_id,commercial_client_id,commercial_contact_id,commercial_site_id) VALUES
 ('b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1500000-0000-0000-0000-000000000002','b1400000-0000-0000-0000-000000000001') $$,
 '42501',NULL,'viewer cannot insert');
DELETE FROM public.commercial_client_contact_sites
 WHERE organization_id='b1200000-0000-0000-0000-000000000001'
   AND commercial_contact_id='b1500000-0000-0000-0000-000000000001';
SELECT is((SELECT count(*) FROM public.commercial_client_contact_sites),3::bigint,'viewer delete changes nothing');

SELECT pg_temp.as_user('b1100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.commercial_client_contact_sites),1::bigint,'provider B sees only its own link');
SELECT pg_temp.as_user('b1100000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.commercial_client_contact_sites),0::bigint,'outsider cannot read links');
SELECT * FROM finish();
ROLLBACK;
