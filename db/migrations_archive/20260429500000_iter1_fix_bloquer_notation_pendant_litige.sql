-- Itération 1 — Fix B.8 : bloquer notation pendant litige ouvert (MEDIATION_EN_COURS ou REVUE_ADMIN)
-- Notation autorisée : OUVERT/EN_DISCUSSION/EN_MEDIATION (avant médiation amiable formelle)
--                    + tous statuts résolus (post-litige)
-- Notation bloquée :   MEDIATION_EN_COURS, REVUE_ADMIN (pendant arbitrage actif)

CREATE OR REPLACE FUNCTION public.fn_creer_notation_mission(p_mission_id uuid, p_sens text, p_critere_1 integer, p_critere_2 integer, p_critere_3 integer, p_critere_4 integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_mission RECORD;
  v_sens public.sens_notation;
  v_notateur_id UUID;
  v_note_id UUID;
  v_id UUID;
  v_tardive BOOLEAN := false;
  v_litige_actif_count INT;
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

  -- Itération 1 fix B.8 : bloquer notation pendant litige actif (médiation/arbitrage)
  IF NOT est_admin() THEN
    SELECT COUNT(*) INTO v_litige_actif_count FROM litiges
    WHERE mission_id = p_mission_id
      AND statut IN ('MEDIATION_EN_COURS', 'REVUE_ADMIN');
    IF v_litige_actif_count > 0 THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution.');
    END IF;
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
$function$;

NOTIFY pgrst, 'reload schema';
