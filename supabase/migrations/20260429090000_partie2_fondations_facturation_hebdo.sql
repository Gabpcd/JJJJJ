-- Partie 2 — Migration 1 : Fondations facturation hebdomadaire libérale
-- D1 (semaines ISO) + D2 (stratégie hybride ≤7j / >7j) + D8 (figée à
-- l'assignation) + D10 (Defacto opt-in) + D11 (statuts EN_GENERATION /
-- ERREUR_GENERATION).

-- 1. factures_honoraires : colonnes période + chaînage hebdo.
--    facture_precedente_id existe déjà dans le schéma.
ALTER TABLE public.factures_honoraires
  ADD COLUMN IF NOT EXISTS periode_debut date,
  ADD COLUMN IF NOT EXISTS periode_fin date,
  ADD COLUMN IF NOT EXISTS numero_semaine_iso smallint,
  ADD COLUMN IF NOT EXISTS annee_iso smallint,
  ADD COLUMN IF NOT EXISTS est_facture_finale_mission boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.factures_honoraires.periode_debut IS
  'Début de la période facturée (ISO date). FINALE_UNIQUE = mission.debut_le::date. Hebdo = lundi de la semaine ISO.';
COMMENT ON COLUMN public.factures_honoraires.periode_fin IS
  'Fin de la période facturée (ISO date inclusive). Finale = mission.fin_le::date. Hebdo = dimanche.';
COMMENT ON COLUMN public.factures_honoraires.numero_semaine_iso IS
  'Numéro de semaine ISO 8601 (1-53). NULL si facture finale unique.';
COMMENT ON COLUMN public.factures_honoraires.annee_iso IS
  'Année ISO 8601 (différente de l''année calendaire en bord d''année).';
COMMENT ON COLUMN public.factures_honoraires.est_facture_finale_mission IS
  'TRUE si facture finale (FINALE_UNIQUE ou facture finale partielle d''une mission HEBDO_ET_FINALE). FALSE si hebdo intermédiaire.';

-- 2. CHECK statut étendu : + EN_GENERATION (avant EMISE) + ERREUR_GENERATION
ALTER TABLE public.factures_honoraires
  DROP CONSTRAINT IF EXISTS factures_honoraires_statut_check;
ALTER TABLE public.factures_honoraires
  ADD CONSTRAINT factures_honoraires_statut_check CHECK (
    statut IN ('BROUILLON','EN_GENERATION','EMISE','PAYEE','ANNULEE',
               'FACTORISEE','EN_RETARD','REMPLACEE','ERREUR_GENERATION')
  );

-- 3. missions : strategie_facturation figée à l'assignation
DO $$ BEGIN
  CREATE TYPE public.strategie_facturation AS ENUM ('FINALE_UNIQUE','HEBDO_ET_FINALE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS strategie_facturation public.strategie_facturation;

COMMENT ON COLUMN public.missions.strategie_facturation IS
  'Stratégie figée à l''assignation par fn_geler_mission_a_assignation : FINALE_UNIQUE si durée ≤ 7 jours, HEBDO_ET_FINALE si > 7 jours. Une prolongation post-assignation NE modifie PAS la stratégie.';

-- 4. soignants : defacto_opt_in (D10)
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS defacto_opt_in boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.soignants.defacto_opt_in IS
  'Si true, à chaque facture EMISE le soignant est automatiquement cédé à Defacto pour paiement J+2 (frais affichés à l''inscription). Modifiable à tout moment dans le profil.';

-- 5. Index
CREATE INDEX IF NOT EXISTS idx_fh_mission_periode_fin
  ON public.factures_honoraires (mission_id, periode_fin DESC);

CREATE INDEX IF NOT EXISTS idx_fh_soignant_iso
  ON public.factures_honoraires (soignant_id, annee_iso, numero_semaine_iso)
  WHERE annee_iso IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_missions_statut_fin_le
  ON public.missions (statut, fin_le)
  WHERE statut IN ('EN_COURS','TERMINEE','ASSIGNEE');

-- 6. Contrainte unique partielle : empêche doublons hebdo
CREATE UNIQUE INDEX IF NOT EXISTS uniq_fh_mission_semaine_active
  ON public.factures_honoraires (mission_id, annee_iso, numero_semaine_iso, type_document)
  WHERE est_facture_finale_mission = false
    AND statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION');

-- 7. BACKFILL — factures existantes (toutes finales par définition)
UPDATE public.factures_honoraires fh
SET
  periode_debut = COALESCE(periode_debut, m.debut_le::date),
  periode_fin = COALESCE(periode_fin, m.fin_le::date),
  est_facture_finale_mission = true
FROM public.missions m
WHERE fh.mission_id = m.id
  AND (fh.periode_debut IS NULL OR fh.periode_fin IS NULL);

UPDATE public.factures_honoraires
SET periode_debut = date_emission, periode_fin = date_emission
WHERE periode_debut IS NULL OR periode_fin IS NULL;

-- 8. BACKFILL — missions existantes : strategie calculée rétroactivement
UPDATE public.missions
SET strategie_facturation = CASE
  WHEN (fin_le::date - debut_le::date) > 7 THEN 'HEBDO_ET_FINALE'::public.strategie_facturation
  ELSE 'FINALE_UNIQUE'::public.strategie_facturation
END
WHERE strategie_facturation IS NULL;

-- 9. NOT NULL post-backfill
ALTER TABLE public.factures_honoraires
  ALTER COLUMN periode_debut SET NOT NULL,
  ALTER COLUMN periode_fin SET NOT NULL;

ALTER TABLE public.missions
  ALTER COLUMN strategie_facturation SET NOT NULL;

ALTER TABLE public.missions
  ALTER COLUMN strategie_facturation SET DEFAULT 'FINALE_UNIQUE'::public.strategie_facturation;

NOTIFY pgrst, 'reload schema';
