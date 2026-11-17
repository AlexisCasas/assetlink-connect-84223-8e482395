-- R2A catalog migrations QA. LOCAL/DISPOSABLE DATABASE ONLY.
-- Requires migrations 20261117130000, 20261117130100 and 20261117130200.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(21);
CREATE FUNCTION pg_temp.as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claim.sub',coalesce(p_id::text,''),true);
$$;

INSERT INTO auth.users(id,email) VALUES
 ('b2100000-0000-0000-0000-000000000001','r2a-owner@test.invalid'),
 ('b2100000-0000-0000-0000-000000000002','r2a-outsider@test.invalid'),
 ('b2100000-0000-0000-0000-000000000003','r2a-viewer@test.invalid');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('b2200000-0000-0000-0000-000000000001','R2A ROMAX A','provider_company'),
 ('b2200000-0000-0000-0000-000000000002','R2A Provider B','provider_company');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES
 ('b2200000-0000-0000-0000-000000000001','b2100000-0000-0000-0000-000000000001','owner',true),
 ('b2200000-0000-0000-0000-000000000001','b2100000-0000-0000-0000-000000000003','viewer',true),
 ('b2200000-0000-0000-0000-000000000002','b2100000-0000-0000-0000-000000000002','owner',true);

SELECT has_table('public','provider_cost_categories','categories exist');
SELECT has_table('public','provider_cost_units','units exist');
SELECT has_table('public','provider_cost_suppliers','suppliers exist');
SELECT has_table('public','provider_cost_items','items exist');
SELECT has_table('public','provider_cost_rates','rates exist');
SELECT has_table('public','provider_cost_settings','settings exist');
SELECT ok(NOT has_table_privilege('anon','public.provider_cost_rates','SELECT'),'anon cannot read rates');
SELECT ok(NOT has_table_privilege('authenticated','public.provider_cost_rates','DELETE'),'no hard delete from app');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b2100000-0000-0000-0000-000000000001');
INSERT INTO public.provider_cost_settings(organization_id,default_usd_pen_rate,fx_source,fx_date)
 VALUES ('b2200000-0000-0000-0000-000000000001',3.75,'manual',current_date);
INSERT INTO public.provider_cost_suppliers(id,organization_id,display_name)
 VALUES ('b2300000-0000-0000-0000-000000000001','b2200000-0000-0000-0000-000000000001','Proveedor A','b2100000-0000-0000-0000-000000000001'),
        ('b2300000-0000-0000-0000-000000000002','b2200000-0000-0000-0000-000000000001','Proveedor B','b2100000-0000-0000-0000-000000000001');
INSERT INTO public.provider_cost_items(id,organization_id,code,name,category_code,default_unit_code)
 VALUES ('b2400000-0000-0000-0000-000000000001','b2200000-0000-0000-0000-000000000001','MAT-001','Cable NH-80','MATERIAL','M','b2100000-0000-0000-0000-000000000001');
SELECT lives_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,supplier_id,unit_code,currency_code,unit_cost_original,fx_rate_to_pen,fx_source,fx_date,tax_treatment,source_type,valid_from,status)
 VALUES ('b2200000-0000-0000-0000-000000000001','b2400000-0000-0000-0000-000000000001','b2300000-0000-0000-0000-000000000001','M','USD',100,3.75,'manual',current_date,'unknown','supplier_quote',current_date ,'pending_review')$$,'owner can register sourced USD rate');
SELECT is((SELECT unit_cost_pen FROM public.provider_cost_rates WHERE supplier_id='b2300000-0000-0000-0000-000000000001'),375.00::numeric,'PEN snapshot generated');
SELECT is((SELECT version_number FROM public.provider_cost_rates WHERE supplier_id='b2300000-0000-0000-0000-000000000001'),1,'first version auto-numbered');
SELECT lives_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,supplier_id,unit_code,currency_code,unit_cost_original,fx_rate_to_pen,fx_source,fx_date,tax_treatment,source_type,valid_from,status,created_by)
 VALUES ('b2200000-0000-0000-0000-000000000001','b2400000-0000-0000-0000-000000000001','b2300000-0000-0000-0000-000000000002','M','PEN',9.2,1,'not_required',NULL,'unknown','manual',current_date ,'draft')$$,'same item accepts another supplier');
SELECT throws_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,supplier_id,unit_code,currency_code,unit_cost_original,fx_rate_to_pen,fx_source,fx_date,tax_treatment,source_type,valid_from,status,created_by)
 VALUES ('b2200000-0000-0000-0000-000000000001','b2400000-0000-0000-0000-000000000001','b2300000-0000-0000-0000-000000000002','M','USD',10,3.75,'manual',NULL,'unknown','manual',current_date,'draft','b2100000-0000-0000-0000-000000000001')$$,'23514',NULL,'USD requires dated FX snapshot');
UPDATE public.provider_cost_rates SET status='approved' WHERE supplier_id='b2300000-0000-0000-0000-000000000001';
SELECT is((SELECT status FROM public.provider_cost_rates WHERE supplier_id='b2300000-0000-0000-0000-000000000001'),'approved','owner can approve own rate');
SELECT is((SELECT reviewed_by FROM public.provider_cost_rates WHERE supplier_id='b2300000-0000-0000-0000-000000000001'),'b2100000-0000-0000-0000-000000000001'::uuid,'reviewer recorded');
SELECT throws_ok($$UPDATE public.provider_cost_rates SET unit_cost_original=110 WHERE supplier_id='b2300000-0000-0000-0000-000000000001'$$,'P0001',NULL,'approved price is immutable');
UPDATE public.provider_cost_rates SET valid_until=current_date WHERE supplier_id='b2300000-0000-0000-0000-000000000001';
SELECT lives_ok($$INSERT INTO public.provider_cost_rates(organization_id,cost_item_id,supplier_id,unit_code,currency_code,unit_cost_original,fx_rate_to_pen,fx_source,fx_date,tax_treatment,source_type,valid_from,status,created_by)
 VALUES ('b2200000-0000-0000-0000-000000000001','b2400000-0000-0000-0000-000000000001','b2300000-0000-0000-0000-000000000001','M','PEN',9.1,1,'not_required',NULL,'unknown','supplier_quote',current_date+1 ,'pending_review')$$,'new version after validity closure');
SELECT is((SELECT max(version_number) FROM public.provider_cost_rates WHERE supplier_id='b2300000-0000-0000-0000-000000000001'),2,'second version numbered');
SELECT pg_temp.as_user('b2100000-0000-0000-0000-000000000003');
SELECT is((SELECT count(*) FROM public.provider_cost_rates),2::bigint,'same-tenant viewer can read rates');
SELECT throws_ok($$INSERT INTO public.provider_cost_items(organization_id,name,category_code,default_unit_code,created_by)
 VALUES ('b2200000-0000-0000-0000-000000000001','Forbidden','MATERIAL','M','b2100000-0000-0000-0000-000000000003')$$,'42501',NULL,'viewer cannot create cost item');
SELECT pg_temp.as_user('b2100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.provider_cost_rates),0::bigint,'other tenant sees no rates');
SELECT * FROM finish();
ROLLBACK;
