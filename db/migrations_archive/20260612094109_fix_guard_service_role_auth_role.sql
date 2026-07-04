-- fn_admin_get_user_id_by_email utilisait le GUC legacy
-- current_setting('request.jwt.claim.role') (singulier) qui n'est peuplé que
-- pour les clés JWT legacy. Les nouvelles clés sb_secret_* ne renseignent que
-- request.jwt.claims (JSON). auth.role() lit les DEUX chemins → guard robuste
-- quel que soit le format de clé service_role (corrige aussi tout outillage
-- admin appelant cette fonction avec une clé v2, et débloque les seeds E2E).
CREATE OR REPLACE FUNCTION public.fn_admin_get_user_id_by_email(p_email text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  IF NOT (
    auth.role() = 'service_role'
    OR (auth.uid() IS NOT NULL AND est_admin())
  ) THEN
    RAISE EXCEPTION 'Accès refusé: réservé service_role ou admin';
  END IF;

  SELECT id INTO v_id
  FROM auth.users
  WHERE email = lower(p_email)
  LIMIT 1;

  RETURN v_id;
END;
$function$;
