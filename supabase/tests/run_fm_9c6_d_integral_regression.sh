#!/usr/bin/env bash
# One Facility 9C.6-D integrated user journey, Docker-isolated Supabase ONLY.
# Requires B2.2 + D4 concurrency fixture scripts first; no Cloud credentials.
set -euo pipefail
DB_CONTAINER="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)"
if [ -z "$DB_CONTAINER" ]; then echo 'NO_GO: no disposable Supabase DB'; exit 1; fi
echo "9C6_D_INTEGRAL_DB=$DB_CONTAINER (isolated Docker)"

docker exec -i "$DB_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='15s';
DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.work_orders
       WHERE request_id IN ('c6800000-0000-0000-0000-0000000000a1'::uuid,
                            'c6800000-0000-0000-0000-0000000000a2'::uuid))<>2
    OR (SELECT count(*) FROM public.facility_management_work_order_followups
         WHERE relationship_id='c6700000-0000-0000-0000-0000000000a1'::uuid
           AND idempotency_key='c6b00000-0000-0000-0000-000000000001'::uuid)<>1
    OR (SELECT count(*) FROM public.facility_management_permissions
         WHERE relationship_id='c6700000-0000-0000-0000-0000000000a1'::uuid
           AND permission='work_orders.manage')<>1
    OR NOT has_function_privilege('authenticated','public.create_facility_management_internal_work_order(uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.create_facility_management_work_order_from_quote(uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.add_facility_management_work_order_followup(uuid,uuid,uuid,text,uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'NO_GO: prior isolated B2.2/D4 fixtures unavailable'; END IF;
  IF EXISTS (SELECT 1 FROM public.organization_members
     WHERE user_id='c6100000-0000-0000-0000-000000000001'::uuid
       AND organization_id='c6200000-0000-0000-0000-0000000000a1'::uuid)
  THEN RAISE EXCEPTION 'NO_GO: assigned FM has unintended client membership'; END IF;
END $preflight$;
-- Only test owner reads the raw IDs; the FM user will access data via B1 RPCs.
SELECT set_config('qa.d.internal_id',
   (SELECT id::text FROM public.work_orders WHERE request_id='c6800000-0000-0000-0000-0000000000a1'::uuid),true);
SELECT set_config('qa.d.external_id',
   (SELECT id::text FROM public.work_orders WHERE quote_id='c6900000-0000-0000-0000-0000000000a1'::uuid),true);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','c6100000-0000-0000-0000-000000000001',true);
DO $authorized$
DECLARE
 v_client uuid:='c6200000-0000-0000-0000-0000000000a1'::uuid;
 v_rel uuid:='c6700000-0000-0000-0000-0000000000a1'::uuid;
 v_internal uuid:=current_setting('qa.d.internal_id')::uuid;
 v_external uuid:=current_setting('qa.d.external_id')::uuid;
 v_list jsonb; v_before jsonb; v_after jsonb; v_ext jsonb;
 v_retry_internal jsonb; v_retry_external jsonb;
 v_note_page jsonb; v_note jsonb;
 v_old text; v_next text; v_sched timestamptz; v_due timestamptz;
 v_cas_denied boolean:=false;
BEGIN
 v_list:=public.get_facility_management_work_orders(v_client,NULL,20,0);
 IF (v_list->>'total')::integer<>2
   OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_list->'items') x WHERE x->>'id'=v_internal::text)
   OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_list->'items') x WHERE x->>'id'=v_external::text)
 THEN RAISE EXCEPTION 'D-01: read list must contain both authorized created OTs'; END IF;
 v_before:=public.get_facility_management_work_order(v_client,v_internal);
 v_ext:=public.get_facility_management_work_order(v_client,v_external);
 IF v_before->>'work_order_type'<>'internal'
    OR v_ext->>'work_order_type'<>'external'
    OR v_before->>'id'<>v_internal::text
    OR v_ext->>'id'<>v_external::text
 THEN RAISE EXCEPTION 'D-02: detail identity/type mismatch'; END IF;
 IF v_ext ? 'provider_organization_id'
    OR v_ext ? 'assigned_member_id'
    OR v_ext ? 'planner_member_id'
    OR (v_ext->>'prices_visible')='false' AND v_ext->>'total_amount' IS NOT NULL
 THEN RAISE EXCEPTION 'D-03: external DTO leaks provider/operator/pricing'; END IF;

 v_retry_internal:=public.create_facility_management_internal_work_order(
   v_client,'c6800000-0000-0000-0000-0000000000a1'::uuid);
 v_retry_external:=public.create_facility_management_work_order_from_quote(
   v_client,'c6900000-0000-0000-0000-0000000000a1'::uuid);
 IF v_retry_internal->>'id'<>v_internal::text OR v_retry_external->>'id'<>v_external::text
 THEN RAISE EXCEPTION 'D-04: repeated creation returned a different OT'; END IF;

 v_old:=v_before->>'priority';
 v_next:=CASE WHEN v_old='high' THEN 'low' ELSE 'high' END;
 v_sched:=(v_before->>'scheduled_at')::timestamptz;
 v_due:=(v_before->>'due_at')::timestamptz;
 PERFORM public.update_facility_management_internal_work_order_schedule(
    v_client,v_internal,v_old,v_sched,v_due,v_next,v_sched,v_due);
 v_after:=public.get_facility_management_work_order(v_client,v_internal);
 IF v_after->>'priority'<>v_next OR v_after->>'status'<>v_before->>'status'
 THEN RAISE EXCEPTION 'D-05: planning priority or status mismatch'; END IF;
 BEGIN
   PERFORM public.update_facility_management_internal_work_order_schedule(
      v_client,v_internal,v_old,v_sched,v_due,v_next,v_sched,v_due);
   RAISE EXCEPTION 'D-06: stale planning CAS unexpectedly succeeded';
 EXCEPTION WHEN SQLSTATE '40001' THEN v_cas_denied:=true; END;
 IF NOT v_cas_denied THEN RAISE EXCEPTION 'D-06: stale CAS not rejected'; END IF;

 v_note_page:=public.get_facility_management_work_order_followups(
    v_client,v_rel,v_external,20,0);
 IF (v_note_page->>'total')::integer<>1 OR
    v_note_page->'items'->0->>'body'<>'Coordinación D4 de prueba concurrente'
 THEN RAISE EXCEPTION 'D-07: external FM note missing or cross-scoped'; END IF;
 v_note:=public.add_facility_management_work_order_followup(
    v_client,v_rel,v_external,'Coordinación D4 de prueba concurrente',
    'c6b00000-0000-0000-0000-000000000001'::uuid);
 IF v_note->>'id'<>v_note_page->'items'->0->>'id'
 THEN RAISE EXCEPTION 'D-08: followup retry generated another note'; END IF;
