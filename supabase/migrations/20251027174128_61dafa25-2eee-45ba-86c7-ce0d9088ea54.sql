-- Add support for file attachments in requests
-- Create storage bucket for request documents
INSERT INTO storage.buckets (id, name, public)
VALUES ('request-documents', 'request-documents', false)
ON CONFLICT (id) DO NOTHING;

-- Create storage bucket for request images
INSERT INTO storage.buckets (id, name, public)
VALUES ('request-images', 'request-images', false)
ON CONFLICT (id) DO NOTHING;

-- Add columns for file attachments to requests table
ALTER TABLE public.requests
ADD COLUMN IF NOT EXISTS image_urls text[],
ADD COLUMN IF NOT EXISTS document_urls text[];

-- Create storage policies for request documents
CREATE POLICY "Anyone can upload request documents"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'request-documents');

CREATE POLICY "Anyone can view request documents"
ON storage.objects
FOR SELECT
USING (bucket_id = 'request-documents');

CREATE POLICY "Anyone can delete request documents"
ON storage.objects
FOR DELETE
USING (bucket_id = 'request-documents');

-- Create storage policies for request images
CREATE POLICY "Anyone can upload request images"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'request-images');

CREATE POLICY "Anyone can view request images"
ON storage.objects
FOR SELECT
USING (bucket_id = 'request-images');

CREATE POLICY "Anyone can delete request images"
ON storage.objects
FOR DELETE
USING (bucket_id = 'request-images');