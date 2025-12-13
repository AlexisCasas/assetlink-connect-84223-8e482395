-- Create table for client-defined specialties
CREATE TABLE public.client_specialties (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  client_email text NOT NULL,
  name text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE(client_email, name)
);

-- Enable RLS
ALTER TABLE public.client_specialties ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Clients can view their own specialties" 
ON public.client_specialties 
FOR SELECT 
USING (true);

CREATE POLICY "Clients can insert their own specialties" 
ON public.client_specialties 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Clients can update their own specialties" 
ON public.client_specialties 
FOR UPDATE 
USING (true);

CREATE POLICY "Clients can delete their own specialties" 
ON public.client_specialties 
FOR DELETE 
USING (true);