-- Finalise l'encodage validé C1-C7 après l'application partielle de
-- 20260712160000. La décision de mission est lue exclusivement depuis
-- matrice_modes_exercice sur la profession_requise de la mission.

ALTER TABLE public.matrice_modes_exercice
  ADD COLUMN IF NOT EXISTS source_url text;

GRANT SELECT ON TABLE public.matrice_modes_exercice TO authenticated, service_role;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.matrice_modes_exercice FROM anon, authenticated;

-- Seed complet. Les cellules absentes sont intentionnelles et résolues par
-- fn_mode_exercice en NON_PROPOSE. En particulier, aucune cellule "public"
-- n'est seedée : salarié par défaut pour toutes les professions (C6).
DELETE FROM public.matrice_modes_exercice;

-- Aide-soignant : JUGÉ par le Conseil d'État. Le public reste au défaut C6.
INSERT INTO public.matrice_modes_exercice
  (profession, categorie_etablissement, niveau, source_libelle, source_force, source_url)
SELECT 'AS', c, 'BLOQUE',
  'L''exercice libéral n''est pas ouvert aux aides-soignants (Conseil d''État, 11/02/2025, n°491128). Mission proposée en salarié.',
  'JUGE',
  'https://www.legifrance.gouv.fr/ceta/id/CETATEXT000051156546'
FROM unnest(ARRAY['cabinet_liberal','prive','centre_sante']) c;

-- Professions visées par la lettre et présentes dans Jolene : doctrine
-- ministérielle + cadre d'actes sans exercice libéral autonome. Le CE n'a jugé
-- au fond que le cas AS ; sa décision valide la mise en garde contestée en tant
-- qu'elle vise cette profession.
INSERT INTO public.matrice_modes_exercice
  (profession, categorie_etablissement, niveau, source_libelle, source_force, source_url)
SELECT p, c, 'BLOQUE',
  'L''exercice libéral n''est pas prévu pour cette profession (lettre interministérielle du 30 décembre 2021, n° D21-031940, validée par le Conseil d''État — 11/02/2025, n°491128). Mission proposée en salarié.',
  'DOCTRINE',
  'https://www.fehap.fr/jcms/navigation-internet/upload/docs/application/pdf/2023-02/courrierconjointministeres_30decembre2021_.pdf'
FROM unnest(ARRAY['AUXILIAIRE_PUERICULTURE','IBODE','IADE']) p,
     unnest(ARRAY['cabinet_liberal','prive','centre_sante']) c;

-- Professions sans cadre d'exercice libéral propre. Pour le manipulateur radio,
-- L.4351-1 CSP impose prescription et responsabilité d'un médecin ; aucun acte
-- n'est coté en propre dans la NGAP. Le public reste au défaut C6.
INSERT INTO public.matrice_modes_exercice
  (profession, categorie_etablissement, niveau, source_libelle, source_force, source_url)
SELECT p, c, 'BLOQUE',
  CASE p
    WHEN 'MANIPULATEUR_RADIO' THEN 'Cette profession n''a pas de cadre d''exercice libéral propre : les actes sont réalisés sur prescription et sous la responsabilité d''un médecin (art. L.4351-1 du code de la santé publique). Mission proposée en salarié.'
    ELSE 'Cette profession n''a pas de cadre d''exercice libéral. Mission proposée en salarié.'
  END,
  'LEGAL',
  CASE p
    WHEN 'MANIPULATEUR_RADIO' THEN 'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033621093'
    ELSE NULL
  END
FROM unnest(ARRAY['AES','PREPARATEUR_PHARMA','MANIPULATEUR_RADIO']) p,
     unnest(ARRAY['cabinet_liberal','prive','centre_sante']) c;

-- Centre de santé : interdiction légale de l'exercice non salarié pour toutes
-- les professions restantes (C5). Les conflits précédents conservent la source
-- propre à la profession, sans changer l'issue BLOQUE.
INSERT INTO public.matrice_modes_exercice
  (profession, categorie_etablissement, niveau, source_libelle, source_force, source_url)
SELECT p, 'centre_sante', 'BLOQUE',
  'Au sein d''un centre de santé, les professionnels sont salariés (art. L.6323-1-5 du code de la santé publique).',
  'LEGAL',
  'https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000047567923'
FROM unnest(ARRAY[
  'MEDECIN','DENTISTE','SAGE_FEMME','IDE','KINE','ORTHOPHONISTE',
  'DIETETICIEN','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','PHARMACIEN'
]) p
ON CONFLICT (profession, categorie_etablissement) DO NOTHING;

