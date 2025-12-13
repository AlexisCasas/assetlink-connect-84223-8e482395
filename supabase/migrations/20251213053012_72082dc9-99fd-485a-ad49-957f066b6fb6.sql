-- Agregar nuevos campos a la tabla requests (cabecera)
ALTER TABLE public.requests 
ADD COLUMN IF NOT EXISTS city text,
ADD COLUMN IF NOT EXISTS store text,
ADD COLUMN IF NOT EXISTS branch text,
ADD COLUMN IF NOT EXISTS requires_visit boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS visit_date timestamp with time zone;

-- Crear tabla de detalle de solicitudes (relación 1 a muchos)
CREATE TABLE public.request_details (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  request_id uuid NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  equipment text,
  sub_equipment text,
  area text,
  sub_area text,
  activities text,
  relevant_materials text,
  quantity numeric,
  unit_measure text,
  observation text,
  responsible_user text,
  delegate_type text CHECK (delegate_type IN ('Tercero', 'Propio')),
  attachment_urls text[],
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Habilitar RLS en request_details
ALTER TABLE public.request_details ENABLE ROW LEVEL SECURITY;

-- Políticas RLS para request_details
CREATE POLICY "Anyone can view request_details"
ON public.request_details
FOR SELECT
USING (true);

CREATE POLICY "Anyone can insert request_details"
ON public.request_details
FOR INSERT
WITH CHECK (true);

CREATE POLICY "Anyone can update request_details"
ON public.request_details
FOR UPDATE
USING (true);

CREATE POLICY "Anyone can delete request_details"
ON public.request_details
FOR DELETE
USING (true);

-- Crear bucket para anexos de detalles si no existe
INSERT INTO storage.buckets (id, name, public)
VALUES ('request-detail-attachments', 'request-detail-attachments', false)
ON CONFLICT (id) DO NOTHING;

-- Políticas de storage para anexos
CREATE POLICY "Anyone can upload detail attachments"
ON storage.objects
FOR INSERT
WITH CHECK (bucket_id = 'request-detail-attachments');

CREATE POLICY "Anyone can view detail attachments"
ON storage.objects
FOR SELECT
USING (bucket_id = 'request-detail-attachments');

CREATE POLICY "Anyone can delete detail attachments"
ON storage.objects
FOR DELETE
USING (bucket_id = 'request-detail-attachments');