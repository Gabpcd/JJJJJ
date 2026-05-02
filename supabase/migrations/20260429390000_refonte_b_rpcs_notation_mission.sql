-- Refonte.B — RPCs notation bidirectionnelle
--
-- 4 RPCs exposées au frontend :
--   * fn_creer_notation_mission : INSERT avec validations (sens, légitimité, mission TERMINEE)
--   * fn_modifier_notation_mission : UPDATE dans les 7j (notateur ou admin)
--   * fn_compter_missions_sans_notation : pour bandeau encouragement (compte 30j)
--   * fn_lister_notations_recues : notations reçues anonymisées (audience auto via mon_etablissement_id())

-- 1) fn_creer_notation_mission
CREATE OR REPLACE FUNCTION public.fn_creer_notation_mission(
  p_mission_id UUID,
  p_sens TEXT,
  p_critere_1 INT,
  p_critere_2 INT,
  p_critere_3 INT,
  p_critere_4 INT,
  p_commentaire TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_mission RECORD;
  v_sens public.sens_notation;
  v_notateur_id UUID;
  v_note_id UUID;
  v_id UUID;
  v_tardive BOOLEAN := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  BEGIN v_sens := UPPER(TRIM(p_sens))::public.sens_notation;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sens invalide');
  END;

  IF p_critere_1 NOT BETWEEN 1 AND 5 OR p_critere_2 NOT BETWEEN 1 AND 5
     OR p_critere_3 NOT BETWEEN 1 AND 5 OR p_critere_4 NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Critères doivent être entre 1 et 5');
  END IF;

  IF p_commentaire IS NOT NULL AND LENGTH(p_commentaire) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Commentaire max 2000 caractères');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut, fin_le INTO v_mission
  FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  IF v_mission.statut <> 'TERMINEE' AND NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seules les missions TERMINEE peuvent être notées');
  END IF;

  IF v_sens = 'ETAB_VERS_SOIGNANT' THEN
    IF NOT est_admin() AND v_mission.etablissement_id <> v_etab_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas l''établissement de cette mission');
    END IF;
    IF v_mission.soignant_assigne_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Mission sans soignant assigné');
    END IF;
    v_notateur_id := COALESCE(v_etab_id, v_mission.etablissement_id);
    v_note_id := v_mission.soignant_assigne_id;
  ELSE
    IF NOT est_admin() AND v_mission.soignant_assigne_id <> v_uid THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas le soignant de cette mission');
    END IF;
    v_notateur_id := v_uid;
    v_note_id := v_mission.etablissement_id;
  END IF;

  IF v_mission.fin_le < NOW() - INTERVAL '30 days' THEN
    v_tardive := true;
  END IF;

  INSERT INTO notations_missions (
    mission_id, notateur_id, note_id, sens,
    critere_1, critere_2, critere_3, critere_4, commentaire
  ) VALUES (
    p_mission_id, v_notateur_id, v_note_id, v_sens,
    p_critere_1, p_critere_2, p_critere_3, p_critere_4, NULLIF(TRIM(p_commentaire), '')
  )
  ON CONFLICT (mission_id, sens) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission déjà notée pour ce sens');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_notateur_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_DONNEE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text, 'note_id', v_note_id, 'tardive', v_tardive)
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_note_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'NOTATION_RECUE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text)
  );

  RETURN jsonb_build_object('success', true, 'id', v_id, 'tardive', v_tardive);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_creer_notation_mission(UUID, TEXT, INT, INT, INT, INT, TEXT) TO authenticated;

