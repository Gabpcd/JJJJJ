-- Suppression complète de la 2FA admin par email (ne fonctionnait pas : le code
-- partait toujours à admin@jolene.app au lieu de l'email perso paramétré).
-- Le guard frontend GardeMfaAdmin est retiré de LayoutAdmin dans le même commit.
-- Idempotent : les objets ont déjà été supprimés en prod via MCP.

DROP TABLE IF EXISTS public.admin_2fa_codes CASCADE;
DROP TABLE IF EXISTS public.admin_securite CASCADE;
DROP FUNCTION IF EXISTS public.fn_lire_email_2fa(uuid);
