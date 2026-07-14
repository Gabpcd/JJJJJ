-- Garde admin de lancement : aucun compte partiel ne passe par RLS/RPC.
BEGIN;

DO $admin_launch_guard$
DECLARE
  v_partial uuid := 'ffffffff-1410-4000-8000-000000000001';
  v_full uuid := 'ffffffff-1410-4000-8000-000000000002';
  v_absent uuid := 'ffffffff-1410-4000-8000-000000000003';
  v_inactive uuid := 'ffffffff-1410-4000-8000-000000000004';
  v_alias_admin uuid := 'ffffffff-1410-4000-8000-000000000005';
  v_unconfirmed uuid := 'ffffffff-1410-4000-8000-000000000006';
  v_access jsonb;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at
  ) VALUES
    (v_partial, '00000000-0000-0000-0000-000000000000', 'launch-partial@test.local',
     'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', now()),
    (v_full, '00000000-0000-0000-0000-000000000000', 'launch-full@test.local',
     'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', now()),
    (v_absent, '00000000-0000-0000-0000-000000000000', 'launch-absent@test.local',
     'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', now()),
    (v_inactive, '00000000-0000-0000-0000-000000000000', 'launch-inactive@test.local',
     'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', now()),
    (v_alias_admin, '00000000-0000-0000-0000-000000000000', 'launch-alias@test.local',
     'authenticated', 'authenticated', '{"role":"ADMIN"}', now()),
    (v_unconfirmed, '00000000-0000-0000-0000-000000000000', 'launch-unconfirmed@test.local',
     'authenticated', 'authenticated', '{"role":"ADMIN_PLATEFORME"}', NULL);

  INSERT INTO public.equipe_admin(
    user_id, nom, prenom, email, actif, acces_groupes
  ) VALUES
    (v_partial, 'Launch', 'Partial', 'launch-partial@test.local', true, ARRAY['Dashboard']::text[]),
    (v_full, 'Launch', 'Full', 'launch-full@test.local', true, ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[]),
    (v_inactive, 'Launch', 'Inactive', 'launch-inactive@test.local', false, ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[]),
    (v_alias_admin, 'Launch', 'Alias', 'launch-alias@test.local', true, ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[]),
    (v_unconfirmed, 'Launch', 'Unconfirmed', 'launch-unconfirmed@test.local', true, ARRAY[
      'Dashboard',
      'Utilisateurs',
      'Missions',
      'Litiges & contrats',
      'Finances',
      'Messagerie',
      'Conformité & Technique',
      'Fondateur'
    ]::text[]);

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_partial, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  IF public.est_admin() THEN
    RAISE EXCEPTION 'Launch guard: un admin partiel est_admin() a ete accepte';
  END IF;

  BEGIN
    PERFORM public.fn_admin_mes_acces();
    RAISE EXCEPTION 'Launch guard: fn_admin_mes_acces a accepte un admin partiel';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.fn_admin_acquisition_canaux(1);
    RAISE EXCEPTION 'Launch guard: RPC historique a accepte un admin partiel';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_absent, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  IF public.est_admin() THEN
    RAISE EXCEPTION 'Launch guard: un admin absent du registre a ete accepte';
  END IF;
  BEGIN
    PERFORM public.fn_admin_mes_acces();
    RAISE EXCEPTION 'Launch guard: fn_admin_mes_acces a accepte un admin absent';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_inactive, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  IF public.est_admin() THEN
    RAISE EXCEPTION 'Launch guard: un admin inactif a ete accepte';
  END IF;

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_alias_admin, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  IF public.est_admin() THEN
    RAISE EXCEPTION 'Launch guard: le role alias ADMIN a ete accepte';
  END IF;

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_unconfirmed, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  IF public.est_admin() THEN
    RAISE EXCEPTION 'Launch guard: un administrateur non confirme a ete accepte';
  END IF;

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_full, 'role', 'authenticated', 'aal', 'aal1'
  )::text, true);
  IF public.est_admin() THEN
    RAISE EXCEPTION 'Launch guard: un membre complet AAL1 a ete accepte';
  END IF;

  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_full, 'role', 'authenticated', 'aal', 'aal2'
  )::text, true);
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Launch guard: un membre actif avec les 8 groupes a ete refuse';
  END IF;
  v_access := public.fn_admin_mes_acces();
  IF COALESCE((v_access ->> 'acces_total')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Launch guard: le membre complet ne recoit pas acces_total';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.fn_list_admin_user_ids() AS admins(admin_user_id)
    WHERE admin_user_id = v_full
  ) OR EXISTS (
    SELECT 1 FROM public.fn_list_admin_user_ids() AS admins(admin_user_id)
    WHERE admin_user_id IN (
      v_partial, v_absent, v_inactive, v_alias_admin, v_unconfirmed
    )
  ) THEN
    RAISE EXCEPTION 'Launch guard: registre interne des admins non full-only';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'private.fn_admin_acquisition_canaux_interne_lancement(integer)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'private.fn_admin_cockpit_fondateur_interne_lancement()',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'private.fn_admin_creer_compte_employe_interne_lancement(text,text,text,text,text,numeric,text[])',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Launch guard: une implementation historique reste executable par authenticated';
  END IF;

  IF has_schema_privilege('authenticated', 'private', 'USAGE')
     OR has_schema_privilege('anon', 'private', 'USAGE') THEN
    RAISE EXCEPTION 'Launch guard: le schema interne est encore expose au Data API';
  END IF;
END;
$admin_launch_guard$;

ROLLBACK;
