-- Umbrales de criticidad configurables (20260925120000_criticality_configurable_thresholds.sql).
-- Se ejecuta con: supabase test db --local
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(144);

-- -------------------------------------------------------------------------
-- Fixture
-- -------------------------------------------------------------------------
INSERT INTO auth.users (id, email)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'owner-a@test.local'),
  ('10000000-0000-0000-0000-000000000002', 'viewer-a@test.local'),
  ('10000000-0000-0000-0000-000000000003', 'technician-a@test.local'),
  ('10000000-0000-0000-0000-000000000004', 'owner-b@test.local'),
  ('10000000-0000-0000-0000-000000000005', 'platform@test.local'),
  ('10000000-0000-0000-0000-000000000006', 'manager-a@test.local'),
  ('10000000-0000-0000-0000-000000000007', 'admin-a@test.local'),
  ('10000000-0000-0000-0000-000000000008', 'requester-a@test.local');

INSERT INTO public.organizations (id, name, organization_type)
VALUES
  ('20000000-0000-0000-0000-000000000001', 'Cliente A', 'client_company'),
  ('20000000-0000-0000-0000-000000000002', 'Cliente B', 'client_company'),
  ('20000000-0000-0000-0000-000000000003', 'Plataforma', 'platform_admin');

INSERT INTO public.organization_members (organization_id, user_id, role)
VALUES
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'viewer'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'technician'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000004', 'owner'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000005', 'owner'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000006', 'manager'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000007', 'admin'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000008', 'requester');

INSERT INTO public.assets (id, organization_id, code, name)
VALUES
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'A-1', 'Equipo A1'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'A-2', 'Equipo A2'),
  ('40000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', 'B-1', 'Equipo B1');

-- Un solo parámetro con peso 100: score == puntaje de la opción elegida, lo
-- que permite probar cada límite con exactitud.
CREATE TEMP TABLE test_matrix AS
SELECT jsonb_build_object('parameters', jsonb_build_array(jsonb_build_object(
  'code', 'P1', 'name', 'Parámetro único', 'weight', 100, 'sequence', 1, 'is_active', true,
  'options', jsonb_build_array(
    jsonb_build_object('code', 's0',     'label', 'cero',   'score', 0,     'sequence', 1),
    jsonb_build_object('code', 's0_99',  'label', '0.99',   'score', 0.99,  'sequence', 2),
    jsonb_build_object('code', 's1',     'label', '1',      'score', 1,     'sequence', 3),
    jsonb_build_object('code', 's1_99',  'label', '1.99',   'score', 1.99,  'sequence', 4),
    jsonb_build_object('code', 's2',     'label', '2',      'score', 2,     'sequence', 5),
    jsonb_build_object('code', 's2_99',  'label', '2.99',   'score', 2.99,  'sequence', 6),
    jsonb_build_object('code', 's3',     'label', '3',      'score', 3,     'sequence', 7),
    jsonb_build_object('code', 's24_99', 'label', '24.99',  'score', 24.99, 'sequence', 8),
    jsonb_build_object('code', 's25',    'label', '25',     'score', 25,    'sequence', 9),
    jsonb_build_object('code', 's49_99', 'label', '49.99',  'score', 49.99, 'sequence', 10),
    jsonb_build_object('code', 's50',    'label', '50',     'score', 50,    'sequence', 11),
    jsonb_build_object('code', 's74_99', 'label', '74.99',  'score', 74.99, 'sequence', 12),
    jsonb_build_object('code', 's75',    'label', '75',     'score', 75,    'sequence', 13),
    jsonb_build_object('code', 's100',   'label', '100',    'score', 100,   'sequence', 14)
  )
))) AS payload;
GRANT SELECT ON test_matrix TO authenticated;

