-- ============================================================
-- CP-LITIGES-7a FIX 3 — missions.type_contrat_applique (structure + backfill)
-- ============================================================
-- Ajoute une colonne sur public.missions qui fige le type de contrat
-- RÉELLEMENT appliqué à la mission (LIBERAL ou SALARIE), par opposition à
-- `type_contrat_recherche` (LIBERAL / SALARIE / TOUS = souhait étab) et
-- `choix_contrat_soignant` (choix brut côté soignant MIXTE, nullable).
--
-- Objectif : fiabiliser la fenêtre de contestation (72h libéral / 5 j.o.
-- salarié) en lisant cette valeur figée au lieu de recalculer depuis le
-- profil soignant (qui peut basculer MIXTE→LIBERAL entre assignation et
-- contestation).
--
-- Backfill : pour chaque mission déjà assignée (soignant_assigne_id
-- NOT NULL), on dérive type_contrat_applique depuis les champs existants
-- par ordre de priorité :
--   1. type_paiement_soignant = 'NOTE_HONORAIRES' → LIBERAL
--   2. type_paiement_soignant = 'BULLETIN_PAIE'   → SALARIE
--   3. choix_contrat_soignant IN ('LIBERAL','SALARIE') → ce choix
--   4. soignant.type_exercice IN ('LIBERAL','SALARIE') → idem
--   5. soignant.type_exercice = 'MIXTE' non tranché → NULL (flag manuel)
--
-- Consommation (fn_fenetre_contestation_ouverte, etc.) : FIX ultérieur.
-- ============================================================

BEGIN;

-- Enum dédié, 2 valeurs seulement (MIXTE est un état de profil, pas
-- une application possible : une mission est soit salariée, soit libérale).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'type_contrat_applique_enum') THEN
    CREATE TYPE public.type_contrat_applique_enum AS ENUM ('LIBERAL', 'SALARIE');
  END IF;
END $$;

ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS type_contrat_applique public.type_contrat_applique_enum;

COMMENT ON COLUMN public.missions.type_contrat_applique IS
  'CP-LITIGES-7a FIX 3 — type de contrat réellement appliqué à la mission, '
  'figé au moment de l''assignation. NULL tant que soignant_assigne_id est '
  'NULL ou si le backfill n''a pas pu trancher (MIXTE ambigu).';

-- Backfill depuis les colonnes existantes.
UPDATE public.missions m
   SET type_contrat_applique = CASE
     WHEN m.type_paiement_soignant = 'NOTE_HONORAIRES' THEN 'LIBERAL'::public.type_contrat_applique_enum
     WHEN m.type_paiement_soignant = 'BULLETIN_PAIE'   THEN 'SALARIE'::public.type_contrat_applique_enum
     WHEN m.choix_contrat_soignant = 'LIBERAL'         THEN 'LIBERAL'::public.type_contrat_applique_enum
     WHEN m.choix_contrat_soignant = 'SALARIE'         THEN 'SALARIE'::public.type_contrat_applique_enum
     WHEN s.type_exercice = 'LIBERAL'                  THEN 'LIBERAL'::public.type_contrat_applique_enum
     WHEN s.type_exercice = 'SALARIE'                  THEN 'SALARIE'::public.type_contrat_applique_enum
     ELSE NULL
   END
  FROM public.soignants s
 WHERE m.soignant_assigne_id = s.id
   AND m.type_contrat_applique IS NULL;

COMMIT;
