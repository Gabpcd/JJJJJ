-- ============================================================
-- Baseline prod Jolene — pg_cron jobs (cron.job)
-- Extrait le 2026-07-03 (projet flripxtsyegjshnhzjkz)
-- 46 jobs — commandes complètes, tri par jobname
-- ============================================================

-- jobid=11 | active=t | schedule=0 8 * * *
-- job: alerter-paiements-retard
SELECT fn_alerter_paiements_retard(); SELECT fn_gerer_blocage_etabs();

-- jobid=3 | active=t | schedule=0 3 * * 0
-- job: anonymiser-gps
SELECT fn_anonymiser_gps_anciennes()

-- jobid=50 | active=t | schedule=20 * * * *
-- job: auto-confirmer-honoraires
SELECT fn_auto_confirmer_honoraires()

-- jobid=2 | active=t | schedule=0 2 1 * *
-- job: auto-facturation-mensuelle
SELECT fn_auto_facturation_mensuelle()

-- jobid=13 | active=t | schedule=*/10 * * * *
-- job: auto-transitions-missions
SELECT fn_auto_transitions_missions();

-- jobid=8 | active=t | schedule=0 6 * * *
-- job: auto-valider-presences-72h
SELECT fn_auto_valider_presences_72h()

-- jobid=46 | active=t | schedule=0 11 * * *
-- job: avis-parrainage-post-mission
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/avis-parrainage',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)

-- jobid=7 | active=t | schedule=0 3 2 1 *
-- job: calculer-bfa-annuel
SELECT fn_calculer_bfa_tous()

-- jobid=1 | active=t | schedule=0 7 * * *
-- job: check-expiring-docs
SELECT fn_verifier_documents_expirants()

-- jobid=58 | active=t | schedule=23 * * * *
-- job: cleanup-missions-test-horaire
SELECT public.fn_cleanup_missions_test()

-- jobid=62 | active=t | schedule=10 * * * *
-- job: confirmations-presence-j1
SELECT public.fn_demander_confirmations_presence()

-- jobid=49 | active=t | schedule=*/10 * * * *
-- job: detecter-noshow-remplacer
SELECT fn_detecter_noshow_et_remplacer()

-- jobid=45 | active=t | schedule=0 9 * * 4
-- job: digest-hebdo-soignants
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/digest-hebdo',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)

-- jobid=20 | active=t | schedule=0 8 * * *
-- job: email-cron-daily
SELECT net.http_post(
  url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/email-cron',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 60000
);

-- jobid=23 | active=t | schedule=0 * * * *
-- job: email-cron-hourly-immediate
    SELECT net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/email-cron',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    );

-- jobid=51 | active=t | schedule=*/2 * * * *
-- job: enrich-prospects-etab
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/enrich-prospects-annuaire',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{"cible":"ETABLISSEMENT","limite":50}'::jsonb,
    timeout_milliseconds := 120000);

-- jobid=52 | active=t | schedule=1-59/2 * * * *
-- job: enrich-prospects-soignant
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/enrich-prospects-annuaire',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{"cible":"SOIGNANT","limite":50}'::jsonb,
    timeout_milliseconds := 120000);

-- jobid=56 | active=t | schedule=*/10 * * * *
-- job: escalade-remplacement-non-pourvu
SELECT fn_escalade_remplacement_non_pourvu()

-- jobid=59 | active=t | schedule=*/20 * * * *
-- job: expirer-candidatures-demarrees
SELECT public.fn_expirer_candidatures_missions_demarrees()

-- jobid=44 | active=t | schedule=45 * * * *
-- job: gerer-blocage-etabs-hourly
SELECT fn_gerer_blocage_etabs()

-- jobid=31 | active=t | schedule=0 9 * * *
-- job: jolene_alert_reclamations_pending
SELECT public.fn_alerte_reclamations_pending_old()

-- jobid=32 | active=t | schedule=*/15 * * * *
-- job: jolene_alerte_teleportation
SELECT public.fn_detecter_teleportations()

-- jobid=27 | active=t | schedule=30 3 * * *
-- job: jolene_nettoyer_tokens_push
SELECT public.fn_nettoyer_tokens_push()

