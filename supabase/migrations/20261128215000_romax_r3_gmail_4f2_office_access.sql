-- R3-GMAIL.4F.2: extend only the existing service-only release allowlist. No data updates.
CREATE OR REPLACE FUNCTION romax_docs_private.unscanned_access(p_org uuid,p_opportunity uuid,p_actor uuid,p_attachment uuid,
 p_ack boolean,p_commit boolean,p_attempt uuid,p_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d public.romax_opportunity_attachments%ROWTYPE; a romax_docs_private.download_attempts%ROWTYPE;
BEGIN
 IF p_ack IS DISTINCT FROM true OR p_commit IS NULL OR p_actor IS NULL THEN RAISE EXCEPTION 'Explicit acknowledgement required' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM public.organizations WHERE id=p_org AND status='active' AND organization_type='provider_company' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.organization_members WHERE organization_id=p_org AND user_id=p_actor AND is_active AND role='owner' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.romax_opportunities WHERE organization_id=p_org AND id=p_opportunity FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO d FROM public.romax_opportunity_attachments WHERE organization_id=p_org AND opportunity_id=p_opportunity AND id=p_attachment FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
 -- Owner approved temporary Office exception; no claim of structural validation or clean scan.
 IF d.availability_status NOT IN ('quarantined','released_unscanned') OR d.scan_status<>'pending'
 OR d.processing_status<>'downloaded' OR d.restriction_code IS NOT NULL OR d.checksum_sha256 IS NULL
 OR d.size_bytes IS NULL OR d.size_bytes NOT BETWEEN 1 AND 10485760
 OR d.mime_type IS NULL OR d.mime_type NOT IN ('application/pdf','image/jpeg','image/png','text/plain','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.wordprocessingml.document')
 OR d.source_system<>'gmail' OR d.storage_path IS NOT NULL
 THEN RAISE EXCEPTION 'Document not eligible' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM romax_docs_private.download_attempts WHERE organization_id=p_org AND opportunity_id=p_opportunity
 AND attachment_id=p_attachment AND state='quarantined' AND checksum_sha256=d.checksum_sha256 AND size_bytes=d.size_bytes
 ORDER BY created_at DESC,id LIMIT 1 FOR SHARE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='romax-request-attachments'
 AND o.name=a.object_path AND o.metadata->>'size'=d.size_bytes::text)
 THEN RAISE EXCEPTION 'Document object unavailable' USING ERRCODE='22023'; END IF;
 IF NOT p_commit THEN
   IF p_attempt IS NOT NULL OR p_hash IS NOT NULL THEN RAISE EXCEPTION 'Invalid prepare' USING ERRCODE='22023'; END IF;
   RETURN jsonb_build_object('attempt',a.id,'path',a.object_path,'hash',a.checksum_sha256,'size',a.size_bytes,'mime',d.mime_type);
 END IF;
 IF p_attempt IS DISTINCT FROM a.id OR p_hash IS DISTINCT FROM a.checksum_sha256 THEN RAISE EXCEPTION 'Document changed' USING ERRCODE='40001'; END IF;
 IF d.availability_status='quarantined' THEN
   UPDATE public.romax_opportunity_attachments SET availability_status='released_unscanned' WHERE id=d.id;
   INSERT INTO romax_docs_private.attachment_events(organization_id,opportunity_id,attachment_id,actor_id,operation,previous_state,next_state,reason_code)
   VALUES(p_org,p_opportunity,p_attachment,p_actor,'state_changed','quarantined','released_unscanned','unscanned_risk_accepted');
 END IF;
 INSERT INTO romax_docs_private.attachment_events(organization_id,opportunity_id,attachment_id,actor_id,operation,previous_state,next_state,reason_code)
 VALUES(p_org,p_opportunity,p_attachment,p_actor,'accessed_unscanned','released_unscanned','released_unscanned','unscanned_risk_accepted');
 RETURN jsonb_build_object('status','released_unscanned');
END; $$;
REVOKE ALL ON FUNCTION romax_docs_private.unscanned_access(uuid,uuid,uuid,uuid,boolean,boolean,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION romax_docs_private.unscanned_access(uuid,uuid,uuid,uuid,boolean,boolean,uuid,text) TO service_role;
