-- Donne au compte réel de Gabrielle le même accès fondateur que le compte
-- technique admin@jolene.app, sans dépendre d'une boîte mail inexistante.
-- L'exception MFA reste bornée à ces deux adresses exactes ; tous les autres
-- administrateurs doivent toujours présenter une session AAL2.

DO $migration$
DECLARE
  v_user_id uuid;
BEGIN
  SELECT id
    INTO v_user_id
    FROM auth.users
   WHERE lower(COALESCE(email, '')) = 'gabrielle.pcd@outlook.com'
     AND deleted_at IS NULL
   FOR UPDATE;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Compte Auth gabrielle.pcd@outlook.com introuvable';
  END IF;

  UPDATE auth.users
     SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
       || jsonb_build_object('role', 'ADMIN_PLATEFORME'),
         email_confirmed_at = COALESCE(email_confirmed_at, now()),
         updated_at = now()
   WHERE id = v_user_id;

  INSERT INTO public.equipe_admin (
    user_id, nom, prenom, email, poste, acces_groupes, actif
  ) VALUES (
    v_user_id,
    'PCD',
    'Gabrielle',
    'gabrielle.pcd@outlook.com',
    'Fondatrice',
    ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[],
    true
  )
  ON CONFLICT (user_id) DO UPDATE
     SET nom = EXCLUDED.nom,
         prenom = EXCLUDED.prenom,
         email = EXCLUDED.email,
         poste = EXCLUDED.poste,
         acces_groupes = EXCLUDED.acces_groupes,
         actif = true,
         maj_le = now();

  -- Idempotent : aucun facteur ne subsiste, y compris un enrôlement TOTP
  -- incomplet créé par l'ancien écran QR.
  DELETE FROM auth.mfa_factors WHERE user_id = v_user_id;
END
$migration$;

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
        OR lower(COALESCE(u.email, '')) IN (
          'admin@jolene.app',
          'gabrielle.pcd@outlook.com'
        )
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
  'Garde admin de lancement : rôle canonique, compte sain, registre 8/8 et AAL2, sauf les deux comptes fondateurs explicitement autorisés sans MFA.';
