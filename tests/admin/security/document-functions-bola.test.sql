-- Anti-BOLA des fonctions documentaires exposées par PostgREST.
-- Usage : psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 \
--   -f tests/admin/security/document-functions-bola.test.sql

\set ON_ERROR_STOP on
BEGIN;

SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aal":"aal1"}',
  true
);

SET LOCAL ROLE authenticated;

DO $test$
BEGIN
  BEGIN
    PERFORM public.fn_documents_ok_pour_mission(
      '22222222-2222-2222-2222-222222222222'::uuid,
      'SALARIE'
    );
    RAISE EXCEPTION 'BOLA-T1: un soignant a pu lire le statut documentaire d''un autre profil';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  IF has_function_privilege(
    'authenticated',
    'public.fn_documents_ok_pour_mission(uuid,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'BOLA-T2: authenticated peut exécuter le calcul documentaire interne';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.fn_calculer_tous_documents_valides(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'BOLA-T3: authenticated peut encore recalculer un profil arbitraire';
  END IF;
END;
$test$;

RESET ROLE;
ROLLBACK;
