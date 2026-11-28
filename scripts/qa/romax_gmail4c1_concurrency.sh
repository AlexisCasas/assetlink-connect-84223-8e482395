#!/usr/bin/env bash
set -euo pipefail
test ! -f supabase/.temp/project-ref
DB='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
psql "$DB" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO auth.users(id,email) VALUES ('e4c20000-0000-4000-8000-000000000002','quarantine-race@qa.invalid');
INSERT INTO public.organizations(id,name,organization_type,status) VALUES ('e4c20000-0000-4000-8000-000000000001','Synthetic quarantine race','provider_company','active');
INSERT INTO public.organization_members(organization_id,user_id,role,is_active) VALUES ('e4c20000-0000-4000-8000-000000000001','e4c20000-0000-4000-8000-000000000002','owner',true);
INSERT INTO public.romax_gmail_connections(organization_id,status,mailbox_email,refresh_ciphertext,connected_by,connected_at) VALUES ('e4c20000-0000-4000-8000-000000000001','connected','synthetic@example.test','synthetic-ciphertext','e4c20000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z');
INSERT INTO public.romax_opportunities(id,organization_id,subject,source_system,source_thread_id,source_message_id) VALUES ('e4c20000-0000-4000-8000-000000000003','e4c20000-0000-4000-8000-000000000001','Synthetic race','gmail','thread-a','source-a');
INSERT INTO public.romax_opportunity_attachments(id,organization_id,opportunity_id,source_system,source_message_id,source_attachment_id,source_locator_kind,source_received_at,source_direction,discovered_by,filename,mime_type,size_bytes) VALUES ('e4c20000-0000-4000-8000-000000000004','e4c20000-0000-4000-8000-000000000001','e4c20000-0000-4000-8000-000000000003','gmail','msg','att','attachment_id','2026-01-01T00:00:00Z','incoming','e4c20000-0000-4000-8000-000000000002','test.pdf','application/pdf',1024);
SQL
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for x in a b; do
  psql "$DB" -v ON_ERROR_STOP=1 -At >"$tmp/$x" 2>&1 <<'SQL' &
SET ROLE service_role;
SELECT public.romax_claim_attachment_downloads('e4c20000-0000-4000-8000-000000000001','e4c20000-0000-4000-8000-000000000003','e4c20000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z',ARRAY['e4c20000-0000-4000-8000-000000000004']::uuid[]);
SQL
  if [ "$x" = a ]; then a=$!; else b=$!; fi
done
set +e
wait "$a"; ra=$?; wait "$b"; rb=$?
set -e
cat "$tmp/a" "$tmp/b"
test "$(( (ra == 0) + (rb == 0) ))" = 1
grep -q 'Download already reserved' "$tmp/a" "$tmp/b"
test "$(psql "$DB" -Atc "SELECT count(*) FROM romax_docs_private.download_attempts WHERE attachment_id='e4c20000-0000-4000-8000-000000000004' AND state='leased'")" = 1
echo ROMAX_GMAIL4C1_CONCURRENCY=PASS
