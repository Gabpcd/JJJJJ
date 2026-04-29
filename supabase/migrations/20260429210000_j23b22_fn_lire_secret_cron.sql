-- J2.3.B.2.2 — Fix prod : email-cron auth 401 silencieux depuis migration JWT asymétrique.
--
-- Contexte : le projet utilise désormais le format `sb_secret_...` (asymmetric JWT)
-- et stocke ce secret dans `vault.secrets`. pg_cron envoie ce secret en Bearer
-- vers email-cron, mais l'edge function comparait à `SUPABASE_SERVICE_ROLE_KEY`
-- (legacy JWT `eyJ...`) → 401 systématique. Aucune série email J0-J7 ni rappel
-- contrat de travail n'a été envoyé depuis le switch.
--
-- Fix : RPC SECURITY DEFINER qui expose le secret stocké en vault, callable
-- uniquement par service_role (le edge function l'utilise pour comparer le
-- bearer reçu).

CREATE OR REPLACE FUNCTION public.fn_lire_secret_cron()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, extensions
AS $$
DECLARE v_secret text;
BEGIN
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';
  RETURN v_secret;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_lire_secret_cron() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_lire_secret_cron() TO service_role;
