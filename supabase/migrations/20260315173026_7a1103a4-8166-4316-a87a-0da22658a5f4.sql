-- 1. Create RPC to get check-in codes for a mission (établissement side)
CREATE OR REPLACE FUNCTION public.fn_codes_pointage_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_mission record;
BEGIN
  SELECT id, code_arrivee, code_depart, etablissement_id
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès interdit');
  END IF;

  IF v_mission.code_arrivee IS NULL THEN
    UPDATE missions SET
      code_arrivee = lpad(floor(random() * 1000000)::text, 6, '0'),
      code_depart = lpad(floor(random() * 1000000)::text, 6, '0')
    WHERE id = p_mission_id
    RETURNING code_arrivee, code_depart INTO v_mission.code_arrivee, v_mission.code_depart;
  END IF;

  RETURN jsonb_build_object(
    'code_arrivee', v_mission.code_arrivee,
    'code_depart', v_mission.code_depart
  );
END;
$$;

-- 2. Create RPC for code-based check-in (arrival)
CREATE OR REPLACE FUNCTION public.fn_pointer_arrivee_code(p_mission_id uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_mission record;
  v_presence_id uuid;
BEGIN
  SELECT id, code_arrivee, soignant_assigne_id, statut
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  IF v_mission.soignant_assigne_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  IF v_mission.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Statut invalide');
  END IF;

  IF v_mission.code_arrivee IS NULL OR v_mission.code_arrivee != p_code THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code incorrect');
  END IF;

  IF EXISTS (SELECT 1 FROM presences WHERE mission_id = p_mission_id AND soignant_id = auth.uid() AND pointage_arrivee_le IS NOT NULL) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Arrivée déjà pointée');
  END IF;

  INSERT INTO presences (
    mission_id, soignant_id, pointage_arrivee_le,
    methode_pointage_arrivee, perimetre_gps_valide
  ) VALUES (
    p_mission_id, auth.uid(), now(),
    'CODE', true
  )
  RETURNING id INTO v_presence_id;

  UPDATE missions SET statut = 'EN_COURS' WHERE id = p_mission_id AND statut = 'ASSIGNEE';

  RETURN jsonb_build_object('success', true, 'presence_id', v_presence_id, 'methode', 'CODE');
END;
$$;

-- 3. Create RPC for code-based check-out (departure)
CREATE OR REPLACE FUNCTION public.fn_pointer_depart_code(p_presence_id uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_presence record;
  v_mission record;
BEGIN
  SELECT p.id, p.mission_id, p.soignant_id, p.pointage_depart_le
  INTO v_presence
  FROM presences p WHERE p.id = p_presence_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Présence introuvable');
  END IF;

  IF v_presence.soignant_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  IF v_presence.pointage_depart_le IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Départ déjà pointé');
  END IF;

  SELECT code_depart INTO v_mission FROM missions WHERE id = v_presence.mission_id;

  IF v_mission.code_depart IS NULL OR v_mission.code_depart != p_code THEN
    RETURN jsonb_build_object('success', false, 'error', 'Code incorrect');
  END IF;

  UPDATE presences SET
    pointage_depart_le = now(),
    methode_pointage_depart = 'CODE'
  WHERE id = p_presence_id;

  UPDATE missions SET statut = 'TERMINEE' WHERE id = v_presence.mission_id;

  RETURN jsonb_build_object('success', true, 'methode', 'CODE');
END;
$$;

-- 4. Add method columns to presences if not exists
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'presences' AND column_name = 'methode_pointage_arrivee') THEN
    ALTER TABLE public.presences ADD COLUMN methode_pointage_arrivee text DEFAULT 'GPS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'presences' AND column_name = 'methode_pointage_depart') THEN
    ALTER TABLE public.presences ADD COLUMN methode_pointage_depart text DEFAULT 'GPS';
  END IF;
END $$;