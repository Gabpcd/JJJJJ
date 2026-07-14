-- Test transactionnel à exécuter après les migrations.
BEGIN;

DO $test$
DECLARE
  v_result jsonb;
BEGIN
  v_result := private.fn_rapprocher_naissance_representant(
    '{"date_naissance_extraite":"1986-04-12"}'::jsonb,
    '[{"type_dirigeant":"Personne physique","nom":"Martin","prenoms":"Alice","date_de_naissance":"1986-04"}]'::jsonb,
    'Martin',
    'Alice',
    NULL
  );
  IF v_result ->> 'statut' <> 'CORRESPOND' THEN
    RAISE EXCEPTION 'Le rapprochement mois/année devrait correspondre: %', v_result;
  END IF;

  v_result := private.fn_rapprocher_naissance_representant(
    '{"date_naissance_extraite":"1987-04-12"}'::jsonb,
    '[{"type_dirigeant":"Personne physique","nom":"Martin","prenoms":"Alice","date_de_naissance":"1986-04"}]'::jsonb,
    'Martin',
    'Alice',
    NULL
  );
  IF v_result ->> 'statut' <> 'DIVERGE' THEN
    RAISE EXCEPTION 'Une date contradictoire doit diverger: %', v_result;
  END IF;

  v_result := private.fn_rapprocher_naissance_representant(
    '{}'::jsonb,
    '[{"type_dirigeant":"Personne physique","nom":"Martin","prenoms":"Alice","annee_de_naissance":"1986"}]'::jsonb,
    'Martin',
    'Alice',
    NULL
  );
  IF v_result ->> 'statut' <> 'PIECE_NON_LUE' THEN
    RAISE EXCEPTION 'Une date officielle disponible exige la lecture de la pièce: %', v_result;
  END IF;

  IF to_regprocedure(
    'public.fn_admin_decider_preuve_etablissement(uuid,text,text,text,bigint,text,date)'
  ) IS NULL THEN
    RAISE EXCEPTION 'RPC de décision par preuve absente';
  END IF;
  IF to_regprocedure(
    'public.fn_admin_finaliser_verification_etablissement(uuid,bigint)'
  ) IS NULL THEN
    RAISE EXCEPTION 'RPC de finalisation absente';
  END IF;
END;
$test$;

ROLLBACK;
