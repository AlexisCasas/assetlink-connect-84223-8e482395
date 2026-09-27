-- Fase 1 · Punto 8
-- Retira el acceso cliente a los generadores legacy de alertas.
--
-- El frontend ya no llama directamente estas funciones.
-- La generación automática se ejecuta mediante:
--   public.run_automatic_alert_generation()
-- invocada por pg_cron.
--
-- Los grants quedan explícitos para garantizar el mismo estado
-- tanto en Supabase local como en hosted.

REVOKE ALL PRIVILEGES
ON FUNCTION public.generate_operational_due_notifications()
FROM PUBLIC, anon, authenticated;

REVOKE ALL PRIVILEGES
ON FUNCTION public.generate_inspection_due_notifications()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.generate_operational_due_notifications()
TO service_role;

GRANT EXECUTE
ON FUNCTION public.generate_inspection_due_notifications()
TO service_role;