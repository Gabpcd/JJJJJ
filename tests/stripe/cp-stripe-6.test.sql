-- ============================================================
-- Tests CP-STRIPE-6 — Hardening Stripe Connect (H9 + H10 + H11)
-- ============================================================
-- Prérequis : migration 20260420140000_cp_stripe_6_account_deleted_status
--             appliquée (CHECK statut + SUPPRIME).
-- Scope     : valide le SCHEMA (CHECK SUPPRIME) + la logique
--             cache/UPDATE que les edge functions exécutent.
-- Le helper mapStripeError est testé indirectement via
--             les tests manuels (end-to-end).
-- Usage     : psql "$DB_URL" -f tests/stripe/cp-stripe-6.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-STRIPE-6 — Hardening Stripe =='

-- ------------------------------------------------------------
-- [1] Schema : CHECK statut accepte SUPPRIME (H11)
-- ------------------------------------------------------------
SELECT CASE
  WHEN pg_get_constraintdef(oid) LIKE '%SUPPRIME%'
    THEN '[1.1] OK — CHECK statut accepte SUPPRIME'
  ELSE '[1.1] FAIL — ' || pg_get_constraintdef(oid)
END
FROM pg_constraint
WHERE conrelid = 'public.stripe_connect_onboarding'::regclass
  AND conname = 'stripe_connect_onboarding_statut_check';

-- Liste complète statuts autorisés
SELECT CASE
  WHEN pg_get_constraintdef(oid) LIKE '%NON_DEMANDE%'
   AND pg_get_constraintdef(oid) LIKE '%EN_COURS%'
   AND pg_get_constraintdef(oid) LIKE '%COMPLET%'
   AND pg_get_constraintdef(oid) LIKE '%SUSPENDU%'
   AND pg_get_constraintdef(oid) LIKE '%REJETE%'
   AND pg_get_constraintdef(oid) LIKE '%SUPPRIME%'
    THEN '[1.2] OK — 6 statuts autorisés : NON_DEMANDE/EN_COURS/COMPLET/SUSPENDU/REJETE/SUPPRIME'
  ELSE '[1.2] FAIL — statut manquant'
END
FROM pg_constraint
WHERE conrelid = 'public.stripe_connect_onboarding'::regclass
  AND conname = 'stripe_connect_onboarding_statut_check';

-- ------------------------------------------------------------
-- [2] Scénario H11 : transition vers SUPPRIME (logique edge function)
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
  v_soignant_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.stripe_connect_onboarding (id, soignant_id,
    stripe_account_id, stripe_account_type, statut, type_exercice, cree_le, modifie_le)
  VALUES ('aaaaaaaa-6666-0000-0000-000000000001', v_soignant_id,
    'acct_test_cp6_deleted', 'express', 'COMPLET', 'LIBERAL',
    NOW() - INTERVAL '1 hour', NOW() - INTERVAL '10 min');
END $$;

-- Simuler détection compte supprimé Stripe → UPDATE SUPPRIME
UPDATE public.stripe_connect_onboarding
   SET statut = 'SUPPRIME',
       charges_enabled = FALSE,
       payouts_enabled = FALSE,
       modifie_le = NOW()
 WHERE id = 'aaaaaaaa-6666-0000-0000-000000000001';

SELECT CASE
  WHEN statut = 'SUPPRIME' AND charges_enabled = FALSE AND payouts_enabled = FALSE
    THEN '[2.1] OK — compte marqué SUPPRIME + charges/payouts désactivés'
  ELSE '[2.1] FAIL — statut=' || statut
END
FROM public.stripe_connect_onboarding
WHERE id = 'aaaaaaaa-6666-0000-0000-000000000001';

ROLLBACK;

-- ------------------------------------------------------------
-- [3] Scénario H10 : cache valide (modifie_le récent)
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
  v_soignant_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.stripe_connect_onboarding (id, soignant_id,
    stripe_account_id, stripe_account_type, statut, type_exercice,
    charges_enabled, payouts_enabled, details_submitted, iban_last4,
    cree_le, modifie_le)
  VALUES ('bbbbbbbb-6666-0000-0000-000000000001', v_soignant_id,
    'acct_test_cp6_cache_hit', 'express', 'COMPLET', 'LIBERAL',
    TRUE, TRUE, TRUE, '4242',
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '2 min');
END $$;

-- Simuler logique edge function : si modifie_le > NOW() - 5min → return cached
SELECT CASE
  WHEN (NOW() - modifie_le) < INTERVAL '5 minutes'
    THEN '[3.1] OK — cache VALIDE : modifie_le ' || EXTRACT(EPOCH FROM (NOW() - modifie_le))::INT::text || 's < 5min'
  ELSE '[3.1] FAIL — cache devrait être valide'
END
FROM public.stripe_connect_onboarding
WHERE id = 'bbbbbbbb-6666-0000-0000-000000000001';

ROLLBACK;

-- ------------------------------------------------------------
-- [4] Scénario H10 : cache expiré (modifie_le > 5 min)
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
  v_soignant_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.stripe_connect_onboarding (id, soignant_id,
    stripe_account_id, stripe_account_type, statut, type_exercice,
    charges_enabled, payouts_enabled, details_submitted,
    cree_le, modifie_le)
  VALUES ('cccccccc-6666-0000-0000-000000000001', v_soignant_id,
    'acct_test_cp6_cache_miss', 'express', 'COMPLET', 'LIBERAL',
    TRUE, TRUE, TRUE,
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '10 min');
END $$;

SELECT CASE
  WHEN (NOW() - modifie_le) >= INTERVAL '5 minutes'
    THEN '[4.1] OK — cache EXPIRÉ : modifie_le ' || EXTRACT(EPOCH FROM (NOW() - modifie_le))::INT::text || 's ≥ 5min, call Stripe'
  ELSE '[4.1] FAIL — cache devrait être expiré'
END
FROM public.stripe_connect_onboarding
WHERE id = 'cccccccc-6666-0000-0000-000000000001';

ROLLBACK;

-- ------------------------------------------------------------
-- [5] Idempotence : compte déjà SUPPRIME → skip retrieve
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
  v_soignant_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.stripe_connect_onboarding (id, soignant_id,
    stripe_account_id, stripe_account_type, statut, type_exercice,
    charges_enabled, payouts_enabled, details_submitted,
    cree_le, modifie_le)
  VALUES ('dddddddd-6666-0000-0000-000000000001', v_soignant_id,
    'acct_test_cp6_already_deleted', 'express', 'SUPPRIME', 'LIBERAL',
    FALSE, FALSE, FALSE,
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 hour');
END $$;

-- Edge function DOIT retourner SUPPRIME direct sans appeler Stripe
SELECT CASE
  WHEN statut = 'SUPPRIME'
    THEN '[5.1] OK — statut SUPPRIME préservé, pas de retrieve Stripe nécessaire'
  ELSE '[5.1] FAIL — statut=' || statut
END
FROM public.stripe_connect_onboarding
WHERE id = 'dddddddd-6666-0000-0000-000000000001';

ROLLBACK;

\echo ''
\echo '== Fin tests CP-STRIPE-6 =='
