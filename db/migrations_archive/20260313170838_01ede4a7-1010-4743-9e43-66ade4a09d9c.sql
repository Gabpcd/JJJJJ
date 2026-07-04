
DROP FUNCTION IF EXISTS public.fn_modifier_mission_etablissement(uuid,text,text,text);

CREATE OR REPLACE FUNCTION public.fn_modifier_mission_etablissement(
  p_mission_id uuid,
  p_intitule text,
  p_description text DEFAULT NULL,
  p_service text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mission missions%ROWTYPE;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id AND etablissement_id = mon_etablissement_id();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable ou accès refusé.');
  END IF;

  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seules les missions ouvertes peuvent être modifiées.');
  END IF;

  IF p_intitule IS NULL OR length(trim(p_intitule)) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'L''intitulé doit contenir au moins 3 caractères.');
  END IF;

  UPDATE missions SET
    intitule = trim(p_intitule),
    description = p_description,
    service = p_service,
    modifie_le = now()
  WHERE id = p_mission_id;

  PERFORM fn_ecrire_audit_safe(
    auth.uid(), 'ADMIN_ETABLISSEMENT', 'MISSION_MODIFICATION',
    'mission', p_mission_id, NULL,
    jsonb_build_object('intitule', p_intitule, 'service', p_service),
    NULL, NULL
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- M1: Trigger transition machine
CREATE OR REPLACE FUNCTION public.fn_valider_transition_statut_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transitions_valides text[][];
  v_valide boolean := false;
  v_pair text[];
BEGIN
  IF NEW.statut IS NOT DISTINCT FROM OLD.statut THEN
    RETURN NEW;
  END IF;

  v_transitions_valides := ARRAY[
    ARRAY['OUVERTE', 'ASSIGNEE'],
    ARRAY['OUVERTE', 'ANNULEE_PAR_ETABLISSEMENT'],
    ARRAY['ASSIGNEE', 'EN_COURS'],
    ARRAY['ASSIGNEE', 'ANNULEE_PAR_ETABLISSEMENT'],
    ARRAY['ASSIGNEE', 'ANNULEE_PAR_SOIGNANT'],
    ARRAY['EN_COURS', 'TERMINEE'],
    ARRAY['EN_COURS', 'ABSENCE'],
    ARRAY['EN_COURS', 'ANNULEE_PAR_ETABLISSEMENT'],
    ARRAY['EN_COURS', 'ANNULEE_PAR_SOIGNANT']
  ];

  FOREACH v_pair SLICE 1 IN ARRAY v_transitions_valides LOOP
    IF OLD.statut::text = v_pair[1] AND NEW.statut::text = v_pair[2] THEN
      v_valide := true;
      EXIT;
    END IF;
  END LOOP;

  IF NOT v_valide AND NOT est_admin() THEN
    RAISE EXCEPTION 'Transition de statut invalide : % → %', OLD.statut, NEW.statut;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_valider_transition_statut ON public.missions;
CREATE TRIGGER trg_valider_transition_statut
  BEFORE UPDATE OF statut ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_valider_transition_statut_mission();
