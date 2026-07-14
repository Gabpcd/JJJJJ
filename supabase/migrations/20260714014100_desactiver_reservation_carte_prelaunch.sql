-- STRIPE_RESERVATION utilisait capture_method=manual sans workflow durable de
-- capture/réautorisation. Une autorisation carte peut expirer avant la mission :
-- ce mode est donc retiré du lancement public, au profit de la facture mensuelle
-- (ou du SEPA déjà configuré explicitement).

UPDATE public.etablissements
SET mode_paiement_commission = 'FACTURE_MENSUELLE'
WHERE mode_paiement_commission = 'STRIPE_RESERVATION';

ALTER TABLE public.etablissements
  DROP CONSTRAINT IF EXISTS etablissements_mode_paiement_commission_check;

ALTER TABLE public.etablissements
  ADD CONSTRAINT etablissements_mode_paiement_commission_check
  CHECK (mode_paiement_commission = ANY (
    ARRAY['FACTURE_MENSUELLE'::text, 'SEPA_DEBIT'::text, 'CHORUS_PRO'::text]
  ));

ALTER TABLE public.etablissements
  ALTER COLUMN mode_paiement_commission SET DEFAULT 'FACTURE_MENSUELLE';
