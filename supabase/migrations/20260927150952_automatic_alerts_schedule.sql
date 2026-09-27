-- =========================================================================
-- Fase 1 · Punto 8 — Alertas automáticas (parte 2: scheduler).
--
-- Habilita pg_cron y programa el wrapper cada hora, más un job diario de
-- limpieza de historial. Sin pg_net, sin Edge Function: los generadores
-- son SQL puro, así que pg_cron los ejecuta directamente.
--
-- Todos los horarios de cron.schedule están en GMT/UTC (documentado por
-- Supabase). El wrapper y los generadores ya comparan siempre timestamptz
-- contra now() — nunca dependen del huso horario del navegador ni de una
-- sesión particular (el generador de inspecciones fija su propio
-- TimeZone=UTC explícitamente, ver la migración anterior).
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- cron.schedule hace upsert por nombre de job: reejecutar esta migración
-- (o un futuro cambio de cadencia) reemplaza el job existente, nunca
-- duplica.
SELECT cron.schedule(
  'automatic-alert-generation',
  '5 * * * *',
  $$SELECT public.run_automatic_alert_generation();$$
);

-- cron.job_run_details NO se limpia automáticamente (documentado por
-- Supabase) y crecería sin límite. cleanup_automatic_alert_history()
-- solo puede definirse aquí: referencia cron.job_run_details, que no
-- existe hasta que se crea la extensión arriba.
CREATE OR REPLACE FUNCTION public.cleanup_automatic_alert_history()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.automatic_alert_runs WHERE created_at < now() - interval '30 days';
  DELETE FROM cron.job_run_details WHERE start_time < now() - interval '30 days';
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_automatic_alert_history() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'automatic-alert-history-cleanup',
  '30 3 * * *',
  $$SELECT public.cleanup_automatic_alert_history();$$
);
