-- ============================================================
-- Tests CP-STRIPE-2 — Propagation stripe_payment_intent_id
--                    + transition EMISE → PAYEE factures_honoraires
--                    + guard statut (H4 partiel)
-- ============================================================
-- Prérequis : migration Sub-PR 2 quater appliquée (colonnes
--             factures_honoraires.stripe_payment_intent_id + statut).
-- Périmètre : valide la LOGIQUE SQL qui sera exécutée par les edge
--             functions. Les appels Stripe eux-mêmes sont mockés.
-- Usage    : psql "$DB_URL" -f tests/stripe/cp-stripe-2.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-STRIPE-2 — factures_honoraires.stripe_payment_intent_id =='

-- ------------------------------------------------------------
-- [1] Colonnes cibles existent (sanity checks DDL)
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) = 1 THEN '[1.1] OK — factures_honoraires.stripe_payment_intent_id présente'
  ELSE '[1.1] FAIL — colonne absente'
END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'factures_honoraires'
  AND column_name = 'stripe_payment_intent_id';

SELECT CASE
  WHEN COUNT(*) = 1 THEN '[1.2] OK — factures_honoraires.mode_paiement présente'
  ELSE '[1.2] FAIL — colonne absente'
END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'factures_honoraires'
  AND column_name = 'mode_paiement';

SELECT CASE
  WHEN COUNT(*) = 1 THEN '[1.3] OK — factures_honoraires.date_paiement présente'
  ELSE '[1.3] FAIL — colonne absente'
END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'factures_honoraires'
  AND column_name = 'date_paiement';

-- ------------------------------------------------------------
-- [2] Scénarios UPDATE (5 scenarios — logique webhook simulée)
-- ------------------------------------------------------------

BEGIN;

-- Setup : créer 5 factures_honoraires avec des statuts distincts
DO $$
DECLARE
  v_mission_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_etab_id UUID := gen_random_uuid();
  v_base_num TEXT := 'CP-STRIPE-2-TEST-' || floor(random() * 1000000)::text;
BEGIN
  -- Facture EMISE (cas nominal)
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, cree_le)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001', v_mission_id, v_soignant_id, v_etab_id,
    v_base_num || '-EMISE', 'EMISE', 100.00, 0.00, 100.00, 0.00, FALSE,
    NOW(), NOW() + INTERVAL '30 days', NOW());

  -- Facture EN_RETARD (doit aussi être mise à jour)
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, cree_le)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000002', v_mission_id, v_soignant_id, v_etab_id,
    v_base_num || '-EN_RETARD', 'EN_RETARD', 150.00, 0.00, 150.00, 0.00, FALSE,
    NOW() - INTERVAL '60 days', NOW() - INTERVAL '30 days', NOW() - INTERVAL '60 days');

  -- Facture ANNULEE (ne doit PAS être mise à jour — guard H4)
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, cree_le)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000003', v_mission_id, v_soignant_id, v_etab_id,
    v_base_num || '-ANNULEE', 'ANNULEE', 200.00, 0.00, 200.00, 0.00, FALSE,
    NOW(), NOW() + INTERVAL '30 days', NOW());

  -- Facture REMPLACEE (ne doit PAS être mise à jour — guard H4)
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, cree_le)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000004', v_mission_id, v_soignant_id, v_etab_id,
    v_base_num || '-REMPLACEE', 'REMPLACEE', 250.00, 0.00, 250.00, 0.00, FALSE,
    NOW(), NOW() + INTERVAL '30 days', NOW());

  -- Facture déjà PAYEE (idempotence : rejeu webhook ne doit rien faire)
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, date_paiement,
    stripe_payment_intent_id, cree_le)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000005', v_mission_id, v_soignant_id, v_etab_id,
    v_base_num || '-PAYEE', 'PAYEE', 300.00, 0.00, 300.00, 0.00, FALSE,
    NOW() - INTERVAL '1 day', NOW() + INTERVAL '30 days', CURRENT_DATE - 1,
    'pi_already_paid_123', NOW() - INTERVAL '1 day');
END $$;

-- Simuler le UPDATE du webhook : UPDATE avec guard statut IN ('EMISE', 'EN_RETARD')
UPDATE public.factures_honoraires
   SET stripe_payment_intent_id = 'pi_test_webhook_connect_001',
       statut = 'PAYEE',
       date_paiement = CURRENT_DATE
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'
   AND statut IN ('EMISE', 'EN_RETARD');

UPDATE public.factures_honoraires
   SET stripe_payment_intent_id = 'pi_test_webhook_connect_002',
       statut = 'PAYEE',
       date_paiement = CURRENT_DATE
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000002'
   AND statut IN ('EMISE', 'EN_RETARD');

UPDATE public.factures_honoraires
   SET stripe_payment_intent_id = 'pi_test_webhook_connect_003',
       statut = 'PAYEE',
       date_paiement = CURRENT_DATE
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000003'
   AND statut IN ('EMISE', 'EN_RETARD');

UPDATE public.factures_honoraires
   SET stripe_payment_intent_id = 'pi_test_webhook_connect_004',
       statut = 'PAYEE',
       date_paiement = CURRENT_DATE
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000004'
   AND statut IN ('EMISE', 'EN_RETARD');

