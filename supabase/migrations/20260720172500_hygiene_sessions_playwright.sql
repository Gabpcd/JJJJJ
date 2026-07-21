-- Les comptes techniques Playwright sont réutilisés par la CI. Chaque login
-- GoTrue crée une session et un refresh token ; un job interrompu ne peut pas
-- exécuter son teardown. Sans purge bornée, ces lignes s'accumulent et
-- finissent par ralentir Auth et la reconstruction du cache PostgREST.
--
-- Cette fonction ne touche qu'aux deux comptes CI exacts. Elle ne supprime ni
-- utilisateur, ni profil, ni donnée de démonstration, et ne contacte personne.
CREATE OR REPLACE FUNCTION public.fn_test_nettoyer_sessions_playwright(
  p_anciennete interval DEFAULT interval '6 hours'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
SET statement_timeout TO '120s'
AS $fonction$
DECLARE
  v_seuil timestamptz;
  v_sessions_cibles uuid[] := ARRAY[]::uuid[];
  v_tokens_supprimes integer := 0;
  v_sessions_supprimees integer := 0;
BEGIN
  IF p_anciennete IS NULL OR p_anciennete < interval '0 seconds' THEN
    RAISE EXCEPTION 'anciennete_invalide';
  END IF;

  v_seuil := clock_timestamp() - p_anciennete;

  -- Une petite transaction régulière vaut mieux qu'une purge monolithique :
  -- elle n'immobilise pas Auth pendant le rattrapage du stock historique.
  SELECT COALESCE(array_agg(cible.id), ARRAY[]::uuid[])
  INTO v_sessions_cibles
  FROM (
    SELECT s.id
    FROM auth.sessions AS s
    JOIN auth.users AS u ON u.id = s.user_id
    WHERE u.email IN (
      'playwright-soignant@jolene.app',
      'playwright-etab@jolene.app'
    )
      AND s.created_at < v_seuil
    ORDER BY s.created_at
    LIMIT 500
  ) AS cible;

  IF cardinality(v_sessions_cibles) = 0 THEN
    RETURN jsonb_build_object(
      'sessions_supprimees', 0,
      'refresh_tokens_supprimes', 0,
      'avant', v_seuil,
      'limite_par_passage', 500
    );
  END IF;

  -- Supprimer d'abord les refresh tokens évite de faire supporter leur cascade
  -- une ligne à la fois au DELETE des sessions lorsque la CI a accumulé un
  -- historique important.
  WITH tokens_supprimes AS (
    DELETE FROM auth.refresh_tokens AS rt
    WHERE rt.session_id = ANY(v_sessions_cibles)
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_tokens_supprimes
  FROM tokens_supprimes;

  WITH sessions_supprimees AS (
    DELETE FROM auth.sessions AS s
    WHERE s.id = ANY(v_sessions_cibles)
    RETURNING 1
  )
  SELECT count(*)::integer INTO v_sessions_supprimees
  FROM sessions_supprimees;

  RETURN jsonb_build_object(
    'sessions_supprimees', v_sessions_supprimees,
    'refresh_tokens_supprimes', v_tokens_supprimes,
    'avant', v_seuil,
    'limite_par_passage', 500
  );
END;
$fonction$;

REVOKE ALL ON FUNCTION public.fn_test_nettoyer_sessions_playwright(interval)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_test_nettoyer_sessions_playwright(interval)
  TO service_role;

COMMENT ON FUNCTION public.fn_test_nettoyer_sessions_playwright(interval) IS
  'Purge exclusivement les sessions anciennes des deux comptes CI Playwright ; service_role uniquement.';

-- Filet de sécurité pour les jobs annulés avant leur teardown. Deux heures
-- laissent largement finir le run actif ; le teardown normal purge sans délai.
-- Le passage toutes les cinq minutes rattrape progressivement un éventuel
-- historique sans créer de pic de charge.
DO $cron$
DECLARE
  v_job record;
BEGIN
  FOR v_job IN
    SELECT jobid FROM cron.job
    WHERE jobname = 'jolene_nettoyer_sessions_playwright'
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;

  PERFORM cron.schedule(
    'jolene_nettoyer_sessions_playwright',
    '3-59/5 * * * *',
    $job$SELECT public.fn_test_nettoyer_sessions_playwright(interval '2 hours');$job$
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron indisponible : purge de secours Playwright non planifiee';
END;
$cron$;
