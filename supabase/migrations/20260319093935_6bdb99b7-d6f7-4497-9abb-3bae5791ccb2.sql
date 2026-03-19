
-- Add type_exercice column to soignants table
-- Values: 'SALARIE' (default), 'LIBERAL', 'MIXTE'
ALTER TABLE public.soignants 
ADD COLUMN IF NOT EXISTS type_exercice text NOT NULL DEFAULT 'SALARIE';

-- Add attestation_cumul column (true if caregiver attested L1222-5 compliance)
ALTER TABLE public.soignants 
ADD COLUMN IF NOT EXISTS attestation_cumul_activite boolean NOT NULL DEFAULT false;

-- Add est_salarie_etablissement for registration question
ALTER TABLE public.soignants 
ADD COLUMN IF NOT EXISTS est_salarie_etablissement boolean DEFAULT NULL;