CREATE FUNCTION pg_temp.answers(p_org uuid, p_code text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_array(jsonb_build_object('parameter_id', cp.id, 'option_id', cpo.id))
  FROM public.criticality_parameters cp
  JOIN public.criticality_parameter_options cpo ON cpo.parameter_id = cp.id AND cpo.is_active
  WHERE cp.organization_id = p_org AND cp.is_active AND cpo.code = p_code;
$$;

CREATE FUNCTION pg_temp.preview(p_org uuid, p_asset uuid, p_code text)
RETURNS TABLE (valid boolean, score numeric, calculated_criticality text) LANGUAGE sql AS $$
  SELECT p.valid, p.score, p.calculated_criticality
  FROM public.preview_bulk_asset_criticality(p_org, jsonb_build_array(jsonb_build_object(
    'row_number', 1, 'asset_id', p_asset, 'answers', pg_temp.answers(p_org, p_code)
  ))) AS p;
$$;

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;

CREATE FUNCTION pg_temp.thresholds(p_org uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'm', (public.get_criticality_thresholds(p_org)->>'medium_min')::numeric,
    'h', (public.get_criticality_thresholds(p_org)->>'high_min')::numeric,
    'c', (public.get_criticality_thresholds(p_org)->>'critical_min')::numeric
  );
$$;

-- Forma comparable de la matriz ACTIVA de una organización (sin ids).
CREATE FUNCTION pg_temp.matrix_shape(p_org uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'code', cp.code, 'name', cp.name, 'description', cp.description, 'weight', cp.weight,
    'sequence', cp.sequence,
    'options', (
      SELECT jsonb_agg(jsonb_build_object('code', cpo.code, 'label', cpo.label, 'score', cpo.score, 'sequence', cpo.sequence)
                       ORDER BY cpo.sequence, cpo.code)
      FROM public.criticality_parameter_options cpo
      WHERE cpo.parameter_id = cp.id AND cpo.is_active
    )
  ) ORDER BY cp.sequence, cp.code), '[]'::jsonb)
  FROM public.criticality_parameters cp
  WHERE cp.organization_id = p_org AND cp.is_active;
$$;

SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
SELECT public.replace_criticality_matrix('20000000-0000-0000-0000-000000000001', (SELECT payload FROM test_matrix));
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT public.replace_criticality_matrix('20000000-0000-0000-0000-000000000002', (SELECT payload FROM test_matrix));

-- -------------------------------------------------------------------------
-- 1. Estructura, RLS y privilegios
-- -------------------------------------------------------------------------
SELECT has_table('public', 'criticality_thresholds', 'criticality_thresholds exists');
SELECT has_column('public', 'asset_criticality_assessments', 'threshold_medium_min', 'assessment snapshot: threshold_medium_min');
SELECT has_column('public', 'asset_criticality_assessments', 'threshold_high_min', 'assessment snapshot: threshold_high_min');
SELECT has_column('public', 'asset_criticality_assessments', 'threshold_critical_min', 'assessment snapshot: threshold_critical_min');
SELECT col_not_null('public', 'asset_criticality_assessments', 'threshold_medium_min', 'assessment snapshot columns are NOT NULL');
SELECT has_column('public', 'criticality_matrix_templates', 'medium_min', 'templates can carry thresholds');
SELECT ok((SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = 'public.criticality_thresholds'::regclass), 'RLS enabled on criticality_thresholds');
SELECT is(
  (SELECT array_agg(p.cmd::text) FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = 'criticality_thresholds'),
  ARRAY['SELECT'],
  'criticality_thresholds only has a SELECT policy'
);
SELECT table_privs_are('public', 'criticality_thresholds', 'authenticated', ARRAY['SELECT'], 'authenticated can only SELECT criticality_thresholds');
SELECT table_privs_are('public', 'criticality_thresholds', 'anon', ARRAY[]::text[], 'anon has no privilege on criticality_thresholds');
SELECT ok(has_function_privilege('authenticated', 'public.get_criticality_thresholds(uuid)', 'EXECUTE'), 'authenticated can execute get_criticality_thresholds');
SELECT ok(has_function_privilege('authenticated', 'public.set_criticality_thresholds(uuid, numeric, numeric, numeric)', 'EXECUTE'), 'authenticated can execute set_criticality_thresholds');
SELECT ok(has_function_privilege('authenticated', 'public.replace_criticality_configuration(uuid, jsonb, jsonb)', 'EXECUTE'), 'authenticated can execute replace_criticality_configuration');
SELECT ok(has_function_privilege('authenticated', 'public.get_asset_criticality_assessments(uuid)', 'EXECUTE'), 'recreated get_asset_criticality_assessments keeps EXECUTE for authenticated');
SELECT ok(NOT has_function_privilege('anon', 'public.get_criticality_thresholds(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.set_criticality_thresholds(uuid, numeric, numeric, numeric)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.replace_criticality_configuration(uuid, jsonb, jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.get_asset_criticality_assessments(uuid)', 'EXECUTE'),
  'anon cannot execute any public threshold RPC');
