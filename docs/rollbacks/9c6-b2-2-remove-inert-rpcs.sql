-- One Facility | 9C.6-B2.2-D emergency rollback, only after authorization.
-- Removes only the two NEW D3 creation RPCs (never B1/B2.1 or OT data).
-- Use if B2.2 deployment is unhealthy. Before executing, inspect activity
-- and confirm no later migration depends on either function.
-- The migration history record is intentionally preserved and must be
-- reconciled separately; never erase migration history casually.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $guard$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action IN (
      'facility_manager_work_order_created_from_quote',
      'facility_manager_internal_work_order_created'
    )
  ) THEN
    RAISE EXCEPTION 'B2.2 rollback blocked: delegated creations exist; inspect before dropping';
  END IF;
END $guard$;

REVOKE ALL ON FUNCTION public.create_facility_management_internal_work_order(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_facility_management_work_order_from_quote(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

DROP FUNCTION public.create_facility_management_internal_work_order(uuid,uuid);
DROP FUNCTION public.create_facility_management_work_order_from_quote(uuid,uuid);
COMMIT;

-- Read-only verification:
-- SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname IN (
--   'create_facility_management_internal_work_order',
--   'create_facility_management_work_order_from_quote'
-- ); -- expected 0
