-- PHASE 1 — Fondation vérification établissement (symétrie soignant).
-- Colonnes additives (sûres). Les flags finess_verifie/finess_verifie_le existaient
-- déjà ; on ajoute les données structurées renvoyées par l'API FHIR Organization +
-- les colonnes du dispositif adaptatif de rattachement personne↔établissement.

-- Données FINESS récupérées via l'API FHIR Organization (raison sociale officielle,
-- catégorie, secteur, public/privé) — validé sur l'API réelle (système d'identifiant
-- FINESS = https://finess.esante.gouv.fr).
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS finess_raison_sociale text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS finess_categorie text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS finess_secteur text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS finess_est_public boolean;

-- Dirigeants exploitables (API INSEE recherche-entreprises) — pour le match auto
-- identité↔titulaire sur les petites structures (personne physique).
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS dirigeants jsonb;

-- Représentant (personne physique inscrite) + sa pièce d'identité (traçabilité).
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_nom text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_prenom text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_identite_verifiee boolean NOT NULL DEFAULT false;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS representant_identite_verifiee_le timestamptz;

-- Dispositif adaptatif de rattachement personne↔établissement.
-- methode : AUTO_DIRIGEANT (match INSEE) | EMAIL_PRO (lien confirmé) | ADMIN (fallback)
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS rattachement_methode text;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS rattachement_verifie boolean NOT NULL DEFAULT false;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS rattachement_verifie_le timestamptz;

-- Email de contact vérifié (lien de confirmation) — pour le cas "gros établissement".
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS email_contact_verifie boolean NOT NULL DEFAULT false;
ALTER TABLE public.etablissements ADD COLUMN IF NOT EXISTS email_contact_verifie_le timestamptz;

ALTER TABLE public.etablissements DROP CONSTRAINT IF EXISTS etablissements_rattachement_methode_check;
ALTER TABLE public.etablissements ADD CONSTRAINT etablissements_rattachement_methode_check
  CHECK (rattachement_methode IS NULL OR rattachement_methode IN ('AUTO_DIRIGEANT','EMAIL_PRO','ADMIN'));
