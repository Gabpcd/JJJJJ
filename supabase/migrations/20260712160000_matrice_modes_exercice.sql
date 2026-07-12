-- ⏳ NON APPLIQUÉE EN PROD — proposition (hard stop n°4). Artefact 2 = le SEED
-- ci-dessous, à relire (relecture éclair Gabrielle) avant apply + merge.
--
-- Matrice des modes d'exercice (profession × catégorie d'établissement) en TABLE
-- PARAMÉTRÉE, 3 niveaux (AUTORISE / NON_PROPOSE / BLOQUE). Remplace la règle en dur
-- (fn_profession_peut_etre_liberal binaire + LIBERAL_COMPATIBILITY front + trigger).
-- Défaut (C6) = NON_PROPOSE (salarié) : toute combinaison absente tombe en salarié ;
-- AUTORISE n'existe que par cellule explicite et sourcée. Lecture sur la PROFESSION
-- REQUISE PAR LA MISSION, jamais les diplômes du soignant.
--
-- Sources : arrêt CE n°491128 (11/02/2025, CETATEXT000051156546) — AS JUGÉ ;
-- lettre interministérielle 30/12/2021 (n° D21-031940) — AUX_PUERICULTURE/IBODE/IADE
-- doctrine ; L.6323-1-5 CSP — centre de santé = salariat (tous professionnels).

-- 1) Table
CREATE TABLE IF NOT EXISTS public.matrice_modes_exercice (
  profession text NOT NULL,
  categorie_etablissement text NOT NULL
    CHECK (categorie_etablissement IN ('cabinet_liberal','prive','centre_sante','public')),
  niveau text NOT NULL CHECK (niveau IN ('AUTORISE','NON_PROPOSE','BLOQUE')),
  source_libelle text NOT NULL,
  source_force text NOT NULL CHECK (source_force IN ('JUGE','DOCTRINE','LEGAL','CONFORMITE_JOLENE')),
  PRIMARY KEY (profession, categorie_etablissement)
);
ALTER TABLE public.matrice_modes_exercice ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS matrice_modes_exercice_lecture ON public.matrice_modes_exercice;
CREATE POLICY matrice_modes_exercice_lecture ON public.matrice_modes_exercice FOR SELECT TO authenticated USING (true);

-- 2) Catégorisation d'un type d'établissement (+ secteur FINESS pour lever l'ambiguïté
--    public/privé des EHPAD/SSIAD/HAD…). Cabinets libéraux = remplacement libéral.
CREATE OR REPLACE FUNCTION public.fn_categorie_etablissement(p_type text, p_finess_secteur text DEFAULT NULL)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $function$
  SELECT CASE
    WHEN p_type LIKE 'CABINET_%' THEN 'cabinet_liberal'
    WHEN p_type = 'CENTRE_SANTE' THEN 'centre_sante'
    WHEN p_type = 'HOPITAL_PUBLIC' THEN 'public'
    WHEN upper(COALESCE(p_finess_secteur,'')) LIKE 'PUBLIC%' THEN 'public'
    ELSE 'prive'
  END;
$function$;

