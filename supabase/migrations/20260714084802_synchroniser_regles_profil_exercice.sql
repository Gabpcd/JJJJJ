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
ON CONFLICT (profession) DO UPDATE
SET types_exercice_autorises = EXCLUDED.types_exercice_autorises,
    description = EXCLUDED.description;
