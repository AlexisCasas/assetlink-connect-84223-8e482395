#!/usr/bin/env bash
# Never accepts external DB URLs. Disposable local CI only.
set -euo pipefail
test ! -f supabase/.temp/project-ref
DB='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
psql "$DB" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO auth.users(id,email) VALUES ('e3210000-0000-4000-8000-000000000002','sol2-concurrent@example.test');
INSERT INTO public.organizations(id,name,organization_type,status) VALUES ('e3210000-0000-4000-8000-000000000001','Synthetic SOL2 concurrency','provider_company','active');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES ('e3210000-0000-4000-8000-000000000001','e3210000-0000-4000-8000-000000000002','owner',true);
INSERT INTO public.romax_opportunities(id,organization_id,subject) VALUES ('e3210000-0000-4000-8000-000000000003','e3210000-0000-4000-8000-000000000001','Synthetic concurrency');
SQL
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql "$DB" -v ON_ERROR_STOP=1 -Atc "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e3210000-0000-4000-8000-000000000002',false); SELECT public.romax_save_request_review('e3210000-0000-4000-8000-000000000001','e3210000-0000-4000-8000-000000000003',0,'e3210000-0000-4000-8000-000000000004','{\"title\":\"First\",\"summary\":null,\"scope\":null,\"restrictions\":null,\"reference\":null,\"reference_kind\":null,\"specialty\":null,\"deadline_date\":null,\"deadline_time\":null,\"deadline_note\":null,\"client_id\":null,\"site_id\":null,\"contact_id\":null,\"additional_contacts\":[],\"provenance\":{\"title\":{\"source\":\"manual\"}}}'::jsonb)->>'outcome';" >"$tmp/a" 2>&1 &
a=$!
psql "$DB" -v ON_ERROR_STOP=1 -Atc "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e3210000-0000-4000-8000-000000000002',false); SELECT public.romax_save_request_review('e3210000-0000-4000-8000-000000000001','e3210000-0000-4000-8000-000000000003',0,'e3210000-0000-4000-8000-000000000005','{\"title\":\"Second\",\"summary\":null,\"scope\":null,\"restrictions\":null,\"reference\":null,\"reference_kind\":null,\"specialty\":null,\"deadline_date\":null,\"deadline_time\":null,\"deadline_note\":null,\"client_id\":null,\"site_id\":null,\"contact_id\":null,\"additional_contacts\":[],\"provenance\":{\"title\":{\"source\":\"manual\"}}}'::jsonb)->>'outcome';" >"$tmp/b" 2>&1 &
b=$!
set +e
wait "$a"; sa=$?
wait "$b"; sb=$?
set -e
cat "$tmp/a" "$tmp/b"
test "$(( (sa==0)+(sb==0) ))" = 1
test "$(grep -h -c '^saved$' "$tmp/a" "$tmp/b" | awk '{s+=$1} END{print s}')" = 1
test "$(grep -h -c 'Review revision conflict' "$tmp/a" "$tmp/b" | awk '{s+=$1} END{print s}')" = 1
test "$(psql "$DB" -Atc "SELECT count(*) FROM public.romax_request_revisions WHERE opportunity_id='e3210000-0000-4000-8000-000000000003'")" = 1
echo ROMAX_SOL2_CONCURRENCY=PASS
