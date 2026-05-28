-- Chantier 1 — Colonnes vérification ADELI (parallèles au RPPS)
--
-- Professions concernées : orthophoniste, ergothérapeute, psychomotricien,
-- diététicien, manipulateur radio (professions à ADELI sans RPPS historique,
-- bien que migrées dans le RPPS depuis oct. 2024).

ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS adeli_verifie BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS adeli_verifie_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS adeli_nom_api TEXT,
  ADD COLUMN IF NOT EXISTS adeli_prenom_api TEXT,
  ADD COLUMN IF NOT EXISTS adeli_profession_api TEXT;

COMMENT ON COLUMN public.soignants.adeli_verifie IS
  'Vérification ADELI via API FHIR Annuaire Santé (esante.gouv.fr). '
  'TRUE = identité cross-checkée avec le registre national.';

NOTIFY pgrst, 'reload schema';
