#!/usr/bin/env bash
# Fixed loopback only; no cloud credentials or linked project.
set -euo pipefail
test ! -f supabase/.temp/project-ref
DB='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
psql "$DB" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO auth.users(id,email) VALUES ('e4a10000-0000-4000-8000-000000000002','docs-concurrent@qa.invalid');
INSERT INTO public.organizations(id,name,organization_type,status) VALUES ('e4a10000-0000-4000-8000-000000000001','Synthetic attachment concurrency','provider_company','active');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES ('e4a10000-0000-4000-8000-000000000001','e4a10000-0000-4000-8000-000000000002','owner',true);
INSERT INTO public.romax_gmail_connections(organization_id,status,mailbox_email,refresh_ciphertext,connected_by,connected_at) VALUES ('e4a10000-0000-4000-8000-000000000001','connected','synthetic@example.test','synthetic-ciphertext','e4a10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z');
INSERT INTO public.romax_opportunities(id,organization_id,subject,source_system,source_thread_id,source_message_id) VALUES ('e4a10000-0000-4000-8000-000000000003','e4a10000-0000-4000-8000-000000000001','Synthetic concurrency','gmail','thread-a','source-a');
SQL
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for x in a b; do
  psql "$DB" -v ON_ERROR_STOP=1 -At >"$tmp/$x" 2>&1 <<'SQL' &
SET ROLE service_role;
SELECT public.romax_register_gmail_attachment_metadata('e4a10000-0000-4000-8000-000000000001','e4a10000-0000-4000-8000-000000000003','e4a10000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','thread-a','[{"message_id":"msg-synthetic","locator":"attachment-1","locator_kind":"attachment_id","filename":"TDR.pdf","mime_type":"application/pdf","size_bytes":1024,"received_at":"2026-11-28T12:00:00Z","direction":"incoming"}]'::jsonb);
SQL
  if [ "$x" = a ]; then a=$!; else b=$!; fi
done
wait "$a"; wait "$b"
cat "$tmp/a" "$tmp/b"
test "$(psql "$DB" -Atc "SELECT count(*) FROM public.romax_opportunity_attachments WHERE opportunity_id='e4a10000-0000-4000-8000-000000000003'")" = 1
test "$(psql "$DB" -Atc "SELECT count(*) FROM romax_docs_private.attachment_events WHERE opportunity_id='e4a10000-0000-4000-8000-000000000003'")" = 1
test "$(grep -h -c '"registered": 1' "$tmp/a" "$tmp/b" | awk '{s+=$1} END{print s}')" = 1
test "$(grep -h -c '"unchanged": 1' "$tmp/a" "$tmp/b" | awk '{s+=$1} END{print s}')" = 1
echo ROMAX_GMAIL4A_CONCURRENCY=PASS