SELECT ok(NOT (
  has_function_privilege('authenticated', 'public.criticality_default_thresholds()', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.get_effective_criticality_thresholds(uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.classify_criticality_score(numeric, numeric, numeric, numeric)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.criticality_label_es(text)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.assert_valid_criticality_thresholds(numeric, numeric, numeric)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.criticality_thresholds_from_jsonb(jsonb)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.write_criticality_thresholds(uuid, numeric, numeric, numeric)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.criticality_unreachable_categories(numeric, numeric, numeric, numeric, numeric)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.criticality_active_score_range(uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.criticality_thresholds_payload(uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.validate_and_score_asset_criticality(uuid, jsonb, uuid)', 'EXECUTE')
), 'internal helpers are not executable by authenticated');

-- -------------------------------------------------------------------------
-- 2. Sin fila → 25/50/75 por defecto
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":25,"h":50,"c":75}'::jsonb, 'organization without row uses 25/50/75');
SELECT ok((public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->>'is_default')::boolean, 'no row → is_default = true');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.criticality_thresholds), 'migration does not insert threshold rows for existing organizations');

-- -------------------------------------------------------------------------
-- 3. Límites exactos con 25/50/75 (regresión del CASE fijo anterior)
-- -------------------------------------------------------------------------
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's24_99')), 'low', 'default: 24.99 → low');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's25')), 'medium', 'default: 25 → medium');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's49_99')), 'medium', 'default: 49.99 → medium');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's50')), 'high', 'default: 50 → high');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's74_99')), 'high', 'default: 74.99 → high');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's75')), 'critical', 'default: 75 → critical');
SELECT is((SELECT score FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's74_99')), 74.99::numeric, 'formula unchanged: weight 100 keeps the option score');

-- Evaluación real con los valores por defecto: snapshot 25/50/75.
SELECT lives_ok($$
  SELECT public.calculate_asset_criticality('40000000-0000-0000-0000-000000000001',
    pg_temp.answers('20000000-0000-0000-0000-000000000001', 's75'), 'default eval')
$$, 'calculate with default thresholds succeeds');
SELECT is(
  (SELECT jsonb_build_array(aca.calculated_criticality, aca.threshold_medium_min, aca.threshold_high_min, aca.threshold_critical_min)
     FROM public.asset_criticality_assessments aca WHERE aca.notes = 'default eval'),
  '["critical", 25, 50, 75]'::jsonb,
  'default evaluation stores critical + snapshot 25/50/75'
);

-- -------------------------------------------------------------------------
-- 4. Escala 1/2/3
-- -------------------------------------------------------------------------
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 3) $$, 'owner sets 1/2/3');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'get returns 1/2/3');
SELECT ok(NOT (public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->>'is_default')::boolean, '1/2/3 → is_default = false');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's0_99')), 'low', '1/2/3: 0.99 → low');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's1')), 'medium', '1/2/3: 1 → medium');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's1_99')), 'medium', '1/2/3: 1.99 → medium');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's2')), 'high', '1/2/3: 2 → high');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's2_99')), 'high', '1/2/3: 2.99 → high');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's3')), 'critical', '1/2/3: 3 → critical');

-- "Restablecer": fila explícita 25/50/75 también es is_default.
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 25, 50, 75) $$, 'reset writes explicit 25/50/75');
SELECT ok(EXISTS (SELECT 1 FROM public.criticality_thresholds WHERE organization_id = '20000000-0000-0000-0000-000000000001'), 'reset keeps a physical row');
SELECT ok((public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->>'is_default')::boolean, 'explicit 25/50/75 row → is_default = true');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 3) $$, 'back to 1/2/3');

-- -------------------------------------------------------------------------
-- 5. Validaciones
-- -------------------------------------------------------------------------
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', NULL, 50, 75) $$, '.*obligatorios.*', 'NULL threshold rejected');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', -1, 50, 75) $$, '.*mayores o iguales a 0.*', 'negative threshold rejected');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 25, 25, 75) $$, '.*estrictamente ascendentes.*', 'equal thresholds rejected');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 75, 50, 25) $$, '.*estrictamente ascendentes.*', 'descending thresholds rejected');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 25, 80, 75) $$, '.*estrictamente ascendentes.*', 'middle out of order rejected');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 25.001, 50, 75) $$, '.*2 decimales.*', 'more than 2 decimals rejected (no silent rounding)');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 100000000) $$, '.*menores a 100000000.*', 'out-of-range threshold rejected');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 'NaN') $$, '.*menores a 100000000.*', 'NaN threshold rejected');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'rejected writes leave previous thresholds intact');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 0, 1, 2) $$, 'medium_min = 0 is allowed');
SELECT ok((public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->'unreachable_categories') ? 'low', 'medium_min = 0 reports Baja (low) as unreachable');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 3) $$, 'restore 1/2/3');

