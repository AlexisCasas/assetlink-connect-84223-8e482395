-- One Facility 9C.6-B2.1 emergency permission disable.
-- Run only with explicit rollback authorization after an incident.
-- This prevents new delegated planning changes while preserving B1/C1 reads.
-- No OT rows, audit entries, RLS policies, or migration history are modified.
BEGIN;
REVOKE EXECUTE ON FUNCTION public.update_facility_management_internal_work_order_schedule(
  uuid,uuid,text,timestamptz,timestamptz,text,timestamptz,timestamptz
) FROM PUBLIC, anon, authenticated;
COMMIT;

-- Read-only verification:
-- SELECT has_function_privilege(
--   'authenticated',
--   'public.update_facility_management_internal_work_order_schedule(uuid,uuid,text,timestamptz,timestamptz,text,timestamptz,timestamptz)',
--   'EXECUTE'
-- ) AS still_executable; -- must be false.
