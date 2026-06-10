-- Lot 1 launch blockers (3/3) — Sécurité : les crons digest/avis/relance passent
-- du secret en dur (présent dans le repo GitHub) au Bearer vault service_role_key,
-- pattern standard du projet (cf. email-cron, process-stripe-refunds).
-- NOTE : déjà appliquée en prod via MCP (version 20260610141039), edge functions
-- redéployées avec bearerAutorise() avant la bascule (testé : vault → 200, ancien
-- secret body → 403).
SELECT cron.unschedule('digest-hebdo-soignants');
SELECT cron.schedule('digest-hebdo-soignants', '0 9 * * 4', $cmd$
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/digest-hebdo',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)
$cmd$);

SELECT cron.unschedule('avis-parrainage-post-mission');
SELECT cron.schedule('avis-parrainage-post-mission', '0 11 * * *', $cmd$
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/avis-parrainage',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)
$cmd$);

SELECT cron.unschedule('relance-soignants-inactifs');
SELECT cron.schedule('relance-soignants-inactifs', '0 10 * * 1', $cmd$
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/relance-inactifs',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)
$cmd$);
