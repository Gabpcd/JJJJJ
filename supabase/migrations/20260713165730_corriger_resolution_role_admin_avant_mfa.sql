-- La résolution de rôle intervient avant AdminMfaGate. Depuis la migration P0,
-- fn_get_my_role() appelait est_admin(), qui exige aal2 : un administrateur en
-- aal1 était donc classé INCONNU puis déconnecté avant de pouvoir saisir son
-- second facteur. Cette fonction identifie ici le compte admin côté serveur,
-- sans accorder de privilège : les RPC/RLS sensibles continuent d'utiliser
-- est_admin()/est_admin_valide(), qui exigent toujours aal2.
CREATE OR REPLACE FUNCTION public.fn_get_my_role()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'INCONNU', 'etablissement_id', NULL);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = v_uid
      AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND u.email_confirmed_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.equipe_admin ea
        WHERE ea.user_id = u.id
          AND ea.actif IS NOT TRUE
      )
  ) THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'ADMIN_PLATEFORME', 'etablissement_id', NULL);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.soignants s
    WHERE s.id = v_uid
      AND s.supprime_le IS NULL
  ) THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'SOIGNANT', 'etablissement_id', NULL);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.admins_groupe_sante ag
    JOIN auth.users u ON u.id = ag.utilisateur_id
    WHERE ag.utilisateur_id = v_uid
      AND u.raw_app_meta_data ->> 'role' = 'ADMIN_GROUPE'
  ) THEN
    RETURN jsonb_build_object('user_id', v_uid, 'role', 'ADMIN_GROUPE', 'etablissement_id', NULL);
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'user_id', v_uid,
      'role', 'ADMIN_ETABLISSEMENT',
      'etablissement_id', v_etab_id
    );
  END IF;

  RETURN jsonb_build_object('user_id', v_uid, 'role', 'INCONNU', 'etablissement_id', NULL);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_get_my_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_get_my_role() TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_get_my_role() IS
  'Résout la famille de compte avant le gate MFA. Identifier ADMIN_PLATEFORME ne confère aucun privilège : les opérations admin restent protégées par est_admin_valide() et aal2.';
