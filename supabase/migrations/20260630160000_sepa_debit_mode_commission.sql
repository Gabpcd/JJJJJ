-- SEPA prélèvement automatique de la commission — activation de bout en bout.
--
-- CONSTAT : le front (ProfilEtablissement) proposait déjà « Prélèvement SEPA » et
-- l'edge function setup-sepa écrit mode_paiement_commission='SEPA_DEBIT' + iban_last4,
-- MAIS :
--   1. la contrainte CHECK de etablissements.mode_paiement_commission n'autorisait pas
--      'SEPA_DEBIT' (seulement STRIPE_RESERVATION / FACTURE_MENSUELLE / CHORUS_PRO) ;
--   2. la colonne iban_last4 n'existait pas ;
--   3. aucun cron n'appelait sepa-auto-charge.
-- Résultat : sélectionner SEPA échouait silencieusement (violation de contrainte +
-- colonne manquante) et aucune facture n'était jamais prélevée. La fonctionnalité
-- était construite mais débranchée.
--
-- On laisse donc le CHOIX à l'établissement (SEPA automatique OU facture mensuelle par
-- virement) en rendant SEPA réellement fonctionnel — on n'impose rien.

-- 1. Autoriser SEPA_DEBIT comme mode de paiement de la commission
ALTER TABLE public.etablissements DROP CONSTRAINT IF EXISTS etablissements_mode_paiement_commission_check;
ALTER TABLE public.etablissements ADD CONSTRAINT etablissements_mode_paiement_commission_check
  CHECK (mode_paiement_commission = ANY (ARRAY['STRIPE_RESERVATION'::text, 'FACTURE_MENSUELLE'::text, 'SEPA_DEBIT'::text, 'CHORUS_PRO'::text]));

-- 2. Colonne iban_last4 (écrite par setup-sepa lors de la signature du mandat SEPA)
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS iban_last4 text;

-- 3. Cron : prélèvement SEPA quotidien des factures de commission EMISE non encore tentées.
--    Quotidien (et non mensuel) pour couvrir les factures générées hors du 1er du mois ;
--    l'idempotence est garantie côté edge function (filtre stripe_payment_intent_id IS NULL),
--    donc aucune facture n'est prélevée deux fois. Auth = service_role lu depuis le vault
--    (même schéma que sync-chorus-status).
DO $unsched$
BEGIN
  PERFORM cron.unschedule('sepa-auto-charge-daily');
EXCEPTION WHEN OTHERS THEN NULL;
END $unsched$;

SELECT cron.schedule('sepa-auto-charge-daily', '0 6 * * *', $cron$
  SELECT net.http_post(
    url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/sepa-auto-charge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
$cron$);
