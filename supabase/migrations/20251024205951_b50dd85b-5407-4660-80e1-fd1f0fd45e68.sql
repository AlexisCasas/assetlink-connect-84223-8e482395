-- Create service type enum
CREATE TYPE public.service_type AS ENUM ('emergencia', 'correctivo', 'preventivo', 'proyecto');

-- Create request status enum
CREATE TYPE public.request_status AS ENUM ('draft', 'sent', 'quoted', 'completed');

-- Create requests table
CREATE TABLE public.requests (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  request_number TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  asset TEXT NOT NULL,
  location TEXT NOT NULL,
  service_type service_type NOT NULL,
  observations TEXT,
  deadline TIMESTAMP WITH TIME ZONE NOT NULL,
  start_time TIMESTAMP WITH TIME ZONE,
  status request_status NOT NULL DEFAULT 'draft',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  created_by TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 4,
  client_name TEXT,
  client_branch TEXT,
  is_public BOOLEAN DEFAULT false,
  notified_at TIMESTAMP WITH TIME ZONE
);

-- Create providers table
CREATE TABLE public.providers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  specialties TEXT[] NOT NULL DEFAULT '{}',
  rating DECIMAL(2,1) DEFAULT 0.0,
  certified BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create team members table
CREATE TABLE public.team_members (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_id UUID NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create request_providers junction table (for selected providers)
CREATE TABLE public.request_providers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(request_id, provider_id)
);

-- Create assignments table
CREATE TABLE public.assignments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  team_member_id UUID NOT NULL REFERENCES public.team_members(id) ON DELETE CASCADE,
  team_member_name TEXT NOT NULL,
  assigned_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  max_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
  reason TEXT,
  UNIQUE(request_id, provider_id)
);

-- Create technical visits table
CREATE TABLE public.technical_visits (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  requested_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(request_id, provider_id)
);

-- Create quotes table
CREATE TABLE public.quotes (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
  team_member_id UUID NOT NULL REFERENCES public.team_members(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.technical_visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for public access (since we don't have auth yet)
CREATE POLICY "Anyone can view requests" ON public.requests FOR SELECT USING (true);
CREATE POLICY "Anyone can insert requests" ON public.requests FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update requests" ON public.requests FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete requests" ON public.requests FOR DELETE USING (true);

CREATE POLICY "Anyone can view providers" ON public.providers FOR SELECT USING (true);
CREATE POLICY "Anyone can insert providers" ON public.providers FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update providers" ON public.providers FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete providers" ON public.providers FOR DELETE USING (true);

CREATE POLICY "Anyone can view team_members" ON public.team_members FOR SELECT USING (true);
CREATE POLICY "Anyone can insert team_members" ON public.team_members FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update team_members" ON public.team_members FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete team_members" ON public.team_members FOR DELETE USING (true);

CREATE POLICY "Anyone can view request_providers" ON public.request_providers FOR SELECT USING (true);
CREATE POLICY "Anyone can insert request_providers" ON public.request_providers FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update request_providers" ON public.request_providers FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete request_providers" ON public.request_providers FOR DELETE USING (true);

CREATE POLICY "Anyone can view assignments" ON public.assignments FOR SELECT USING (true);
CREATE POLICY "Anyone can insert assignments" ON public.assignments FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update assignments" ON public.assignments FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete assignments" ON public.assignments FOR DELETE USING (true);

CREATE POLICY "Anyone can view technical_visits" ON public.technical_visits FOR SELECT USING (true);
CREATE POLICY "Anyone can insert technical_visits" ON public.technical_visits FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update technical_visits" ON public.technical_visits FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete technical_visits" ON public.technical_visits FOR DELETE USING (true);

CREATE POLICY "Anyone can view quotes" ON public.quotes FOR SELECT USING (true);
CREATE POLICY "Anyone can insert quotes" ON public.quotes FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update quotes" ON public.quotes FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete quotes" ON public.quotes FOR DELETE USING (true);

-- Create indexes for better query performance
CREATE INDEX idx_requests_status ON public.requests(status);
CREATE INDEX idx_requests_is_public ON public.requests(is_public);
CREATE INDEX idx_requests_priority ON public.requests(priority);
CREATE INDEX idx_request_providers_request_id ON public.request_providers(request_id);
CREATE INDEX idx_request_providers_provider_id ON public.request_providers(provider_id);
CREATE INDEX idx_assignments_request_id ON public.assignments(request_id);
CREATE INDEX idx_assignments_provider_id ON public.assignments(provider_id);
CREATE INDEX idx_technical_visits_request_id ON public.technical_visits(request_id);
CREATE INDEX idx_quotes_request_id ON public.quotes(request_id);