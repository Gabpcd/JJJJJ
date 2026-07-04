
-- C1: fn_creer_mission - Secure RPC for single mission creation
CREATE OR REPLACE FUNCTION public.fn_creer_mission(
  p_intitule text,
  p_description text DEFAULT NULL,
  p_profession_requise type_profession DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_debut_le timestamptz DEFAULT NULL,
  p_fin_le timestamptz DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etablissement_id uuid;
  v_factures_impayees integer;
  v_mission_id uuid;
BEGIN
  -- Resolve etablissement_id from caller
  v_etablissement_id := mon_etablissement_id();
  IF v_etablissement_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé.');
  END IF;

  -- Validate required fields
  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Champs obligatoires manquants.');
  END IF;

  -- Validate dates
  IF p_fin_le <= p_debut_le THEN
    RETURN jsonb_build_object('success', false, 'error', 'La fin doit être après le début.');
  END IF;
  IF p_debut_le < now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'La mission ne peut pas commencer dans le passé.');
  END IF;

  -- Check unpaid invoices
  SELECT count(*) INTO v_factures_impayees
  FROM factures
  WHERE etablissement_id = v_etablissement_id
    AND statut IN ('EMISE', 'EN_RETARD')
    AND date_echeance < CURRENT_DATE;

  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez des factures impayées. Veuillez régulariser avant de publier.');
  END IF;

  -- Insert mission with controlled columns only
  INSERT INTO missions (
    etablissement_id, intitule, description, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence
  ) VALUES (
    v_etablissement_id, p_intitule, p_description, p_profession_requise, p_service,
    p_debut_le, p_fin_le, p_taux_horaire_base, p_est_urgente, CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END
  )
  RETURNING id INTO v_mission_id;

  RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- C2: fn_creer_serie - Atomic batch creation with max 30
CREATE OR REPLACE FUNCTION public.fn_creer_serie(
  p_intitule text,
  p_description text DEFAULT NULL,
  p_profession_requise type_profession DEFAULT NULL,
  p_service text DEFAULT NULL,
  p_taux_horaire_base numeric DEFAULT NULL,
  p_est_urgente boolean DEFAULT false,
  p_niveau_urgence integer DEFAULT 0,
  p_missions jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etablissement_id uuid;
  v_factures_impayees integer;
  v_count integer;
  v_mission jsonb;
  v_created_ids uuid[] := '{}';
  v_mission_id uuid;
BEGIN
  v_etablissement_id := mon_etablissement_id();
  IF v_etablissement_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé.');
  END IF;

  -- Validate required fields
  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Champs obligatoires manquants.');
  END IF;

  -- Max 30 missions per batch
  v_count := jsonb_array_length(p_missions);
  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun créneau fourni.');
  END IF;
  IF v_count > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Maximum 30 créneaux par série.');
  END IF;

  -- Check unpaid invoices
  SELECT count(*) INTO v_factures_impayees
  FROM factures
  WHERE etablissement_id = v_etablissement_id
    AND statut IN ('EMISE', 'EN_RETARD')
    AND date_echeance < CURRENT_DATE;

  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez des factures impayées. Veuillez régulariser avant de publier.');
  END IF;

  -- Insert all missions in one transaction
  FOR v_mission IN SELECT * FROM jsonb_array_elements(p_missions)
  LOOP
    INSERT INTO missions (
      etablissement_id, intitule, description, profession_requise, service,
      debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence
    ) VALUES (
      v_etablissement_id,
      p_intitule,
      p_description,
      p_profession_requise,
      p_service,
      (v_mission->>'debut')::timestamptz,
      (v_mission->>'fin')::timestamptz,
      p_taux_horaire_base,
      p_est_urgente,
      CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END
    )
    RETURNING id INTO v_mission_id;
    v_created_ids := v_created_ids || v_mission_id;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count, 'mission_ids', to_jsonb(v_created_ids));
EXCEPTION WHEN OTHERS THEN
  -- Transaction auto-rolls back
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
