CREATE OR REPLACE FUNCTION public.fn_proposer_cloture_litige(p_litige_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_litige litiges%ROWTYPE;
  v_uid uuid := auth.uid();
  v_role text;
  v_autre_accord boolean;
BEGIN
  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  IF v_litige.statut NOT IN ('OUVERT', 'CONTESTEE', 'EN_DISCUSSION') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Ce litige est déjà résolu ou fermé');
  END IF;

  IF v_uid = v_litige.soignant_id THEN
    v_role := 'SOIGNANT';
    v_autre_accord := v_litige.accord_etablissement;
  ELSIF (SELECT raw_app_meta_data->>'etablissement_id' FROM auth.users WHERE id = v_uid) = v_litige.etablissement_id::text THEN
    v_role := 'ETABLISSEMENT';
    v_autre_accord := v_litige.accord_soignant;
  ELSIF public.est_admin() THEN
    UPDATE litiges SET
      statut = 'RESOLUE_ADMIN',
      resolution = 'Clôture à l''amiable validée par l''admin',
      resolu_par = v_uid,
      resolu_le = now()
    WHERE id = p_litige_id;
    RETURN jsonb_build_object('success', true, 'statut', 'cloture_validee');
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  IF v_autre_accord = true THEN
    UPDATE litiges SET
      accord_soignant = CASE WHEN v_role = 'SOIGNANT' THEN true ELSE accord_soignant END,
      accord_soignant_le = CASE WHEN v_role = 'SOIGNANT' THEN now() ELSE accord_soignant_le END,
      accord_etablissement = CASE WHEN v_role = 'ETABLISSEMENT' THEN true ELSE accord_etablissement END,
      accord_etablissement_le = CASE WHEN v_role = 'ETABLISSEMENT' THEN now() ELSE accord_etablissement_le END,
      statut = 'FERME',
      resolution = 'Clôture à l''amiable acceptée par les deux parties',
      resolu_le = now(),
      resolu_par = v_uid
    WHERE id = p_litige_id;
    RETURN jsonb_build_object('success', true, 'statut', 'cloture_validee');
  ELSE
    IF v_role = 'SOIGNANT' THEN
      UPDATE litiges SET accord_soignant = true, accord_soignant_le = now() WHERE id = p_litige_id;
    ELSE
      UPDATE litiges SET accord_etablissement = true, accord_etablissement_le = now() WHERE id = p_litige_id;
    END IF;
    RETURN jsonb_build_object('success', true, 'statut', 'en_attente_accord');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_proposer_cloture_litige(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_proposer_cloture_litige(uuid) TO service_role;