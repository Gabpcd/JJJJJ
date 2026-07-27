-- Hotfix App Review 27/07/2026.
--
-- Après suspension des crons en échec, Auth et PostgREST conservaient des
-- connexions techniques figées. Leur terminaison force les services gérés par
-- Supabase à ouvrir des connexions propres, sans supprimer de donnée ni de
-- session utilisateur.
DO $cleanup$
DECLARE
  v_pid integer;
BEGIN
  FOR v_pid IN
    SELECT pid
    FROM pg_stat_activity
    WHERE pid <> pg_backend_pid()
      AND backend_type = 'client backend'
      AND usename IN ('authenticator', 'supabase_auth_admin')
  LOOP
    PERFORM pg_terminate_backend(v_pid);
  END LOOP;
END;
$cleanup$;
