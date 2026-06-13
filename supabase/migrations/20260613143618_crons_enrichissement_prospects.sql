-- Crons d'enrichissement automatique des prospects depuis l'Annuaire Santé.
-- Appellent enrich-prospects-annuaire en continu (50/run) jusqu'à épuisement.
-- Étabs aux minutes paires, soignants aux impaires (stagger anti-saturation
-- de l'API ANS). Bearer = service_role_key du vault (pattern crons Jolene).
-- cron.schedule remplace le job s'il existe déjà (idempotent).

SELECT cron.schedule('enrich-prospects-etab', '*/2 * * * *', $job$
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/enrich-prospects-annuaire',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{"cible":"ETABLISSEMENT","limite":50}'::jsonb,
    timeout_milliseconds := 120000);
$job$);

SELECT cron.schedule('enrich-prospects-soignant', '1-59/2 * * * *', $job$
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/enrich-prospects-annuaire',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{"cible":"SOIGNANT","limite":50}'::jsonb,
    timeout_milliseconds := 120000);
$job$);
