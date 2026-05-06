-- ============================================================
-- Tests CP-STRIPE-4 — Webhook events Stripe supplémentaires (H6)
-- ============================================================
-- Prérequis : migration 20260420130000_cp_stripe_4_webhook_events
--             appliquée (dispute_* + reversed_le + CHECK statut + ANNULEE)
-- Scope     : valide le SCHEMA et la LOGIQUE des UPDATE que les
--             handlers webhook effectuent. Les appels Stripe
--             eux-mêmes sont mockés.
-- Usage     : psql "$DB_URL" -f tests/stripe/cp-stripe-4.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-STRIPE-4 — webhook events Stripe =='

-- ------------------------------------------------------------
-- [1] Schema : colonnes ajoutées par la migration DDL
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) = 5 THEN '[1.1] OK — 5 colonnes dispute_*/reversed_le présentes'
  ELSE '[1.1] FAIL — colonnes manquantes (count=' || COUNT(*)::text || ')'
END
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'stripe_transfers'
  AND column_name IN ('dispute_id','dispute_statut','dispute_reason','dispute_cree_le','reversed_le');

-- ------------------------------------------------------------
-- [2] CHECK statut : ANNULEE accepté
-- ------------------------------------------------------------
SELECT CASE
  WHEN pg_get_constraintdef(oid) LIKE '%ANNULEE%'
    THEN '[2.1] OK — CHECK statut accepte ANNULEE'
  ELSE '[2.1] FAIL — ' || pg_get_constraintdef(oid)
END
FROM pg_constraint
WHERE conrelid = 'public.stripe_transfers'::regclass
  AND conname = 'stripe_transfers_statut_check';

-- ------------------------------------------------------------
-- [3] CHECK dispute_statut : valeurs valides
-- ------------------------------------------------------------
SELECT CASE
  WHEN pg_get_constraintdef(oid) LIKE '%OUVERT%' AND pg_get_constraintdef(oid) LIKE '%CLOS_lost%'
    THEN '[3.1] OK — CHECK dispute_statut accepte OUVERT/CLOS_*'
  ELSE '[3.1] FAIL — ' || pg_get_constraintdef(oid)
END
FROM pg_constraint
WHERE conrelid = 'public.stripe_transfers'::regclass
  AND conname = 'stripe_transfers_dispute_statut_check';

-- ------------------------------------------------------------
-- [4] Index pour matching webhook
-- ------------------------------------------------------------
SELECT CASE
  WHEN COUNT(*) = 4 THEN '[4.1] OK — 4 index ajoutés (payout, transfer_id, charge_id, dispute_id)'
  ELSE '[4.1] FAIL — index manquants (count=' || COUNT(*)::text || ')'
END
FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'stripe_transfers'
  AND indexname IN (
    'idx_transfers_stripe_payout',
    'idx_transfers_stripe_transfer_id',
    'idx_transfers_stripe_charge_id',
    'idx_transfers_dispute_id'
  );

-- ------------------------------------------------------------
-- [5] Scénarios UPDATE simulés (handlers webhook)
-- ------------------------------------------------------------

BEGIN;

