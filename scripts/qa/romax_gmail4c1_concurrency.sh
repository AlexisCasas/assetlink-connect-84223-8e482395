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

# Real local Storage HTTP API: the synthetic winner's unique private object.
# Do not print local keys, auth headers or object contents.
env_values=$(supabase status -o env 2>/dev/null)
service=$(printf '%s\n' "$env_values" | sed -n 's/^SERVICE_ROLE_KEY=//p' | tr -d '"')
anon=$(printf '%s\n' "$env_values" | sed -n 's/^ANON_KEY=//p' | tr -d '"')
unset env_values
test -n "$service" && test -n "$anon"
attempt=$(psql "$DB" -Atc "SELECT id FROM romax_docs_private.download_attempts WHERE attachment_id='e4c20000-0000-4000-8000-000000000004' AND state='leased'")
path=$(psql "$DB" -Atc "SELECT object_path FROM romax_docs_private.download_attempts WHERE id='$attempt'")
test "$path" = "quarantine/e4c20000-0000-4000-8000-000000000001/e4c20000-0000-4000-8000-000000000003/e4c20000-0000-4000-8000-000000000004/$attempt"
url="http://127.0.0.1:54321/storage/v1/object/romax-request-attachments/$path"
printf '%%PDF-' >"$tmp/file"
head -c 1019 /dev/zero | tr '\000' x >>"$tmp/file"
test "$(wc -c <"$tmp/file")" -eq 1024
hash=$(sha256sum "$tmp/file" | cut -d' ' -f1)
code=$(curl -sS --max-time 25 -o "$tmp/upload" -w '%{http_code}' -X POST -H "Authorization: Bearer $service" -H "apikey: $service" -H 'Content-Type: application/octet-stream' -H 'x-upsert: false' --data-binary "@$tmp/file" "$url")
case "$code" in 2*) ;; *) echo "Local private upload failed ($code)"; exit 1;; esac
code=$(curl -sS --max-time 25 -o "$tmp/anon" -w '%{http_code}' -H "Authorization: Bearer $anon" -H "apikey: $anon" "$url")
case "$code" in 4*) ;; *) echo "Anonymous read was not denied ($code)"; exit 1;; esac
code=$(curl -sS --max-time 25 -o "$tmp/anon_write" -w '%{http_code}' -X POST -H "Authorization: Bearer $anon" -H "apikey: $anon" -H 'Content-Type: application/octet-stream' -H 'x-upsert: false' --data-binary "@$tmp/file" "$url-anon")
case "$code" in 4*) ;; *) echo "Anonymous write was not denied ($code)"; exit 1;; esac
printf 'different' >"$tmp/different"
code=$(curl -sS --max-time 25 -o "$tmp/duplicate" -w '%{http_code}' -X POST -H "Authorization: Bearer $service" -H "apikey: $service" -H 'Content-Type: application/octet-stream' -H 'x-upsert: false' --data-binary "@$tmp/different" "$url")
case "$code" in 4*) ;; *) echo "Object overwrite was not denied ($code)"; exit 1;; esac
curl -fsS --max-time 25 -o "$tmp/download" -H "Authorization: Bearer $service" -H "apikey: $service" "$url"
cmp "$tmp/file" "$tmp/download"
psql "$DB" -v ON_ERROR_STOP=1 -qAt <<SQL
SET ROLE service_role;
SELECT public.romax_finish_attachment_download('e4c20000-0000-4000-8000-000000000001','e4c20000-0000-4000-8000-000000000003','e4c20000-0000-4000-8000-000000000002','2026-01-01T00:00:00Z','e4c20000-0000-4000-8000-000000000004','$attempt','$hash',1024,NULL);
SQL
test "$(psql "$DB" -Atc "SELECT availability_status||':'||scan_status||':'||(storage_path IS NULL)::text FROM public.romax_opportunity_attachments WHERE id='e4c20000-0000-4000-8000-000000000004'")" = 'quarantined:pending:true'
unset service anon
echo ROMAX_GMAIL4C1_STORAGE_HTTP=PASS
