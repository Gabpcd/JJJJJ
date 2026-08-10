-- Une purge E2E peut rencontrer une transaction encore active sur la mission
-- ou l'un de ses nombreux enfants. Sans bornes propres, le service_role et les
-- appels SQL administratifs peuvent attendre un verrou indéfiniment et occuper
-- une connexion PostgREST bien après l'arrêt du job Playwright.
--
-- Ces réglages restent attachés à l'unique RPC technique. PostgREST hoiste le
-- statement_timeout avant l'appel ; lock_timeout protège chaque prise de
-- verrou dans le corps de la fonction. Toute annulation fait rollback de la
-- transaction complète : aucune purge partielle n'est conservée.
ALTER FUNCTION public.fn_test_purge_mission(uuid)
  SET statement_timeout TO '20s';

ALTER FUNCTION public.fn_test_purge_mission(uuid)
  SET lock_timeout TO '3s';

DO $assertions$
DECLARE
  v_config text[];
BEGIN
  SELECT COALESCE(p.proconfig, ARRAY[]::text[])
  INTO v_config
  FROM pg_catalog.pg_proc p
  WHERE p.oid = 'public.fn_test_purge_mission(uuid)'::pg_catalog.regprocedure;

  IF NOT v_config @> ARRAY[
    'statement_timeout=20s',
    'lock_timeout=3s'
  ]::text[] THEN
    RAISE EXCEPTION
      'fn_test_purge_mission doit rester bornée (config=%)',
      v_config;
  END IF;
END;
$assertions$;

-- Les paramètres de fonction font partie du cache de schéma utilisé par
-- PostgREST pour appliquer statement_timeout avant l'exécution de la RPC.
NOTIFY pgrst, 'reload schema';