-- Setup : 3 transfers avec des états distincts
DO $$
BEGIN
  INSERT INTO public.stripe_transfers (id, mission_id, soignant_id, etablissement_id,
    montant_total, montant_commission, montant_soignant, stripe_transfer_id,
    stripe_charge_id, stripe_payout_id, statut, cree_le)
  VALUES
    ('cccccccc-4444-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      100, 15, 85, 'tr_test_001', 'ch_test_001', NULL, 'TRANSFERE', NOW()),
    ('cccccccc-4444-0000-0000-000000000002', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      200, 30, 170, 'tr_test_002', 'ch_test_002', 'po_test_002', 'TRANSFERE', NOW()),
    ('cccccccc-4444-0000-0000-000000000003', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      300, 45, 255, 'tr_test_003', 'ch_test_003', NULL, 'EN_ATTENTE', NOW());
END $$;

-- [5.1] payout.paid : transfer TRANSFERE → PAYE avec match par stripe_payout_id
UPDATE public.stripe_transfers
   SET statut = 'PAYE',
       stripe_payout_id = 'po_test_002',
       paye_le = NOW()
 WHERE stripe_payout_id = 'po_test_002'
   AND statut = 'TRANSFERE';

SELECT CASE
  WHEN statut = 'PAYE' AND paye_le IS NOT NULL AND stripe_payout_id = 'po_test_002'
    THEN '[5.1] OK — payout.paid : transfer passé PAYE avec payout_id + paye_le'
  ELSE '[5.1] FAIL — statut=' || statut || ', paye_le=' || COALESCE(paye_le::text,'NULL')
END
FROM public.stripe_transfers WHERE id = 'cccccccc-4444-0000-0000-000000000002';

-- [5.2] transfer.failed : statut → ECHOUE
UPDATE public.stripe_transfers
   SET statut = 'ECHOUE', erreur = 'Bank account closed', modifie_le = NOW()
 WHERE stripe_transfer_id = 'tr_test_001'
   AND statut != 'ECHOUE';

SELECT CASE
  WHEN statut = 'ECHOUE' AND erreur = 'Bank account closed'
    THEN '[5.2] OK — transfer.failed : statut ECHOUE + erreur enregistrée'
  ELSE '[5.2] FAIL — statut=' || statut
END
FROM public.stripe_transfers WHERE id = 'cccccccc-4444-0000-0000-000000000001';

-- [5.3] transfer.reversed : statut → REMBOURSE + reversed_le
UPDATE public.stripe_transfers
   SET statut = 'REMBOURSE', reversed_le = NOW(), modifie_le = NOW()
 WHERE stripe_transfer_id = 'tr_test_003';

SELECT CASE
  WHEN statut = 'REMBOURSE' AND reversed_le IS NOT NULL
    THEN '[5.3] OK — transfer.reversed : statut REMBOURSE + reversed_le'
  ELSE '[5.3] FAIL — statut=' || statut || ', reversed_le=' || COALESCE(reversed_le::text,'NULL')
END
FROM public.stripe_transfers WHERE id = 'cccccccc-4444-0000-0000-000000000003';

-- [5.4] charge.dispute.created : dispute_* colonnes remplies
UPDATE public.stripe_transfers
   SET dispute_id = 'dp_test_001',
       dispute_statut = 'OUVERT',
       dispute_reason = 'fraudulent',
       dispute_cree_le = NOW()
 WHERE stripe_charge_id = 'ch_test_001';

SELECT CASE
  WHEN dispute_id = 'dp_test_001' AND dispute_statut = 'OUVERT' AND dispute_reason = 'fraudulent'
    THEN '[5.4] OK — charge.dispute.created : dispute_* rempli'
  ELSE '[5.4] FAIL — dispute_statut=' || COALESCE(dispute_statut, 'NULL')
END
FROM public.stripe_transfers WHERE id = 'cccccccc-4444-0000-0000-000000000001';

-- [5.5] charge.dispute.closed : dispute_statut → CLOS_lost
UPDATE public.stripe_transfers
   SET dispute_statut = 'CLOS_lost'
 WHERE dispute_id = 'dp_test_001';

SELECT CASE
  WHEN dispute_statut = 'CLOS_lost'
    THEN '[5.5] OK — charge.dispute.closed : statut CLOS_lost'
  ELSE '[5.5] FAIL — dispute_statut=' || COALESCE(dispute_statut, 'NULL')
END
FROM public.stripe_transfers WHERE id = 'cccccccc-4444-0000-0000-000000000001';

-- [5.6] payout.canceled : statut → ANNULEE (nouveau statut ajouté en CHECK)
UPDATE public.stripe_transfers
   SET statut = 'ANNULEE', modifie_le = NOW()
 WHERE stripe_payout_id = 'po_test_002';

SELECT CASE
  WHEN statut = 'ANNULEE'
    THEN '[5.6] OK — payout.canceled : statut ANNULEE (nouveau)'
  ELSE '[5.6] FAIL — statut=' || statut
END
FROM public.stripe_transfers WHERE id = 'cccccccc-4444-0000-0000-000000000002';

ROLLBACK;

-- ------------------------------------------------------------
-- [6] charge.refunded : UPDATE factures_honoraires AVOIR → REMBOURSEE
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
  v_mission_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_etab_id UUID := gen_random_uuid();
BEGIN
  -- AVOIR qui sera marqué REMBOURSEE
  INSERT INTO public.factures_honoraires (id, mission_id, soignant_id, etablissement_id,
    numero_facture, statut, montant_ht, montant_tva, montant_ttc, taux_tva,
    tva_applicable, date_emission, date_echeance, type_document,
    stripe_payment_intent_id, cree_le)
  VALUES ('dddddddd-4444-0000-0000-000000000001', v_mission_id, v_soignant_id, v_etab_id,
    'AVC-TEST-001', 'EMISE', -50, -10, -60, 20, TRUE,
    NOW(), NOW() + INTERVAL '30 days', 'AVOIR',
    'pi_test_refund_001', NOW());
END $$;

-- Simuler webhook charge.refunded : UPDATE avoir → REMBOURSEE
UPDATE public.factures_honoraires
   SET statut = 'REMBOURSEE',
       date_remboursement = NOW(),
       reference_remboursement = 'ch_test_refund_001'
 WHERE stripe_payment_intent_id = 'pi_test_refund_001'
   AND type_document = 'AVOIR'
   AND statut IN ('EMISE', 'EN_RETARD');

SELECT CASE
  WHEN statut = 'REMBOURSEE' AND date_remboursement IS NOT NULL
       AND reference_remboursement = 'ch_test_refund_001'
    THEN '[6.1] OK — charge.refunded : AVOIR passé REMBOURSEE + référence + date'
  ELSE '[6.1] FAIL — statut=' || statut
END
FROM public.factures_honoraires
WHERE id = 'dddddddd-4444-0000-0000-000000000001';

ROLLBACK;

-- ------------------------------------------------------------
-- [7] ALLOWED_TYPES send-email : nouveaux templates (metadata test)
-- ------------------------------------------------------------
\echo '[7] Templates email (non-testable SQL, voir docs/tests-cp-stripe-4.md)'

\echo ''
\echo '== Fin tests CP-STRIPE-4 =='
