-- Corrige deux surfaces de la matrice des modes d'exercice :
--   1. les professions visées par la lettre D21-031940 exposent les deux
--      textes primaires utiles, sans étendre la portée de l'arrêt : copie de
--      la lettre originale, puis CE n°491128 limité au cas aide-soignant ;
--   2. une mission IADE/IBODE exige cette profession exacte. La hiérarchie ne
--      fonctionne que dans l'autre sens : un profil IADE/IBODE peut remplir
--      une mission IDE, dont les règles IDE s'appliquent.

ALTER TABLE public.matrice_modes_exercice
  ADD COLUMN IF NOT EXISTS source_url_complementaire text;

COMMENT ON COLUMN public.matrice_modes_exercice.source_url_complementaire IS
  'Second texte officiel utile lorsque la force juridique ne peut pas être résumée par une URL unique.';

UPDATE public.matrice_modes_exercice
   SET source_libelle =
         'L''exercice libéral n''est pas prévu pour cette profession — lettre interministérielle du 30 décembre 2021 (n° D21-031940), validée par le Conseil d''État (11/02/2025, n°491128). Mission proposée en salarié.',
       source_url = 'https://www.fehap.fr/jcms/navigation-internet/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf',
       source_url_complementaire = 'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546'
 WHERE profession IN ('AUXILIAIRE_PUERICULTURE', 'IBODE', 'IADE')
   AND source_force = 'DOCTRINE';

-- Réaffirme les deux autres liens légaux affichés par la même surface. Ces
-- mises à jour portent uniquement sur le référentiel de conformité, jamais
-- sur les missions, comptes ou données de démonstration.
UPDATE public.matrice_modes_exercice
   SET source_url = 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033621093'
 WHERE profession = 'MANIPULATEUR_RADIO'
   AND source_force = 'LEGAL';

UPDATE public.matrice_modes_exercice
   SET source_url = 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000047567923'
 WHERE categorie_etablissement = 'centre_sante'
   AND source_force = 'LEGAL'
   AND source_libelle ILIKE '%L.6323-1-5%';

-- La Data API renvoie les deux liens sans les reconstruire côté client. Le
-- wording C7 et source_force=DOCTRINE restent inchangés ; le second lien est
-- explicitement présenté dans l'UI comme le seul cas aide-soignant jugé.
CREATE OR REPLACE FUNCTION public.fn_mode_exercice(
  p_profession text,
  p_type_etab text,
  p_finess_secteur text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_cat text;
  v_row public.matrice_modes_exercice%ROWTYPE;
BEGIN
  v_cat := public.fn_categorie_etablissement(p_type_etab, p_finess_secteur);
  SELECT * INTO v_row
  FROM public.matrice_modes_exercice
  WHERE profession = p_profession
    AND categorie_etablissement = v_cat;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'niveau', v_row.niveau,
      'categorie', v_cat,
      'source_libelle', v_row.source_libelle,
      'source_force', v_row.source_force,
      'source_url', v_row.source_url,
      'source_url_complementaire', v_row.source_url_complementaire
    );
  END IF;

  RETURN jsonb_build_object(
    'niveau', 'NON_PROPOSE',
    'categorie', v_cat,
    'source_libelle', 'Jolene propose cette mission en salarié : l''exercice libéral au sein d''un établissement expose à une requalification.',
    'source_force', 'CONFORMITE_JOLENE',
    'source_url', NULL,
    'source_url_complementaire', NULL
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_soignant_compatible_mission(
  p_soignant_profession public.type_profession,
  p_soignant_specialite text,
  p_mission_profession public.type_profession,
  p_mission_specialite text,
  p_accepte_non_specialises boolean
) RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    -- La profession requise par la mission prime. Un match exact est accepté ;
    -- pour les médecins, la souplesse ne porte que sur la spécialité médicale.
    WHEN p_soignant_profession = p_mission_profession THEN
      CASE
        WHEN p_mission_profession = 'MEDECIN'
             AND p_mission_specialite IS NOT NULL
             AND p_mission_specialite <> '' THEN
          COALESCE(p_accepte_non_specialises, true)
          OR COALESCE(p_soignant_specialite, '') = p_mission_specialite
        ELSE TRUE
      END
    -- IADE et IBODE sont aussi IDE : ils peuvent candidater à une mission IDE,
    -- laquelle reste résolue selon la cellule IDE de la matrice.
    WHEN p_mission_profession = 'IDE'
         AND p_soignant_profession IN ('IBODE', 'IADE') THEN TRUE
    -- Le sens inverse est interdit : une mission IADE/IBODE ne peut pas être
    -- transformée en mission d'assistance ouverte à un IDE non spécialisé.
    ELSE FALSE
  END;
$function$;

COMMENT ON FUNCTION public.fn_soignant_compatible_mission(
  public.type_profession, text, public.type_profession, text, boolean
) IS
  'Compatibilité lue sur la profession requise : match exact, plus IADE/IBODE vers mission IDE uniquement. Une mission IADE/IBODE exige la spécialité correspondante.';

-- Défense en profondeur pour les créations/éditions futures. Aucun backfill :
-- les lignes historiques restent intactes et le booléen est désormais ignoré
-- par la fonction de compatibilité pour IADE/IBODE.
CREATE OR REPLACE FUNCTION public.dec_normaliser_specialite_infirmiere_mission()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.profession_requise IN ('IBODE', 'IADE') THEN
    NEW.accepte_non_specialises := false;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_normaliser_specialite_infirmiere_mission ON public.missions;
CREATE TRIGGER trg_normaliser_specialite_infirmiere_mission
BEFORE INSERT OR UPDATE
ON public.missions
FOR EACH ROW
EXECUTE FUNCTION public.dec_normaliser_specialite_infirmiere_mission();

REVOKE ALL ON FUNCTION public.dec_normaliser_specialite_infirmiere_mission()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_normaliser_specialite_infirmiere_mission()
  TO service_role;