-- jobid=30 | active=t | schedule=*/5 * * * *
-- job: jolene_process_externalisations
SELECT net.http_post(url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/process-externalisation-actions', headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)), body := '{}'::jsonb)

-- jobid=36 | active=t | schedule=0 3 * * *
-- job: jolene_purger_pings_gps
SELECT public.fn_purger_pings_gps_anciens()

-- jobid=28 | active=t | schedule=0 9 * * *
-- job: jolene_rappel_dpae_quotidien
SELECT public.fn_rappel_dpae_quotidien()

-- jobid=29 | active=t | schedule=*/15 * * * *
-- job: jolene_rappel_pointage
SELECT public.fn_rappel_pointage_arrivee()

-- jobid=26 | active=t | schedule=15 */6 * * *
-- job: jolene_valider_presences_72h
SELECT public.fn_valider_presences_72h_auto()

-- jobid=37 | active=t | schedule=*/30 * * * *
-- job: jolene_verifier_pointages_incoherents
SELECT public.fn_verifier_pointages_incoherents()

-- jobid=21 | active=t | schedule=0 7 * * *
-- job: litige-escalation-cron
SELECT net.http_post(
  url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/litige-escalation-cron',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 30000
);

-- jobid=38 | active=t | schedule=0 * * * *
-- job: matching_scores_recalcul_hourly
SELECT public.fn_recalculer_scores_soignants_actifs();

-- jobid=24 | active=t | schedule=30 * * * *
-- job: monitoring-health-check-hourly
    SELECT public.fn_check_crons_health();
    SELECT public.fn_check_stripe_webhook_health();

-- jobid=10 | active=t | schedule=15 * * * *
-- job: nettoyage-rate-limits
DELETE FROM rate_limits WHERE premiere_tentative < NOW() - INTERVAL '2 hours'

-- jobid=9 | active=t | schedule=0 4 * * *
-- job: nettoyer-missions-fantomes
SELECT fn_nettoyer_missions_fantomes()

-- jobid=60 | active=t | schedule=47 * * * *
-- job: notifier-favoris-expirants
SELECT public.fn_notifier_favoris_expirants()

-- jobid=17 | active=t | schedule=*/15 * * * *
-- job: process-stripe-refunds-15min
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/process-stripe-refunds',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );

-- jobid=6 | active=t | schedule=0 1 1 * *
-- job: recalculer-paliers-commission
SELECT fn_recalculer_tous_paliers()

-- jobid=55 | active=t | schedule=0 9 * * *
-- job: relance-candidatures-en-attente
SELECT public.fn_relancer_candidatures_en_attente()

-- jobid=43 | active=t | schedule=30 8 * * *
-- job: relance-missions-sans-candidat
SELECT fn_relancer_missions_sans_candidat()

-- jobid=47 | active=t | schedule=0 10 * * 1
-- job: relance-soignants-inactifs
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/relance-inactifs',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)

-- jobid=39 | active=t | schedule=0 8 * * *
-- job: sales-relance-auto
UPDATE public.sales_contacts SET statut='RELANCE', maj_le=now()
      WHERE statut='CONTACTE' AND archive=false AND maj_le < now() - interval '7 days'

-- jobid=57 | active=t | schedule=0 6 * * *
-- job: sepa-auto-charge-daily
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/sepa-auto-charge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );

-- jobid=18 | active=t | schedule=0 7-22/2 * * *
-- job: sync-chorus-status-hourly
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/sync-chorus-status',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );

-- jobid=61 | active=t | schedule=*/15 * * * *
-- job: vagues-notification-urgentes
SELECT public.fn_vagues_notification_urgentes()

-- jobid=14 | active=t | schedule=*/5 * * * *
-- job: warm-edge-functions
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/verify-document',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"warm": true}'::jsonb
  );
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-sms',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"warm": true}'::jsonb
  );

-- jobid=22 | active=t | schedule=0 4 * * *
-- job: weekly-invoicing
SELECT net.http_post(
  url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/weekly-invoicing-cron',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 120000
);

-- Fin — 46 jobs.
