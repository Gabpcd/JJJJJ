-- Interne en médecine : licence de remplacement (délivrée par le Conseil de l'Ordre)
-- autorisant le remplacement de médecin. Justificatif DISTINCT de l'attestation de
-- scolarité (vérif IA dédiée). Appliquée en prod via MCP puis enregistrée.

-- Nouveau type de document (idempotent ; déjà appliqué hors transaction en prod)
ALTER TYPE public.type_document ADD VALUE IF NOT EXISTS 'LICENCE_REMPLACEMENT';

-- Niveau vérifié sur soignants
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS licence_remplacement_verifiee boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS licence_remplacement_le timestamptz,
  ADD COLUMN IF NOT EXISTS licence_remplacement_valide_jusqua date,
  ADD COLUMN IF NOT EXISTS licence_remplacement_specialite text;
