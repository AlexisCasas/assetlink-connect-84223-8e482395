-- R2-E2.1 pricing access/RLS regression. LOCAL/DISPOSABLE DATABASE ONLY.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(46);
CREATE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claim.sub',coalesce(p_id::text,''),true);
$$;

INSERT INTO auth.users(id,email) VALUES
 ('e2100000-0000-0000-0000-000000000001','e21-owner@test.invalid'),
 ('e2100000-0000-0000-0000-000000000002','e21-logistics@test.invalid'),
 ('e2100000-0000-0000-0000-000000000003','e21-validator@test.invalid'),
 ('e2100000-0000-0000-0000-000000000004','e21-viewer@test.invalid'),
 ('e2100000-0000-0000-0000-000000000005','e21-no-access@test.invalid'),
 ('e2100000-0000-0000-0000-000000000006','e21-rules@test.invalid'),
 ('e2100000-0000-0000-0000-000000000007','e21-outsider@test.invalid'),
 ('e2100000-0000-0000-0000-000000000008','e21-inactive@test.invalid');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('e2200000-0000-0000-0000-000000000001','R2E21 ROMAX A','provider_company'),
 ('e2200000-0000-0000-0000-000000000002','R2E21 Provider B','provider_company');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','owner',true),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000002','manager',true),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000003','manager',true),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000004','viewer',true),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000005','technician',true),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000006','manager',true),
 ('e2200000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000007','owner',true),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000008','viewer',false);

SELECT has_table('public','provider_pricing_access_grants','capability grants table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.provider_pricing_access_grants'::regclass),'grant table has RLS');
SELECT ok(to_regclass('public.provider_pricing_access_grants_user_idx') IS NOT NULL,'user foreign key has a supporting index');
SELECT ok(to_regclass('public.provider_pricing_access_grants_revoked_by_idx') IS NOT NULL,'revoked_by foreign key has a supporting index');
SELECT ok(NOT has_table_privilege('anon','public.provider_pricing_access_grants','SELECT'),'anon cannot inspect grants');
SELECT ok(NOT has_table_privilege('authenticated','public.provider_pricing_access_grants','DELETE'),'authenticated cannot delete grant history');
SELECT ok(NOT has_table_privilege('service_role','public.provider_pricing_access_grants','DELETE'),'service role cannot hard-delete grant audit');
SELECT ok(NOT has_table_privilege('service_role','public.provider_pricing_access_grants','TRUNCATE'),'service role cannot truncate grant audit');
SELECT ok(NOT has_column_privilege('authenticated','public.provider_pricing_access_grants','granted_at','INSERT'),'authenticated cannot forge grant timestamps');
SELECT ok(NOT has_column_privilege('authenticated','public.provider_pricing_access_grants','revoked_at','INSERT'),'authenticated cannot create pre-revoked grants');
SELECT ok(NOT has_table_privilege('authenticated','public.provider_cost_rates','DELETE'),'authenticated cannot hard-delete rates');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000001');

INSERT INTO public.provider_pricing_access_grants(organization_id,user_id,capability,granted_by) VALUES
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','market_cost.manage','e2100000-0000-0000-0000-000000000001'),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','market_cost.validate','e2100000-0000-0000-0000-000000000001'),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000001','pricing_rules.manage','e2100000-0000-0000-0000-000000000001'),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000002','market_cost.manage','e2100000-0000-0000-0000-000000000001'),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000003','market_cost.validate','e2100000-0000-0000-0000-000000000001'),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000004','market_cost.read','e2100000-0000-0000-0000-000000000001'),
 ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000006','pricing_rules.manage','e2100000-0000-0000-0000-000000000001');

