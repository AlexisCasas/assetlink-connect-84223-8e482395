-- R2 cost catalog: disposable local Supabase only.
-- Synthetic tenants and rates are discarded with ROLLBACK.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(38);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config('request.jwt.claim.sub', p_user::text, true);
$$;

INSERT INTO auth.users (id, email) VALUES
  ('e8100000-0000-0000-0000-000000000001', 'r2-owner-a@test.invalid'),
  ('e8100000-0000-0000-0000-000000000002', 'r2-owner-b@test.invalid'),
  ('e8100000-0000-0000-0000-000000000003', 'r2-viewer-a@test.invalid');

INSERT INTO public.organizations (id, name, organization_type, status) VALUES
  ('e8200000-0000-0000-0000-000000000001', 'R2 Provider A', 'provider_company', 'active'),
  ('e8200000-0000-0000-0000-000000000002', 'R2 Provider B', 'provider_company', 'active');

INSERT INTO public.organization_members (id, organization_id, user_id, role, is_active) VALUES
  ('e8300000-0000-0000-0000-000000000001',
   'e8200000-0000-0000-0000-000000000001',
   'e8100000-0000-0000-0000-000000000001', 'manager', true),
  ('e8300000-0000-0000-0000-000000000002',
   'e8200000-0000-0000-0000-000000000002',
   'e8100000-0000-0000-0000-000000000002', 'manager', true),
  ('e8300000-0000-0000-0000-000000000003',
   'e8200000-0000-0000-0000-000000000001',
   'e8100000-0000-0000-0000-000000000003', 'viewer', true);

-- Provider B fixtures are inserted as the migration-test owner.
INSERT INTO public.provider_cost_suppliers
  (id, organization_id, display_name, tax_id)
VALUES
  ('e8400000-0000-0000-0000-000000000002',
   'e8200000-0000-0000-0000-000000000002', 'Supplier B', '20111111112');

INSERT INTO public.provider_cost_items
  (id, organization_id, code, name, category_code, default_unit_code)
VALUES
  ('e8500000-0000-0000-0000-000000000002',
   'e8200000-0000-0000-0000-000000000002',
   'B-CABLE', 'Cable B', 'MATERIAL', 'M');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e8100000-0000-0000-0000-000000000001');

SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_categories WHERE is_active),
  8,
  'seeded cost categories are available'
);
SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_units WHERE is_active),
  13,
  'seeded canonical units are available'
);
SELECT ok(
  NOT has_table_privilege('anon', 'public.provider_cost_suppliers', 'SELECT'),
  'anonymous role cannot read supplier costs'
);
SELECT ok(
  NOT has_table_privilege('anon', 'public.provider_cost_rates', 'SELECT'),
  'anonymous role cannot read cost rates'
);
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.provider_cost_suppliers', 'DELETE'),
  'authenticated users cannot hard-delete suppliers'
);
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.provider_cost_rates', 'DELETE'),
  'authenticated users cannot hard-delete cost rates'
);

INSERT INTO public.provider_cost_settings (
  organization_id, default_usd_pen_rate, default_fx_source,
  default_fx_date, default_fx_reference
) VALUES (
  'e8200000-0000-0000-0000-000000000001',
  3.750000, 'manual', '2026-11-17', 'R2 QA default exchange rate'
);

SELECT is(
  (SELECT base_currency_code FROM public.provider_cost_settings
   WHERE organization_id = 'e8200000-0000-0000-0000-000000000001'),
  'PEN',
  'organization base currency defaults to PEN'
);

INSERT INTO public.provider_cost_suppliers
  (organization_id, display_name, tax_id)
VALUES
  ('e8200000-0000-0000-0000-000000000001', 'Supplier A1', '20111111111'),
  ('e8200000-0000-0000-0000-000000000001', 'Supplier A2', '20111111113');

INSERT INTO public.provider_cost_items
  (organization_id, code, name, category_code, default_unit_code)
VALUES
  ('e8200000-0000-0000-0000-000000000001',
   'CABLE-NH80', 'Cable NH-80', 'MATERIAL', 'M'),
  ('e8200000-0000-0000-0000-000000000001',
   'TECH-ELECTRIC', 'Técnico electricista', 'LABOR', 'JOR'),
  ('e8200000-0000-0000-0000-000000000001',
   'PAINT-EPOXY', 'Pintura epóxica', 'MATERIAL', 'GAL');

SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_suppliers
   WHERE organization_id = 'e8200000-0000-0000-0000-000000000001'),
  2,
  'one resource organization can register multiple suppliers'
);
SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_items
   WHERE organization_id = 'e8200000-0000-0000-0000-000000000001'),
  3,
  'resources are independent of clients and inventory'
);

INSERT INTO public.provider_cost_rates (
  organization_id, cost_item_id, supplier_id, unit_code, currency_code,
  unit_cost_original, fx_source, tax_treatment, tax_rate,
  source_type, source_reference, valid_from
)
SELECT
  'e8200000-0000-0000-0000-000000000001',
  i.id, s.id, 'M', 'USD', 10.000000, 'organization_default',
  'exclusive', 18.0000, 'supplier_quote', 'R2A-TEST-A1-V1', '2026-11-17'
FROM public.provider_cost_items i
JOIN public.provider_cost_suppliers s
  ON s.organization_id = i.organization_id
WHERE i.organization_id = 'e8200000-0000-0000-0000-000000000001'
  AND i.code = 'CABLE-NH80'
  AND s.display_name = 'Supplier A1';

SELECT is(
  (SELECT fx_rate_to_pen FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V1'),
  3.75000000::numeric,
  'USD rate snapshots the configured organization FX rate'
);
SELECT is(
  (SELECT unit_cost_pen FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V1'),
  37.500000::numeric,
  'generated PEN unit cost is reproducible'
);
SELECT is(
  (SELECT version_number FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V1'),
  1,
  'first supplier rate receives version 1'
);

INSERT INTO public.provider_cost_rates (
  organization_id, cost_item_id, supplier_id, unit_code, currency_code,
  unit_cost_original, tax_treatment, source_type, source_reference, valid_from
)
SELECT
  'e8200000-0000-0000-0000-000000000001',
  i.id, s.id, 'M', 'PEN', 11.250000, 'unknown',
  'supplier_quote', 'R2A-TEST-A2-V1', '2026-11-17'
FROM public.provider_cost_items i
JOIN public.provider_cost_suppliers s
  ON s.organization_id = i.organization_id
WHERE i.organization_id = 'e8200000-0000-0000-0000-000000000001'
  AND i.code = 'CABLE-NH80'
  AND s.display_name = 'Supplier A2';

SELECT is(
  (SELECT version_number FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A2-V1'),
  1,
  'a different supplier has its own independent version sequence'
);

INSERT INTO public.provider_cost_rates (
  organization_id, cost_item_id, supplier_id, unit_code, currency_code,
  unit_cost_original, tax_treatment, source_type, source_reference, valid_from
)
SELECT
  'e8200000-0000-0000-0000-000000000001',
  i.id, s.id, 'M', 'PEN', 12.000000, 'unknown',
  'supplier_quote', 'R2A-TEST-A1-V2', '2026-12-01'
FROM public.provider_cost_items i
JOIN public.provider_cost_suppliers s
  ON s.organization_id = i.organization_id
WHERE i.organization_id = 'e8200000-0000-0000-0000-000000000001'
  AND i.code = 'CABLE-NH80'
  AND s.display_name = 'Supplier A1';

SELECT is(
  (SELECT version_number FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V2'),
  2,
  'new supplier quote increments the version'
);

UPDATE public.provider_cost_rates
SET status = 'pending_review'
WHERE source_reference = 'R2A-TEST-A1-V2';

UPDATE public.provider_cost_rates
SET status = 'approved'
WHERE source_reference = 'R2A-TEST-A1-V2';

SELECT is(
  (SELECT reviewed_by FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V2'),
  'e8100000-0000-0000-0000-000000000001'::uuid,
  'the same authorized user may create and approve a rate'
);
SELECT is(
  (SELECT valid_until FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V1'),
  '2026-11-30'::date,
  'approving a new version closes the previous overlapping validity window'
);
SELECT ok(
  (SELECT review_note LIKE 'Vigencia cerrada automáticamente%'
   FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V1'),
  'automatic validity closure records its audit reason'
);

INSERT INTO public.provider_cost_rates (
  organization_id, cost_item_id, unit_code, currency_code,
  unit_cost_original, tax_treatment, source_type, source_reference, valid_from
)
SELECT
  'e8200000-0000-0000-0000-000000000001',
  i.id, 'JOR', 'PEN', 120.000000, 'unknown',
  'payroll_basis', 'R2A-TEST-INTERNAL-LABOR', '2026-11-17'
FROM public.provider_cost_items i
WHERE i.organization_id = 'e8200000-0000-0000-0000-000000000001'
  AND i.code = 'TECH-ELECTRIC';

SELECT ok(
  (SELECT supplier_id IS NULL FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-INTERNAL-LABOR'),
  'internal labor rates do not require an external supplier'
);
SELECT is(
  (SELECT unit_cost_pen FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-INTERNAL-LABOR'),
  120.000000::numeric,
  'PEN internal costs use FX factor 1'
);

SELECT throws_ok(
  $$
    INSERT INTO public.provider_cost_rates (
      organization_id, cost_item_id, supplier_id, unit_code, currency_code,
      unit_cost_original, tax_treatment, source_type, source_reference, valid_from
    )
    SELECT
      'e8200000-0000-0000-0000-000000000001',
      i.id, s.id, 'UND', 'PEN', 1, 'unknown',
      'supplier_quote', 'R2A-TEST-BAD-UNIT', '2026-11-17'
    FROM public.provider_cost_items i
    JOIN public.provider_cost_suppliers s
      ON s.organization_id = i.organization_id
    WHERE i.code = 'CABLE-NH80'
      AND s.display_name = 'Supplier A1'
  $$,
  '23514',
  NULL,
  'a rate cannot silently change the resource default unit'
);

SELECT throws_ok(
  $$
    INSERT INTO public.provider_cost_rates (
      organization_id, cost_item_id, unit_code, currency_code,
      unit_cost_original, tax_treatment, source_type, source_reference, valid_from
    )
    SELECT
      'e8200000-0000-0000-0000-000000000001',
      i.id, 'M', 'PEN', 1, 'unknown',
      'supplier_quote', 'R2A-TEST-MISSING-SUPPLIER', '2026-11-17'
    FROM public.provider_cost_items i
    WHERE i.code = 'CABLE-NH80'
  $$,
  '23514',
  NULL,
  'supplier quote source requires a supplier'
);

SELECT throws_ok(
  $$
    INSERT INTO public.provider_cost_rates (
      organization_id, cost_item_id, supplier_id, unit_code, currency_code,
      unit_cost_original, tax_treatment, source_type, source_reference, valid_from
    )
    SELECT
      'e8200000-0000-0000-0000-000000000001',
      i.id, 'e8400000-0000-0000-0000-000000000002'::uuid,
      'M', 'PEN', 1, 'unknown',
      'supplier_quote', 'R2A-TEST-CROSS-TENANT', '2026-11-17'
    FROM public.provider_cost_items i
    WHERE i.organization_id = 'e8200000-0000-0000-0000-000000000001'
      AND i.code = 'CABLE-NH80'
  $$,
  '23503',
  NULL,
  'composite tenant foreign key blocks a supplier from another organization'
);

SELECT throws_ok(
  $$
    UPDATE public.provider_cost_rates
    SET unit_cost_original = 99
    WHERE source_reference = 'R2A-TEST-A1-V1'
  $$,
  '23514',
  NULL,
  'approved rate economic values are immutable'
);

UPDATE public.provider_cost_settings
SET default_usd_pen_rate = 4.000000,
    default_fx_date = '2026-11-18',
    default_fx_reference = 'R2 QA updated default exchange rate'
WHERE organization_id = 'e8200000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT fx_rate_to_pen FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V1'),
  3.75000000::numeric,
  'changing the default FX rate does not rewrite previous rate snapshots'
);

INSERT INTO public.provider_cost_rates (
  organization_id, cost_item_id, supplier_id, unit_code, currency_code,
  unit_cost_original, fx_source, tax_treatment, tax_rate,
  source_type, source_reference, valid_from
)
SELECT
  'e8200000-0000-0000-0000-000000000001',
  i.id, s.id, 'M', 'USD', 10.000000, 'organization_default',
  'exclusive', 18.0000, 'supplier_quote', 'R2A-TEST-A1-V3', '2026-12-02'
FROM public.provider_cost_items i
JOIN public.provider_cost_suppliers s
  ON s.organization_id = i.organization_id
WHERE i.organization_id = 'e8200000-0000-0000-0000-000000000001'
  AND i.code = 'CABLE-NH80'
  AND s.display_name = 'Supplier A1';

SELECT is(
  (SELECT version_number FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V3'),
  3,
  'third rate version increments without overwriting prior versions'
);
SELECT is(
  (SELECT fx_rate_to_pen FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-A1-V3'),
  4.00000000::numeric,
  'new USD rate uses the updated default FX snapshot'
);
SELECT throws_ok(
  $
    UPDATE public.provider_cost_rates
    SET unit_code = 'UND'
    WHERE source_reference = 'R2A-TEST-A1-V3'
  $,
  '23514',
  NULL,
  'draft rate cannot change to a unit that differs from its resource'
);

INSERT INTO public.provider_cost_rates (
  organization_id, cost_item_id, supplier_id, unit_code, currency_code,
  unit_cost_original, tax_treatment, source_type, source_reference, valid_from
)
SELECT
  'e8200000-0000-0000-0000-000000000001',
  i.id, s.id, 'GAL', 'PEN', 50.000000, 'unknown',
  'supplier_quote', 'R2A-TEST-REJECT', '2026-11-17'
FROM public.provider_cost_items i
JOIN public.provider_cost_suppliers s
  ON s.organization_id = i.organization_id
WHERE i.organization_id = 'e8200000-0000-0000-0000-000000000001'
  AND i.code = 'PAINT-EPOXY'
  AND s.display_name = 'Supplier A2';

UPDATE public.provider_cost_rates
SET status = 'pending_review'
WHERE source_reference = 'R2A-TEST-REJECT';

SELECT throws_ok(
  $$
    UPDATE public.provider_cost_rates
    SET status = 'rejected'
    WHERE source_reference = 'R2A-TEST-REJECT'
  $$,
  '23514',
  NULL,
  'rejection requires a reason'
);

UPDATE public.provider_cost_rates
SET status = 'rejected', review_note = 'Rejected in R2 test'
WHERE source_reference = 'R2A-TEST-REJECT';

SELECT is(
  (SELECT reviewed_by FROM public.provider_cost_rates
   WHERE source_reference = 'R2A-TEST-REJECT'),
  'e8100000-0000-0000-0000-000000000001'::uuid,
  'rejected rate records the reviewer'
);

SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_suppliers),
  2,
  'provider A cannot read provider B suppliers'
);
SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_items),
  3,
  'provider A cannot read provider B resources'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e8100000-0000-0000-0000-000000000002');

SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_suppliers),
  1,
  'provider B reads only its own supplier'
);
SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_items),
  1,
  'provider B reads only its own resource'
);
SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_rates),
  0,
  'provider B cannot read provider A rates'
);
SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_settings),
  0,
  'provider B cannot read provider A currency settings'
);

SELECT throws_ok(
  $
    INSERT INTO public.provider_cost_rates (
      organization_id, cost_item_id, supplier_id, unit_code, currency_code,
      unit_cost_original, fx_source, tax_treatment, source_type,
      source_reference, valid_from
    )
    VALUES (
      'e8200000-0000-0000-0000-000000000002',
      'e8500000-0000-0000-0000-000000000002',
      'e8400000-0000-0000-0000-000000000002',
      'M', 'USD', 10, 'organization_default', 'unknown',
      'supplier_quote', 'R2A-TEST-B-NO-FX', '2026-11-17'
    )
  $,
  '23514',
  NULL,
  'USD approval preparation fails closed without a configured default FX rate'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e8100000-0000-0000-0000-000000000003');

SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_suppliers),
  0,
  'viewer role cannot read internal suppliers'
);
SELECT is(
  (SELECT count(*)::int FROM public.provider_cost_rates),
  0,
  'viewer role cannot read internal cost rates'
);

SELECT * FROM finish();
ROLLBACK;
