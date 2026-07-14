-- Lancement public — fermeture temporaire du RBAC admin partiel.
--
-- Aucun enregistrement equipe_admin n'est modifie par cette migration.
-- Les comptes historiques a acces partiel restent en place mais echouent fermes,
-- cote RLS/RPC comme cote routes, jusqu'a une future delegation serveur par groupe.

-- ---------------------------------------------------------------------------
-- 1. Source de verite serveur : AAL2 + compte sain + acces complet au lancement
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.est_admin_valide()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT COALESCE(EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = auth.uid()
      AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
      AND u.email_confirmed_at IS NOT NULL
      AND COALESCE(auth.jwt() ->> 'aal', '') = 'aal2'
      -- Au lancement public, l'inscription explicite dans equipe_admin est
      -- obligatoire : aucune compatibilite implicite hors registre.
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
$$;

CREATE OR REPLACE FUNCTION public.est_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT public.est_admin_valide();
$$;

REVOKE ALL ON FUNCTION public.est_admin_valide() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.est_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.est_admin_valide() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.est_admin() TO authenticated, service_role;

COMMENT ON FUNCTION public.est_admin_valide() IS
  'Garde admin de lancement : AAL2, compte actif et ligne equipe_admin active avec les 8 groupes canoniques.';

-- Les notifications et traitements internes utilisent cette source sans JWT
-- utilisateur. Elle applique donc le même registre full-only, hors contrôle
-- AAL qui n'a pas de sens pour une énumération service_role.
CREATE OR REPLACE FUNCTION public.fn_list_admin_user_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
  SELECT u.id
  FROM auth.users u
  JOIN public.equipe_admin ea ON ea.user_id = u.id
  WHERE u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
    AND u.deleted_at IS NULL
    AND (u.banned_until IS NULL OR u.banned_until <= now())
    AND u.email_confirmed_at IS NOT NULL
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
    ]::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[]);
$$;

REVOKE ALL ON FUNCTION public.fn_list_admin_user_ids()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_list_admin_user_ids() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_mes_acces()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse au lancement' USING ERRCODE = '42501';
  END IF;

  -- Tant que les controles serveur ne sont pas delegues groupe par groupe,
  -- tout compte autorise est necessairement un administrateur complet.
  RETURN jsonb_build_object(
    'acces_total', true,
    'groupes', '[]'::jsonb,
    'actif', true,
    'mode_lancement', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_mes_acces() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_mes_acces() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Trois RPC historiques lisaient directement le role Auth et contournaient
--    est_admin(). Leurs implementations sont rendues internes, non executables
--    par authenticated, puis exposees derriere un wrapper fail-closed.
-- ---------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated, service_role;

ALTER FUNCTION public.fn_admin_acquisition_canaux(integer)
  RENAME TO fn_admin_acquisition_canaux_interne_lancement;
ALTER FUNCTION public.fn_admin_acquisition_canaux_interne_lancement(integer)
  SET SCHEMA private;
REVOKE ALL ON FUNCTION private.fn_admin_acquisition_canaux_interne_lancement(integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_canaux(p_jours integer DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse au lancement' USING ERRCODE = '42501';
  END IF;
  RETURN private.fn_admin_acquisition_canaux_interne_lancement(p_jours);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_acquisition_canaux(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_canaux(integer) TO authenticated, service_role;

ALTER FUNCTION public.fn_admin_cockpit_fondateur()
  RENAME TO fn_admin_cockpit_fondateur_interne_lancement;
ALTER FUNCTION public.fn_admin_cockpit_fondateur_interne_lancement()
  SET SCHEMA private;
REVOKE ALL ON FUNCTION private.fn_admin_cockpit_fondateur_interne_lancement()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_fondateur()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse au lancement' USING ERRCODE = '42501';
  END IF;
  RETURN private.fn_admin_cockpit_fondateur_interne_lancement();
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_cockpit_fondateur() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_cockpit_fondateur() TO authenticated, service_role;

ALTER FUNCTION public.fn_admin_creer_compte_employe(
  text, text, text, text, text, numeric, text[]
) RENAME TO fn_admin_creer_compte_employe_interne_lancement;
-- L'implementation historique utilise pgcrypto sans qualification. Le schema
-- extensions est ajoute explicitement apres les schemas systeme/applicatifs.
ALTER FUNCTION public.fn_admin_creer_compte_employe_interne_lancement(
  text, text, text, text, text, numeric, text[]
) SET search_path TO pg_catalog, public, auth, extensions;
ALTER FUNCTION public.fn_admin_creer_compte_employe_interne_lancement(
  text, text, text, text, text, numeric, text[]
) SET SCHEMA private;
REVOKE ALL ON FUNCTION private.fn_admin_creer_compte_employe_interne_lancement(
  text, text, text, text, text, numeric, text[]
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_creer_compte_employe(
  p_email text,
  p_password text,
  p_prenom text,
  p_nom text,
  p_poste text DEFAULT 'Opérations'::text,
  p_salaire_brut numeric DEFAULT 0,
  p_acces_groupes text[] DEFAULT ARRAY[
    'Dashboard',
    'Utilisateurs',
    'Missions',
    'Litiges & contrats',
    'Finances',
    'Messagerie',
    'Conformité & Technique',
    'Fondateur'
  ]::text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  v_groupes_lancement constant text[] := ARRAY[
    'Dashboard',
    'Utilisateurs',
    'Missions',
    'Litiges & contrats',
    'Finances',
    'Messagerie',
    'Conformité & Technique',
    'Fondateur'
  ]::text[];
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse au lancement' USING ERRCODE = '42501';
  END IF;

  -- p_acces_groupes reste dans la signature pour compatibilite PostgREST,
  -- mais une creation partielle est volontairement impossible au lancement.
  RETURN private.fn_admin_creer_compte_employe_interne_lancement(
    p_email,
    p_password,
    p_prenom,
    p_nom,
    p_poste,
    p_salaire_brut,
    v_groupes_lancement
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_creer_compte_employe(
  text, text, text, text, text, numeric, text[]
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_creer_compte_employe(
  text, text, text, text, text, numeric, text[]
) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_creer_compte_employe(
  text, text, text, text, text, numeric, text[]
) IS 'Creation admin de lancement : garde est_admin() et attribution forcee des 8 groupes canoniques.';

NOTIFY pgrst, 'reload schema';
