-- Le schéma public Jolene contient de nombreuses RPC métier et politiques RLS.
-- Après l'import RPPS, la reconstruction du cache PostgREST peut dépasser le
-- timeout interne historique de 8 s et laisser toute l'API en PGRST002/503.
--
-- Ce réglage concerne uniquement la connexion technique `authenticator` qui
-- construit le cache. Les rôles applicatifs conservent leurs bornes propres :
-- anon=3 s et authenticated=8 s.
DO $role$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    EXECUTE 'ALTER ROLE authenticator SET statement_timeout = ''120s''';
  END IF;
END;
$role$;

NOTIFY pgrst, 'reload schema';
