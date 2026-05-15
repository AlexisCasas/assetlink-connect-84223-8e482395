
-- 1. Enum de roles
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('cliente', 'proveedor', 'team_member');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 2. Tabla profiles
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  name text,
  provider_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. Tabla user_roles
CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- 4. Función has_role (security definer, evita recursión RLS)
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

-- 5. Trigger handle_new_user: crea perfil + rol al registrarse
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _role public.app_role;
BEGIN
  INSERT INTO public.profiles (id, email, name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;

  -- Asigna rol desde metadata (default cliente)
  BEGIN
    _role := COALESCE((NEW.raw_user_meta_data->>'role')::public.app_role, 'cliente'::public.app_role);
  EXCEPTION WHEN others THEN
    _role := 'cliente'::public.app_role;
  END;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, _role)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 6. RLS profiles
DROP POLICY IF EXISTS "Users view own profile" ON public.profiles;
CREATE POLICY "Users view own profile" ON public.profiles
  FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "Users insert own profile" ON public.profiles;
CREATE POLICY "Users insert own profile" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- 7. RLS user_roles (solo lectura propia; escritura solo via trigger / service role)
DROP POLICY IF EXISTS "Users view own roles" ON public.user_roles;
CREATE POLICY "Users view own roles" ON public.user_roles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- 8. Cerrar políticas abiertas: requieren autenticación
-- Helper para reemplazar políticas
DO $$
DECLARE
  t text;
  pol record;
  tables text[] := ARRAY[
    'assignments','chat_messages','notifications','providers',
    'quote_templates','quotes','request_chat_participants',
    'request_details','request_providers','requests','team_members',
    'technical_visit_documents','technical_visits'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    FOR pol IN
      SELECT polname FROM pg_policy
      WHERE polrelid = ('public.'||t)::regclass
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.polname, t);
    END LOOP;
  END LOOP;
END $$;

-- Tablas compartidas: requieren auth, pero acceso amplio (mockup)
CREATE POLICY "auth_all" ON public.assignments FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.chat_messages FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.providers FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.quote_templates FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.quotes FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.request_chat_participants FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.request_details FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.request_providers FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.requests FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.team_members FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.technical_visit_documents FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON public.technical_visits FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Notificaciones: solo destinatario
CREATE POLICY "own_notifications_select" ON public.notifications
  FOR SELECT TO authenticated USING (user_email = (SELECT email FROM auth.users WHERE id = auth.uid()));
CREATE POLICY "own_notifications_update" ON public.notifications
  FOR UPDATE TO authenticated USING (user_email = (SELECT email FROM auth.users WHERE id = auth.uid()));
CREATE POLICY "auth_insert_notifications" ON public.notifications
  FOR INSERT TO authenticated WITH CHECK (true);

-- client_approved_providers / client_specialties: solo dueño
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT polname, tablename FROM (
    SELECT polname, c.relname AS tablename FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    WHERE c.relname IN ('client_approved_providers','client_specialties')
  ) s LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.polname, pol.tablename);
  END LOOP;
END $$;

CREATE POLICY "own_client_approved" ON public.client_approved_providers
  FOR ALL TO authenticated
  USING (client_email = (SELECT email FROM auth.users WHERE id = auth.uid()))
  WITH CHECK (client_email = (SELECT email FROM auth.users WHERE id = auth.uid()));

CREATE POLICY "own_client_specialties" ON public.client_specialties
  FOR ALL TO authenticated
  USING (client_email = (SELECT email FROM auth.users WHERE id = auth.uid()))
  WITH CHECK (client_email = (SELECT email FROM auth.users WHERE id = auth.uid()));

-- Storage buckets: solo autenticados
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
    AND policyname LIKE '%request-%' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "auth read request buckets" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id IN ('request-documents','request-images','request-detail-attachments'));
CREATE POLICY "auth insert request buckets" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id IN ('request-documents','request-images','request-detail-attachments'));
CREATE POLICY "auth update request buckets" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id IN ('request-documents','request-images','request-detail-attachments'));
CREATE POLICY "auth delete request buckets" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id IN ('request-documents','request-images','request-detail-attachments'));
