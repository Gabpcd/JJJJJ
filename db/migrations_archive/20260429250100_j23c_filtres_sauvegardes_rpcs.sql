-- J2.3.C — 4 RPCs CRUD filtres_sauvegardes

-- 1. fn_creer_filtre_sauvegarde
CREATE OR REPLACE FUNCTION public.fn_creer_filtre_sauvegarde(
  p_nom text,
  p_audience public.filtre_audience,
  p_filtres jsonb,
  p_alerte_active boolean DEFAULT false,
  p_frequence_alerte public.filtre_frequence_alerte DEFAULT 'QUOTIDIENNE'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  IF length(p_nom) = 0 OR length(p_nom) > 100 THEN
    RETURN jsonb_build_object('error','Nom invalide (1-100 caractères)');
  END IF;

  INSERT INTO filtres_sauvegardes (utilisateur_id, nom, audience, filtres, alerte_active, frequence_alerte)
  VALUES (v_uid, p_nom, p_audience, COALESCE(p_filtres, '{}'::jsonb), p_alerte_active, p_frequence_alerte)
  RETURNING id INTO v_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_CREE', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := v_id,
    p_details := jsonb_build_object('nom', p_nom, 'audience', p_audience::text, 'alerte_active', p_alerte_active, 'frequence', p_frequence_alerte::text)
  );

  IF p_alerte_active THEN
    PERFORM fn_ecrire_audit_safe(
      p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
      p_action := 'ALERTE_ACTIVEE', p_type_ressource := 'filtre_sauvegarde',
      p_id_ressource := v_id,
      p_details := jsonb_build_object('frequence', p_frequence_alerte::text)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Un filtre avec ce nom existe déjà');
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_creer_filtre_sauvegarde(text, public.filtre_audience, jsonb, boolean, public.filtre_frequence_alerte) TO authenticated;

-- 2. fn_lister_mes_filtres_sauvegardes
CREATE OR REPLACE FUNCTION public.fn_lister_mes_filtres_sauvegardes(
  p_audience public.filtre_audience DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
STABLE AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'nom', nom, 'audience', audience::text,
    'filtres', filtres, 'alerte_active', alerte_active,
    'frequence_alerte', frequence_alerte::text,
    'dernier_check_le', dernier_check_le,
    'nb_resultats_dernier_check', nb_resultats_dernier_check,
    'cree_le', cree_le, 'mis_a_jour_le', mis_a_jour_le
  ) ORDER BY mis_a_jour_le DESC), '[]'::jsonb)
  INTO v_result
  FROM filtres_sauvegardes
  WHERE utilisateur_id = v_uid
    AND (p_audience IS NULL OR audience = p_audience);

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_lister_mes_filtres_sauvegardes(public.filtre_audience) TO authenticated;

-- 3. fn_modifier_filtre_sauvegarde
CREATE OR REPLACE FUNCTION public.fn_modifier_filtre_sauvegarde(
  p_id uuid,
  p_nom text DEFAULT NULL,
  p_alerte_active boolean DEFAULT NULL,
  p_frequence_alerte public.filtre_frequence_alerte DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  SELECT * INTO v_old FROM filtres_sauvegardes WHERE id = p_id AND utilisateur_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Filtre introuvable'); END IF;

  IF p_nom IS NOT NULL AND (length(p_nom) = 0 OR length(p_nom) > 100) THEN
    RETURN jsonb_build_object('error','Nom invalide (1-100 caractères)');
  END IF;

  UPDATE filtres_sauvegardes SET
    nom = COALESCE(p_nom, nom),
    alerte_active = COALESCE(p_alerte_active, alerte_active),
    frequence_alerte = COALESCE(p_frequence_alerte, frequence_alerte)
  WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_MODIFIE', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := p_id,
    p_details := jsonb_build_object(
      'nom_avant', v_old.nom, 'nom_apres', COALESCE(p_nom, v_old.nom),
      'alerte_active_avant', v_old.alerte_active,
      'alerte_active_apres', COALESCE(p_alerte_active, v_old.alerte_active),
      'frequence_avant', v_old.frequence_alerte::text,
      'frequence_apres', COALESCE(p_frequence_alerte, v_old.frequence_alerte)::text
    )
  );

  IF p_alerte_active IS NOT NULL AND p_alerte_active <> v_old.alerte_active THEN
    PERFORM fn_ecrire_audit_safe(
      p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
      p_action := CASE WHEN p_alerte_active THEN 'ALERTE_ACTIVEE' ELSE 'ALERTE_DESACTIVEE' END,
      p_type_ressource := 'filtre_sauvegarde', p_id_ressource := p_id,
      p_details := jsonb_build_object('frequence', COALESCE(p_frequence_alerte, v_old.frequence_alerte)::text)
    );
  END IF;

  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Un filtre avec ce nom existe déjà');
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_modifier_filtre_sauvegarde(uuid, text, boolean, public.filtre_frequence_alerte) TO authenticated;

-- 4. fn_supprimer_filtre_sauvegarde
CREATE OR REPLACE FUNCTION public.fn_supprimer_filtre_sauvegarde(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  SELECT * INTO v_old FROM filtres_sauvegardes WHERE id = p_id AND utilisateur_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Filtre introuvable'); END IF;

  DELETE FROM filtres_sauvegardes WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_SUPPRIME', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := p_id,
    p_details := jsonb_build_object('nom', v_old.nom, 'audience', v_old.audience::text)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_supprimer_filtre_sauvegarde(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
