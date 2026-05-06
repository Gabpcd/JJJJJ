-- ============================================================
-- CP-STRIPE-6 — Statut 'SUPPRIME' pour stripe_connect_onboarding (H11)
-- ============================================================
-- Quand Stripe retourne resource_missing ou account_invalid lors de
-- accounts.retrieve(), le compte Connect a été supprimé côté Stripe
-- (soignant qui clôture, fraude, décision plateforme).
-- On ajoute le statut 'SUPPRIME' pour le tracer gracieusement.
-- ============================================================

BEGIN;

ALTER TABLE public.stripe_connect_onboarding
  DROP CONSTRAINT IF EXISTS stripe_connect_onboarding_statut_check;

ALTER TABLE public.stripe_connect_onboarding
  ADD CONSTRAINT stripe_connect_onboarding_statut_check
  CHECK (
    statut = ANY (ARRAY[
      'NON_DEMANDE'::text,
      'EN_COURS'::text,
      'COMPLET'::text,
      'SUSPENDU'::text,
      'REJETE'::text,
      'SUPPRIME'::text
    ])
  );

COMMENT ON COLUMN public.stripe_connect_onboarding.statut IS
  'Statut Connect onboarding : NON_DEMANDE / EN_COURS / COMPLET / SUSPENDU (Stripe a restreint) / REJETE (Stripe a rejete) / SUPPRIME (compte supprime cote Stripe, detecte par CP-STRIPE-6).';

COMMIT;
