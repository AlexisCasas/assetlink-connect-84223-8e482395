
-- Enum
DO $$ BEGIN
  CREATE TYPE public.certification_status AS ENUM ('not_started','in_review','certified','rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- provider_profiles
CREATE TABLE IF NOT EXISTS public.provider_profiles (
  provider_id uuid PRIMARY KEY,
  owner_user_id uuid NOT NULL,
  contact_name text,
  contact_email text,
  phone text,
  whatsapp_phone text,
  position text,
  business_name text,
  commercial_name text,
  tax_id text,
  country text,
  currency text,
  timezone text,
  fiscal_address text,
  city text,
  region text,
  website text,
  industry text,
  logo_url text,
  company_description text,
  foundation_year integer,
  employee_range text,
  coverage_area text,
  presentation_letter_url text,
  presentation_letter_name text,
  receive_all_invitations boolean NOT NULL DEFAULT false,
  certification_status public.certification_status NOT NULL DEFAULT 'not_started',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.provider_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_read_provider_profiles" ON public.provider_profiles
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "owner_insert_provider_profiles" ON public.provider_profiles
  FOR INSERT TO authenticated WITH CHECK (owner_user_id = auth.uid());

CREATE POLICY "owner_update_provider_profiles" ON public.provider_profiles
  FOR UPDATE TO authenticated USING (owner_user_id = auth.uid()) WITH CHECK (owner_user_id = auth.uid());

CREATE POLICY "owner_delete_provider_profiles" ON public.provider_profiles
  FOR DELETE TO authenticated USING (owner_user_id = auth.uid());

CREATE TRIGGER trg_provider_profiles_updated
  BEFORE UPDATE ON public.provider_profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- provider_commercial_clients
CREATE TABLE IF NOT EXISTS public.provider_commercial_clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL,
  business_name text NOT NULL,
  contact_person text,
  email text,
  phone text,
  extension text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.provider_commercial_clients ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_read_pcc" ON public.provider_commercial_clients
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "owner_cud_pcc" ON public.provider_commercial_clients
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.provider_profiles pp WHERE pp.provider_id = provider_commercial_clients.provider_id AND pp.owner_user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.provider_profiles pp WHERE pp.provider_id = provider_commercial_clients.provider_id AND pp.owner_user_id = auth.uid()));

CREATE TRIGGER trg_pcc_updated
  BEFORE UPDATE ON public.provider_commercial_clients
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- provider_documents
CREATE TABLE IF NOT EXISTS public.provider_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL,
  document_type text NOT NULL,
  file_name text NOT NULL,
  file_url text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.provider_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_read_pd" ON public.provider_documents
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "owner_cud_pd" ON public.provider_documents
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.provider_profiles pp WHERE pp.provider_id = provider_documents.provider_id AND pp.owner_user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.provider_profiles pp WHERE pp.provider_id = provider_documents.provider_id AND pp.owner_user_id = auth.uid()));

CREATE TRIGGER trg_pd_updated
  BEFORE UPDATE ON public.provider_documents
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Storage buckets
INSERT INTO storage.buckets (id, name, public) VALUES ('provider-logos','provider-logos', true)
  ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('provider-documents','provider-documents', false)
  ON CONFLICT (id) DO NOTHING;

-- Storage policies: provider-logos (public read, authenticated write to own folder)
CREATE POLICY "provider_logos_public_read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'provider-logos');

CREATE POLICY "provider_logos_auth_write" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'provider-logos');

CREATE POLICY "provider_logos_auth_update" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'provider-logos');

CREATE POLICY "provider_logos_auth_delete" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'provider-logos');

-- Storage policies: provider-documents (authenticated read/write)
CREATE POLICY "provider_docs_auth_read" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'provider-documents');

CREATE POLICY "provider_docs_auth_write" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'provider-documents');

CREATE POLICY "provider_docs_auth_update" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'provider-documents');

CREATE POLICY "provider_docs_auth_delete" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'provider-documents');
