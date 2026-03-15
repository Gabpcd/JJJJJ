
-- Add bio, annees_experience, specialites columns to soignants
ALTER TABLE public.soignants 
  ADD COLUMN IF NOT EXISTS bio text,
  ADD COLUMN IF NOT EXISTS annees_experience integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS specialites jsonb DEFAULT '[]'::jsonb;

-- Update fn_modifier_mon_profil to accept bio params
CREATE OR REPLACE FUNCTION public.fn_modifier_mon_profil(
  p_telephone text DEFAULT NULL,
  p_adresse_rue text DEFAULT NULL,
  p_adresse_ville text DEFAULT NULL,
  p_adresse_code_postal text DEFAULT NULL,
  p_rayon_deplacement_km integer DEFAULT NULL,
  p_prenom text DEFAULT NULL,
  p_nom text DEFAULT NULL,
  p_date_naissance date DEFAULT NULL,
  p_type_contrat text DEFAULT NULL,
  p_types_contrat_acceptes text DEFAULT NULL,
  p_numero_rpps text DEFAULT NULL,
  p_numero_adeli text DEFAULT NULL,
  p_adresse_lat numeric DEFAULT NULL,
  p_adresse_lng numeric DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_annees_experience integer DEFAULT NULL,
  p_specialites text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_specialites jsonb;
BEGIN
  -- Parse specialites JSON
  BEGIN
    v_specialites := COALESCE(p_specialites::jsonb, '[]'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_specialites := '[]'::jsonb;
  END;

  UPDATE soignants SET
    telephone = COALESCE(p_telephone, telephone),
    prenom = COALESCE(p_prenom, prenom),
    nom = COALESCE(p_nom, nom),
    date_naissance = COALESCE(p_date_naissance, date_naissance),
    type_contrat = COALESCE(p_type_contrat, type_contrat),
    types_contrat_acceptes = COALESCE(p_types_contrat_acceptes, types_contrat_acceptes),
    numero_rpps = COALESCE(p_numero_rpps, numero_rpps),
    numero_adeli = COALESCE(p_numero_adeli, numero_adeli),
    rayon_deplacement_km = COALESCE(p_rayon_deplacement_km, rayon_deplacement_km),
    adresse_lat = COALESCE(p_adresse_lat, adresse_lat),
    adresse_lng = COALESCE(p_adresse_lng, adresse_lng),
    bio = p_bio,
    annees_experience = COALESCE(p_annees_experience, annees_experience),
    specialites = v_specialites,
    modifie_le = now()
  WHERE id = auth.uid();

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Create fn_postuler_mission RPC
CREATE OR REPLACE FUNCTION public.fn_postuler_mission(
  p_mission_id uuid,
  p_message text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_mission record;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_mission.statut != 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible');
  END IF;
  IF v_mission.mode_attribution != 'CANDIDATURE' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures');
  END IF;
  
  -- Check not already applied
  IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
    RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission');
  END IF;

  INSERT INTO candidatures (mission_id, soignant_id, message, statut)
  VALUES (p_mission_id, auth.uid(), p_message, 'EN_ATTENTE');

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Create fn_traiter_candidature RPC
CREATE OR REPLACE FUNCTION public.fn_traiter_candidature(
  p_candidature_id uuid,
  p_decision text,
  p_motif text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_cand record;
  v_mission record;
BEGIN
  SELECT * INTO v_cand FROM candidatures WHERE id = p_candidature_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Candidature introuvable');
  END IF;

  SELECT * INTO v_mission FROM missions WHERE id = v_cand.mission_id;
  IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  IF p_decision = 'ACCEPTEE' THEN
    -- Accept this candidature
    UPDATE candidatures SET statut = 'ACCEPTEE', traite_le = now() WHERE id = p_candidature_id;
    -- Reject all others
    UPDATE candidatures SET statut = 'REFUSEE', motif_refus = 'Un autre candidat a été sélectionné', traite_le = now()
    WHERE mission_id = v_cand.mission_id AND id != p_candidature_id AND statut = 'EN_ATTENTE';
    -- Assign the mission
    UPDATE missions SET soignant_assigne_id = v_cand.soignant_id, statut = 'ASSIGNEE', modifie_le = now()
    WHERE id = v_cand.mission_id;
  ELSIF p_decision = 'REFUSEE' THEN
    UPDATE candidatures SET statut = 'REFUSEE', motif_refus = p_motif, traite_le = now() WHERE id = p_candidature_id;
  ELSE
    RETURN jsonb_build_object('error', 'Décision invalide');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
