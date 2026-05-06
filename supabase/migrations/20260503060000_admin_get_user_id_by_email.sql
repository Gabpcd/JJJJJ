-- RPC dédiée pour récupérer l'id auth d'un user par email.
--
-- Pourquoi : `auth.admin.listUsers()` côté SDK est paginé (50/page par défaut)
-- et peut échouer silencieusement en CI (pagination, rate limit, timeout).
-- Les helpers Playwright `userIdByEmail()` retournaient null silencieusement,
-- ce qui faisait skip/échouer 13 tests E2E.
--
-- Cette RPC SECURITY DEFINER lit directement `auth.users` et est restreinte à
-- `service_role` (utilisée par les tests E2E uniquement, pas par le client web).

CREATE OR REPLACE FUNCTION public.fn_admin_get_user_id_by_email(p_email text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT (
    COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
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
$$;

REVOKE ALL ON FUNCTION public.fn_admin_get_user_id_by_email(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_admin_get_user_id_by_email(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_get_user_id_by_email(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
