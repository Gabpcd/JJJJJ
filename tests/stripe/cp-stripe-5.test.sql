-- ============================================================
-- Tests CP-STRIPE-5 — process-stripe-refunds cron (H3 + A21/T13)
-- ============================================================
-- Prérequis : table stripe_refunds_queue créée par CP-LITIGES-3.
-- Scope     : valide la LOGIQUE SQL du cron (SELECT éligibles,
--             UPDATE lock atomique, transitions statut).
-- Les appels Stripe eux-mêmes sont mockés.
-- Usage     : psql "$DB_URL" -f tests/stripe/cp-stripe-5.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-STRIPE-5 — process-stripe-refunds =='

-- ------------------------------------------------------------
-- [1] Schema : CHECK statut accepte les 4 valeurs du cycle
-- ------------------------------------------------------------
SELECT CASE
  WHEN pg_get_constraintdef(oid) LIKE '%EN_ATTENTE%'
   AND pg_get_constraintdef(oid) LIKE '%EN_COURS%'
   AND pg_get_constraintdef(oid) LIKE '%TRAITE%'
   AND pg_get_constraintdef(oid) LIKE '%ECHEC%'
    THEN '[1.1] OK — CHECK statut accepte EN_ATTENTE/EN_COURS/TRAITE/ECHEC'
  ELSE '[1.1] FAIL — ' || pg_get_constraintdef(oid)
END
FROM pg_constraint
WHERE conrelid = 'public.stripe_refunds_queue'::regclass
  AND contype = 'c'
  AND pg_get_constraintdef(oid) LIKE '%EN_ATTENTE%';

-- ------------------------------------------------------------
-- [2] Scénario : SELECT éligibles (EN_ATTENTE, tentatives < 3, délai 15min)
-- ------------------------------------------------------------

BEGIN;

-- Setup : 6 lignes avec états variés
DO $$
BEGIN
  -- Éligible : EN_ATTENTE, tentatives=0, jamais tenté
  INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
    stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le)
  VALUES ('11111111-5555-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
    'pi_test_cp5_001', 1000, 'EN_ATTENTE', 0, NOW() - INTERVAL '10 min');

  -- Éligible : EN_ATTENTE, tentatives=1, dernier essai > 15min
  INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
    stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le, dernier_essai_le)
  VALUES ('11111111-5555-0000-0000-000000000002', gen_random_uuid(), gen_random_uuid(),
    'pi_test_cp5_002', 2000, 'EN_ATTENTE', 1, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '20 min');

  -- NON éligible : EN_ATTENTE, tentatives=3 (max atteint)
  INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
    stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le, dernier_essai_le)
  VALUES ('11111111-5555-0000-0000-000000000003', gen_random_uuid(), gen_random_uuid(),
    'pi_test_cp5_003', 3000, 'EN_ATTENTE', 3, NOW() - INTERVAL '2 hours', NOW() - INTERVAL '1 hour');

  -- NON éligible : EN_ATTENTE, dernier essai récent (< 15min)
  INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
    stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le, dernier_essai_le)
  VALUES ('11111111-5555-0000-0000-000000000004', gen_random_uuid(), gen_random_uuid(),
    'pi_test_cp5_004', 4000, 'EN_ATTENTE', 1, NOW() - INTERVAL '30 min', NOW() - INTERVAL '5 min');

  -- NON éligible : EN_COURS (déjà locké)
  INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
    stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le, dernier_essai_le)
  VALUES ('11111111-5555-0000-0000-000000000005', gen_random_uuid(), gen_random_uuid(),
    'pi_test_cp5_005', 5000, 'EN_COURS', 0, NOW() - INTERVAL '5 min', NOW() - INTERVAL '30 sec');

  -- NON éligible : TRAITE (fini)
  INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
    stripe_payment_intent_id, montant_cts, statut, tentatives, stripe_refund_id, cree_le, traite_le)
  VALUES ('11111111-5555-0000-0000-000000000006', gen_random_uuid(), gen_random_uuid(),
    'pi_test_cp5_006', 6000, 'TRAITE', 0, 're_test_cp5_006', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day');
END $$;

-- Simuler le SELECT éligibles du cron
SELECT CASE
  WHEN COUNT(*) = 2
   AND SUM(CASE WHEN id::text IN ('11111111-5555-0000-0000-000000000001', '11111111-5555-0000-0000-000000000002') THEN 1 ELSE 0 END) = 2
    THEN '[2.1] OK — SELECT éligibles retourne 2 lignes (001, 002)'
  ELSE '[2.1] FAIL — count=' || COUNT(*)::text
END
FROM public.stripe_refunds_queue
WHERE statut = 'EN_ATTENTE'
  AND tentatives < 3
  AND (dernier_essai_le IS NULL OR dernier_essai_le < NOW() - INTERVAL '15 min');

ROLLBACK;

-- ------------------------------------------------------------
-- [3] Lock atomique : UPDATE conditionnel EN_ATTENTE → EN_COURS
-- ------------------------------------------------------------

BEGIN;

INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
  stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le)
VALUES ('22222222-5555-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
  'pi_test_cp5_lock', 1000, 'EN_ATTENTE', 0, NOW());

-- Premier cron prend le lock
UPDATE public.stripe_refunds_queue
   SET statut = 'EN_COURS', dernier_essai_le = NOW()
 WHERE id = '22222222-5555-0000-0000-000000000001'
   AND statut = 'EN_ATTENTE';

