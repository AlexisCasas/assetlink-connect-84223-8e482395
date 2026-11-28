#!/usr/bin/env bash
set -euo pipefail
test ! -f supabase/.temp/project-ref
DB='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
# Reuse only fixture statements, not test assertions or transaction markers.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed -n '/^INSERT INTO auth.users/,/^CREATE TEMP TABLE qa_extract/{ /^CREATE TEMP TABLE qa_extract/!p; }' supabase/tests/romax_r3_gmail_4e1_extraction.test.sql > "$tmp/fixture.sql"
psql "$DB" -v ON_ERROR_STOP=1 -f "$tmp/fixture.sql"

for n in 70 71; do
 psql "$DB" -v ON_ERROR_STOP=1 -At >"$tmp/enqueue-$n" 2>&1 <<SQL &
SET ROLE service_role;
SELECT public.romax_extract_enqueue('e4e10000-0000-4000-8000-000000000001','e4e10000-0000-4000-8000-000000000004','e4e10000-0000-4000-8000-000000000002','e4e10000-0000-4000-8000-000000000010','synthetic-v1','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','e4e10000-0000-4000-8000-0000000000$n',true,false);
SQL
 if [ "$n" = 70 ]; then a=$!; else b=$!; fi
done
wait "$a"; wait "$b"
job=$(psql "$DB" -Atc "SELECT id FROM romax_extract_private.jobs WHERE attachment_id='e4e10000-0000-4000-8000-000000000010'")
test "$(psql "$DB" -Atc "SELECT count(*) FROM romax_extract_private.jobs WHERE attachment_id='e4e10000-0000-4000-8000-000000000010'")" = 1
for n in a b; do
 psql "$DB" -v ON_ERROR_STOP=1 -At >"$tmp/claim-$n" 2>&1 <<SQL &
SET ROLE service_role;
SELECT public.romax_extract_claim('e4e10000-0000-4000-8000-000000000001','e4e10000-0000-4000-8000-000000000004','$job');
SQL
 if [ "$n" = a ]; then a=$!; else b=$!; fi
done
set +e
wait "$a"; ra=$?; wait "$b"; rb=$?
set -e
test "$(( (ra == 0) + (rb == 0) ))" = 1
grep -q 'Job not claimable' "$tmp/claim-a" "$tmp/claim-b"
test "$(psql "$DB" -Atc "SELECT attempts FROM romax_extract_private.jobs WHERE id='$job'")" = 1
echo ROMAX_GMAIL4E1_CONCURRENCY=PASS
