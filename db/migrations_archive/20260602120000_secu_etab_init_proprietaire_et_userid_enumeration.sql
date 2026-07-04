-- 🔴 FAILLE : fn_init_proprietaire_etab acceptait un p_user_id arbitraire et n'avait
-- pour seul garde-fou que « membres déjà présents » → prise de contrôle possible de
-- tout établissement sans membre actif par n'importe quel utilisateur authentifié.
-- Correctif :
--   - appel serveur (service_role, auth.uid() NULL) : p_user_id obligatoire (inscription) ;
--   - appel client authentifié : p_user_id IGNORÉ (anti-usurpation) + revendication
--     autorisée seulement si admin OU app_metadata.etablissement_id = p_etablissement_id.
CREATE OR REPLACE FUNCTION public.fn_init_proprietaire_etab(p_etablissement_id uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_uid uuid;
  v_membre_id uuid;
BEGIN
  IF v_caller IS NULL THEN
    v_uid := p_user_id;
    IF v_uid IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
    END IF;
  ELSE
    v_uid := v_caller;
    IF NOT (
      est_admin()
      OR EXISTS (
        SELECT 1 FROM auth.users u
        WHERE u.id = v_caller
          AND (u.raw_app_meta_data ->> 'etablissement_id') = p_etablissement_id::text
      )
    ) THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.membres_etablissement
    WHERE etablissement_id = p_etablissement_id AND actif = true
  ) THEN
    RETURN jsonb_build_object('success', true, 'message', 'Membres déjà présents');
  END IF;

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, accepte_le, actif
  ) VALUES (
    p_etablissement_id, v_uid, 'PROPRIETAIRE', now(), true
  )
  RETURNING id INTO v_membre_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', v_membre_id,
    jsonb_build_object(
      'evenement', 'PROPRIETAIRE_INITIALISE',
      'etablissement_id', p_etablissement_id
    )
  );

  RETURN jsonb_build_object('success', true, 'membre_id', v_membre_id);
END;
$function$;

-- 🟡 fn_user_id_pour_etablissement résolvait le user_id de n'importe quel établissement
-- pour tout utilisateur authentifié (énumération). Restreint aux relations légitimes :
-- admin, l'établissement lui-même, ou un soignant lié via mission assignée / candidature.
CREATE OR REPLACE FUNCTION public.fn_user_id_pour_etablissement(p_etablissement_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_caller uuid := auth.uid();
  v_autorise boolean;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;
  -- NULL-safe : mon_etablissement_id() peut valoir NULL (soignant) ; sans le garde
  -- IS NOT NULL la comparaison renverrait NULL et contaminerait tout le OR.
  v_autorise :=
       est_admin()
    OR (mon_etablissement_id() IS NOT NULL AND p_etablissement_id = mon_etablissement_id())
    OR EXISTS (
         SELECT 1 FROM public.missions m
         WHERE m.etablissement_id = p_etablissement_id AND m.soignant_assigne_id = v_caller
       )
    OR EXISTS (
         SELECT 1 FROM public.candidatures c
         JOIN public.missions m ON m.id = c.mission_id
         WHERE m.etablissement_id = p_etablissement_id AND c.soignant_id = v_caller
       );
  IF NOT COALESCE(v_autorise, false) THEN
    RAISE EXCEPTION 'Non autorisé' USING ERRCODE = '42501';
  END IF;
  SELECT id INTO v_user_id FROM auth.users
  WHERE (raw_app_meta_data ->> 'etablissement_id')::uuid = p_etablissement_id
  LIMIT 1;
  RETURN v_user_id;
END;
$function$;
