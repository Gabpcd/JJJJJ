-- Régression du refus 42501 constaté sur le parcours public. Aucune fixture,
-- ligne personnelle, écriture métier ou invocation de fournisseur.
BEGIN;
SET LOCAL statement_timeout = '10s';
DO $test$
DECLARE r jsonb; attendu jsonb;
BEGIN
  IF NOT has_function_privilege('anon', 'public.fn_apercu_marche_profession(text,double precision,double precision,integer)', 'EXECUTE')
    OR NOT has_function_privilege('authenticated', 'public.fn_apercu_marche_profession(text,double precision,double precision,integer)', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.fn_apercu_marche_profession(text,double precision,double precision,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Droit explicite aperçu public manquant';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  EXECUTE 'SET LOCAL ROLE anon';
  r := public.fn_apercu_marche_profession(NULL, NULL, NULL, NULL);
  IF r IS NULL OR jsonb_typeof(r) IS DISTINCT FROM 'object'
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k)
       IS DISTINCT FROM ARRAY['nb_etablissements','nb_missions','taux_max','taux_moyen','zone']
    OR r->>'zone' IS DISTINCT FROM 'national'
    OR jsonb_typeof(r->'nb_missions') IS DISTINCT FROM 'number'
    OR jsonb_typeof(r->'nb_etablissements') IS DISTINCT FROM 'number' THEN
    RAISE EXCEPTION 'Projection publique aperçu incorrecte';
  END IF;
  attendu := r;
  -- Une profession inconnue ne dévoile aucune mission, et n'empêche pas
  -- l'aperçu global des établissements déjà public.
  r := public.fn_apercu_marche_profession('PROFESSION_INCONNUE_RECETTE', NULL, NULL, NULL);
  IF r->'nb_missions' IS DISTINCT FROM '0'::jsonb
    OR r->'taux_max' IS DISTINCT FROM 'null'::jsonb
    OR r->'taux_moyen' IS DISTINCT FROM 'null'::jsonb
    OR r->'nb_etablissements' IS DISTINCT FROM attendu->'nb_etablissements' THEN
    RAISE EXCEPTION 'Filtre public profession incorrect';
  END IF;
  EXECUTE 'RESET ROLE';
END;
$test$;
ROLLBACK;