-- 3) Résolution du mode d'exercice (niveau + source) — défaut NON_PROPOSE (C6).
CREATE OR REPLACE FUNCTION public.fn_mode_exercice(p_profession text, p_type_etab text, p_finess_secteur text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $function$
DECLARE v_cat text; v_row public.matrice_modes_exercice%ROWTYPE;
BEGIN
  v_cat := public.fn_categorie_etablissement(p_type_etab, p_finess_secteur);
  SELECT * INTO v_row FROM public.matrice_modes_exercice
    WHERE profession = p_profession AND categorie_etablissement = v_cat;
  IF FOUND THEN
    RETURN jsonb_build_object('niveau', v_row.niveau, 'categorie', v_cat,
      'source_libelle', v_row.source_libelle, 'source_force', v_row.source_force);
  END IF;
  -- Défaut C6 : salarié.
  RETURN jsonb_build_object('niveau','NON_PROPOSE','categorie',v_cat,
    'source_libelle','Jolene propose cette mission en salarié : l''exercice libéral au sein d''un établissement expose à une requalification.',
    'source_force','CONFORMITE_JOLENE');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_categorie_etablissement(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mode_exercice(text, text, text) TO authenticated;

-- 4) SEED (artefact 2 — relecture éclair). On ne seede QUE le non-défaut
--    (AUTORISE + BLOQUE) ; NON_PROPOSE = défaut.
DELETE FROM public.matrice_modes_exercice;

-- Wordings sources réutilisés
-- BLOQUE AS (JUGÉ)
INSERT INTO public.matrice_modes_exercice(profession, categorie_etablissement, niveau, source_libelle, source_force) VALUES
  ('AS','cabinet_liberal','BLOQUE','L''exercice libéral n''est pas ouvert aux aides-soignants (Conseil d''État, 11/02/2025, n°491128). Mission proposée en salarié.','JUGE'),
  ('AS','prive','BLOQUE','L''exercice libéral n''est pas ouvert aux aides-soignants (Conseil d''État, 11/02/2025, n°491128). Mission proposée en salarié.','JUGE'),
  ('AS','centre_sante','BLOQUE','L''exercice libéral n''est pas ouvert aux aides-soignants (Conseil d''État, 11/02/2025, n°491128). Mission proposée en salarié.','JUGE'),
  ('AS','public','BLOQUE','L''exercice libéral n''est pas ouvert aux aides-soignants (Conseil d''État, 11/02/2025, n°491128). Mission proposée en salarié.','JUGE');

-- BLOQUE professions de la lettre (doctrine, double source C7) : AUXILIAIRE_PUERICULTURE, IBODE, IADE
INSERT INTO public.matrice_modes_exercice(profession, categorie_etablissement, niveau, source_libelle, source_force)
SELECT p, c, 'BLOQUE',
  'L''exercice libéral n''est pas prévu pour cette profession (lettre interministérielle du 30 décembre 2021, n° D21-031940, validée par le Conseil d''État — 11/02/2025, n°491128). Mission proposée en salarié.','DOCTRINE'
FROM unnest(ARRAY['AUXILIAIRE_PUERICULTURE','IBODE','IADE']) p,
     unnest(ARRAY['cabinet_liberal','prive','centre_sante','public']) c;

-- BLOQUE professions sans cadre libéral : AES, PREPARATEUR_PHARMA, MANIPULATEUR_RADIO (C4)
INSERT INTO public.matrice_modes_exercice(profession, categorie_etablissement, niveau, source_libelle, source_force)
SELECT p, c, 'BLOQUE',
  'Cette profession n''a pas de cadre d''exercice libéral. Mission proposée en salarié.','LEGAL'
FROM unnest(ARRAY['AES','PREPARATEUR_PHARMA','MANIPULATEUR_RADIO']) p,
     unnest(ARRAY['cabinet_liberal','prive','centre_sante','public']) c;

-- Centre de santé = salariat pour TOUS (L.6323-1-5 CSP) — BLOQUE toutes professions non déjà bloquées
INSERT INTO public.matrice_modes_exercice(profession, categorie_etablissement, niveau, source_libelle, source_force)
SELECT p, 'centre_sante', 'BLOQUE',
  'Au sein d''un centre de santé, les professionnels sont salariés (art. L.6323-1-5 du code de la santé publique).','LEGAL'
FROM unnest(ARRAY['MEDECIN','DENTISTE','SAGE_FEMME','IDE','KINE','ORTHOPHONISTE','DIETETICIEN','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','PHARMACIEN']) p
ON CONFLICT (profession, categorie_etablissement) DO NOTHING;

-- AUTORISE praticiens (MEDECIN, DENTISTE, SAGE_FEMME) : cabinet libéral + établissement privé
INSERT INTO public.matrice_modes_exercice(profession, categorie_etablissement, niveau, source_libelle, source_force)
SELECT p, c, 'AUTORISE',
  'Exercice libéral proposé (contrat d''exercice libéral, honoraires facturés directement).','CONFORMITE_JOLENE'
FROM unnest(ARRAY['MEDECIN','DENTISTE','SAGE_FEMME']) p,
     unnest(ARRAY['cabinet_liberal','prive']) c
ON CONFLICT (profession, categorie_etablissement) DO NOTHING;

-- AUTORISE IDE + paramédicaux à exercice libéral, UNIQUEMENT en cabinet libéral (remplacement)
-- (en établissement privé/public → défaut NON_PROPOSE ; en centre de santé → BLOQUE ci-dessus)
INSERT INTO public.matrice_modes_exercice(profession, categorie_etablissement, niveau, source_libelle, source_force)
SELECT p, 'cabinet_liberal', 'AUTORISE',
  'Exercice libéral proposé (remplacement en cabinet libéral).','CONFORMITE_JOLENE'
FROM unnest(ARRAY['IDE','KINE','ORTHOPHONISTE','DIETETICIEN','ERGOTHERAPEUTE','PSYCHOMOTRICIEN']) p
ON CONFLICT (profession, categorie_etablissement) DO NOTHING;

-- NB : PHARMACIEN → aucune cellule AUTORISE ni BLOQUE (hors centre de santé) → tombe en
-- défaut NON_PROPOSE (C3, PUI salarié). IADE/IBODE profil peut candidater mission IDE →
-- la matrice est lue sur la profession REQUISE (IDE), pas sur les diplômes.