-- 2) fn_modifier_notation_mission
CREATE OR REPLACE FUNCTION public.fn_modifier_notation_mission(
  p_notation_id UUID,
  p_critere_1 INT,
  p_critere_2 INT,
  p_critere_3 INT,
  p_critere_4 INT,
  p_commentaire TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_notation RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_critere_1 NOT BETWEEN 1 AND 5 OR p_critere_2 NOT BETWEEN 1 AND 5
     OR p_critere_3 NOT BETWEEN 1 AND 5 OR p_critere_4 NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Critères doivent être entre 1 et 5');
  END IF;

  IF p_commentaire IS NOT NULL AND LENGTH(p_commentaire) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Commentaire max 2000 caractères');
  END IF;

  SELECT * INTO v_notation FROM notations_missions WHERE id = p_notation_id;
  IF v_notation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation introuvable');
  END IF;

  IF NOT est_admin() THEN
    IF v_notation.notateur_id NOT IN (v_uid, COALESCE(v_etab_id, '00000000-0000-0000-0000-000000000000'::uuid)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
    END IF;
  END IF;

  IF v_notation.cree_le < NOW() - INTERVAL '7 days' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation non modifiable après 7 jours');
  END IF;

  UPDATE notations_missions SET
    critere_1 = p_critere_1, critere_2 = p_critere_2,
    critere_3 = p_critere_3, critere_4 = p_critere_4,
    commentaire = NULLIF(TRIM(p_commentaire), ''),
    mis_a_jour_le = NOW()
  WHERE id = p_notation_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_notation.notateur_id,
    p_type_acteur := CASE WHEN v_notation.sens = 'ETAB_VERS_SOIGNANT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_DONNEE',
    p_type_ressource := 'mission',
    p_id_ressource := v_notation.mission_id,
    p_details := jsonb_build_object('notation_id', p_notation_id, 'sens', v_notation.sens::text, 'modification', true)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_modifier_notation_mission(UUID, INT, INT, INT, INT, TEXT) TO authenticated;

-- 3) fn_compter_missions_sans_notation
CREATE OR REPLACE FUNCTION public.fn_compter_missions_sans_notation(p_role TEXT DEFAULT 'auto')
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID;
  v_role TEXT;
  v_count INT := 0;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('count', 0); END IF;

  v_etab_id := mon_etablissement_id();
  v_role := CASE
    WHEN p_role = 'auto' THEN
      CASE WHEN v_etab_id IS NOT NULL THEN 'ETAB' ELSE 'SOIGNANT' END
    ELSE p_role
  END;

  IF v_role = 'ETAB' AND v_etab_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_count FROM missions m
    WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE'
      AND m.soignant_assigne_id IS NOT NULL
      AND m.fin_le >= NOW() - INTERVAL '30 days'
      AND NOT EXISTS (SELECT 1 FROM notations_missions n WHERE n.mission_id = m.id AND n.sens = 'ETAB_VERS_SOIGNANT');
  ELSE
    SELECT COUNT(*) INTO v_count FROM missions m
    WHERE m.soignant_assigne_id = v_uid AND m.statut = 'TERMINEE'
      AND m.fin_le >= NOW() - INTERVAL '30 days'
      AND NOT EXISTS (SELECT 1 FROM notations_missions n WHERE n.mission_id = m.id AND n.sens = 'SOIGNANT_VERS_ETAB');
  END IF;

  RETURN jsonb_build_object('count', v_count, 'role', v_role);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_compter_missions_sans_notation(TEXT) TO authenticated;

-- 4) fn_lister_notations_recues
CREATE OR REPLACE FUNCTION public.fn_lister_notations_recues(p_limit INT DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_target_id UUID;
  v_target_sens public.sens_notation;
  v_result JSONB;
  v_limit INT;
BEGIN
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);

  IF v_etab_id IS NOT NULL THEN
    v_target_id := v_etab_id;
    v_target_sens := 'SOIGNANT_VERS_ETAB';
  ELSIF v_uid IS NOT NULL THEN
    v_target_id := v_uid;
    v_target_sens := 'ETAB_VERS_SOIGNANT';
  ELSE
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', n.id,
    'mission_id', n.mission_id,
    'mission_intitule', m.intitule,
    'mission_fin_le', m.fin_le,
    'critere_1', n.critere_1,
    'critere_2', n.critere_2,
    'critere_3', n.critere_3,
    'critere_4', n.critere_4,
    'note_moyenne', ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1),
    'commentaire', n.commentaire,
    'cree_le', n.cree_le
  ) ORDER BY n.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM notations_missions n
  JOIN missions m ON m.id = n.mission_id
  WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false
  LIMIT v_limit;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_lister_notations_recues(INT) TO authenticated;

NOTIFY pgrst, 'reload schema';