SELECT CASE
  WHEN statut = 'EN_COURS'
    THEN '[3.1] OK — premier lock réussi : EN_COURS'
  ELSE '[3.1] FAIL — statut=' || statut
END
FROM public.stripe_refunds_queue
WHERE id = '22222222-5555-0000-0000-000000000001';

-- Second cron (concurrent) tente le lock : doit échouer (0 rows)
WITH upd AS (
  UPDATE public.stripe_refunds_queue
     SET statut = 'EN_COURS', dernier_essai_le = NOW()
   WHERE id = '22222222-5555-0000-0000-000000000001'
     AND statut = 'EN_ATTENTE'
   RETURNING id
)
SELECT CASE
  WHEN COUNT(*) = 0
    THEN '[3.2] OK — second lock rejeté (statut déjà EN_COURS)'
  ELSE '[3.2] FAIL — lock double réussi'
END
FROM upd;

ROLLBACK;

-- ------------------------------------------------------------
-- [4] Transition success : EN_COURS → TRAITE + stripe_refund_id
-- ------------------------------------------------------------

BEGIN;

INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
  stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le)
VALUES ('33333333-5555-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
  'pi_test_cp5_success', 1500, 'EN_COURS', 0, NOW());

-- Simulation success refund
UPDATE public.stripe_refunds_queue
   SET statut = 'TRAITE',
       stripe_refund_id = 're_test_cp5_success_001',
       traite_le = NOW(),
       erreur = NULL
 WHERE id = '33333333-5555-0000-0000-000000000001';

SELECT CASE
  WHEN statut = 'TRAITE' AND stripe_refund_id = 're_test_cp5_success_001'
       AND traite_le IS NOT NULL AND erreur IS NULL
    THEN '[4.1] OK — EN_COURS → TRAITE + refund_id + traite_le'
  ELSE '[4.1] FAIL — statut=' || statut
END
FROM public.stripe_refunds_queue
WHERE id = '33333333-5555-0000-0000-000000000001';

ROLLBACK;

-- ------------------------------------------------------------
-- [5] Transition retry : EN_COURS → EN_ATTENTE, tentatives++
-- ------------------------------------------------------------

BEGIN;

INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
  stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le)
VALUES ('44444444-5555-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
  'pi_test_cp5_retry', 2500, 'EN_COURS', 1, NOW());

-- Simulation retry temporaire (rate limit)
UPDATE public.stripe_refunds_queue
   SET statut = 'EN_ATTENTE',
       tentatives = tentatives + 1,
       erreur = 'Rate limit exceeded, retry in 15min'
 WHERE id = '44444444-5555-0000-0000-000000000001';

SELECT CASE
  WHEN statut = 'EN_ATTENTE' AND tentatives = 2
    THEN '[5.1] OK — EN_COURS → EN_ATTENTE, tentatives passées de 1 à 2'
  ELSE '[5.1] FAIL — statut=' || statut || ', tentatives=' || tentatives::text
END
FROM public.stripe_refunds_queue
WHERE id = '44444444-5555-0000-0000-000000000001';

ROLLBACK;

-- ------------------------------------------------------------
-- [6] Transition échec permanent : tentatives=3 → ECHEC
-- ------------------------------------------------------------

BEGIN;

INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
  stripe_payment_intent_id, montant_cts, statut, tentatives, cree_le)
VALUES ('55555555-5555-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
  'pi_test_cp5_echec', 3500, 'EN_COURS', 2, NOW());

-- Simulation 3e échec → ECHEC permanent
UPDATE public.stripe_refunds_queue
   SET statut = 'ECHEC',
       tentatives = tentatives + 1,
       erreur = 'amount_too_large: refund exceeds original charge'
 WHERE id = '55555555-5555-0000-0000-000000000001';

SELECT CASE
  WHEN statut = 'ECHEC' AND tentatives = 3
    THEN '[6.1] OK — 3e échec → ECHEC permanent (tentatives=3)'
  ELSE '[6.1] FAIL — statut=' || statut || ', tentatives=' || tentatives::text
END
FROM public.stripe_refunds_queue
WHERE id = '55555555-5555-0000-0000-000000000001';

ROLLBACK;

-- ------------------------------------------------------------
-- [7] Webhook charge.refunded filet de sécurité : UPDATE idempotent
-- ------------------------------------------------------------

BEGIN;

INSERT INTO public.stripe_refunds_queue (id, avoir_id, facture_origine_id,
  stripe_payment_intent_id, montant_cts, statut, tentatives, stripe_refund_id, cree_le, traite_le)
VALUES ('66666666-5555-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
  'pi_test_cp5_webhook', 4500, 'TRAITE', 0, 're_already_set', NOW() - INTERVAL '1 min', NOW() - INTERVAL '30 sec');

-- Webhook charge.refunded arrive (CP-STRIPE-4) : UPDATE ne doit rien changer
UPDATE public.stripe_refunds_queue
   SET statut = 'TRAITE', traite_le = NOW()
 WHERE stripe_payment_intent_id = 'pi_test_cp5_webhook'
   AND statut IN ('EN_ATTENTE', 'EN_COURS');

SELECT CASE
  WHEN statut = 'TRAITE' AND stripe_refund_id = 're_already_set'
    THEN '[7.1] OK — webhook idempotent : ligne déjà TRAITE préservée'
  ELSE '[7.1] FAIL — ligne TRAITE modifiée'
END
FROM public.stripe_refunds_queue
WHERE id = '66666666-5555-0000-0000-000000000001';

ROLLBACK;

\echo ''
\echo '== Fin tests CP-STRIPE-5 =='
