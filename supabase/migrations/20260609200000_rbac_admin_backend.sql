-- RBAC admin backend — vérification côté serveur des accès par groupe nav.
-- Chaque admin a des acces_groupes dans equipe_admin. Cette RPC vérifie si
-- l'utilisateur connecté a accès à un groupe donné, et retourne ses groupes.

CREATE OR REPLACE FUNCTION public.fn_admin_mes_acces()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid;
  v_role text;
  v_groupes text[];
  v_actif boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT raw_app_meta_data->>'role' INTO v_role
  FROM auth.users WHERE id = v_uid;

  IF v_role <> 'ADMIN_PLATEFORME' THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  SELECT acces_groupes, actif INTO v_groupes, v_actif
  FROM equipe_admin WHERE user_id = v_uid;

  -- Fondatrice ou admin sans entrée dans equipe_admin → accès total
  IF v_groupes IS NULL THEN
    RETURN jsonb_build_object(
      'acces_total', true,
      'groupes', '[]'::jsonb,
      'actif', true
    );
  END IF;

  IF NOT v_actif THEN
    RAISE EXCEPTION 'Compte désactivé';
  END IF;

  RETURN jsonb_build_object(
    'acces_total', false,
    'groupes', to_jsonb(v_groupes),
    'actif', v_actif
  );
END;
$body$;

-- RPC pour créer un compte auth + lier à equipe_admin (ADMIN_PLATEFORME only)
CREATE OR REPLACE FUNCTION public.fn_admin_creer_compte_employe(
  p_email text,
  p_password text,
  p_prenom text,
  p_nom text,
  p_poste text DEFAULT 'Opérations',
  p_salaire_brut numeric DEFAULT 0,
  p_acces_groupes text[] DEFAULT ARRAY['Dashboard']
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_caller_role text;
  v_new_user_id uuid;
BEGIN
  SELECT raw_app_meta_data->>'role' INTO v_caller_role
  FROM auth.users WHERE id = auth.uid();

  IF v_caller_role <> 'ADMIN_PLATEFORME' THEN
    RAISE EXCEPTION 'Seul un ADMIN_PLATEFORME peut créer des comptes employés';
  END IF;

  IF p_email IS NULL OR p_email = '' THEN
    RAISE EXCEPTION 'Email requis';
  END IF;
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'Mot de passe requis (8 caractères minimum)';
  END IF;

  -- Créer le compte via auth.users (service_role, SECURITY DEFINER)
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    p_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', ARRAY['email'], 'role', 'ADMIN_PLATEFORME'),
    jsonb_build_object('prenom', p_prenom, 'nom', p_nom),
    now(), now(), '', '', '', ''
  )
  RETURNING id INTO v_new_user_id;

  -- Créer l'identité
  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_new_user_id,
    jsonb_build_object('sub', v_new_user_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
    'email', v_new_user_id::text, now(), now(), now()
  );

  -- Enregistrer dans equipe_admin
  INSERT INTO equipe_admin (user_id, nom, prenom, email, poste, salaire_brut_mensuel, acces_groupes, date_embauche)
  VALUES (v_new_user_id, p_nom, p_prenom, p_email, p_poste, p_salaire_brut, p_acces_groupes, current_date);

  -- Email 2FA destination = même email
  INSERT INTO admin_securite (admin_id, email_2fa)
  VALUES (v_new_user_id, p_email)
  ON CONFLICT (admin_id) DO UPDATE SET email_2fa = EXCLUDED.email_2fa;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_new_user_id,
    'email', p_email,
    'acces_groupes', to_jsonb(p_acces_groupes)
  );
END;
$body$;