-- Praticiens : libéral explicitement proposé en cabinet et établissement privé.
INSERT INTO public.matrice_modes_exercice
  (profession, categorie_etablissement, niveau, source_libelle, source_force, source_url)
SELECT p, c, 'AUTORISE',
  'Exercice libéral proposé (contrat d''exercice libéral, honoraires facturés directement).',
  'CONFORMITE_JOLENE', NULL
FROM unnest(ARRAY['MEDECIN','DENTISTE','SAGE_FEMME']) p,
     unnest(ARRAY['cabinet_liberal','prive']) c;

-- IDE et paramédicaux : remplacement libéral uniquement en cabinet. En
-- établissement privé, PHARMACIEN compris, l'absence de cellule déclenche le
-- défaut NON_PROPOSE. Une mission IADE/IBODE n'a aucune cellule AUTORISE.
INSERT INTO public.matrice_modes_exercice
  (profession, categorie_etablissement, niveau, source_libelle, source_force, source_url)
SELECT p, 'cabinet_liberal', 'AUTORISE',
  'Exercice libéral proposé (remplacement en cabinet libéral).',
  'CONFORMITE_JOLENE', NULL
FROM unnest(ARRAY['IDE','KINE','ORTHOPHONISTE','DIETETICIEN','ERGOTHERAPEUTE','PSYCHOMOTRICIEN']) p;

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
      'source_url', v_row.source_url
    );
  END IF;

  RETURN jsonb_build_object(
    'niveau', 'NON_PROPOSE',
    'categorie', v_cat,
    'source_libelle', 'Jolene propose cette mission en salarié : l''exercice libéral au sein d''un établissement expose à une requalification.',
    'source_force', 'CONFORMITE_JOLENE',
    'source_url', NULL
  );
END;
$function$;

-- Compatibilité historique conservée pour les consommateurs existants, mais
-- désormais résolue par la table et non par un CASE juridique en dur.
CREATE OR REPLACE FUNCTION public.peut_exercer_liberal(
  p_profession text,
  p_type_etablissement text
) RETURNS boolean
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (public.fn_mode_exercice(p_profession, p_type_etablissement, NULL)->>'niveau') = 'AUTORISE',
    false
  );
$function$;

-- Cette fonction historique est PROFIL-level, pas mission-level. Elle lit le
-- référentiel de profil existant afin qu'un profil IADE/IBODE reste valide ; la
-- décision sur une mission est exclusivement fn_mode_exercice(profession_requise,…).
CREATE OR REPLACE FUNCTION public.fn_profession_peut_etre_liberal(p_profession text)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    EXISTS (
      SELECT 1
      FROM public.regles_exercice_profession r
      WHERE r.profession::text = p_profession
        AND r.types_exercice_autorises && ARRAY['LIBERAL','MIXTE']::text[]
    ),
    false
  );
$function$;

-- Un seul trigger décide le type de mission à partir de la profession requise.
-- TOUS se rabat sur SALARIE si le libéral n'est pas explicitement AUTORISE ; une
-- demande LIBERAL est refusée avec le wording exact stocké dans la table.
CREATE OR REPLACE FUNCTION public.dec_valider_compatibilite_mission_liberal()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type_etab text;
  v_est_public boolean;
  v_mode jsonb;
BEGIN
  SELECT type::text, COALESCE(est_secteur_public, false)
  INTO v_type_etab, v_est_public
  FROM public.etablissements
  WHERE id = NEW.etablissement_id;

  IF NEW.profession_requise IS NULL OR v_type_etab IS NULL THEN
    RETURN NEW;
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_type_etab,
    CASE WHEN v_est_public THEN 'PUBLIC' ELSE NULL END
  );

  IF NEW.type_contrat_recherche = 'LIBERAL'
     AND v_mode->>'niveau' <> 'AUTORISE' THEN
    RAISE EXCEPTION '%', v_mode->>'source_libelle';
  END IF;

  IF NEW.type_contrat_recherche = 'TOUS'
     AND v_mode->>'niveau' <> 'AUTORISE' THEN
    NEW.type_contrat_recherche := 'SALARIE';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_valider_type_contrat_mission ON public.missions;

REVOKE ALL ON FUNCTION public.fn_mode_exercice(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mode_exercice(text, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_categorie_etablissement(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_categorie_etablissement(text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.peut_exercer_liberal(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.peut_exercer_liberal(text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_profession_peut_etre_liberal(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_profession_peut_etre_liberal(text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.dec_valider_compatibilite_mission_liberal() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_valider_compatibilite_mission_liberal() TO service_role;
