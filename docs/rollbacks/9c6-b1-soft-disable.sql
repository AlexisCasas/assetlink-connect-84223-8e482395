-- One Facility 9C.6-B1: emergency soft-disable of delegated work-order read RPCs.
-- This does NOT restore a database backup or remove migration history.
-- Execute ONLY with explicit rollback authorization after detecting a B1 incident.
-- No business rows, RLS, legacy functions, or tables are modified.
BEGIN;
REVOKE EXECUTE ON FUNCTION public.get_facility_management_work_orders(uuid,text,integer,integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_facility_management_work_order(uuid,uuid) FROM PUBLIC, anon, authenticated;
COMMIT;

-- Verify after rollback (read only):
-- SELECT proname, has_function_privilege('authenticated',oid,'EXECUTE') AS authenticated_execute,
--        has_function_privilege('anon',oid,'EXECUTE') AS anon_execute
-- FROM pg_proc WHERE pronamespace='public'::regnamespace
-- AND proname IN ('get_facility_management_work_orders','get_facility_management_work_order');
