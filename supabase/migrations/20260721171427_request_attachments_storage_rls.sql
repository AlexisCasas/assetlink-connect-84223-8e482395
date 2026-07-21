-- Private request-detail attachments. Object names follow:
-- request-details/{request_id}/{safe-random-filename}
INSERT INTO storage.buckets (id, name, public)
VALUES ('request-detail-attachments', 'request-detail-attachments', false)
ON CONFLICT (id) DO UPDATE SET public = false;

CREATE OR REPLACE FUNCTION public.storage_request_id_from_name(object_name text)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  path_parts text[];
BEGIN
  path_parts := string_to_array(object_name, '/');

  IF path_parts IS NULL
    OR array_length(path_parts, 1) < 3
    OR path_parts[1] <> 'request-details'
    OR path_parts[2] IS NULL
    OR path_parts[2] = ''
    OR path_parts[3] IS NULL
    OR path_parts[3] = '' THEN
    RETURN NULL;
  END IF;

  RETURN path_parts[2]::uuid;
EXCEPTION
  WHEN invalid_text_representation THEN
    RETURN NULL;
END;
$$;

-- Remove only policies that currently grant access to this bucket. The legacy
-- shared request-bucket policies are recreated below without this bucket so
-- their existing behavior for request documents and images is preserved.
DO $$
DECLARE
  policy_record record;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND (
        coalesce(qual, '') LIKE '%request-detail-attachments%'
        OR coalesce(with_check, '') LIKE '%request-detail-attachments%'
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', policy_record.policyname);
  END LOOP;
END $$;

-- Preserve the legacy behavior of the two unrelated request buckets.
CREATE POLICY "auth read request documents and images" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id IN ('request-documents', 'request-images'));
CREATE POLICY "auth insert request documents and images" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id IN ('request-documents', 'request-images'));
CREATE POLICY "auth update request documents and images" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id IN ('request-documents', 'request-images'))
  WITH CHECK (bucket_id IN ('request-documents', 'request-images'));
CREATE POLICY "auth delete request documents and images" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id IN ('request-documents', 'request-images'));

CREATE POLICY "organization members can view request detail attachments" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'request-detail-attachments'
    AND (
      (SELECT public.is_platform_admin())
      OR EXISTS (
        SELECT 1
        FROM public.requests request
        WHERE request.id = public.storage_request_id_from_name(name)
          AND request.organization_id IS NOT NULL
          AND (SELECT public.is_organization_member(request.organization_id))
      )
    )
  );

CREATE POLICY "request members can upload request detail attachments" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'request-detail-attachments'
    AND (
      (SELECT public.is_platform_admin())
      OR EXISTS (
        SELECT 1
        FROM public.requests request
        WHERE request.id = public.storage_request_id_from_name(name)
          AND request.organization_id IS NOT NULL
          AND (SELECT public.has_organization_role(
            request.organization_id,
            ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
          ))
      )
    )
  );

CREATE POLICY "request members can update request detail attachments" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'request-detail-attachments'
    AND (
      (SELECT public.is_platform_admin())
      OR EXISTS (
        SELECT 1
        FROM public.requests request
        WHERE request.id = public.storage_request_id_from_name(name)
          AND request.organization_id IS NOT NULL
          AND (SELECT public.has_organization_role(
            request.organization_id,
            ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
          ))
      )
    )
  )
  WITH CHECK (
    bucket_id = 'request-detail-attachments'
    AND (
      (SELECT public.is_platform_admin())
      OR EXISTS (
        SELECT 1
        FROM public.requests request
        WHERE request.id = public.storage_request_id_from_name(name)
          AND request.organization_id IS NOT NULL
          AND (SELECT public.has_organization_role(
            request.organization_id,
            ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
          ))
      )
    )
  );

CREATE POLICY "request members can delete request detail attachments" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'request-detail-attachments'
    AND (
      (SELECT public.is_platform_admin())
      OR EXISTS (
        SELECT 1
        FROM public.requests request
        WHERE request.id = public.storage_request_id_from_name(name)
          AND request.organization_id IS NOT NULL
          AND (SELECT public.has_organization_role(
            request.organization_id,
            ARRAY['owner', 'admin', 'manager', 'requester']::public.organization_member_role[]
          ))
      )
    )
  );
