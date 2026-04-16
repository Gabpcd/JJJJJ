-- ============================================================
-- CP5b Step 5 — Garde-fous : fn_declarer_fin_retroactive + fn_verifier_pre_facturation
-- ============================================================
-- Audit: /docs/cp5b-creneaux-et-pointage.md sections 4.4, 5.2
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 5a. fn_declarer_fin_retroactive
-- ──────────────────────────────────────────────────────────────
-- Déclare la fin d'un créneau EFFECTIF oublié (pas de scan FERMETURE).
-- Callable par : soignant assigné OU admin de l'étab de la mission.
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_declarer_fin_retroactive(
  p_mission_id uuid,
  p_heure_fin timestamptz,
  p_raison text DEFAULT 'Oubli de scan'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission RECORD;
  v_creneau_id uuid;
  v_creneau_debut timestamptz;
  v_arrondi timestamptz;
  v_scan_numero smallint;
  v_new_code text;
  v_new_hmac text;
  v_caller_is_soignant boolean;
  v_caller_is_etab_admin boolean;
BEGIN
  -- Step 1: Load mission + lock
  SELECT id, soignant_assigne_id, etablissement_id, nb_scans, statut
  INTO v_mission
  FROM missions
  WHERE id = p_mission_id AND statut IN ('ASSIGNEE', 'EN_COURS')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable ou dans un statut incompatible.', p_mission_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Step 2: Caller = soignant assigné OU admin de l'étab
  v_caller_is_soignant := (auth.uid() = v_mission.soignant_assigne_id);
  v_caller_is_etab_admin := est_admin_etablissement()
    AND mon_etablissement_id() = v_mission.etablissement_id;

  IF NOT (v_caller_is_soignant OR v_caller_is_etab_admin OR est_admin()) THEN
    RAISE EXCEPTION 'Vous n''êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Step 3: Find open EFFECTIF créneau
  SELECT id, debut INTO v_creneau_id, v_creneau_debut
  FROM mission_creneaux
  WHERE mission_id = v_mission.id AND type_creneau = 'EFFECTIF' AND fin IS NULL
  ORDER BY debut DESC LIMIT 1;

  IF v_creneau_id IS NULL THEN
    RAISE EXCEPTION 'Aucun créneau effectif ouvert à fermer pour cette mission.'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Step 4: Validate p_heure_fin > debut
  IF p_heure_fin <= v_creneau_debut THEN
    RAISE EXCEPTION 'L''heure de fin (%) doit être postérieure au début du créneau (%).',
      p_heure_fin, v_creneau_debut USING ERRCODE = 'check_violation';
  END IF;

  -- Step 5: Arrondir + minimum 15-min slot
  v_arrondi := fn_arrondir_quart_heure(p_heure_fin);
  IF v_arrondi <= v_creneau_debut THEN
    v_arrondi := v_creneau_debut + INTERVAL '15 minutes';
  END IF;

  -- Step 6: UPDATE créneau SET fin
  UPDATE mission_creneaux SET fin = v_arrondi WHERE id = v_creneau_id;

  -- Step 7: INSERT scan fictif FERMETURE
  v_scan_numero := COALESCE(v_mission.nb_scans, 0) + 1;
  INSERT INTO scans_pointage (
    mission_id, soignant_id, code_saisi, numero_scan, type_scan,
    scanne_le, horodatage_arrondi, creneau_effectif_id,
    est_en_avance, validation_etab_requise
  ) VALUES (
    v_mission.id, v_mission.soignant_assigne_id, 'RETROACTIF', v_scan_numero, 'FERMETURE',
    now(), v_arrondi, v_creneau_id,
    false, true
  );

  -- Step 8: Regenerate code
  v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  WHILE EXISTS (
    SELECT 1 FROM missions
    WHERE code_pointage_actif = v_new_code AND id != v_mission.id
      AND statut IN ('ASSIGNEE', 'EN_COURS')
  ) LOOP
    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  END LOOP;

  v_new_hmac := CASE
    WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL THEN
      encode(extensions.hmac(v_mission.id::text || ':' || v_new_code,
        current_setting('app.settings.hmac_secret', true), 'sha256'), 'hex')
    ELSE NULL
  END;

  UPDATE missions SET
    code_pointage_actif = v_new_code,
    code_pointage_hmac = v_new_hmac,
    prochain_type_scan = 'OUVERTURE',
    nb_scans = v_scan_numero
  WHERE id = v_mission.id;

  -- Step 9: Audit
  INSERT INTO journaux_audit
    (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (
    auth.uid(),
    CASE WHEN v_caller_is_soignant THEN 'SOIGNANT'
         WHEN v_caller_is_etab_admin THEN 'ADMIN_ETABLISSEMENT'
         ELSE 'ADMIN_PLATEFORME' END,
    'POINTAGE', 'mission', v_mission.id,
    jsonb_build_object(
      'sous_action', 'FIN_RETROACTIVE',
      'raison', p_raison,
      'creneau_effectif_id', v_creneau_id,
      'debut_creneau', v_creneau_debut,
      'heure_fin_declaree', p_heure_fin,
      'horodatage_arrondi', v_arrondi,
      'validation_etab_requise', true
    )
  );

  -- Step 10: Return
  RETURN jsonb_build_object(
    'creneau_effectif_id', v_creneau_id,
    'debut_creneau', v_creneau_debut,
    'fin_declaree', v_arrondi,
    'validation_etab_requise', true,
    'nouveau_code', v_new_code,
    'nouveau_hmac', v_new_hmac,
    'prochain_type_scan', 'OUVERTURE',
    'numero_scan', v_scan_numero
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_declarer_fin_retroactive(uuid, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_declarer_fin_retroactive(uuid, timestamptz, text) TO service_role;

-- ──────────────────────────────────────────────────────────────
-- 5b. fn_verifier_pre_facturation
-- ──────────────────────────────────────────────────────────────
-- Garde-fou pré-facturation appelé par generate-invoice edge function.
-- Raise EXCEPTION si créneau EFFECTIF ouvert ou écart > 10% sur facturation EFFECTIF.
-- Retourne { ok, source_facturation, duree_previsionnelle, duree_effective,
--           ecart_heures, ecart_pourcent }.
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_verifier_pre_facturation(
  p_mission_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission RECORD;
  v_nb_effectif_ouvert integer;
  v_nb_effectif_ferme integer;
  v_source text;
  v_duree_previsionnelle numeric;
  v_ecart_heures numeric;
  v_ecart_pourcent numeric;
BEGIN
  SELECT id, duree_heures, duree_heures_effective, statut
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable.', p_mission_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Check 1: créneaux EFFECTIF ouverts
  SELECT
    COUNT(*) FILTER (WHERE fin IS NULL),
    COUNT(*) FILTER (WHERE fin IS NOT NULL)
  INTO v_nb_effectif_ouvert, v_nb_effectif_ferme
  FROM mission_creneaux
  WHERE mission_id = p_mission_id AND type_creneau = 'EFFECTIF';

  IF v_nb_effectif_ouvert > 0 THEN
    RAISE EXCEPTION 'Facturation bloquée : % créneau(x) effectif(s) ouvert(s) (fin IS NULL). Utilisez fn_declarer_fin_retroactive pour compléter le pointage.',
      v_nb_effectif_ouvert USING ERRCODE = 'check_violation';
  END IF;

  -- Détermine source de facturation
  v_source := CASE WHEN v_nb_effectif_ferme > 0 THEN 'EFFECTIF' ELSE 'PREVISIONNEL' END;

  -- Compute duree_previsionnelle à partir des créneaux PREVISIONNEL.
  -- NB: missions.duree_heures vaut COALESCE(effectif, prévisionnel) donc
  --     inutilisable pour l'écart.
  SELECT COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
                        FILTER (WHERE NOT est_pause)::numeric, 2), 0)
  INTO v_duree_previsionnelle
  FROM mission_creneaux
  WHERE mission_id = p_mission_id AND type_creneau = 'PREVISIONNEL';

  IF v_duree_previsionnelle = 0 OR v_mission.duree_heures_effective IS NULL THEN
    v_ecart_heures := 0;
    v_ecart_pourcent := 0;
  ELSE
    v_ecart_heures := ROUND(ABS(v_duree_previsionnelle - v_mission.duree_heures_effective), 2);
    v_ecart_pourcent := ROUND(v_ecart_heures / v_duree_previsionnelle * 100, 2);
  END IF;

  -- Check 2: écart > 10% sur facturation EFFECTIF → BLOQUANT (décision C3)
  IF v_source = 'EFFECTIF' AND v_ecart_pourcent > 10 THEN
    RAISE EXCEPTION 'Facturation bloquée : écart prévisionnel/effectif de % pct (seuil 10 pct). Prévisionnel=%h, effectif=%h. Utilisez fn_declarer_fin_retroactive pour ajuster.',
      v_ecart_pourcent, v_duree_previsionnelle, v_mission.duree_heures_effective
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'source_facturation', v_source,
    'duree_previsionnelle', v_duree_previsionnelle,
    'duree_effective', v_mission.duree_heures_effective,
    'ecart_heures', v_ecart_heures,
    'ecart_pourcent', v_ecart_pourcent,
    'nb_creneaux_effectif_fermes', v_nb_effectif_ferme
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_verifier_pre_facturation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verifier_pre_facturation(uuid) TO service_role;
