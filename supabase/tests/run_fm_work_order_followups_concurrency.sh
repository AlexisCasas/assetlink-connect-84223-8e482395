#!/usr/bin/env bash
# One Facility | 9C.6-B2.3 D4 two REAL simultaneous sessions, Docker-local ONLY.
# Runs after B2.2 concurrency fixtures create a valid external OT in this
# throwaway GitHub Actions Supabase stack; never connect to Cloud.
set -euo pipefail
DB_CONTAINER="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)"
if [ -z "$DB_CONTAINER" ]; then
  echo 'FAIL: isolated Docker Supabase database unavailable' >&2
  exit 1
fi
echo "FM_D4_CONCURRENCY_DB=$DB_CONTAINER"
db() { docker exec -i "$DB_CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
db <<'SQL'
DO $pre$
BEGIN
  IF (SELECT count(*) FROM public.work_orders WHERE quote_id='c6900000-0000-0000-0000-0000000000a1'::uuid)<>1
    OR (SELECT count(*) FROM public.facility_management_permissions p WHERE p.relationship_id='c6700000-0000-0000-0000-0000000000a1'::uuid
      AND p.permission='work_orders.manage'::public.facility_management_permission)<>1
  THEN RAISE EXCEPTION 'D4 local race fixture missing: B2.2 must run first'; END IF;
END $pre$;
GRANT EXECUTE ON FUNCTION public.add_facility_management_work_order_followup(uuid,uuid,uuid,text,uuid)
  TO authenticated;
SQL

# Serializing on the external work order makes both clients overlap at the
# source lock before competing over the unique idempotency key.
docker exec -i "$DB_CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres >"$tmp/holder" 2>&1 <<'SQL' &
BEGIN;
SELECT id FROM public.work_orders
WHERE quote_id='c6900000-0000-0000-0000-0000000000a1'::uuid FOR UPDATE;
SELECT pg_sleep(1.2);
COMMIT;
SQL
hold_pid=$!
sleep 0.2
for i in 1 2; do
  docker exec -i "$DB_CONTAINER" psql -X -q -At -v ON_ERROR_STOP=1 -U postgres -d postgres >"$tmp/$i" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','c6100000-0000-0000-0000-000000000001',true);
SELECT (public.add_facility_management_work_order_followup(
 'c6200000-0000-0000-0000-0000000000a1'::uuid,
 'c6700000-0000-0000-0000-0000000000a1'::uuid,
 (SELECT id FROM public.work_orders WHERE quote_id='c6900000-0000-0000-0000-0000000000a1'::uuid),
 'Coordinación D4 de prueba concurrente',
 'c6b00000-0000-0000-0000-000000000001'::uuid
)->>'id');
COMMIT;
SQL
  if [ "$i" -eq 1 ]; then pid1=$!; else pid2=$!; fi
done
rc1=0; rc2=0
wait "$pid1" || rc1=$?
wait "$pid2" || rc2=$?
wait "$hold_pid" || { echo 'FAIL: lock holder'; cat "$tmp/holder"; exit 1; }
if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
  echo 'FAIL: D4 concurrent RPC invocation'
  cat "$tmp/1" "$tmp/2"
  exit 1
fi
id1="$(grep -E '^[a-f0-9]{8}-[a-f0-9-]{27,}$' "$tmp/1" | tail -n 1 || true)"
id2="$(grep -E '^[a-f0-9]{8}-[a-f0-9-]{27,}$' "$tmp/2" | tail -n 1 || true)"
if [ -z "$id1" ] || [ "$id1" != "$id2" ]; then
  echo "FAIL: D4 duplicate note IDs: '$id1' vs '$id2'"
  cat "$tmp/1" "$tmp/2"
  exit 1
fi

db <<'SQL'
DO $verify$
BEGIN
  IF (SELECT count(*) FROM public.facility_management_work_order_followups n
      WHERE n.relationship_id='c6700000-0000-0000-0000-0000000000a1'::uuid
        AND n.idempotency_key='c6b00000-0000-0000-0000-000000000001'::uuid)<>1
  THEN RAISE EXCEPTION 'D4 concurrent retry created more than one note'; END IF;
  IF (SELECT count(*) FROM public.audit_logs a
      WHERE a.action='facility_manager_external_work_order_followup_created'
        AND a.organization_id='c6200000-0000-0000-0000-0000000000a1'::uuid)<>1
  THEN RAISE EXCEPTION 'D4 concurrent retry emitted duplicate/missing audits'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.audit_logs
    WHERE action='facility_manager_external_work_order_followup_created'
      AND new_data::text LIKE '%Coordinación D4 de prueba concurrente%'
  ) THEN RAISE EXCEPTION 'D4 audit contains note body'; END IF;
END $verify$;
SQL
echo "FM_D4_TWO_SESSION_IDEMPOTENCY=PASS note=$id1 (single note and single audit)"