END $authorized$;

-- Unassigned actor must not resolve any of the IDs, regardless of UUID.
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
DO $negative$
DECLARE
 v_denied boolean:=false;
BEGIN
 BEGIN
   PERFORM public.get_facility_management_work_order(
     'c6200000-0000-0000-0000-0000000000a1'::uuid,
     current_setting('qa.d.internal_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'D-09: unassigned actor can read OT'; END IF;
 v_denied:=false;
 BEGIN
   PERFORM public.get_facility_management_work_order_followups(
     'c6200000-0000-0000-0000-0000000000a1'::uuid,
     'c6700000-0000-0000-0000-0000000000a1'::uuid,
     current_setting('qa.d.external_id')::uuid,20,0);
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'D-10: unassigned actor can read D4'; END IF;
END $negative$;
RESET ROLE;

-- Revocation must stop further writes without suppressing authorized reads.
DELETE FROM public.facility_management_permissions
 WHERE relationship_id='c6700000-0000-0000-0000-0000000000a1'::uuid
   AND permission='work_orders.manage';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','c6100000-0000-0000-0000-000000000001',true);
DO $revoked$
DECLARE v_denied boolean:=false;
BEGIN
 BEGIN
   PERFORM public.create_facility_management_internal_work_order(
     'c6200000-0000-0000-0000-0000000000a1'::uuid,
     'c6800000-0000-0000-0000-0000000000a1'::uuid);
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'D-11: creation remains possible after revoke'; END IF;
 v_denied:=false;
 BEGIN
   PERFORM public.add_facility_management_work_order_followup(
     'c6200000-0000-0000-0000-0000000000a1'::uuid,
     'c6700000-0000-0000-0000-0000000000a1'::uuid,
     current_setting('qa.d.external_id')::uuid,'Revoked',
     'c6b00000-0000-0000-0000-000000000009'::uuid);
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'D-12: D4 writes remain possible after revoke'; END IF;
 IF public.get_facility_management_work_order(
   'c6200000-0000-0000-0000-0000000000a1'::uuid,
   current_setting('qa.d.external_id')::uuid)->>'work_order_type'<>'external'
 THEN RAISE EXCEPTION 'D-13: read lost after manage revocation'; END IF;
END $revoked$;
RESET ROLE;
DO $postcheck$
BEGIN
 IF (SELECT count(*) FROM public.work_orders
       WHERE request_id IN ('c6800000-0000-0000-0000-0000000000a1'::uuid,
                            'c6800000-0000-0000-0000-0000000000a2'::uuid))<>2
   OR (SELECT count(*) FROM public.facility_management_work_order_followups
        WHERE relationship_id='c6700000-0000-0000-0000-0000000000a1'::uuid)<>1
   OR (SELECT count(*) FROM public.audit_logs WHERE organization_id='c6200000-0000-0000-0000-0000000000a1'::uuid
        AND action='facility_manager_internal_work_order_created')<>1
   OR (SELECT count(*) FROM public.audit_logs WHERE organization_id='c6200000-0000-0000-0000-0000000000a1'::uuid
        AND action='facility_manager_work_order_created_from_quote')<>1
   OR (SELECT count(*) FROM public.audit_logs WHERE organization_id='c6200000-0000-0000-0000-0000000000a1'::uuid
        AND action='facility_manager_internal_work_order_planning')<>1
   OR (SELECT count(*) FROM public.audit_logs WHERE organization_id='c6200000-0000-0000-0000-0000000000a1'::uuid
        AND action='facility_manager_external_work_order_followup_created')<>1
 THEN RAISE EXCEPTION 'D-14: regression in OT count or audit count'; END IF;
END $postcheck$;
SELECT '9C6_D_INTEGRAL_FLOW=PASS' AS verification;
ROLLBACK;
SQL
echo '9C6_D_INTEGRAL_FLOW=PASS (client-free FM, B1/B2/D3/D4, revoke, no persisted changes)'