UPDATE public.factures_honoraires
   SET stripe_payment_intent_id = 'pi_test_webhook_connect_005_retry',
       statut = 'PAYEE',
       date_paiement = CURRENT_DATE
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000005'
   AND statut IN ('EMISE', 'EN_RETARD');

-- Assertions

-- [2.1] Facture EMISE → PAYEE + PI rempli
SELECT CASE
  WHEN statut = 'PAYEE' AND stripe_payment_intent_id = 'pi_test_webhook_connect_001'
       AND date_paiement IS NOT NULL
    THEN '[2.1] OK — facture EMISE passée à PAYEE + PI rempli + date_paiement'
  ELSE '[2.1] FAIL — statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures_honoraires
WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- [2.2] Facture EN_RETARD → PAYEE + PI rempli
SELECT CASE
  WHEN statut = 'PAYEE' AND stripe_payment_intent_id = 'pi_test_webhook_connect_002'
    THEN '[2.2] OK — facture EN_RETARD passée à PAYEE + PI rempli'
  ELSE '[2.2] FAIL — statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures_honoraires
WHERE id = 'aaaaaaaa-0000-0000-0000-000000000002';

-- [2.3] Facture ANNULEE → inchangée (guard H4)
SELECT CASE
  WHEN statut = 'ANNULEE' AND stripe_payment_intent_id IS NULL
    THEN '[2.3] OK — facture ANNULEE rejetée par guard, inchangée'
  ELSE '[2.3] FAIL — guard cassé, statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures_honoraires
WHERE id = 'aaaaaaaa-0000-0000-0000-000000000003';

-- [2.4] Facture REMPLACEE → inchangée (guard H4)
SELECT CASE
  WHEN statut = 'REMPLACEE' AND stripe_payment_intent_id IS NULL
    THEN '[2.4] OK — facture REMPLACEE rejetée par guard, inchangée'
  ELSE '[2.4] FAIL — guard cassé, statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures_honoraires
WHERE id = 'aaaaaaaa-0000-0000-0000-000000000004';

-- [2.5] Facture déjà PAYEE → PI NE DOIT PAS être remplacé par rejeu (idempotence)
SELECT CASE
  WHEN statut = 'PAYEE' AND stripe_payment_intent_id = 'pi_already_paid_123'
    THEN '[2.5] OK — facture déjà PAYEE rejetée par guard, PI préservé'
  ELSE '[2.5] FAIL — idempotence cassée, PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures_honoraires
WHERE id = 'aaaaaaaa-0000-0000-0000-000000000005';

ROLLBACK;

-- ------------------------------------------------------------
-- [3] Lookup pay-mission (SELECT avec filtres EMISE/EN_RETARD)
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
  v_mission_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_etab_id UUID := gen_random_uuid();
  v_base_num TEXT := 'CP-STRIPE-2-LOOKUP-' || floor(random() * 1000000)::text;
BEGIN
  -- Une facture EMISE
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, cree_le)
  VALUES ('bbbbbbbb-0000-0000-0000-000000000001', v_mission_id, v_soignant_id, v_etab_id,
    v_base_num || '-EMISE', 'EMISE', 100.00, 0.00, 100.00, 0.00, FALSE,
    NOW() - INTERVAL '2 days', NOW() + INTERVAL '28 days', NOW() - INTERVAL '2 days');

  -- Une facture ANNULEE (ne doit pas être retournée)
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, cree_le)
  VALUES ('bbbbbbbb-0000-0000-0000-000000000002', v_mission_id, v_soignant_id, v_etab_id,
    v_base_num || '-ANNULEE', 'ANNULEE', 100.00, 0.00, 100.00, 0.00, FALSE,
    NOW() - INTERVAL '5 days', NOW() + INTERVAL '25 days', NOW() - INTERVAL '5 days');

  -- Lookup comme dans stripe-connect-pay-mission
  PERFORM 1 FROM public.factures_honoraires
    WHERE mission_id = v_mission_id
      AND soignant_id = v_soignant_id
      AND statut IN ('EMISE', 'EN_RETARD')
    ORDER BY date_emission ASC LIMIT 1;

  IF FOUND THEN
    RAISE NOTICE '[3.1] OK — lookup retourne 1 facture EMISE';
  ELSE
    RAISE NOTICE '[3.1] FAIL — lookup ne trouve pas la facture EMISE';
  END IF;
END $$;

ROLLBACK;

-- ------------------------------------------------------------
-- [4] Absence de facture → lookup retourne NULL
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
  v_mission_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_found BOOLEAN;
BEGIN
  -- Aucune facture créée pour cette mission

  v_found := EXISTS(
    SELECT 1 FROM public.factures_honoraires
    WHERE mission_id = v_mission_id
      AND soignant_id = v_soignant_id
      AND statut IN ('EMISE', 'EN_RETARD')
  );

  IF NOT v_found THEN
    RAISE NOTICE '[4.1] OK — lookup vide : pay-mission bloquera avec FACTURE_NON_GENEREE';
  ELSE
    RAISE NOTICE '[4.1] FAIL — facture trouvée alors qu''aucune créée';
  END IF;
END $$;

ROLLBACK;

\echo ''
\echo '== Fin tests CP-STRIPE-2 =='
