-- Tracking d'envoi du template de prospection (envoi en masse) : un prospect
-- n'est emailé qu'une fois (email_envoye_le sert de garde anti-doublon).
ALTER TABLE public.prospects_etablissements ADD COLUMN IF NOT EXISTS email_envoye_le timestamptz;
ALTER TABLE public.prospects_soignants ADD COLUMN IF NOT EXISTS email_envoye_le timestamptz;
CREATE INDEX IF NOT EXISTS idx_prospects_etab_email_a_envoyer ON public.prospects_etablissements (email) WHERE email IS NOT NULL AND email_envoye_le IS NULL;
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_email_a_envoyer ON public.prospects_soignants (email) WHERE email IS NOT NULL AND email_envoye_le IS NULL;
