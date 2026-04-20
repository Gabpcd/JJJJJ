-- ============================================================
-- Tests CP-STRIPE-3 — Guards factures commission + webhook FACTURE
-- ============================================================
-- Prérequis : CP-STRIPE-2 déjà livré, webhook stripe-webhook v212+
-- Périmètre : valide la LOGIQUE SQL du guard statut FACTURE (H4)
--             pour la branche checkout.session.completed FACTURE
--             (paiements commission Jolene par l'étab).
-- Usage    : psql "$DB_URL" -f tests/stripe/cp-stripe-3.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-STRIPE-3 — guards factures commission =='

-- ------------------------------------------------------------
-- [1] Sanity DDL : colonnes cibles existent
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) = 1 THEN '[1.1] OK — factures.stripe_payment_intent_id présente'
  ELSE '[1.1] FAIL — colonne absente'
END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'factures'
  AND column_name = 'stripe_payment_intent_id';

SELECT CASE
  WHEN COUNT(*) = 1 THEN '[1.2] OK — factures.statut présente'
  ELSE '[1.2] FAIL — colonne absente'
END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'factures'
  AND column_name = 'statut';

-- ------------------------------------------------------------
-- [2] Scénarios UPDATE webhook (5 cas)
-- ------------------------------------------------------------

BEGIN;

-- Setup : 5 factures commission avec statuts distincts
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_base_num TEXT := 'CP-STRIPE-3-' || floor(random() * 1000000)::text;
BEGIN
  -- Facture EMISE (cas nominal)
  INSERT INTO public.factures (id, etablissement_id, numero_facture, statut,
    montant_ht, montant_tva, montant_ttc, taux_tva, date_emission,
    date_echeance, type_document)
  VALUES ('bbbbbbbb-1111-0000-0000-000000000001', v_etab_id,
    v_base_num || '-EMISE', 'EMISE', 100.00, 20.00, 120.00, 20.00,
    NOW(), NOW() + INTERVAL '30 days', 'FACTURE');

  -- Facture EN_RETARD
  INSERT INTO public.factures (id, etablissement_id, numero_facture, statut,
    montant_ht, montant_tva, montant_ttc, taux_tva, date_emission,
    date_echeance, type_document)
  VALUES ('bbbbbbbb-1111-0000-0000-000000000002', v_etab_id,
    v_base_num || '-EN_RETARD', 'EN_RETARD', 150.00, 30.00, 180.00, 20.00,
    NOW() - INTERVAL '60 days', NOW() - INTERVAL '30 days', 'FACTURE');

  -- Facture ANNULEE (guard H4 doit bloquer)
  INSERT INTO public.factures (id, etablissement_id, numero_facture, statut,
    montant_ht, montant_tva, montant_ttc, taux_tva, date_emission,
    date_echeance, type_document)
  VALUES ('bbbbbbbb-1111-0000-0000-000000000003', v_etab_id,
    v_base_num || '-ANNULEE', 'ANNULEE', 200.00, 40.00, 240.00, 20.00,
    NOW(), NOW() + INTERVAL '30 days', 'FACTURE');

  -- Facture BROUILLON (guard H4 doit bloquer — impossible en théorie mais test defensif)
  INSERT INTO public.factures (id, etablissement_id, numero_facture, statut,
    montant_ht, montant_tva, montant_ttc, taux_tva, date_emission,
    date_echeance, type_document)
  VALUES ('bbbbbbbb-1111-0000-0000-000000000004', v_etab_id,
    v_base_num || '-BROUILLON', 'BROUILLON', 250.00, 50.00, 300.00, 20.00,
    NOW(), NOW() + INTERVAL '30 days', 'FACTURE');

  -- Facture déjà PAYEE (idempotent, short-circuit avant UPDATE)
  INSERT INTO public.factures (id, etablissement_id, numero_facture, statut,
    montant_ht, montant_tva, montant_ttc, taux_tva, date_emission,
    date_echeance, date_paiement, stripe_payment_intent_id, type_document)
  VALUES ('bbbbbbbb-1111-0000-0000-000000000005', v_etab_id,
    v_base_num || '-PAYEE', 'PAYEE', 300.00, 60.00, 360.00, 20.00,
    NOW() - INTERVAL '1 day', NOW() + INTERVAL '30 days',
    NOW() - INTERVAL '1 day', 'pi_already_paid_commission_123', 'FACTURE');
