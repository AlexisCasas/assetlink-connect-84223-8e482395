#!/usr/bin/env bash
# 9C.6-B2.2 | TWO real concurrent sessions on an ISOLATED Supabase Docker DB.
# Must never run against Supabase Cloud. All IDs are dedicated to this CI check.
set -euo pipefail

DB_CONTAINER="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)"
if [ -z "$DB_CONTAINER" ]; then
  echo "FAIL: disposable local Supabase PostgreSQL container missing" >&2
  exit 1
fi
echo "FM_B22_CONCURRENCY_DB=$DB_CONTAINER (Docker-local only)"
db() { docker exec -i "$DB_CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"; }
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Local-only committed fixtures are needed for visibility from two sessions.
# The CI workflow ALWAYS destroys its disposable stack afterward.
db <<'SQL'
BEGIN;
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('c6100000-0000-0000-0000-000000000001','fm-concurrent-qa@example.invalid','{}');
INSERT INTO public.organizations(id,name,organization_type) VALUES
 ('c6200000-0000-0000-0000-0000000000a1','C2.2 race client','client_company'),
 ('c6200000-0000-0000-0000-0000000000fa','C2.2 race FM','facility_manager'),
 ('c6200000-0000-0000-0000-0000000000c1','C2.2 race provider','provider_company');
INSERT INTO public.organization_members(id,organization_id,user_id,role,is_active)
VALUES ('c6300000-0000-0000-0000-000000000001',
 'c6200000-0000-0000-0000-0000000000fa',
 'c6100000-0000-0000-0000-000000000001','manager',true);
INSERT INTO public.organization_relationships(id,source_organization_id,target_organization_id,relationship_type,status)
VALUES ('c6700000-0000-0000-0000-0000000000a1',
 'c6200000-0000-0000-0000-0000000000a1',
 'c6200000-0000-0000-0000-0000000000fa','facility_management','pending');
UPDATE public.organization_relationships SET status='active'
 WHERE id='c6700000-0000-0000-0000-0000000000a1';
INSERT INTO public.facility_management_permissions(relationship_id,permission) VALUES
 ('c6700000-0000-0000-0000-0000000000a1','requests.view'),
 ('c6700000-0000-0000-0000-0000000000a1','work_orders.view'),
 ('c6700000-0000-0000-0000-0000000000a1','work_orders.manage'),
 ('c6700000-0000-0000-0000-0000000000a1','quotes.view');
INSERT INTO public.facility_management_relationship_members(relationship_id,organization_member_id)
VALUES ('c6700000-0000-0000-0000-0000000000a1','c6300000-0000-0000-0000-000000000001');
INSERT INTO public.requests
(id,organization_id,request_number,title,description,asset,location,service_type,deadline,status,request_type,is_public,created_by,min_quotes,quotes_closed)
VALUES
 ('c6800000-0000-0000-0000-0000000000a1','c6200000-0000-0000-0000-0000000000a1',
 'QA-CONC-INT','Internal concurrency','Internal work','Equipment','Lima','preventivo',now()+interval '10 days','sent','internal',false,'fixture',1,false),
 ('c6800000-0000-0000-0000-0000000000a2','c6200000-0000-0000-0000-0000000000a1',
 'QA-CONC-EXT','External concurrency','External work','Equipment','Lima','correctivo',now()+interval '10 days','quoted','external',true,'fixture',1,false);
INSERT INTO public.quotes(id,request_id,provider_organization_id,amount,description,status,total_amount)
VALUES ('c6900000-0000-0000-0000-0000000000a1','c6800000-0000-0000-0000-0000000000a2',
 'c6200000-0000-0000-0000-0000000000c1',100,'QA approved','approved',100);
COMMIT;
SQL

