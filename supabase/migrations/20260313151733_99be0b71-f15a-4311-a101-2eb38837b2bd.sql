
-- RPC: Validate a presence (establishment side)
CREATE OR REPLACE FUNCTION public.fn_valider_presence(p_presence_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid;
  v_presence record;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT p.* INTO v_presence
  FROM presences p
  JOIN missions m ON m.id = p.mission_id
  WHERE p.id = p_presence_id
    AND m.etablissement_id = v_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Présence introuvable');
  END IF;

  IF v_presence.valide_par_etablissement = true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Déjà validée');
  END IF;

  UPDATE presences
  SET valide_par_etablissement = true,
      valide_le = now(),
      modifie_le = now()
  WHERE id = p_presence_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- RPC: Contest a presence (establishment side)
CREATE OR REPLACE FUNCTION public.fn_contester_presence(p_presence_id uuid, p_motif text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  IF p_motif IS NULL OR length(trim(p_motif)) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Le motif est obligatoire (3 caractères min.)');
  END IF;

  UPDATE presences
  SET motif_litige = trim(p_motif),
      modifie_le = now()
  FROM missions m
  WHERE presences.id = p_presence_id
    AND presences.mission_id = m.id
    AND m.etablissement_id = v_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Présence introuvable');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- RPC: Bulk validate presences (establishment side)
CREATE OR REPLACE FUNCTION public.fn_valider_presences_lot(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_etab_id uuid;
  v_count integer;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE presences p
  SET valide_par_etablissement = true,
      valide_le = now(),
      modifie_le = now()
  FROM missions m
  WHERE p.id = ANY(p_ids)
    AND p.mission_id = m.id
    AND m.etablissement_id = v_etab_id
    AND p.valide_par_etablissement = false
    AND p.perimetre_gps_valide = true
    AND (p.alerte_teleportation = false OR p.alerte_teleportation IS NULL);

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'nb_validees', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_valider_presence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_contester_presence(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_valider_presences_lot(uuid[]) TO authenticated;
