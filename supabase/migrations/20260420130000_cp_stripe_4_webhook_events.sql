-- ============================================================
-- CP-STRIPE-4 — Migration DDL pour webhook events Stripe (H6)
-- ============================================================
-- Scope : étendre stripe_transfers pour tracer disputes + reversal + ANNULEE
-- Events Stripe concernés :
--   - charge.dispute.created / charge.dispute.closed → 4 colonnes dispute_*
--   - transfer.reversed → reversed_le
--   - payout.canceled → statut 'ANNULEE' ajouté à la CHECK constraint
--   - transfer.failed, payout.failed/paid → index pour lookups rapides
--
-- Idempotent : IF NOT EXISTS / DROP CONSTRAINT IF EXISTS partout.
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────
-- 1. Colonnes dispute + reversed_le
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.stripe_transfers
  ADD COLUMN IF NOT EXISTS dispute_id TEXT,
  ADD COLUMN IF NOT EXISTS dispute_statut TEXT,
  ADD COLUMN IF NOT EXISTS dispute_reason TEXT,
  ADD COLUMN IF NOT EXISTS dispute_cree_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reversed_le TIMESTAMPTZ;

COMMENT ON COLUMN public.stripe_transfers.dispute_id IS
  'ID Stripe Dispute lorsque étab conteste le paiement (chargeback). Lié à stripe_charge_id via webhook charge.dispute.created.';

COMMENT ON COLUMN public.stripe_transfers.dispute_statut IS
  'Statut Stripe Dispute : OUVERT (ouverture), CLOS_won/lost/warning_closed/etc. (clôture).';

COMMENT ON COLUMN public.stripe_transfers.reversed_le IS
  'Horodatage webhook transfer.reversed. Le transfer Connect a été annulé côté Stripe (statut passe REMBOURSE).';

-- ──────────────────────────────────────────────────────────────
-- 2. CHECK constraint dispute_statut (valide valeurs possibles)
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.stripe_transfers
  DROP CONSTRAINT IF EXISTS stripe_transfers_dispute_statut_check;

ALTER TABLE public.stripe_transfers
  ADD CONSTRAINT stripe_transfers_dispute_statut_check
  CHECK (
    dispute_statut IS NULL
    OR dispute_statut IN (
      'OUVERT',
      'CLOS_won',
      'CLOS_lost',
      'CLOS_warning_closed',
      'CLOS_warning_needs_response',
      'CLOS_charge_refunded'
    )
  );

-- ──────────────────────────────────────────────────────────────
-- 3. CHECK statut : ajouter 'ANNULEE' (payout.canceled)
-- ──────────────────────────────────────────────────────────────

ALTER TABLE public.stripe_transfers
  DROP CONSTRAINT IF EXISTS stripe_transfers_statut_check;

ALTER TABLE public.stripe_transfers
  ADD CONSTRAINT stripe_transfers_statut_check
  CHECK (
    statut IN (
      'EN_ATTENTE',
      'CHARGE_REUSSI',
      'TRANSFERE',
      'PAYE',
      'ECHOUE',
      'REMBOURSE',
      'ANNULEE'
    )
  );

-- ──────────────────────────────────────────────────────────────
-- 4. Index pour matching rapide dans les handlers webhook
-- ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_transfers_stripe_payout
  ON public.stripe_transfers (stripe_payout_id)
  WHERE stripe_payout_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transfers_stripe_transfer_id
  ON public.stripe_transfers (stripe_transfer_id)
  WHERE stripe_transfer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transfers_stripe_charge_id
  ON public.stripe_transfers (stripe_charge_id)
  WHERE stripe_charge_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transfers_dispute_id
  ON public.stripe_transfers (dispute_id)
  WHERE dispute_id IS NOT NULL;

COMMIT;
