-- R4-A.1 regression: isolated Supabase stack ONLY; all fixtures are rolled back.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(30);
CREATE FUNCTION pg_temp.r4a1_as_user(p_id uuid) RETURNS void LANGUAGE sql AS $$
  SELECT pg_catalog.set_config('request.jwt.claim.sub',coalesce(p_id::text,''),true);
$$;
INSERT INTO auth.users(id,email) VALUES
 ('d6100000-0000-0000-0000-000000000001','romax-r4a1-owner@qa.invalid'),
 ('d6100000-0000-0000-0000-000000000002','romax-r4a1-viewer@qa.invalid'),
 ('d6100000-0000-0000-0000-000000000003','romax-r4a1-other@qa.invalid');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('d6200000-0000-0000-0000-0000000000a1','R4A1 provider A','provider_company'),
 ('d6200000-0000-0000-0000-0000000000b1','R4A1 provider B','provider_company');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES
 ('d6200000-0000-0000-0000-0000000000a1','d6100000-0000-0000-0000-000000000001','owner',true),
 ('d6200000-0000-0000-0000-0000000000a1','d6100000-0000-0000-0000-000000000002','viewer',true),
 ('d6200000-0000-0000-0000-0000000000b1','d6100000-0000-0000-0000-000000000003','owner',true);

SELECT ok(to_regprocedure('public.romax_save_opportunity_analysis_v2(uuid,text,text,jsonb,jsonb,jsonb,jsonb)') IS NOT NULL,'v2 RPC exists');
SELECT ok(NOT has_function_privilege('anon','public.romax_save_opportunity_analysis_v2(uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE'),'anon cannot call v2');
SELECT ok(has_function_privilege('authenticated','public.romax_save_opportunity_analysis_v2(uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE'),'authenticated can call v2');
SELECT ok((SELECT NOT prosecdef FROM pg_proc WHERE oid='public.romax_save_opportunity_analysis_v2(uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure),'v2 is security invoker');

CREATE FUNCTION pg_temp.save_r4a1(p_scope text, p_items jsonb, p_considerations jsonb DEFAULT '[]'::jsonb)
RETURNS TABLE(analysis_id uuid,version_number integer,created_new boolean)
LANGUAGE sql SECURITY INVOKER AS $fn$
 SELECT * FROM public.romax_save_opportunity_analysis_v2(
   'd6300000-0000-0000-0000-000000000001'::uuid,
   'Instalación de ventiladores',p_scope,
   '["Confirmar medidas"]'::jsonb,p_considerations,'["Acceso"]'::jsonb,p_items
 );
$fn$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.r4a1_as_user('d6100000-0000-0000-0000-000000000001');
INSERT INTO public.romax_opportunities(id,organization_id,subject,source_system)
VALUES ('d6300000-0000-0000-0000-000000000001','d6200000-0000-0000-0000-0000000000a1','R4A1 idempotency QA','manual');


SELECT lives_ok($save$
  SELECT * FROM pg_temp.save_r4a1('Montaje de dos equipos',
    '[{"item_type":"equipment","description":"Ventilador","quantity":2,"unit_code":"UND"},
      {"item_type":"labor","description":"Técnico","quantity":2,"unit_code":"JORNADA"}]'::jsonb)
$save$,'first save creates analysis');
SELECT is((SELECT max(version_number) FROM public.romax_opportunity_analyses),1,'first version is 1');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analysis_items),2::bigint,'first version contains two items');
SELECT is((SELECT status FROM public.romax_opportunities WHERE id='d6300000-0000-0000-0000-000000000001'),'in_analysis','first save advances opportunity to in_analysis');
SELECT is((SELECT created_new FROM pg_temp.save_r4a1('Montaje de dos equipos',
  '[{"item_type":"equipment","description":"Ventilador","quantity":2,"unit_code":"UND"},
    {"item_type":"labor","description":"Técnico","quantity":2,"unit_code":"JORNADA"}]'::jsonb)),false,'identical save returns created_new=false');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),1::bigint,'identical save leaves only V1');
SELECT is((SELECT created_new FROM pg_temp.save_r4a1('  Montaje de dos equipos  ',
  '[{"item_type":"labor","description":" Técnico ","quantity":2,"unit_code":"JORNADA"},
    {"item_type":"equipment","description":"Ventilador","quantity":2,"unit_code":"UND"}]'::jsonb)),false,'order and whitespace cannot create a duplicate');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),1::bigint,'canonical no-op still has only V1');

SELECT lives_ok($save$
  SELECT * FROM pg_temp.save_r4a1('Montaje actualizado',
    '[{"item_type":"equipment","description":"Ventilador","quantity":2,"unit_code":"UND"},
      {"item_type":"labor","description":"Técnico","quantity":3,"unit_code":"JORNADA"}]'::jsonb)
$save$,'material change creates V2');
SELECT is((SELECT max(version_number) FROM public.romax_opportunity_analyses),2,'changed version numbered 2');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses WHERE status='superseded'),1::bigint,'old V1 superseded');
SELECT is((SELECT scope_of_work FROM public.romax_opportunity_analyses WHERE version_number=1),'Montaje de dos equipos','old scope remains unchanged');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analysis_items i JOIN public.romax_opportunity_analyses a ON a.id=i.analysis_id WHERE a.version_number=1),2::bigint,'old line items retained');
SELECT is((SELECT quantity FROM public.romax_opportunity_analysis_items i JOIN public.romax_opportunity_analyses a ON a.id=i.analysis_id WHERE a.version_number=1 AND i.item_type='labor'),2::numeric,'old quantity remains 2');
SELECT is((SELECT quantity FROM public.romax_opportunity_analysis_items i JOIN public.romax_opportunity_analyses a ON a.id=i.analysis_id WHERE a.version_number=2 AND i.item_type='labor'),3::numeric,'new quantity is 3');
SELECT is((SELECT created_new FROM pg_temp.save_r4a1('Montaje actualizado',
  '[{"item_type":"equipment","description":"Ventilador","quantity":2,"unit_code":"UND"},
    {"item_type":"labor","description":"Técnico","quantity":3,"unit_code":"JORNADA"}]'::jsonb)),false,'V2 repeated save returns existing version');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),2::bigint,'V2 no-op does not create V3');
SELECT throws_ok($bad$
 SELECT * FROM pg_temp.save_r4a1('Montaje actualizado',
 '[{"item_type":"equipment","description":"Ventilador","quantity":-1,"unit_code":"UND"}]'::jsonb)
$bad$,'23514',NULL,'invalid quantity rolls back new version');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),2::bigint,'failed save leaves two versions');

