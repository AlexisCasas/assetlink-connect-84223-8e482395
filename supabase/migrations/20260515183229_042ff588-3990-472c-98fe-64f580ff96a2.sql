
-- 1. client_branches table
CREATE TABLE IF NOT EXISTS public.client_branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_email text NOT NULL,
  name text NOT NULL,
  city text NOT NULL,
  site text NOT NULL,
  address text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.client_branches ENABLE ROW LEVEL SECURITY;

-- Owner can do everything with own rows
CREATE POLICY "own_client_branches_all"
ON public.client_branches
FOR ALL
TO authenticated
USING (client_email = ((SELECT users.email FROM auth.users WHERE users.id = auth.uid()))::text)
WITH CHECK (client_email = ((SELECT users.email FROM auth.users WHERE users.id = auth.uid()))::text);

-- Allow any authenticated user to read branches (so providers/team members can see the branch on a request)
CREATE POLICY "auth_read_client_branches"
ON public.client_branches
FOR SELECT
TO authenticated
USING (true);

CREATE INDEX IF NOT EXISTS idx_client_branches_client_email ON public.client_branches(client_email);

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_client_branches_updated_at ON public.client_branches;
CREATE TRIGGER trg_client_branches_updated_at
BEFORE UPDATE ON public.client_branches
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- 2. Extend requests table
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS branch_id uuid,
  ADD COLUMN IF NOT EXISTS created_by_user_id uuid,
  ADD COLUMN IF NOT EXISTS created_by_name text,
  ADD COLUMN IF NOT EXISTS created_by_email text;

-- 3. Seed demo branches for the demo client
INSERT INTO public.client_branches (client_email, name, city, site, address, is_active)
VALUES
  ('cliente@test.com', 'Plaza Vea Marina', 'Tacna', 'Marina', 'Av. Marina 123, Tacna', true),
  ('cliente@test.com', 'Plaza Vea Centro', 'Lima', 'Centro', 'Jr. Centro 456, Lima', true),
  ('cliente@test.com', 'Plaza Vea Norte', 'Lima', 'Norte', 'Av. Norte 789, Lima', true),
  ('cliente@test.com', 'Tienda Arequipa Principal', 'Arequipa', 'Principal', 'Calle Principal 321, Arequipa', true)
ON CONFLICT DO NOTHING;
