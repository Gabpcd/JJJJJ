-- ============================================================
-- CP-C-5 C.2 — CHECK notifications + cron sync-chorus-status
-- ============================================================
-- A. Étend notifications_type_check pour inclure les 5 types CHORUS_*
--    émis par sync-chorus-status (C5-C.1).
-- B. Schedule cron pg_cron qui appelle sync-chorus-status toutes
--    les 2h entre 7h et 22h UTC (8 runs/jour).
-- ============================================================

-- A. CHECK notifications.type : ajout des types CHORUS_*
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'CANDIDATURE_ACCEPTEE'::text, 'CANDIDATURE_REFUSEE'::text, 'CANDIDATURE_PROPOSEE'::text,
    'MISSION_ACCEPTEE'::text, 'MISSION_ANNULEE'::text, 'MISSION_TERMINEE'::text, 'MISSION_URGENTE'::text, 'MISSION_NON_POURVUE'::text,
    'CONTRAT_A_SIGNER'::text, 'CONTRAT_SIGNE'::text,
    'FACTURE_EMISE'::text, 'FACTURE_PAYEE'::text,
    'DOCUMENT_EXPIRANT'::text, 'RAPPEL_DOCUMENTS'::text, 'DOCUMENT_VERIFIE'::text, 'DOCUMENT_REJETE'::text,
    'MESSAGE_RECU'::text, 'MESSAGE_ADMIN'::text,
    'POINTAGE_ARRIVEE'::text, 'POINTAGE_DEPART'::text,
    'EVALUATION_RECUE'::text, 'PARRAINAGE'::text,
    'RAPPEL_MISSION'::text, 'POOL_URGENCE'::text,
    'SYSTEM'::text,
    'LITIGE_OUVERT'::text, 'LITIGE_REPONSE'::text, 'LITIGE_RESOLU'::text, 'LITIGE_MEDIATION'::text,
    'CHORUS_DEPOSEE'::text, 'CHORUS_MISE_A_DISPOSITION'::text,
    'CHORUS_PAIEMENT_EN_COURS'::text, 'CHORUS_PAIEMENT_COMPTABILISE'::text,
    'CHORUS_REJETEE'::text
  ]));

-- B. Cron sync-chorus-status toutes les 2h entre 7h et 22h UTC
-- D'abord unschedule si existe (idempotent)
DO $$
BEGIN
  PERFORM cron.unschedule('sync-chorus-status-hourly');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'sync-chorus-status-hourly',
  '0 7-22/2 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/sync-chorus-status',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $cron$
);
