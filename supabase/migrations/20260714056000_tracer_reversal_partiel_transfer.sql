-- Un transfer Connect peut être reversé partiellement. Ne jamais traduire un
-- reversal partiel par le statut REMBOURSE (qui signifie reversal total).
ALTER TABLE public.stripe_transfers
  ADD COLUMN IF NOT EXISTS stripe_amount_reversed_cents integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stripe_reversal_statut text NOT NULL DEFAULT 'AUCUN';

ALTER TABLE public.stripe_transfers
  DROP CONSTRAINT IF EXISTS stripe_transfers_amount_reversed_check,
  ADD CONSTRAINT stripe_transfers_amount_reversed_check
    CHECK (stripe_amount_reversed_cents >= 0),
  DROP CONSTRAINT IF EXISTS stripe_transfers_reversal_statut_check,
  ADD CONSTRAINT stripe_transfers_reversal_statut_check
    CHECK (stripe_reversal_statut IN ('AUCUN', 'PARTIEL', 'TOTAL'));

UPDATE public.stripe_transfers
SET stripe_amount_reversed_cents = ROUND(montant_soignant * 100)::integer,
    stripe_reversal_statut = 'TOTAL'
WHERE statut = 'REMBOURSE'
  AND stripe_reversal_statut = 'AUCUN';

COMMENT ON COLUMN public.stripe_transfers.stripe_amount_reversed_cents IS
  'Montant cumulé exact des TransferReversal Stripe, en centimes.';
COMMENT ON COLUMN public.stripe_transfers.stripe_reversal_statut IS
  'AUCUN, PARTIEL ou TOTAL. REMBOURSE n’est posé que pour TOTAL.';