run_pair() {
  local kind="$1" source_id="$2" fn="$3"
  local hold_pid p1 p2 rc1=0 rc2=0
  echo "START concurrent race: $kind"
  # Hold the same source lock used inside the RPC, so both clients are
  # simultaneously queued at its gate before either is allowed to insert.
  docker exec -i "$DB_CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres > "$TEMP_DIR/$kind.hold" 2>&1 <<SQL &
BEGIN;
SELECT id FROM public.$([ "$kind" = "internal" ] && echo requests || echo quotes)
 WHERE id='$source_id'::uuid FOR UPDATE;
SELECT pg_sleep(1.3);
COMMIT;
SQL
  hold_pid=$!
  sleep 0.2
  for i in 1 2; do
    docker exec -i "$DB_CONTAINER" psql -X -q -At -v ON_ERROR_STOP=1 -U postgres -d postgres > "$TEMP_DIR/$kind.$i" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','c6100000-0000-0000-0000-000000000001',true);
SELECT (public.$fn('c6200000-0000-0000-0000-0000000000a1'::uuid,'$source_id'::uuid)->>'id');
COMMIT;
SQL
    if [ "$i" -eq 1 ]; then p1=$!; else p2=$!; fi
  done
  wait "$p1" || rc1=$?
  wait "$p2" || rc2=$?
  wait "$hold_pid" || { echo "FAIL: source-row lock holder"; cat "$TEMP_DIR/$kind.hold"; exit 1; }
  if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
    echo "FAIL: concurrent $kind RPC sessions"
    cat "$TEMP_DIR/$kind.1" "$TEMP_DIR/$kind.2"
    exit 1
  fi
  local id1 id2
  id1="$(grep -E '^[a-f0-9]{8}-[a-f0-9-]{27,}$' "$TEMP_DIR/$kind.1" | tail -n 1 || true)"
  id2="$(grep -E '^[a-f0-9]{8}-[a-f0-9-]{27,}$' "$TEMP_DIR/$kind.2" | tail -n 1 || true)"
  if [ -z "$id1" ] || [ "$id1" != "$id2" ]; then
    echo "FAIL: concurrent $kind responses differ/missing: '$id1' vs '$id2'"
    cat "$TEMP_DIR/$kind.1" "$TEMP_DIR/$kind.2"
    exit 1
  fi
  echo "PASS: 2 concurrent $kind sessions returned exactly one OT id"
}

run_pair internal c6800000-0000-0000-0000-0000000000a1 create_facility_management_internal_work_order
run_pair external c6900000-0000-0000-0000-0000000000a1 create_facility_management_work_order_from_quote

db <<'SQL'
DO $verify$
DECLARE
 n int;
BEGIN
 SELECT count(*) INTO n FROM public.work_orders WHERE request_id='c6800000-0000-0000-0000-0000000000a1';
 IF n<>1 THEN RAISE EXCEPTION 'Internal race generated % OT',n; END IF;
 SELECT count(*) INTO n FROM public.work_orders WHERE quote_id='c6900000-0000-0000-0000-0000000000a1';
 IF n<>1 THEN RAISE EXCEPTION 'External race generated % OT',n; END IF;
 SELECT count(*) INTO n FROM public.audit_logs
 WHERE action='facility_manager_internal_work_order_created'
 AND organization_id='c6200000-0000-0000-0000-0000000000a1';
 IF n<>1 THEN RAISE EXCEPTION 'Internal race generated % audit entries',n; END IF;
 SELECT count(*) INTO n FROM public.audit_logs
 WHERE action='facility_manager_work_order_created_from_quote'
 AND organization_id='c6200000-0000-0000-0000-0000000000a1';
 IF n<>1 THEN RAISE EXCEPTION 'External race generated % audit entries',n; END IF;
 IF EXISTS(SELECT 1 FROM public.work_orders w
    WHERE w.request_id IN ('c6800000-0000-0000-0000-0000000000a1','c6800000-0000-0000-0000-0000000000a2')
      AND (w.planner_member_id IS NOT NULL OR w.assigned_member_id IS NOT NULL))
 THEN RAISE EXCEPTION 'FM improperly assigned operator members'; END IF;
END $verify$;
SQL
echo 'FM_B22_TWO_SESSION_CONCURRENCY=PASS'