-- -------------------------------------------------------------------------
-- 6. Permisos
-- -------------------------------------------------------------------------
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000002');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 5, 6, 7) $$, '.*Not authorized.*', 'viewer cannot set thresholds');
SELECT lives_ok($$ SELECT public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001') $$, 'viewer can read its tenant thresholds');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000003');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 5, 6, 7) $$, '.*Not authorized.*', 'technician cannot set thresholds');
SELECT lives_ok($$ SELECT public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001') $$, 'technician can read its tenant thresholds');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000008');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 5, 6, 7) $$, '.*Not authorized.*', 'requester cannot set thresholds');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT throws_matching($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 5, 6, 7) $$, '.*Not authorized.*', 'Client B owner cannot set Client A thresholds');
SELECT throws_matching($$ SELECT public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001') $$, '.*Not authorized.*', 'Client B owner cannot read Client A thresholds');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000006');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 3) $$, 'manager can set thresholds');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000007');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 3) $$, 'admin can set thresholds');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000005');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 3) $$, 'platform admin can set thresholds');
SELECT lives_ok($$ SELECT public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001') $$, 'platform admin can read thresholds');
SELECT ok(
  (SELECT ct.updated_by_user_id FROM public.criticality_thresholds ct WHERE ct.organization_id = '20000000-0000-0000-0000-000000000001')
    = '10000000-0000-0000-0000-000000000005'::uuid,
  'updated_by_user_id records the last writer'
);
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000002');
SELECT throws_matching($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM test_matrix), '{"medium_min":5,"high_min":6,"critical_min":7}') $$,
  '.*Not authorized.*', 'viewer cannot replace the configuration');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT throws_matching($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM test_matrix), '{"medium_min":5,"high_min":6,"critical_min":7}') $$,
  '.*Not authorized.*', 'Client B cannot replace Client A configuration');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'unauthorized attempts did not change thresholds');

-- -------------------------------------------------------------------------
-- 7. Aislamiento entre organizaciones
-- -------------------------------------------------------------------------
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 's2')), 'high', 'Client A (1/2/3): score 2 → high');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT is((SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003', 's2')), 'low', 'Client B (default): the same score 2 → low');
SELECT ok((public.get_criticality_thresholds('20000000-0000-0000-0000-000000000002')->>'is_default')::boolean, 'Client B still uses defaults');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');

-- -------------------------------------------------------------------------
-- 8. Snapshot inmutable ante cambios posteriores
-- -------------------------------------------------------------------------
SELECT lives_ok($$
  SELECT public.calculate_asset_criticality('40000000-0000-0000-0000-000000000001',
    pg_temp.answers('20000000-0000-0000-0000-000000000001', 's2'), 'custom eval')
$$, 'calculate with 1/2/3 succeeds');
CREATE TEMP TABLE custom_eval AS
  SELECT aca.id, aca.score, aca.calculated_criticality, aca.threshold_medium_min, aca.threshold_high_min, aca.threshold_critical_min
  FROM public.asset_criticality_assessments aca WHERE aca.notes = 'custom eval';
SELECT is(
  (SELECT jsonb_build_array(calculated_criticality, threshold_medium_min, threshold_high_min, threshold_critical_min) FROM custom_eval),
  '["high", 1, 2, 3]'::jsonb,
  'evaluation stores high + snapshot 1/2/3'
);
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 10, 20, 30) $$, 'thresholds change to 10/20/30');
SELECT is(
  (SELECT jsonb_build_array(aca.score, aca.calculated_criticality, aca.threshold_medium_min, aca.threshold_high_min, aca.threshold_critical_min)
     FROM public.asset_criticality_assessments aca WHERE aca.id = (SELECT id FROM custom_eval)),
  (SELECT jsonb_build_array(score, calculated_criticality, threshold_medium_min, threshold_high_min, threshold_critical_min) FROM custom_eval),
  'changing thresholds never rewrites a past evaluation'
);
SELECT is(
  (SELECT a.criticality FROM public.assets a WHERE a.id = '40000000-0000-0000-0000-000000000001'),
  'high',
  'changing thresholds never recalculates assets.criticality'
);
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 1, 2, 3) $$, 'back to 1/2/3');

