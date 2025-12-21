-- Añadir el valor 'anulado' al enum request_status
ALTER TYPE public.request_status ADD VALUE IF NOT EXISTS 'anulado';