SELECT throws_ok($$INSERT INTO public.provider_pricing_access_grants(organization_id,user_id,capability,granted_by) VALUES ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000002','market_cost.manage','e2100000-0000-0000-0000-000000000001')$$,'23505',NULL,'duplicate active capability is rejected');
SELECT throws_ok($$INSERT INTO public.provider_pricing_access_grants(organization_id,user_id,capability,granted_by) VALUES ('e2200000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000007','market_cost.read','e2100000-0000-0000-0000-000000000001')$$,'42501',NULL,'owner cannot grant capability in another tenant');
SELECT throws_ok($$INSERT INTO public.provider_pricing_access_grants(organization_id,user_id,capability,granted_by) VALUES ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000008','market_cost.read','e2100000-0000-0000-0000-000000000001')$$,'42501',NULL,'inactive member cannot receive a capability');
SELECT throws_ok($$INSERT INTO public.provider_pricing_access_grants(organization_id,user_id,capability,granted_by) VALUES ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000002','unknown.capability','e2100000-0000-0000-0000-000000000001')$$,'23514',NULL,'unknown capability is rejected');
SELECT is((SELECT count(*) FROM public.provider_pricing_access_grants WHERE organization_id='e2200000-0000-0000-0000-000000000001' AND revoked_at IS NULL),7::bigint,'owner sees all active tenant grants');

INSERT INTO public.provider_cost_settings(organization_id,default_usd_pen_rate,fx_source,fx_date,updated_by)
 VALUES ('e2200000-0000-0000-0000-000000000001',3.75,'manual',current_date,'e2100000-0000-0000-0000-000000000001');
INSERT INTO public.provider_cost_suppliers(id,organization_id,display_name)
 VALUES ('e2300000-0000-0000-0000-000000000001','e2200000-0000-0000-0000-000000000001','Synthetic supplier');
INSERT INTO public.provider_cost_items(id,organization_id,code,name,category_code,default_unit_code)
 VALUES ('e2400000-0000-0000-0000-000000000001','e2200000-0000-0000-0000-000000000001','E21-ITEM-01','Synthetic material','MATERIAL','UND');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000002');
SELECT lives_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,supplier_id,unit_code,currency_code,unit_cost_original,fx_source,tax_treatment,source_type,valid_from,status) VALUES ('e2200000-0000-0000-0000-000000000001','e2400000-0000-0000-0000-000000000001','e2300000-0000-0000-0000-000000000001','UND','USD',100,'organization_default','unknown','supplier_quote',current_date,'pending_review')$$,'market_cost.manage can create a pending rate');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000005');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'member without capability cannot read rates');
SELECT is((SELECT count(*) FROM public.provider_cost_suppliers WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'member without capability cannot read suppliers');
SELECT is((SELECT count(*) FROM public.provider_pricing_access_grants WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'member without grant sees no other users grants');
SELECT throws_ok($$INSERT INTO public.provider_cost_suppliers(organization_id,display_name) VALUES ('e2200000-0000-0000-0000-000000000001','Forbidden supplier')$$,'42501',NULL,'member without market_cost.manage cannot create supplier');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),1::bigint,'logistics can read rates through manage capability');
SELECT throws_ok($$UPDATE public.provider_cost_rates SET status='approved' WHERE organization_id='e2200000-0000-0000-0000-000000000001'$$,'P0001',NULL,'market_cost.manage cannot approve a cost rate');
SELECT lives_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,unit_code,currency_code,unit_cost_original,fx_rate_to_pen,fx_source,fx_date,tax_treatment,source_type,valid_from,status) VALUES ('e2200000-0000-0000-0000-000000000001','e2400000-0000-0000-0000-000000000001','UND','PEN',15,1,'not_required',NULL,'unknown','manual',current_date,'draft')$$,'logistics can register an internal draft');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),2::bigint,'validator can read acquisition costs');
SELECT throws_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,unit_code,currency_code,unit_cost_original,fx_rate_to_pen,fx_source,fx_date,tax_treatment,source_type,valid_from,status) VALUES ('e2200000-0000-0000-0000-000000000001','e2400000-0000-0000-0000-000000000001','UND','PEN',16,1,'not_required',NULL,'unknown','manual',current_date,'draft')$$,'P0001',NULL,'validator cannot create cost rates');
UPDATE public.provider_cost_rates SET status='approved',review_note='Validated by separate user'
 WHERE organization_id='e2200000-0000-0000-0000-000000000001' AND created_by='e2100000-0000-0000-0000-000000000002' AND status='pending_review';
SELECT is((SELECT status FROM public.provider_cost_rates WHERE created_by='e2100000-0000-0000-0000-000000000002' AND status='approved'),'approved','validator approves another users rate');
SELECT is((SELECT reviewed_by FROM public.provider_cost_rates WHERE created_by='e2100000-0000-0000-0000-000000000002' AND status='approved'),'e2100000-0000-0000-0000-000000000003'::uuid,'reviewer identity is recorded');
SELECT throws_ok($$UPDATE public.provider_cost_rates SET unit_cost_original=999 WHERE created_by='e2100000-0000-0000-0000-000000000002' AND status='approved'$$,'P0001',NULL,'approved acquisition cost remains immutable');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),2::bigint,'market_cost.read grants read-only access');
SELECT throws_ok($$INSERT INTO public.provider_cost_suppliers(organization_id,display_name) VALUES ('e2200000-0000-0000-0000-000000000001','Viewer forbidden')$$,'42501',NULL,'market_cost.read cannot create suppliers');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000006');
UPDATE public.provider_cost_settings SET default_usd_pen_rate=3.80,updated_by='e2100000-0000-0000-0000-000000000006'
 WHERE organization_id='e2200000-0000-0000-0000-000000000001';