END $$;

-- Simuler le UPDATE du webhook branche FACTURE (guard H4)
-- [2.1] EMISE → PAYEE
UPDATE public.factures
   SET statut = 'PAYEE',
       date_paiement = NOW(),
       stripe_payment_intent_id = 'pi_test_cp3_webhook_001',
       modifie_le = NOW()
 WHERE id = 'bbbbbbbb-1111-0000-0000-000000000001'
   AND statut IN ('EMISE', 'EN_RETARD');

-- [2.2] EN_RETARD → PAYEE
UPDATE public.factures
   SET statut = 'PAYEE',
       date_paiement = NOW(),
       stripe_payment_intent_id = 'pi_test_cp3_webhook_002',
       modifie_le = NOW()
 WHERE id = 'bbbbbbbb-1111-0000-0000-000000000002'
   AND statut IN ('EMISE', 'EN_RETARD');

-- [2.3] ANNULEE → rejet
UPDATE public.factures
   SET statut = 'PAYEE',
       date_paiement = NOW(),
       stripe_payment_intent_id = 'pi_test_cp3_webhook_003',
       modifie_le = NOW()
 WHERE id = 'bbbbbbbb-1111-0000-0000-000000000003'
   AND statut IN ('EMISE', 'EN_RETARD');

-- [2.4] BROUILLON → rejet
UPDATE public.factures
   SET statut = 'PAYEE',
       date_paiement = NOW(),
       stripe_payment_intent_id = 'pi_test_cp3_webhook_004',
       modifie_le = NOW()
 WHERE id = 'bbbbbbbb-1111-0000-0000-000000000004'
   AND statut IN ('EMISE', 'EN_RETARD');

-- [2.5] PAYEE → rejet guard (webhook short-circuit avant idéalement, mais guard double-protection)
UPDATE public.factures
   SET statut = 'PAYEE',
       date_paiement = NOW(),
       stripe_payment_intent_id = 'pi_test_cp3_webhook_005_retry',
       modifie_le = NOW()
 WHERE id = 'bbbbbbbb-1111-0000-0000-000000000005'
   AND statut IN ('EMISE', 'EN_RETARD');

-- Assertions
SELECT CASE
  WHEN statut = 'PAYEE' AND stripe_payment_intent_id = 'pi_test_cp3_webhook_001'
    THEN '[2.1] OK — facture EMISE → PAYEE + PI rempli'
  ELSE '[2.1] FAIL — statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures WHERE id = 'bbbbbbbb-1111-0000-0000-000000000001';

SELECT CASE
  WHEN statut = 'PAYEE' AND stripe_payment_intent_id = 'pi_test_cp3_webhook_002'
    THEN '[2.2] OK — facture EN_RETARD → PAYEE + PI rempli'
  ELSE '[2.2] FAIL — statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures WHERE id = 'bbbbbbbb-1111-0000-0000-000000000002';

SELECT CASE
  WHEN statut = 'ANNULEE' AND stripe_payment_intent_id IS NULL
    THEN '[2.3] OK — facture ANNULEE rejetée par guard'
  ELSE '[2.3] FAIL — guard cassé, statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures WHERE id = 'bbbbbbbb-1111-0000-0000-000000000003';

SELECT CASE
  WHEN statut = 'BROUILLON' AND stripe_payment_intent_id IS NULL
    THEN '[2.4] OK — facture BROUILLON rejetée par guard'
  ELSE '[2.4] FAIL — guard cassé, statut=' || statut || ', PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures WHERE id = 'bbbbbbbb-1111-0000-0000-000000000004';

SELECT CASE
  WHEN statut = 'PAYEE' AND stripe_payment_intent_id = 'pi_already_paid_commission_123'
    THEN '[2.5] OK — facture déjà PAYEE préservée (rejeu webhook idempotent)'
  ELSE '[2.5] FAIL — idempotence cassée, PI=' || COALESCE(stripe_payment_intent_id, 'NULL')
END
FROM public.factures WHERE id = 'bbbbbbbb-1111-0000-0000-000000000005';

ROLLBACK;

\echo ''
\echo '== Fin tests CP-STRIPE-3 =='
