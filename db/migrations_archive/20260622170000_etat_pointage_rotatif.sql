-- Pointage rotatif (PR 2/3) — RPC de lecture d'état pour l'écran de pointage.
--
-- L'étab a besoin d'afficher le code rotatif courant (code_pointage_actif) et de
-- savoir si un segment est ouvert. Le soignant a besoin de voir ses segments du
-- jour et le prochain type de scan. Cette RPC sert les deux (SECURITY DEFINER,
-- contrôle d'accès interne). Le code rotatif n'est renvoyé qu'à l'étab (le soignant
-- ne doit pas le connaître : il le scanne/saisit depuis l'écran de l'établissement).

CREATE OR REPLACE FUNCTION public.fn_etat_pointage_mission(p_mission_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_is_etab boolean;
  v_is_soignant boolean;
  v_segments jsonb;
  v_segment_ouvert boolean;
BEGIN
  SELECT id, etablissement_id, soignant_assigne_id, statut,
         code_pointage_actif, prochain_type_scan, nb_scans, intitule
    INTO v_mission
    FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  v_is_etab := est_admin() OR v_mission.etablissement_id = mon_etablissement_id();
  v_is_soignant := v_mission.soignant_assigne_id = auth.uid();

  IF NOT v_is_etab AND NOT v_is_soignant THEN
    RETURN jsonb_build_object('error', 'Accès interdit');
  END IF;

  -- Segments effectifs (les vrais créneaux travaillés, base de la paie)
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object('id', id, 'debut', debut, 'fin', fin) ORDER BY debut), '[]'::jsonb),
    bool_or(fin IS NULL)
    INTO v_segments, v_segment_ouvert
    FROM mission_creneaux
    WHERE mission_id = p_mission_id AND type_creneau = 'EFFECTIF';

  RETURN jsonb_build_object(
    'statut', v_mission.statut,
    'intitule', v_mission.intitule,
    'prochain_type_scan', v_mission.prochain_type_scan,
    'nb_scans', v_mission.nb_scans,
    'segment_ouvert', COALESCE(v_segment_ouvert, false),
    'segments', v_segments,
    -- Visible uniquement par l'établissement (l'affiche au soignant à pointer).
    'code_pointage_actif', CASE WHEN v_is_etab THEN v_mission.code_pointage_actif ELSE NULL END,
    'est_etab', v_is_etab
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_etat_pointage_mission(uuid) TO authenticated;
