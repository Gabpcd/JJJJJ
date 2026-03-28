-- 1) fn_ouvrir_litige_rate_limited
CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
  p_mission_id UUID,
  p_motif TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role TEXT;
  v_etab_id UUID;
  v_soignant_id UUID;
  v_presence_id UUID;
  v_recent_count INT;
  v_litige_id UUID;
  v_initie_par TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT role INTO v_role FROM user_roles WHERE user_id = v_uid LIMIT 1;

  SELECT etablissement_id, soignant_assigne_id
    INTO v_etab_id, v_soignant_id
    FROM missions WHERE id = p_mission_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_role IN ('ETABLISSEMENT', 'ADMIN_ETABLISSEMENT') THEN
    IF v_etab_id != COALESCE(
      (SELECT etablissement_id FROM user_roles WHERE user_id = v_uid LIMIT 1),
      v_uid
    ) THEN
      RETURN jsonb_build_object('error', 'Non autorisé');
    END IF;
    v_initie_par := 'ETABLISSEMENT';
  ELSIF v_role = 'SOIGNANT' THEN
    IF v_soignant_id != v_uid THEN
      RETURN jsonb_build_object('error', 'Non autorisé');
    END IF;
    v_initie_par := 'SOIGNANT';
  ELSIF v_role = 'ADMIN_PLATEFORME' THEN
    v_initie_par := 'ADMIN';
  ELSE
    RETURN jsonb_build_object('error', 'Rôle non autorisé');
  END IF;

  SELECT COUNT(*) INTO v_recent_count
    FROM litiges
    WHERE (etablissement_id = v_etab_id OR soignant_id = v_uid)
      AND cree_le > NOW() - INTERVAL '24 hours';

  IF v_recent_count >= 3 THEN
    RETURN jsonb_build_object('error', 'Limite de 3 litiges par 24h atteinte. Réessayez demain.');
  END IF;

  IF EXISTS (SELECT 1 FROM litiges WHERE mission_id = p_mission_id AND statut NOT IN ('FERME', 'RESOLU')) THEN
    RETURN jsonb_build_object('error', 'Un litige est déjà ouvert pour cette mission');
  END IF;

  SELECT id INTO v_presence_id FROM presences WHERE mission_id = p_mission_id LIMIT 1;

  INSERT INTO litiges (mission_id, presence_id, soignant_id, etablissement_id, motif, initie_par, statut)
  VALUES (p_mission_id, v_presence_id, COALESCE(v_soignant_id, v_uid), v_etab_id, p_motif, v_initie_par, 'OUVERT')
  RETURNING id INTO v_litige_id;

  RETURN jsonb_build_object('success', true, 'litige_id', v_litige_id);
END;
$$;

-- 2) fn_repondre_litige
CREATE OR REPLACE FUNCTION public.fn_repondre_litige(
  p_litige_id UUID,
  p_reponse TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_litige RECORD;
  v_auteur TEXT;
  v_nouvelle_reponse TEXT;
  v_date_str TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;

  IF v_litige.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Litige introuvable');
  END IF;

  IF v_litige.statut IN ('FERME', 'RESOLU', 'RESOLUE_SOIGNANT', 'RESOLUE_ETABLISSEMENT', 'RESOLUE_ADMIN') THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé');
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    v_auteur := 'Soignant';
  ELSIF v_uid = v_litige.etablissement_id OR EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = v_uid AND etablissement_id = v_litige.etablissement_id
  ) THEN
    v_auteur := 'Établissement';
  ELSIF EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'ADMIN_PLATEFORME') THEN
    v_auteur := 'Admin';
  ELSE
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  v_date_str := TO_CHAR(NOW(), 'DD/MM/YYYY HH24:MI');
  v_nouvelle_reponse := '[' || v_date_str || '] ' || v_auteur || ': ' || p_reponse;

  IF v_litige.reponse IS NOT NULL AND v_litige.reponse != '' THEN
    v_nouvelle_reponse := v_litige.reponse || E'\n---\n' || v_nouvelle_reponse;
  END IF;

  UPDATE litiges
  SET reponse = v_nouvelle_reponse,
      statut = 'EN_DISCUSSION'
  WHERE id = p_litige_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 3) fn_cloturer_litige_mutuel
CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_mutuel(
  p_litige_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_litige RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;

  IF v_litige.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Litige introuvable');
  END IF;

  IF v_litige.statut IN ('FERME', 'RESOLU', 'RESOLUE_SOIGNANT', 'RESOLUE_ETABLISSEMENT', 'RESOLUE_ADMIN') THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé');
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
  ELSIF v_uid = v_litige.etablissement_id OR EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = v_uid AND etablissement_id = v_litige.etablissement_id
  ) THEN
    UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
  ELSE
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;

  IF v_litige.accord_soignant = TRUE AND v_litige.accord_etablissement = TRUE THEN
    UPDATE litiges
    SET statut = 'RESOLU',
        resolution = 'Clôturé d''un commun accord',
        resolu_le = NOW()
    WHERE id = p_litige_id;
    RETURN jsonb_build_object('success', true, 'cloture', true);
  END IF;

  RETURN jsonb_build_object('success', true, 'cloture', false);
END;
$$;

-- 4) fn_demander_mediation_admin
CREATE OR REPLACE FUNCTION public.fn_demander_mediation_admin(
  p_litige_id UUID,
  p_message TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_litige RECORD;
  v_auteur TEXT;
  v_date_str TEXT;
  v_msg TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;

  IF v_litige.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Litige introuvable');
  END IF;

  IF v_litige.statut IN ('FERME', 'RESOLU', 'RESOLUE_SOIGNANT', 'RESOLUE_ETABLISSEMENT', 'RESOLUE_ADMIN') THEN
    RETURN jsonb_build_object('error', 'Ce litige est déjà clôturé');
  END IF;

  IF v_litige.statut = 'EN_MEDIATION' THEN
    RETURN jsonb_build_object('error', 'La médiation est déjà demandée pour ce litige');
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    v_auteur := 'Soignant';
  ELSIF v_uid = v_litige.etablissement_id OR EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = v_uid AND etablissement_id = v_litige.etablissement_id
  ) THEN
    v_auteur := 'Établissement';
  ELSE
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  v_date_str := TO_CHAR(NOW(), 'DD/MM/YYYY HH24:MI');
  v_msg := '[' || v_date_str || '] ' || v_auteur || ' (demande médiation): ' || COALESCE(p_message, 'Demande de médiation administrateur');

  IF v_litige.reponse IS NOT NULL AND v_litige.reponse != '' THEN
    v_msg := v_litige.reponse || E'\n---\n' || v_msg;
  END IF;

  UPDATE litiges
  SET statut = 'EN_MEDIATION',
      reponse = v_msg
  WHERE id = p_litige_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_repondre_litige(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cloturer_litige_mutuel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_demander_mediation_admin(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_repondre_litige(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_cloturer_litige_mutuel(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_demander_mediation_admin(UUID, TEXT) TO service_role;