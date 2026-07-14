-- L'exception sans second facteur est strictement limitée au compte fondateur
-- admin@jolene.app. Tout autre administrateur présent ou futur conserve
-- l'obligation AAL2, en plus des gardes de rôle, d'état du compte et du registre
-- equipe_admin déjà imposées par cette fonction.

CREATE OR REPLACE FUNCTION public.est_admin_valide()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public, auth
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = auth.uid()
      AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND u.email_confirmed_at IS NOT NULL
      AND (
        COALESCE(auth.jwt() ->> 'aal', '') = 'aal2'
        OR lower(COALESCE(u.email, '')) = 'admin@jolene.app'
      )
      AND EXISTS (
        SELECT 1
        FROM public.equipe_admin ea
        WHERE ea.user_id = u.id
          AND ea.actif IS TRUE
          AND ARRAY[
            'Dashboard',
            'Utilisateurs',
            'Missions',
            'Litiges & contrats',
            'Finances',
            'Messagerie',
            'Conformité & Technique',
            'Fondateur'
          ]::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[])
      )
  ), false);
$function$;

REVOKE ALL ON FUNCTION public.est_admin_valide() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.est_admin_valide() TO authenticated, service_role;

COMMENT ON FUNCTION public.est_admin_valide() IS
  'Garde admin de lancement : rôle canonique, compte sain, registre 8/8 et AAL2, avec exception sans MFA limitée à admin@jolene.app.';
