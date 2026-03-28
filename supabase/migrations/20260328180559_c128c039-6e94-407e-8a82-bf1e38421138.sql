
CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(p_mission_id UUID, p_motif TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_mission RECORD;
  v_existing INT;
  v_recent INT;
  v_initie_par TEXT;
  v_etab_id UUID;
  v_presence_id UUID;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  IF length(trim(p_motif)) < 10 THEN RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.'); END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut INTO v_mission
  FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;

  IF v_mission.soignant_assigne_id = v_user_id THEN
    v_initie_par := 'SOIGNANT';
    v_etab_id := v_mission.etablissement_id;
  ELSIF v_mission.etablissement_id = mon_etablissement_id() THEN
    v_initie_par := 'ETABLISSEMENT';
    v_etab_id := v_mission.etablissement_id;
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante de cette mission.');
  END IF;

  SELECT COUNT(*) INTO v_existing FROM litiges WHERE mission_id = p_mission_id;
  IF v_existing > 0 THEN RETURN jsonb_build_object('error', 'Un litige existe déjà pour cette mission.'); END IF;

  SELECT COUNT(*) INTO v_recent FROM litiges
  WHERE (soignant_id = v_user_id OR etablissement_id = mon_etablissement_id())
    AND cree_le > NOW() - INTERVAL '1 hour';
  IF v_recent >= 3 THEN RETURN jsonb_build_object('error', 'Trop de litiges ouverts récemment. Réessayez plus tard.'); END IF;

  SELECT id INTO v_presence_id FROM presences WHERE mission_id = p_mission_id LIMIT 1;

  INSERT INTO litiges (mission_id, soignant_id, etablissement_id, presence_id, initie_par, motif, statut)
  VALUES (p_mission_id, COALESCE(v_mission.soignant_assigne_id, v_user_id), v_etab_id, v_presence_id, v_initie_par, trim(p_motif), 'OUVERT');

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_repondre_litige(p_litige_id UUID, p_reponse TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_litige RECORD;
  v_auteur TEXT;
  v_new_reponse TEXT;
  v_date_str TEXT;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  IF length(trim(p_reponse)) < 10 THEN RETURN jsonb_build_object('error', 'La réponse doit contenir au moins 10 caractères.'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;

  IF v_litige.statut NOT IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE') THEN
    RETURN jsonb_build_object('error', 'Ce litige est clôturé.');
  END IF;

  IF v_litige.soignant_id = v_user_id THEN
    v_auteur := 'Soignant';
  ELSIF v_litige.etablissement_id = mon_etablissement_id() THEN
    v_auteur := 'Établissement';
  ELSIF est_admin() THEN
    v_auteur := 'Admin';
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante de ce litige.');
  END IF;

  v_date_str := to_char(NOW(), 'DD/MM/YYYY HH24:MI');
  v_new_reponse := '[' || v_date_str || '] ' || v_auteur || ': ' || trim(p_reponse);

  IF v_litige.reponse IS NOT NULL AND v_litige.reponse != '' THEN
    v_new_reponse := v_litige.reponse || E'\n---\n' || v_new_reponse;
  END IF;

  UPDATE litiges SET reponse = v_new_reponse, statut = 'EN_DISCUSSION' WHERE id = p_litige_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_mutuel(p_litige_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_litige RECORD;
  v_is_soignant BOOLEAN := FALSE;
  v_is_etab BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;

  IF v_litige.statut NOT IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE') THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé.');
  END IF;

  IF v_litige.soignant_id = v_user_id THEN
    v_is_soignant := TRUE;
  ELSIF v_litige.etablissement_id = mon_etablissement_id() THEN
    v_is_etab := TRUE;
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante.');
  END IF;

  IF v_is_soignant THEN
    UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
  ELSIF v_is_etab THEN
    UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
  END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige.accord_soignant AND v_litige.accord_etablissement THEN
    UPDATE litiges SET statut = 'RESOLU', resolution = 'Clôturé d''un commun accord', resolu_le = NOW() WHERE id = p_litige_id;
    RETURN jsonb_build_object('ok', true, 'cloture', true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'cloture', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_demander_mediation_admin(p_litige_id UUID, p_message TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_litige RECORD;
  v_auteur TEXT;
  v_date_str TEXT;
  v_msg TEXT;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;

  IF v_litige.statut NOT IN ('OUVERT', 'EN_DISCUSSION', 'CONTESTEE') THEN
    RETURN jsonb_build_object('error', 'Médiation impossible pour ce statut.');
  END IF;

  IF v_litige.soignant_id = v_user_id THEN
    v_auteur := 'Soignant';
  ELSIF v_litige.etablissement_id = mon_etablissement_id() THEN
    v_auteur := 'Établissement';
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante.');
  END IF;

  v_date_str := to_char(NOW(), 'DD/MM/YYYY HH24:MI');
  v_msg := '[' || v_date_str || '] ' || v_auteur || ': 🔔 Demande de médiation admin';
  IF p_message IS NOT NULL AND trim(p_message) != '' THEN
    v_msg := v_msg || ' — ' || trim(p_message);
  END IF;

  IF v_litige.reponse IS NOT NULL AND v_litige.reponse != '' THEN
    v_msg := v_litige.reponse || E'\n---\n' || v_msg;
  END IF;

  UPDATE litiges SET statut = 'EN_MEDIATION', reponse = v_msg WHERE id = p_litige_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_repondre_litige(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_cloturer_litige_mutuel(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_demander_mediation_admin(UUID, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