-- -------------------------------------------------------------------------
-- 9. Paridad preview ↔ evaluación real y bulk
-- -------------------------------------------------------------------------
SELECT is(
  (SELECT jsonb_build_array(p.score, p.calculated_criticality) FROM pg_temp.preview('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002', 's2_99') p),
  (SELECT jsonb_build_array(r.score, r.calculated_criticality)
     FROM public.calculate_asset_criticality('40000000-0000-0000-0000-000000000002',
       pg_temp.answers('20000000-0000-0000-0000-000000000001', 's2_99'), 'parity eval') r),
  'single-row preview and calculate return the same score and class'
);
SELECT is(
  (SELECT public.bulk_calculate_asset_criticality('20000000-0000-0000-0000-000000000001', jsonb_build_array(
    jsonb_build_object('row_number', 2, 'asset_id', '40000000-0000-0000-0000-000000000001', 'answers', pg_temp.answers('20000000-0000-0000-0000-000000000001', 's2')),
    jsonb_build_object('row_number', 3, 'asset_id', '40000000-0000-0000-0000-000000000002', 'answers', pg_temp.answers('20000000-0000-0000-0000-000000000001', 's3'))
  ))->'counts'),
  '{"low":0,"medium":0,"high":1,"critical":1}'::jsonb,
  'bulk counts are classified with the configured thresholds'
);
SELECT is(
  (SELECT count(*) FROM public.asset_criticality_assessments aca
    WHERE aca.organization_id = '20000000-0000-0000-0000-000000000001' AND aca.threshold_critical_min = 3 AND aca.notes IS NULL),
  2::bigint,
  'bulk evaluations also store the 1/2/3 snapshot'
);

-- -------------------------------------------------------------------------
-- 10. Plantillas
-- -------------------------------------------------------------------------
SELECT lives_ok($$ SELECT public.create_template_from_current_matrix('20000000-0000-0000-0000-000000000001', 'Tpl A 123') $$, 'save template with custom thresholds');
SELECT is(
  (SELECT jsonb_build_array(cmt.medium_min, cmt.high_min, cmt.critical_min) FROM public.criticality_matrix_templates cmt WHERE cmt.name = 'Tpl A 123'),
  '[1, 2, 3]'::jsonb,
  'template stores the effective custom thresholds'
);
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.create_template_from_current_matrix('20000000-0000-0000-0000-000000000002', 'Tpl B default') $$, 'save template with default thresholds');
SELECT is(
  (SELECT jsonb_build_array(cmt.medium_min, cmt.high_min, cmt.critical_min) FROM public.criticality_matrix_templates cmt WHERE cmt.name = 'Tpl B default'),
  '[25, 50, 75]'::jsonb,
  'template of an organization on defaults stores explicit 25/50/75'
);
SELECT throws_matching($$
  SELECT public.apply_criticality_template('20000000-0000-0000-0000-000000000002',
    (SELECT cmt.id FROM public.criticality_matrix_templates cmt WHERE cmt.name = 'Tpl A 123'))
$$, '.*Not authorized to use this criticality template.*', 'Client B cannot apply a private template of Client A');
SELECT ok((public.get_criticality_thresholds('20000000-0000-0000-0000-000000000002')->>'is_default')::boolean, 'rejected foreign template leaves Client B thresholds untouched');

SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');
-- Plantilla legacy (sin umbrales), creada directamente como si viniera de V2.
INSERT INTO public.criticality_matrix_templates (id, organization_id, name, scope)
VALUES ('60000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Tpl legacy', 'organization');
INSERT INTO public.criticality_template_parameters (id, template_id, code, name, weight, sequence)
VALUES ('61000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'LEG', 'Legacy', 100, 1);
INSERT INTO public.criticality_template_options (template_parameter_id, code, label, score, sequence)
VALUES ('61000000-0000-0000-0000-000000000001', 'L0', 'Bajo', 0, 1), ('61000000-0000-0000-0000-000000000001', 'L4', 'Alto', 4, 2);

SELECT is(public.get_criticality_template('60000000-0000-0000-0000-000000000001')->'thresholds', 'null'::jsonb, 'legacy template exposes thresholds = null');
SELECT is((public.get_criticality_template('60000000-0000-0000-0000-000000000001')->>'max_possible_score')::numeric, 4::numeric, 'template preview exposes max possible score');
SELECT lives_ok($$ SELECT public.set_criticality_thresholds('20000000-0000-0000-0000-000000000001', 10, 20, 30) $$, 'Client A at 10/20/30 before applying the legacy template');
SELECT lives_ok($$ SELECT public.apply_criticality_template('20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001') $$, 'apply legacy template');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":10,"h":20,"c":30}'::jsonb, 'legacy template keeps current thresholds');
SELECT is((SELECT jsonb_agg(x->>'code') FROM jsonb_array_elements(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001')) x), '["LEG"]'::jsonb, 'legacy template matrix was applied');
SELECT ok((public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->'unreachable_categories') ? 'critical',
  'thresholds 10/20/30 with a 0–4 matrix report Muy Alta as unreachable');

SELECT is(
  public.get_criticality_template((SELECT cmt.id FROM public.criticality_matrix_templates cmt WHERE cmt.name = 'Tpl A 123'))->'thresholds',
  '{"medium_min":1,"high_min":2,"critical_min":3}'::jsonb,
  'template preview exposes its own thresholds'
);
SELECT lives_ok($$
  SELECT public.apply_criticality_template('20000000-0000-0000-0000-000000000001',
    (SELECT cmt.id FROM public.criticality_matrix_templates cmt WHERE cmt.name = 'Tpl A 123'))
$$, 'apply template with thresholds');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'template thresholds applied together with its matrix');
SELECT is((SELECT jsonb_agg(x->>'code') FROM jsonb_array_elements(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001')) x), '["P1"]'::jsonb, 'template matrix applied');

-- Plantilla con umbrales pero matriz inválida (parámetro activo sin
-- opciones): no cambia ni la matriz ni los umbrales.
INSERT INTO public.criticality_matrix_templates (id, organization_id, name, scope, medium_min, high_min, critical_min)
VALUES ('60000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'Tpl rota', 'organization', 7, 8, 9);
INSERT INTO public.criticality_template_parameters (template_id, code, name, weight, sequence)
VALUES ('60000000-0000-0000-0000-000000000002', 'ROTO', 'Sin opciones', 100, 1);
SELECT throws_matching($$ SELECT public.apply_criticality_template('20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000002') $$,
  '.*al menos una opción activa.*', 'template with an unanswerable parameter is rejected');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'failed template apply leaves thresholds unchanged');
SELECT is((SELECT jsonb_agg(x->>'code') FROM jsonb_array_elements(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001')) x), '["P1"]'::jsonb, 'failed template apply leaves the matrix unchanged');

-- -------------------------------------------------------------------------
-- 11. Operaciones de matriz que NO deben tocar umbrales
-- -------------------------------------------------------------------------
SELECT lives_ok($$ SELECT public.replace_criticality_matrix('20000000-0000-0000-0000-000000000001', (SELECT payload FROM test_matrix)) $$, 'replace_criticality_matrix keeps working with its original contract');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'replace_criticality_matrix does not touch thresholds');
SELECT lives_ok($$ SELECT public.clear_active_criticality_matrix('20000000-0000-0000-0000-000000000001') $$, 'clear active matrix');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'clear_active_criticality_matrix does not touch thresholds');
SELECT is(public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->'active_matrix'->'max_possible_score', 'null'::jsonb, 'no active matrix → no possible score range');
SELECT is(public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->'unreachable_categories', '[]'::jsonb, 'no active matrix → no unreachable warnings');
SELECT lives_ok($$ SELECT public.replace_criticality_matrix('20000000-0000-0000-0000-000000000001', (SELECT payload FROM test_matrix)) $$, 'restore Client A matrix');

-- -------------------------------------------------------------------------
-- 12. Historial con snapshot y permisos
-- -------------------------------------------------------------------------
SELECT is(
  (SELECT jsonb_build_array(h.threshold_medium_min, h.threshold_high_min, h.threshold_critical_min)
     FROM public.get_asset_criticality_assessments('40000000-0000-0000-0000-000000000001') h WHERE h.notes = 'custom eval'),
  '[1, 2, 3]'::jsonb,
  'history RPC returns the threshold snapshot'
);
SELECT is(
  (SELECT jsonb_build_array(h.threshold_medium_min, h.threshold_high_min, h.threshold_critical_min)
     FROM public.get_asset_criticality_assessments('40000000-0000-0000-0000-000000000001') h WHERE h.notes = 'default eval'),
  '[25, 50, 75]'::jsonb,
  'history RPC returns 25/50/75 for evaluations made with defaults'
);
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000002');
SELECT lives_ok($$ SELECT * FROM public.get_asset_criticality_assessments('40000000-0000-0000-0000-000000000001') $$, 'viewer can read its tenant history');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT throws_matching($$ SELECT * FROM public.get_asset_criticality_assessments('40000000-0000-0000-0000-000000000001') $$, '.*Not authorized.*', 'Client B cannot read Client A history');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');

-- -------------------------------------------------------------------------
-- 13. Rango de score posible
-- -------------------------------------------------------------------------
SELECT is(
  public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->'active_matrix',
  '{"parameter_count":1,"min_possible_score":0,"max_possible_score":100}'::jsonb,
  'score range of the active matrix'
);
SELECT is(public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->'unreachable_categories', '[]'::jsonb, '0–100 with 1/2/3: every category is reachable');

-- -------------------------------------------------------------------------
-- 14. Sin escritura directa; RLS de lectura
-- -------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT throws_matching($$ INSERT INTO public.criticality_thresholds (organization_id, medium_min, high_min, critical_min) VALUES ('20000000-0000-0000-0000-000000000002', 1, 2, 3) $$,
  '.*permission denied.*', 'authenticated cannot INSERT thresholds directly');
SELECT throws_matching($$ UPDATE public.criticality_thresholds SET critical_min = 99 $$, '.*permission denied.*', 'authenticated cannot UPDATE thresholds directly');
SELECT throws_matching($$ DELETE FROM public.criticality_thresholds $$, '.*permission denied.*', 'authenticated cannot DELETE thresholds directly');
SELECT is((SELECT count(*) FROM public.criticality_thresholds WHERE organization_id = '20000000-0000-0000-0000-000000000001'), 1::bigint, 'member sees its own thresholds row through RLS');
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT is((SELECT count(*) FROM public.criticality_thresholds WHERE organization_id = '20000000-0000-0000-0000-000000000001'), 0::bigint, 'Client B cannot see Client A thresholds row through RLS');
RESET ROLE;
SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000001');

-- -------------------------------------------------------------------------
-- 15. Eventos nuevos: español + umbrales en el payload
-- -------------------------------------------------------------------------
SELECT lives_ok($$
  SELECT public.calculate_asset_criticality('40000000-0000-0000-0000-000000000002',
    pg_temp.answers('20000000-0000-0000-0000-000000000001', 's3'), 'event eval')
$$, 'evaluation that produces critical');
SELECT is(
  (SELECT ae.description FROM public.asset_events ae
    WHERE ae.payload->>'assessment_id' = (SELECT aca.id::text FROM public.asset_criticality_assessments aca WHERE aca.notes = 'event eval')),
  'Criticidad evaluada: Muy Alta (score 3.00)',
  'new event description is in Spanish and shows critical as Muy Alta'
);
SELECT is(
  (SELECT ae.payload->'thresholds' FROM public.asset_events ae
    WHERE ae.payload->>'assessment_id' = (SELECT aca.id::text FROM public.asset_criticality_assessments aca WHERE aca.notes = 'event eval')),
  '{"medium_min":1,"high_min":2,"critical_min":3}'::jsonb,
  'new event payload includes the thresholds used'
);
SELECT is(
  (SELECT ae.payload->>'calculated_criticality' FROM public.asset_events ae
    WHERE ae.payload->>'assessment_id' = (SELECT aca.id::text FROM public.asset_criticality_assessments aca WHERE aca.notes = 'event eval')),
  'critical',
  'event payload keeps the internal enum'
);
SELECT is(
  (SELECT ae.description FROM public.asset_events ae
    WHERE ae.payload->>'assessment_id' = (SELECT aca.id::text FROM public.asset_criticality_assessments aca WHERE aca.notes = 'custom eval')),
  'Criticidad evaluada: Alta (score 2.00)',
  'high is described as Alta'
);

-- -------------------------------------------------------------------------
-- 16. Excel de configuración: replace_criticality_configuration
-- -------------------------------------------------------------------------
CREATE TEMP TABLE excel_matrix_v2 AS
SELECT jsonb_build_object('parameters', jsonb_build_array(jsonb_build_object(
  'code', 'P2', 'name', 'Parámetro Excel', 'weight', 100, 'sequence', 1, 'is_active', true,
  'options', jsonb_build_array(
    jsonb_build_object('code', 'x0', 'label', 'Nada', 'score', 0, 'sequence', 1),
    jsonb_build_object('code', 'x4', 'label', 'Máximo', 'score', 4, 'sequence', 2)
  )
))) AS payload;
GRANT SELECT ON excel_matrix_v2 TO authenticated;

-- Excel legacy (sin hoja Configuración) → p_thresholds NULL.
SELECT lives_ok($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM excel_matrix_v2), NULL) $$, 'legacy Excel import (no thresholds) succeeds');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":1,"h":2,"c":3}'::jsonb, 'legacy Excel import keeps current thresholds');
SELECT is((SELECT jsonb_agg(x->>'code') FROM jsonb_array_elements(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001')) x), '["P2"]'::jsonb, 'legacy Excel import replaced the matrix');

-- Excel nuevo: matriz + umbrales.
SELECT lives_ok($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM test_matrix), '{"medium_min":5,"high_min":10,"critical_min":15}') $$, 'new Excel import (matrix + thresholds) succeeds');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":5,"h":10,"c":15}'::jsonb, 'new Excel import applies thresholds');
SELECT is((SELECT jsonb_agg(x->>'code') FROM jsonb_array_elements(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001')) x), '["P1"]'::jsonb, 'new Excel import applies the matrix');
SELECT is(
  (public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM test_matrix), '{"medium_min":5,"high_min":10,"critical_min":15}')->'thresholds'->>'critical_min')::numeric,
  15::numeric,
  'replace_criticality_configuration returns the resulting thresholds'
);

-- Umbral inválido → aborta TODO (la matriz tampoco cambia).
SELECT throws_matching($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM excel_matrix_v2), '{"medium_min":10,"high_min":5,"critical_min":20}') $$,
  '.*estrictamente ascendentes.*', 'invalid thresholds abort the whole import');
SELECT is((SELECT jsonb_agg(x->>'code') FROM jsonb_array_elements(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001')) x), '["P1"]'::jsonb, 'invalid thresholds leave the matrix unchanged');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":5,"h":10,"c":15}'::jsonb, 'invalid thresholds leave thresholds unchanged');
SELECT throws_matching($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM excel_matrix_v2), '{"medium_min":"10","high_min":20,"critical_min":30}') $$,
  '.*debe ser numérico.*', 'threshold sent as text is rejected');
SELECT throws_matching($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM excel_matrix_v2), '{"medium_min":10,"high_min":20}') $$,
  '.*Muy Alta desde.*', 'missing threshold is rejected');
SELECT throws_matching($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001', (SELECT payload FROM excel_matrix_v2), '{"medium_min":10.123,"high_min":20,"critical_min":30}') $$,
  '.*2 decimales.*', 'threshold with 3 decimals is rejected in the import');

-- Matriz inválida → aborta también los umbrales.
SELECT throws_matching($$
  SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000001',
    jsonb_set((SELECT payload FROM excel_matrix_v2), '{parameters,0,weight}', '-5'),
    '{"medium_min":40,"high_min":60,"critical_min":80}')
$$, '.*el peso debe ser >= 0.*', 'invalid matrix aborts the import');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000001'), '{"m":5,"h":10,"c":15}'::jsonb, 'invalid matrix leaves thresholds unchanged');
SELECT is((SELECT jsonb_agg(x->>'code') FROM jsonb_array_elements(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001')) x), '["P1"]'::jsonb, 'invalid matrix leaves the matrix unchanged');

-- Round-trip entre organizaciones: la configuración ACTIVA de A, exportada
-- (misma forma que genera el Excel) e importada en B, deja a B igual que A.
CREATE TEMP TABLE export_a AS
SELECT
  jsonb_build_object('parameters', (
    SELECT jsonb_agg(jsonb_build_object(
      'code', p->>'code', 'name', p->>'name', 'description', p->'description',
      'weight', (p->>'weight')::numeric, 'sequence', (p->>'sequence')::integer, 'is_active', true,
      'options', (
        SELECT jsonb_agg(jsonb_build_object('code', o->>'code', 'label', o->>'label',
          'score', (o->>'score')::numeric, 'sequence', (o->>'sequence')::integer, 'is_active', true))
        FROM jsonb_array_elements(p->'options') o
      )
    ))
    FROM jsonb_array_elements(public.get_criticality_matrix('20000000-0000-0000-0000-000000000001', false)) p
  )) AS matrix,
  jsonb_build_object(
    'medium_min', (public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->>'medium_min')::numeric,
    'high_min', (public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->>'high_min')::numeric,
    'critical_min', (public.get_criticality_thresholds('20000000-0000-0000-0000-000000000001')->>'critical_min')::numeric
  ) AS thresholds;
GRANT SELECT ON export_a TO authenticated;

SELECT pg_temp.as_user('10000000-0000-0000-0000-000000000004');
SELECT lives_ok($$ SELECT public.replace_criticality_configuration('20000000-0000-0000-0000-000000000002', (SELECT matrix FROM export_a), (SELECT thresholds FROM export_a)) $$,
  'Client B imports the configuration exported from Client A');
SELECT is(pg_temp.thresholds('20000000-0000-0000-0000-000000000002'), '{"m":5,"h":10,"c":15}'::jsonb, 'round-trip keeps thresholds');
SELECT is(pg_temp.matrix_shape('20000000-0000-0000-0000-000000000002'), pg_temp.matrix_shape('20000000-0000-0000-0000-000000000001'), 'round-trip keeps the matrix (codes, names, weights, options, scores, order)');
SELECT is(
  (SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003', 's1')),
  'low',
  'after the round-trip Client B classifies with the imported thresholds (1 < 5 → low)'
);
SELECT is(
  (SELECT calculated_criticality FROM pg_temp.preview('20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003', 's25')),
  'critical',
  'after the round-trip 25 ≥ 15 → critical in Client B'
);

SELECT * FROM finish();
ROLLBACK;
