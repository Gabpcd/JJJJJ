-- ============================================================
-- CP5b Step 3 — fn_arrondir + gel extension + fn_scanner_code_pointage
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 3a. fn_arrondir_quart_heure
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_arrondir_quart_heure(p_ts timestamptz)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
  SELECT date_trunc('hour', p_ts) +
    INTERVAL '15 minutes' * ROUND(EXTRACT(MINUTE FROM p_ts) / 15.0);
$$;

-- ──────────────────────────────────────────────────────────────
-- 3b. fn_geler_mission_a_assignation — extended with pointage + GEL_APPLIED
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_geler_mission_a_assignation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_etab RECORD;
  v_champ_modifie text;
  v_new_code text;
BEGIN
  -- ════════════════════════════════════════════════════
  -- BLOC 1 : GEL — transition OUVERTE → ASSIGNEE
  -- ════════════════════════════════════════════════════
  IF OLD.statut = 'OUVERTE' AND NEW.statut = 'ASSIGNEE' THEN
    SELECT
      COALESCE(e.taux_majoration_nuit_pourcent, 25)     AS taux_nuit,
      COALESCE(e.taux_majoration_dimanche_pourcent, 25)  AS taux_dim,
      COALESCE(e.taux_majoration_ferie_pourcent, 50)     AS taux_fer,
      COALESCE(e.heure_debut_nuit, '21:00'::time)        AS h_debut_nuit,
      COALESCE(e.heure_fin_nuit, '06:00'::time)          AS h_fin_nuit,
      COALESCE(e.taux_commission_negocie, 15)             AS taux_comm
    INTO v_etab
    FROM etablissements e WHERE e.id = NEW.etablissement_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Établissement % introuvable', NEW.etablissement_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Snapshot _fige
    NEW.taux_horaire_base_fige        := NEW.taux_horaire_base;
    NEW.taux_majoration_nuit_fige     := v_etab.taux_nuit;
    NEW.taux_majoration_dimanche_fige := v_etab.taux_dim;
    NEW.taux_majoration_ferie_fige    := v_etab.taux_fer;
    NEW.heure_debut_nuit_fige         := v_etab.h_debut_nuit;
    NEW.heure_fin_nuit_fige           := v_etab.h_fin_nuit;
    NEW.taux_commission_fige          := COALESCE(NEW.taux_commission, v_etab.taux_comm);
    NEW.fige_le                       := now();

    -- Pointage: generate initial code
    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
    WHILE EXISTS (
      SELECT 1 FROM missions
      WHERE code_pointage_actif = v_new_code AND id != NEW.id
        AND statut IN ('ASSIGNEE', 'EN_COURS')
    ) LOOP
      v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
    END LOOP;

    NEW.code_pointage_actif := v_new_code;
    NEW.code_pointage_hmac := CASE
      WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL THEN
        encode(extensions.hmac(NEW.id::text || ':' || v_new_code,
          current_setting('app.settings.hmac_secret', true), 'sha256'), 'hex')
      ELSE NULL
    END;
    NEW.prochain_type_scan := 'OUVERTURE';
    NEW.nb_scans := 0;

    -- Audit: GEL_APPLIED
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'SYSTEME', 'GEL_APPLIED', 'mission', NEW.id,
      jsonb_build_object(
        'snapshot', jsonb_build_object(
          'taux_horaire_base_fige', NEW.taux_horaire_base_fige,
          'taux_majoration_nuit_fige', NEW.taux_majoration_nuit_fige,
          'taux_majoration_dimanche_fige', NEW.taux_majoration_dimanche_fige,
          'taux_majoration_ferie_fige', NEW.taux_majoration_ferie_fige,
          'heure_debut_nuit_fige', NEW.heure_debut_nuit_fige,
          'heure_fin_nuit_fige', NEW.heure_fin_nuit_fige,
          'taux_commission_fige', NEW.taux_commission_fige
        ),
        'code_pointage_genere', true,
        'soignant_assigne_id', NEW.soignant_assigne_id
      )
    );

    RETURN NEW;
  END IF;

  -- ════════════════════════════════════════════════════
  -- BLOC 2 : DEGEL — transition vers OUVERTE
  -- ════════════════════════════════════════════════════
  IF NEW.statut = 'OUVERTE' AND OLD.statut != 'OUVERTE'
     AND OLD.fige_le IS NOT NULL THEN

    -- Audit: DEGEL_APPLIED (save old snapshot before NULLification)
    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'SYSTEME', 'DEGEL_APPLIED', 'mission', OLD.id,
      jsonb_build_object(
        'old_snapshot', jsonb_build_object(
          'taux_horaire_base_fige', OLD.taux_horaire_base_fige,
          'taux_majoration_nuit_fige', OLD.taux_majoration_nuit_fige,
          'taux_majoration_dimanche_fige', OLD.taux_majoration_dimanche_fige,
          'taux_majoration_ferie_fige', OLD.taux_majoration_ferie_fige,
          'heure_debut_nuit_fige', OLD.heure_debut_nuit_fige,
          'heure_fin_nuit_fige', OLD.heure_fin_nuit_fige,
          'taux_commission_fige', OLD.taux_commission_fige,
          'fige_le', OLD.fige_le
        ),
        'old_statut', OLD.statut,
        'new_statut', 'OUVERTE',
        'nb_scans_before_degel', OLD.nb_scans
      )
    );

    -- Cleanup EFFECTIF créneaux + scans (CASCADE)
    PERFORM set_config('jolene.sync_in_progress', 'true', true);
    DELETE FROM mission_creneaux WHERE mission_id = OLD.id AND type_creneau = 'EFFECTIF';
    PERFORM set_config('jolene.sync_in_progress', 'false', true);

    -- NULL _fige
    NEW.taux_horaire_base_fige        := NULL;
    NEW.taux_majoration_nuit_fige     := NULL;
    NEW.taux_majoration_dimanche_fige := NULL;
    NEW.taux_majoration_ferie_fige    := NULL;
    NEW.heure_debut_nuit_fige         := NULL;
    NEW.heure_fin_nuit_fige           := NULL;
    NEW.taux_commission_fige          := NULL;
    NEW.fige_le                       := NULL;

    -- NULL pointage
    NEW.code_pointage_actif           := NULL;
    NEW.code_pointage_hmac            := NULL;
    NEW.prochain_type_scan            := NULL;
    NEW.nb_scans                      := 0;

    -- NULL effectives
    NEW.debut_effectif                := NULL;
    NEW.fin_effective                 := NULL;
    NEW.duree_heures_effective        := NULL;

    RETURN NEW;
  END IF;

  -- ════════════════════════════════════════════════════
  -- BLOC 3 : PROTECTION — champs bloqués après gel
  -- ════════════════════════════════════════════════════
  IF OLD.fige_le IS NOT NULL THEN

    IF current_setting('jolene.admin_override_gel', true) = OLD.id::text
       AND COALESCE(current_setting('jolene.admin_override_reason', true), '') != '' THEN

      DECLARE
        v_fields_modified jsonb := '{}'::jsonb;
        v_override_reason text := current_setting('jolene.admin_override_reason', true);
      BEGIN
        IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('taux_horaire_base', jsonb_build_object('old', OLD.taux_horaire_base, 'new', NEW.taux_horaire_base));
        END IF;
        IF NEW.intitule IS DISTINCT FROM OLD.intitule THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('intitule', jsonb_build_object('old', OLD.intitule, 'new', NEW.intitule));
        END IF;
        IF NEW.profession_requise IS DISTINCT FROM OLD.profession_requise THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('profession_requise', jsonb_build_object('old', OLD.profession_requise, 'new', NEW.profession_requise));
        END IF;
        IF NEW.taux_horaire_base_fige IS DISTINCT FROM OLD.taux_horaire_base_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('taux_horaire_base_fige', jsonb_build_object('old', OLD.taux_horaire_base_fige, 'new', NEW.taux_horaire_base_fige));
        END IF;
        IF NEW.taux_majoration_nuit_fige IS DISTINCT FROM OLD.taux_majoration_nuit_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('taux_majoration_nuit_fige', jsonb_build_object('old', OLD.taux_majoration_nuit_fige, 'new', NEW.taux_majoration_nuit_fige));
        END IF;
        IF NEW.taux_majoration_dimanche_fige IS DISTINCT FROM OLD.taux_majoration_dimanche_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('taux_majoration_dimanche_fige', jsonb_build_object('old', OLD.taux_majoration_dimanche_fige, 'new', NEW.taux_majoration_dimanche_fige));
        END IF;
        IF NEW.taux_majoration_ferie_fige IS DISTINCT FROM OLD.taux_majoration_ferie_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('taux_majoration_ferie_fige', jsonb_build_object('old', OLD.taux_majoration_ferie_fige, 'new', NEW.taux_majoration_ferie_fige));
        END IF;
        IF NEW.heure_debut_nuit_fige IS DISTINCT FROM OLD.heure_debut_nuit_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('heure_debut_nuit_fige', jsonb_build_object('old', OLD.heure_debut_nuit_fige, 'new', NEW.heure_debut_nuit_fige));
        END IF;
        IF NEW.heure_fin_nuit_fige IS DISTINCT FROM OLD.heure_fin_nuit_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('heure_fin_nuit_fige', jsonb_build_object('old', OLD.heure_fin_nuit_fige, 'new', NEW.heure_fin_nuit_fige));
        END IF;
        IF NEW.taux_commission_fige IS DISTINCT FROM OLD.taux_commission_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('taux_commission_fige', jsonb_build_object('old', OLD.taux_commission_fige, 'new', NEW.taux_commission_fige));
        END IF;
        IF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN
          v_fields_modified := v_fields_modified || jsonb_build_object('fige_le', jsonb_build_object('old', OLD.fige_le, 'new', NEW.fige_le));
        END IF;

        IF v_fields_modified != '{}'::jsonb THEN
          INSERT INTO journaux_audit
            (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
          VALUES (auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_CHAMP_POST_GEL', 'mission', OLD.id,
            jsonb_build_object('reason', v_override_reason, 'fields_modified', v_fields_modified));
        END IF;
      END;
      RETURN NEW;

    ELSE
      -- NOTE : seul le premier champ modifié est signalé. Acceptable V1.
      IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base THEN v_champ_modifie := 'taux_horaire_base';
      ELSIF NEW.intitule IS DISTINCT FROM OLD.intitule THEN v_champ_modifie := 'intitule';
      ELSIF NEW.profession_requise IS DISTINCT FROM OLD.profession_requise THEN v_champ_modifie := 'profession_requise';
      ELSIF NEW.taux_horaire_base_fige IS DISTINCT FROM OLD.taux_horaire_base_fige THEN v_champ_modifie := 'taux_horaire_base_fige';
      ELSIF NEW.taux_majoration_nuit_fige IS DISTINCT FROM OLD.taux_majoration_nuit_fige THEN v_champ_modifie := 'taux_majoration_nuit_fige';
      ELSIF NEW.taux_majoration_dimanche_fige IS DISTINCT FROM OLD.taux_majoration_dimanche_fige THEN v_champ_modifie := 'taux_majoration_dimanche_fige';
      ELSIF NEW.taux_majoration_ferie_fige IS DISTINCT FROM OLD.taux_majoration_ferie_fige THEN v_champ_modifie := 'taux_majoration_ferie_fige';
      ELSIF NEW.heure_debut_nuit_fige IS DISTINCT FROM OLD.heure_debut_nuit_fige THEN v_champ_modifie := 'heure_debut_nuit_fige';
      ELSIF NEW.heure_fin_nuit_fige IS DISTINCT FROM OLD.heure_fin_nuit_fige THEN v_champ_modifie := 'heure_fin_nuit_fige';
      ELSIF NEW.taux_commission_fige IS DISTINCT FROM OLD.taux_commission_fige THEN v_champ_modifie := 'taux_commission_fige';
      ELSIF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN v_champ_modifie := 'fige_le';
      END IF;

      IF v_champ_modifie IS NOT NULL THEN
        RAISE EXCEPTION 'Modification du champ "%" interdite après assignation (gel du %). Pour corriger une coquille, contactez le support Jolene pour un override admin tracé. Pour modifier le contenu substantiel, annuler la mission et en créer une nouvelle.',
          v_champ_modifie, OLD.fige_le USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 3c. fn_scanner_code_pointage
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage(
  p_code text,
  p_metadata jsonb DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission RECORD;
  v_now timestamptz := now();
  v_arrondi timestamptz;
  v_dernier_scan timestamptz;
  v_premier_prevu timestamptz;
  v_dernier_prevu timestamptz;
  v_est_en_avance boolean := false;
  v_validation_requise boolean := false;
  v_creneau_id uuid;
  v_new_code text;
  v_new_hmac text;
  v_scan_numero smallint;
BEGIN
  -- Step 1: Find mission by active code (FOR UPDATE = anti-race R1)
  SELECT id, soignant_assigne_id, code_pointage_actif, prochain_type_scan, nb_scans, statut
  INTO v_mission
  FROM missions
  WHERE code_pointage_actif = p_code AND statut IN ('ASSIGNEE', 'EN_COURS')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Code de pointage invalide ou expiré.'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Step 2: Check caller is assigned soignant
  IF auth.uid() != v_mission.soignant_assigne_id THEN
    RAISE EXCEPTION 'Vous n''êtes pas assigné(e) à cette mission.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Step 3: Anti-doublon < 2 min
  SELECT scanne_le INTO v_dernier_scan
  FROM scans_pointage
  WHERE mission_id = v_mission.id
  ORDER BY numero_scan DESC LIMIT 1;

  IF v_dernier_scan IS NOT NULL AND v_now - v_dernier_scan < INTERVAL '2 minutes' THEN
    RAISE EXCEPTION 'Scan déjà pris en compte. Prochain scan possible dans % secondes.',
      CEIL(EXTRACT(EPOCH FROM (v_dernier_scan + INTERVAL '2 minutes' - v_now)))
      USING ERRCODE = 'check_violation';
  END IF;

  -- Step 4: Compute scan number + arrondi
  v_scan_numero := COALESCE(v_mission.nb_scans, 0) + 1;
  v_arrondi := fn_arrondir_quart_heure(v_now);

  -- Step 5/6: OUVERTURE or FERMETURE
  IF v_mission.prochain_type_scan = 'OUVERTURE' THEN
    -- Step 5a: Check time window (-15 min)
    SELECT MIN(debut) INTO v_premier_prevu
    FROM mission_creneaux
    WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';

    IF v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'Pointage trop tôt. Mission commence à %. Possible à partir de %.',
        TO_CHAR(v_premier_prevu AT TIME ZONE 'Europe/Paris', 'HH24:MI'),
        TO_CHAR((v_premier_prevu - INTERVAL '15 minutes') AT TIME ZONE 'Europe/Paris', 'HH24:MI')
        USING ERRCODE = 'check_violation';
    END IF;

    v_est_en_avance := (v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu);

    SELECT MAX(fin) INTO v_dernier_prevu
    FROM mission_creneaux
    WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';

    v_validation_requise := v_est_en_avance
      OR (v_dernier_prevu IS NOT NULL AND v_now > v_dernier_prevu + INTERVAL '24 hours');

    -- Step 5c: INSERT EFFECTIF créneau (open, fin NULL)
    INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre, type_creneau)
    VALUES (v_mission.id, v_arrondi, NULL, false,
      COALESCE((SELECT MAX(ordre) + 1 FROM mission_creneaux WHERE mission_id = v_mission.id), 1),
      'EFFECTIF')
    RETURNING id INTO v_creneau_id;

    -- Step 5d: INSERT scan
    INSERT INTO scans_pointage (
      mission_id, soignant_id, code_saisi, numero_scan, type_scan,
      scanne_le, horodatage_arrondi, creneau_effectif_id,
      est_en_avance, validation_etab_requise,
      latitude, longitude, precision_gps_m, id_terminal, ip_address
    ) VALUES (
      v_mission.id, auth.uid(), p_code, v_scan_numero, 'OUVERTURE',
      v_now, v_arrondi, v_creneau_id,
      v_est_en_avance, v_validation_requise,
      (p_metadata->>'latitude')::numeric,
      (p_metadata->>'longitude')::numeric,
      (p_metadata->>'precision_gps_m')::numeric,
      p_metadata->>'id_terminal',
      (p_metadata->>'ip_address')::inet
    );

  ELSE -- FERMETURE
    -- Step 6b: Find open EFFECTIF créneau
    DECLARE v_creneau_debut timestamptz;
    BEGIN
    SELECT id, debut INTO v_creneau_id, v_creneau_debut
    FROM mission_creneaux
    WHERE mission_id = v_mission.id AND type_creneau = 'EFFECTIF' AND fin IS NULL
    ORDER BY debut DESC LIMIT 1;

    IF v_creneau_id IS NULL THEN
      RAISE EXCEPTION 'Aucun créneau effectif ouvert à fermer.'
        USING ERRCODE = 'no_data_found';
    END IF;

    -- Minimum 15-min slot: if arrondi <= debut, push to debut + 15min
    IF v_arrondi <= v_creneau_debut THEN
      v_arrondi := v_creneau_debut + INTERVAL '15 minutes';
    END IF;

    -- Step 6b: Close it
    UPDATE mission_creneaux SET fin = v_arrondi WHERE id = v_creneau_id;
    END;

    -- Validation check
    SELECT MAX(fin) INTO v_dernier_prevu
    FROM mission_creneaux
    WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';

    v_validation_requise := (v_dernier_prevu IS NOT NULL AND v_now > v_dernier_prevu + INTERVAL '24 hours');

    -- Step 6c: INSERT scan
    INSERT INTO scans_pointage (
      mission_id, soignant_id, code_saisi, numero_scan, type_scan,
      scanne_le, horodatage_arrondi, creneau_effectif_id,
      est_en_avance, validation_etab_requise,
      latitude, longitude, precision_gps_m, id_terminal, ip_address
    ) VALUES (
      v_mission.id, auth.uid(), p_code, v_scan_numero, 'FERMETURE',
      v_now, v_arrondi, v_creneau_id,
      false, v_validation_requise,
      (p_metadata->>'latitude')::numeric,
      (p_metadata->>'longitude')::numeric,
      (p_metadata->>'precision_gps_m')::numeric,
      p_metadata->>'id_terminal',
      (p_metadata->>'ip_address')::inet
    );
  END IF;

  -- Step 7: Regenerate code
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
    prochain_type_scan = CASE WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE' ELSE 'OUVERTURE' END,
    nb_scans = v_scan_numero
  WHERE id = v_mission.id;

  -- Step 8: Return
  RETURN jsonb_build_object(
    'nouveau_code', v_new_code,
    'nouveau_hmac', v_new_hmac,
    'type_scan_effectue', v_mission.prochain_type_scan,
    'prochain_type_scan', CASE WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE' ELSE 'OUVERTURE' END,
    'creneau_effectif_id', v_creneau_id,
    'horodatage_arrondi', v_arrondi,
    'numero_scan', v_scan_numero,
    'validation_etab_requise', v_validation_requise
  );
END;
$$;
