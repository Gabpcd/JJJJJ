-- Rétablit la convention Supabase standard pour service_role (rôle backend de
-- confiance, jamais exposé côté client) : un hardening antérieur avait révoqué
-- ses privilèges sur 22 tables et 511 fonctions, cassant les edge functions /
-- tests E2E qui accèdent aux tables via la clé service_role ("permission
-- denied for table evenements_score_soignant", etc.).
-- Les rôles PUBLICS (anon, authenticated) ne sont PAS touchés : la surface
-- d'attaque publique et les politiques RLS restent identiques.

GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Les futurs objets créés par postgres (migrations MCP/CLI) incluent
-- service_role d'office — évite la réapparition du problème.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO service_role;
