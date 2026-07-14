-- Le snapshot de schéma ne contenait pas les données du référentiel de profil.
-- Un environnement reconstruit depuis les migrations considérait donc toutes
-- les professions comme salariées uniquement, alors que la production avait
-- quinze lignes créées historiquement hors migration. Ce seed rend les 17
-- valeurs de l'enum reproductibles.
--
-- Ces règles décrivent le PROFIL du soignant. La décision d'une mission reste
-- exclusivement fondée sur missions.profession_requise via fn_mode_exercice :
-- un profil IADE/IBODE peut ainsi accepter une mission IDE libérale, tandis
-- qu'une mission demandant IADE ou IBODE reste toujours salariée.

INSERT INTO public.regles_exercice_profession (
  profession,
  types_exercice_autorises,
  description
)
VALUES
  (
    'IDE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil IDE — salarié, libéral ou mixte ; chaque mission applique les règles de la profession demandée.'
  ),
  (
    'AS', ARRAY['SALARIE']::text[],
    'Profil aide-soignant — salarié uniquement.'
  ),
  (
    'AES', ARRAY['SALARIE']::text[],
    'Profil accompagnant éducatif et social — salarié uniquement.'
  ),
  (
    'IBODE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil IBODE — libéral ou mixte uniquement pour les missions IDE compatibles ; toute mission IBODE est salariée.'
  ),
  (
    'IADE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil IADE — libéral ou mixte uniquement pour les missions IDE compatibles ; toute mission IADE est salariée.'
  ),
  (
    'SAGE_FEMME', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil sage-femme — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'KINE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil kinésithérapeute — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'MEDECIN', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil médecin — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'PHARMACIEN', ARRAY['SALARIE']::text[],
    'Profil pharmacien — les missions d’établissement Jolene sont salariées.'
  ),
  (
    'MANIPULATEUR_RADIO', ARRAY['SALARIE']::text[],
    'Profil manipulateur en électroradiologie médicale — salarié uniquement.'
  ),
  (
    'PREPARATEUR_PHARMA', ARRAY['SALARIE']::text[],
    'Profil préparateur en pharmacie — salarié uniquement.'
  ),
  (
    'DIETETICIEN', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil diététicien — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'ERGOTHERAPEUTE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil ergothérapeute — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'PSYCHOMOTRICIEN', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil psychomotricien — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'ORTHOPHONISTE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil orthophoniste — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'DENTISTE', ARRAY['SALARIE', 'LIBERAL', 'MIXTE']::text[],
    'Profil chirurgien-dentiste — salarié, libéral ou mixte selon la mission.'
  ),
  (
    'AUXILIAIRE_PUERICULTURE', ARRAY['SALARIE']::text[],
    'Profil auxiliaire de puériculture — salarié uniquement.'
  )
ON CONFLICT (profession) DO NOTHING;

-- Ne réécrit jamais silencieusement une configuration déjà présente en
-- production. Une divergence bloque la migration et impose une revue métier.
DO $verifier_regles_profils$
DECLARE
  v_ecarts text;
BEGIN
  WITH attendu(profession, types_exercice_autorises) AS (
    VALUES
      ('IDE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('AS'::public.type_profession, ARRAY['SALARIE']::text[]),
      ('AES'::public.type_profession, ARRAY['SALARIE']::text[]),
      ('IBODE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('IADE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('SAGE_FEMME'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('KINE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('MEDECIN'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('PHARMACIEN'::public.type_profession, ARRAY['SALARIE']::text[]),
      ('MANIPULATEUR_RADIO'::public.type_profession, ARRAY['SALARIE']::text[]),
      ('PREPARATEUR_PHARMA'::public.type_profession, ARRAY['SALARIE']::text[]),
      ('DIETETICIEN'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('ERGOTHERAPEUTE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('PSYCHOMOTRICIEN'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('ORTHOPHONISTE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('DENTISTE'::public.type_profession, ARRAY['SALARIE','LIBERAL','MIXTE']::text[]),
      ('AUXILIAIRE_PUERICULTURE'::public.type_profession, ARRAY['SALARIE']::text[])
  )
  SELECT string_agg(a.profession::text, ', ' ORDER BY a.profession::text)
  INTO v_ecarts
  FROM attendu a
  LEFT JOIN public.regles_exercice_profession r
    ON r.profession = a.profession
  WHERE r.profession IS NULL
     OR r.types_exercice_autorises IS DISTINCT FROM a.types_exercice_autorises;

  IF v_ecarts IS NOT NULL THEN
    RAISE EXCEPTION
      'Règles de profil divergentes, migration interrompue : %', v_ecarts;
  END IF;
END;
$verifier_regles_profils$;
