-- =============================================================================
-- NOTIFICACIONES PUSH — SQL de infraestructura
-- Ejecutar en el SQL Editor de Supabase DESPUÉS de desplegar las Edge Functions
-- =============================================================================

-- 1. Tabla para evitar enviar recordatorios duplicados
CREATE TABLE IF NOT EXISTS sent_reminders (
  match_no  INTEGER PRIMARY KEY,
  sent_at   TIMESTAMPTZ DEFAULT now()
);

-- Limpieza automática: borrar reminders de más de 2 días
-- (se ejecuta cada día a las 3 AM UTC)
SELECT cron.schedule(
  'clean-sent-reminders',
  '0 3 * * *',
  $$ DELETE FROM sent_reminders WHERE sent_at < now() - INTERVAL '2 days' $$
);

-- 2. pg_cron: recordatorio 20 min antes del partido (cada 5 minutos)
SELECT cron.schedule(
  'match-reminders',
  '*/5 * * * *',
  format(
    $$ SELECT net.http_post(
         url     := %L,
         headers := %L::jsonb,
         body    := '{}'::jsonb
       ) $$,
    'https://blqglkqywmchqrtsqcxi.supabase.co/functions/v1/match-reminders',
    json_build_object('Authorization', 'Bearer sb_publishable_1SdbwZXSpp9tLybeubtGXQ_tu1AIMBA', 'Content-Type', 'application/json')::text
  )
);

-- 3. pg_cron: resumen matutino a las 12:00 UTC (8:00 AM Venezuela)
SELECT cron.schedule(
  'daily-digest',
  '0 12 * * *',
  format(
    $$ SELECT net.http_post(
         url     := %L,
         headers := %L::jsonb,
         body    := '{}'::jsonb
       ) $$,
    'https://blqglkqywmchqrtsqcxi.supabase.co/functions/v1/daily-digest',
    json_build_object('Authorization', 'Bearer sb_publishable_1SdbwZXSpp9tLybeubtGXQ_tu1AIMBA', 'Content-Type', 'application/json')::text
  )
);

-- Verificar que los cron jobs quedaron registrados:
SELECT jobname, schedule, command FROM cron.job;
