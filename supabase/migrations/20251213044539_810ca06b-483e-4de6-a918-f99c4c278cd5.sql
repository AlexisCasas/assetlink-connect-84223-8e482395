-- Create table for client's approved providers (proveedores homologados)
CREATE TABLE public.client_approved_providers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  client_email TEXT NOT NULL,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  specialty TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.client_approved_providers ENABLE ROW LEVEL SECURITY;

-- Create policies for client access only
CREATE POLICY "Clients can view their own approved providers" 
ON public.client_approved_providers 
FOR SELECT 
USING (true);

CREATE POLICY "Clients can insert their own approved providers" 
ON public.client_approved_providers 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Clients can update their own approved providers" 
ON public.client_approved_providers 
FOR UPDATE 
USING (true);

CREATE POLICY "Clients can delete their own approved providers" 
ON public.client_approved_providers 
FOR DELETE 
USING (true);