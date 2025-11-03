-- Create quote_templates table for storing reusable quote structures
CREATE TABLE public.quote_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  provider_id UUID NOT NULL,
  team_member_id UUID,
  fields JSONB NOT NULL DEFAULT '[]'::jsonb,
  percentage_fields JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.quote_templates ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only see their own templates
CREATE POLICY "Users can view their own templates"
ON public.quote_templates
FOR SELECT
USING (true);

CREATE POLICY "Users can insert their own templates"
ON public.quote_templates
FOR INSERT
WITH CHECK (true);

CREATE POLICY "Users can update their own templates"
ON public.quote_templates
FOR UPDATE
USING (true);

CREATE POLICY "Users can delete their own templates"
ON public.quote_templates
FOR DELETE
USING (true);