UPDATE public.romax_opportunities SET status='quoted' WHERE id='d6300000-0000-0000-0000-000000000001';
SELECT is((SELECT created_new FROM pg_temp.save_r4a1('Nuevo alcance tras cotización',
  '[{"item_type":"equipment","description":"Ventilador","quantity":2,"unit_code":"UND"}]'::jsonb)),true,'changed content can version even after quote');
SELECT is((SELECT status FROM public.romax_opportunities WHERE id='d6300000-0000-0000-0000-000000000001'),'quoted','save never regresses a quoted opportunity');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),3::bigint,'only content change generated V3');

SELECT pg_temp.r4a1_as_user('d6100000-0000-0000-0000-000000000002');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),0::bigint,'viewer cannot see analysis history');
SELECT throws_ok($denied$ SELECT * FROM pg_temp.save_r4a1('Denied','[]'::jsonb) $denied$,'42501',NULL,'viewer cannot call v2 on tenant');
SELECT pg_temp.r4a1_as_user('d6100000-0000-0000-0000-000000000003');
SELECT throws_ok($denied$ SELECT * FROM pg_temp.save_r4a1('Denied','[]'::jsonb) $denied$,'42501',NULL,'other tenant cannot call v2');
SELECT is((SELECT count(*) FROM public.romax_opportunity_analyses),0::bigint,'other tenant cannot read history');

SELECT * FROM finish();
ROLLBACK;
