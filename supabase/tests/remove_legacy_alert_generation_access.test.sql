-- Fase 1 · Punto 8
-- Retiro del acceso legacy a los generadores manuales de alertas.
--
-- Ejecutar:
-- supabase test db supabase/tests/remove_legacy_alert_generation_access.test.sql --local

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- -------------------------------------------------------------------------
-- 1. authenticated no puede ejecutar el generador operacional
-- -------------------------------------------------------------------------

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000001',
  true
);

SELECT throws_ok(
  $$ SELECT public.generate_operational_due_notifications() $$,
  '42501',
  NULL,
  'authenticated cannot execute generate_operational_due_notifications'
);

-- -------------------------------------------------------------------------
-- 2. authenticated no puede ejecutar el generador de inspecciones
-- -------------------------------------------------------------------------

SELECT throws_ok(
  $$ SELECT public.generate_inspection_due_notifications() $$,
  '42501',
  NULL,
  'authenticated cannot execute generate_inspection_due_notifications'
);

RESET ROLE;

-- -------------------------------------------------------------------------
-- 3. service_role conserva EXECUTE
-- -------------------------------------------------------------------------

SELECT ok(
  has_function_privilege(
    'service_role',
    'public.generate_operational_due_notifications()',
    'EXECUTE'
  )
  AND
  has_function_privilege(
    'service_role',
    'public.generate_inspection_due_notifications()',
    'EXECUTE'
  ),
  'service_role keeps EXECUTE on both legacy generators'
);

-- -------------------------------------------------------------------------
-- 4. postgres conserva EXECUTE
-- -------------------------------------------------------------------------

SELECT ok(
  has_function_privilege(
    'postgres',
    'public.generate_operational_due_notifications()',
    'EXECUTE'
  )
  AND
  has_function_privilege(
    'postgres',
    'public.generate_inspection_due_notifications()',
    'EXECUTE'
  ),
  'postgres keeps EXECUTE on both legacy generators'
);

-- -------------------------------------------------------------------------
-- 5. El wrapper automático sigue funcionando
-- -------------------------------------------------------------------------

SELECT ok(
  public.run_automatic_alert_generation() ? 'generators',
  'run_automatic_alert_generation still executes and returns generator results'
);

-- -------------------------------------------------------------------------
-- 6. Cron continúa llamando al wrapper
-- -------------------------------------------------------------------------

SELECT ok(
  EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'automatic-alert-generation'
      AND active = true
      AND command = 'SELECT public.run_automatic_alert_generation();'
  ),
  'automatic-alert-generation cron remains active and calls the wrapper'
);

SELECT * FROM finish();

ROLLBACK;