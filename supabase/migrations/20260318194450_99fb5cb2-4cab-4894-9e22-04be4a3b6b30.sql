CREATE OR REPLACE FUNCTION public.fn_creer_mission(
  p_intitule text,
  p_description text DEFAULT NULL,
  p_profession_requise type_profession DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_debut_le timestamptz DEFAULT NULL,
  p_fin_le timestamptz DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_etablissement_id uuid;
  v_factures_impayees integer;
  v_mission_id uuid;
  v_mode text;
BEGIN
  v_etablissement_id := mon_etablissement_id();
  IF v_etablissement_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé.');
  END IF;

  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Champs obligatoires manquants.');
  END IF;

  IF p_fin_le <= p_debut_le THEN
    RETURN jsonb_build_object('success', false, 'error', 'La fin doit être après le début.');
  END IF;
  IF p_debut_le < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'La mission ne peut pas commencer dans le passé.');
  END IF;

  SELECT count(*) INTO v_factures_impayees
  FROM factures
  WHERE etablissement_id = v_etablissement_id
    AND statut IN ('EMISE', 'EN_RETARD')
    AND date_echeance < CURRENT_DATE;

  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez des factures impayées. Veuillez régulariser avant de publier.');
  END IF;

  v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
  IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
    v_mode := 'PREMIER_ARRIVE';
  END IF;

  INSERT INTO missions (
    etablissement_id, intitule, description, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, mode_attribution
  ) VALUES (
    v_etablissement_id, p_intitule, p_description, p_profession_requise, p_service,
    p_debut_le, p_fin_le, p_taux_horaire_base, p_est_urgente, CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
    v_mode
  )
  RETURNING id INTO v_mission_id;

  RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;