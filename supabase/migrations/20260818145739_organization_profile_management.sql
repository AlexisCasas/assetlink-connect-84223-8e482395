CREATE TABLE public.organization_profiles (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  commercial_name text,
  legal_name text,
  tax_id text,
  country text NOT NULL DEFAULT 'Perú',
  currency text NOT NULL DEFAULT 'PEN',
  timezone text NOT NULL DEFAULT 'America/Lima',
  contact_email text,
  phone text,
  whatsapp text,
  website text,
  logo_url text,
  description text,
  founded_year integer,
  employee_range text,
  service_regions text,
  primary_clients jsonb NOT NULL DEFAULT '[]'::jsonb,
  presentation_file_url text,
  certification_status text NOT NULL DEFAULT 'not_requested',
  certification_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT organization_profiles_founded_year_check
    CHECK (founded_year IS NULL OR founded_year BETWEEN 1800 AND EXTRACT(YEAR FROM CURRENT_DATE)::integer + 1),
  CONSTRAINT organization_profiles_primary_clients_array_check
    CHECK (jsonb_typeof(primary_clients) = 'array')
);

ALTER TABLE public.organization_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "organization members can view organization profiles" ON public.organization_profiles;
CREATE POLICY "organization members can view organization profiles"
  ON public.organization_profiles FOR SELECT TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.is_organization_member(organization_id))
  );

DROP POLICY IF EXISTS "organization administrators can create organization profiles" ON public.organization_profiles;
CREATE POLICY "organization administrators can create organization profiles"
  ON public.organization_profiles FOR INSERT TO authenticated
  WITH CHECK (
    updated_by_user_id = auth.uid()
    AND (
      (SELECT public.is_platform_admin())
      OR (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin']::public.organization_member_role[]
      ))
    )
  );

DROP POLICY IF EXISTS "organization administrators can update organization profiles" ON public.organization_profiles;
CREATE POLICY "organization administrators can update organization profiles"
  ON public.organization_profiles FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_platform_admin())
    OR (SELECT public.has_organization_role(
      organization_id,
      ARRAY['owner', 'admin']::public.organization_member_role[]
    ))
  )
  WITH CHECK (
    updated_by_user_id = auth.uid()
    AND (
      (SELECT public.is_platform_admin())
      OR (SELECT public.has_organization_role(
        organization_id,
        ARRAY['owner', 'admin']::public.organization_member_role[]
      ))
    )
  );

DROP TRIGGER IF EXISTS trg_organization_profiles_updated_at ON public.organization_profiles;
CREATE TRIGGER trg_organization_profiles_updated_at
  BEFORE UPDATE ON public.organization_profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

GRANT SELECT, INSERT, UPDATE ON public.organization_profiles TO authenticated;
