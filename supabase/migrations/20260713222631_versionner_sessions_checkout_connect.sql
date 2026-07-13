ALTER TABLE public.stripe_transfers
  ADD COLUMN IF NOT EXISTS stripe_checkout_session_id text;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_stripe_transfers_checkout_session
  ON public.stripe_transfers (stripe_checkout_session_id)
  WHERE stripe_checkout_session_id IS NOT NULL;

COMMENT ON COLUMN public.stripe_transfers.stripe_checkout_session_id IS
  'Checkout Session de la tentative Connect courante. Sert à reprendre une tentative active et à versionner déterministement la suivante après expiration.';