SELECT is((SELECT default_usd_pen_rate FROM public.provider_cost_settings WHERE organization_id='e2200000-0000-0000-0000-000000000001'),3.80::numeric,'pricing_rules.manage can update FX settings');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'pricing_rules.manage alone does not expose market costs');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000001');
SELECT throws_ok($$UPDATE public.provider_pricing_access_grants SET capability='market_cost.manage' WHERE user_id='e2100000-0000-0000-0000-000000000004' AND capability='market_cost.read'$$,'42501',NULL,'grant identity cannot be edited by API');
UPDATE public.provider_pricing_access_grants SET revoked_at=now(),revoked_by='e2100000-0000-0000-0000-000000000001',revocation_reason='Access review'
 WHERE organization_id='e2200000-0000-0000-0000-000000000001' AND user_id='e2100000-0000-0000-0000-000000000004' AND capability='market_cost.read' AND revoked_at IS NULL;
SELECT is((SELECT count(*) FROM public.provider_pricing_access_grants WHERE user_id='e2100000-0000-0000-0000-000000000004' AND capability='market_cost.read' AND revoked_at IS NULL),0::bigint,'owner can revoke a capability');
UPDATE public.provider_pricing_access_grants SET revoked_at=NULL,revoked_by=NULL WHERE user_id='e2100000-0000-0000-0000-000000000004' AND capability='market_cost.read';
SELECT is((SELECT count(*) FROM public.provider_pricing_access_grants WHERE user_id='e2100000-0000-0000-0000-000000000004' AND capability='market_cost.read' AND revoked_at IS NULL),0::bigint,'revoked grants cannot be reactivated');
SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000002');
SELECT throws_ok($$INSERT INTO public.provider_pricing_access_grants(organization_id,user_id,capability,granted_by) VALUES ('e2200000-0000-0000-0000-000000000001','e2100000-0000-0000-0000-000000000002','market_cost.validate','e2100000-0000-0000-0000-000000000002')$$,'42501',NULL,'non-admin cannot grant capabilities');

-- A previously granted capability must not outlive active organization membership.
RESET ROLE;
UPDATE public.organization_members SET is_active=false
 WHERE organization_id='e2200000-0000-0000-0000-000000000001'
  AND user_id='e2100000-0000-0000-0000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'deactivated logistics member cannot read rates despite a retained grant');
SELECT is((SELECT count(*) FROM public.provider_cost_suppliers WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'deactivated logistics member cannot read suppliers despite a retained grant');
SELECT throws_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,unit_code,currency_code,unit_cost_original,fx_rate_to_pen,fx_source,fx_date,tax_treatment,source_type,valid_from,status) VALUES ('e2200000-0000-0000-0000-000000000001','e2400000-0000-0000-0000-000000000001','UND','PEN',17,1,'not_required',NULL,'unknown','manual',current_date,'draft')$$,'P0001',NULL,'deactivated logistics member cannot insert rates despite a retained grant');
SELECT throws_ok($$INSERT INTO public.provider_cost_suppliers(organization_id,display_name) VALUES ('e2200000-0000-0000-0000-000000000001','Inactive member supplier')$$,'42501',NULL,'deactivated logistics member cannot insert suppliers despite a retained grant');



SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'revoked market_cost.read no longer exposes rates');
SELECT is((SELECT count(*) FROM public.provider_pricing_access_grants WHERE user_id='e2100000-0000-0000-0000-000000000004'),1::bigint,'member can still see own revoked grant audit');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000007');
SELECT is((SELECT count(*) FROM public.provider_cost_rates WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'other tenant cannot read ROMAX costs');
SELECT is((SELECT count(*) FROM public.provider_cost_suppliers WHERE organization_id='e2200000-0000-0000-0000-000000000001'),0::bigint,'other tenant cannot read ROMAX suppliers');

SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000007');
INSERT INTO public.provider_pricing_access_grants(organization_id,user_id,capability,granted_by)
 VALUES ('e2200000-0000-0000-0000-000000000002','e2100000-0000-0000-0000-000000000007','pricing_rules.manage','e2100000-0000-0000-0000-000000000007');
RESET ROLE;
UPDATE public.organization_members SET is_active=false
 WHERE organization_id='e2200000-0000-0000-0000-000000000002'
  AND user_id='e2100000-0000-0000-0000-000000000007';
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e2100000-0000-0000-0000-000000000007');
SELECT throws_ok($$INSERT INTO public.provider_cost_settings(organization_id,default_usd_pen_rate,fx_source,fx_date,updated_by) VALUES ('e2200000-0000-0000-0000-000000000002',3.75,'manual',current_date,'e2100000-0000-0000-0000-000000000007')$$,'42501',NULL,'deactivated member cannot insert FX settings despite a retained grant');

SELECT * FROM finish();
ROLLBACK;
