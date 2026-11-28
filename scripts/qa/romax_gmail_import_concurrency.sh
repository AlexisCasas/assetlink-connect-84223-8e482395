#!/usr/bin/env bash
# Synthetic records in disposable local stack only. No remote URL or credentials accepted.
set -euo pipefail
test ! -f supabase/.temp/project-ref
DB='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
psql "$DB" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO auth.users(id,email) VALUES ('d3100000-0000-4000-8000-000000000002','gmail-owner@example.test'),('d3100000-0000-4000-8000-000000000003','gmail-manager@example.test');
INSERT INTO public.organizations(id,name,organization_type,status) VALUES ('d3100000-0000-4000-8000-000000000001','Synthetic Gmail QA','provider_company','active'),('d3100000-0000-4000-8000-000000000004','Synthetic other QA','provider_company','active');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES ('d3100000-0000-4000-8000-000000000001','d3100000-0000-4000-8000-000000000002','owner',true),('d3100000-0000-4000-8000-000000000001','d3100000-0000-4000-8000-000000000003','manager',true);
INSERT INTO public.romax_gmail_connections(organization_id,status,mailbox_email,refresh_ciphertext,connected_by,connected_at) VALUES ('d3100000-0000-4000-8000-000000000001','connected','synthetic@example.test','synthetic-ciphertext','d3100000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z');

SQL
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql "$DB" -v ON_ERROR_STOP=1 -Atc "SET ROLE service_role; SELECT (public.romax_confirm_gmail_import('d3100000-0000-4000-8000-000000000001','d3100000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',repeat('a',64),repeat('b',64),clock_timestamp()+interval '4 minutes','synthetic-thread','synthetic-msg','Synthetic request','sender@example.test',clock_timestamp()-interval '1 minute','Synthetic excerpt','Synthetic classification'))->>'outcome';" >"$tmp/a" &
a=$!
psql "$DB" -v ON_ERROR_STOP=1 -Atc "SET ROLE service_role; SELECT (public.romax_confirm_gmail_import('d3100000-0000-4000-8000-000000000001','d3100000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',repeat('d',64),repeat('b',64),clock_timestamp()+interval '4 minutes','synthetic-thread','synthetic-msg','Synthetic request','sender@example.test',clock_timestamp()-interval '1 minute','Synthetic excerpt','Synthetic classification'))->>'outcome';" >"$tmp/b" &
b=$!
wait "$a"; wait "$b"
test "$(cat "$tmp/a" "$tmp/b" | grep -c '^imported$')" = 1
test "$(cat "$tmp/a" "$tmp/b" | grep -c '^already_exists$')" = 1
test "$(psql "$DB" -Atc "SELECT count(*) FROM public.romax_opportunities WHERE organization_id='d3100000-0000-4000-8000-000000000001' AND source_system='gmail'")" = 1
test "$(psql "$DB" -Atc "SELECT count(*) FROM public.romax_gmail_import_audit WHERE organization_id='d3100000-0000-4000-8000-000000000001'")" = 1
echo 'ROMAX_GMAIL_IMPORT_CONCURRENCY=PASS'
