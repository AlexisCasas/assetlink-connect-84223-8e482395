-- Agregar campo min_quotes a la tabla requests con valor por defecto 3
ALTER TABLE public.requests ADD COLUMN IF NOT EXISTS min_quotes integer NOT NULL DEFAULT 3;