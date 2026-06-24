-- Fix légal : rétablit le gate « contrat signé avant pointage » sur le système
-- rotatif fn_scanner_code_pointage.
--
-- Régression introduite par la migration du pointage vers le système rotatif :
-- l'ancien fn_pointer_arrivee BLOQUAIT le pointage tant qu'aucun contrat
-- SIGNE_COMPLET n'existait (obligation légale — un CDD/contrat doit être signé
-- AVANT la 1ʳᵉ heure travaillée). fn_scanner_code_pointage avait perdu ce contrôle.
--
-- On le rétablit sur l'OUVERTURE (arrivée / reprise) : impossible d'ouvrir un
-- segment de travail sans contrat signé. La FERMETURE n'est pas regatée (on ne
-- peut pas avoir ouvert sans contrat). Le reste de la fonction est inchangé.

CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage(p_code text, p_metadata jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD; v_now timestamptz := now(); v_arrondi timestamptz;
  v_dernier_scan timestamptz; v_premier_prevu timestamptz; v_dernier_prevu timestamptz;
  v_est_en_avance boolean := false; v_validation_requise boolean := false;
  v_creneau_id uuid; v_creneau_debut timestamptz;
  v_new_code text; v_new_hmac text; v_scan_numero smallint;
BEGIN
  SELECT id, soignant_assigne_id, code_pointage_actif, prochain_type_scan, nb_scans, statut
  INTO v_mission FROM missions WHERE code_pointage_actif = p_code AND statut IN ('ASSIGNEE','EN_COURS') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Code de pointage invalide ou expiré.' USING ERRCODE = 'no_data_found'; END IF;
  IF auth.uid() != v_mission.soignant_assigne_id THEN RAISE EXCEPTION 'Vous n''êtes pas assigné(e) à cette mission.' USING ERRCODE = 'insufficient_privilege'; END IF;

  SELECT scanne_le INTO v_dernier_scan FROM scans_pointage WHERE mission_id = v_mission.id ORDER BY numero_scan DESC LIMIT 1;
  IF v_dernier_scan IS NOT NULL AND v_now - v_dernier_scan < INTERVAL '2 minutes' THEN
    RAISE EXCEPTION 'Scan déjà pris en compte. Prochain scan possible dans % secondes.',
      CEIL(EXTRACT(EPOCH FROM (v_dernier_scan + INTERVAL '2 minutes' - v_now))) USING ERRCODE = 'check_violation';
  END IF;

  v_scan_numero := COALESCE(v_mission.nb_scans, 0) + 1;
  v_arrondi := fn_arrondir_quart_heure(v_now);

  IF v_mission.prochain_type_scan = 'OUVERTURE' THEN
    -- GATE LÉGAL : aucun pointage d'arrivée/reprise sans contrat signé complet.
    IF NOT EXISTS (SELECT 1 FROM contrats_mission WHERE mission_id = v_mission.id AND statut = 'SIGNE_COMPLET') THEN
      RAISE EXCEPTION 'Le contrat doit être signé avant le pointage.' USING ERRCODE = 'check_violation';
    END IF;

    SELECT MIN(debut) INTO v_premier_prevu FROM mission_creneaux WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';
    IF v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'Pointage trop tôt. Mission commence à %. Possible à partir de %.',
        TO_CHAR(v_premier_prevu AT TIME ZONE 'Europe/Paris', 'HH24:MI'),
        TO_CHAR((v_premier_prevu - INTERVAL '15 minutes') AT TIME ZONE 'Europe/Paris', 'HH24:MI') USING ERRCODE = 'check_violation';
    END IF;
    v_est_en_avance := (v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu);
    SELECT MAX(fin) INTO v_dernier_prevu FROM mission_creneaux WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';
    v_validation_requise := v_est_en_avance OR (v_dernier_prevu IS NOT NULL AND v_now > v_dernier_prevu + INTERVAL '24 hours');

    INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre, type_creneau)
    VALUES (v_mission.id, v_arrondi, NULL, false,
      COALESCE((SELECT MAX(ordre)+1 FROM mission_creneaux WHERE mission_id = v_mission.id), 1), 'EFFECTIF')
    RETURNING id INTO v_creneau_id;

    INSERT INTO scans_pointage (mission_id, soignant_id, code_saisi, numero_scan, type_scan, scanne_le, horodatage_arrondi, creneau_effectif_id, est_en_avance, validation_etab_requise, latitude, longitude, precision_gps_m, id_terminal, ip_address)
    VALUES (v_mission.id, auth.uid(), p_code, v_scan_numero, 'OUVERTURE', v_now, v_arrondi, v_creneau_id, v_est_en_avance, v_validation_requise,
      (p_metadata->>'latitude')::numeric, (p_metadata->>'longitude')::numeric, (p_metadata->>'precision_gps_m')::numeric, p_metadata->>'id_terminal', (p_metadata->>'ip_address')::inet);

    -- PONT : créer le résumé presences (arrivée) au 1ʳᵉ pointage + passer EN_COURS.
    -- Si la présence existe déjà (reprise après pause), on annule le départ
    -- provisoire posé par la fermeture précédente (le soignant repart en service).
    IF NOT EXISTS (SELECT 1 FROM presences WHERE mission_id = v_mission.id AND soignant_id = auth.uid()) THEN
      INSERT INTO presences (mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m, arrivee_id_terminal, methode_pointage_arrivee)
      VALUES (v_mission.id, auth.uid(), v_arrondi,
        (p_metadata->>'latitude')::numeric, (p_metadata->>'longitude')::numeric,
        (p_metadata->>'precision_gps_m')::numeric, p_metadata->>'id_terminal', 'CODE');
      UPDATE missions SET statut = 'EN_COURS', modifie_le = now()
        WHERE id = v_mission.id AND statut = 'ASSIGNEE';
    ELSE
      UPDATE presences SET pointage_depart_le = NULL, modifie_le = now()
        WHERE mission_id = v_mission.id AND soignant_id = auth.uid();
    END IF;

  ELSE -- FERMETURE
    SELECT id, debut INTO v_creneau_id, v_creneau_debut FROM mission_creneaux
    WHERE mission_id = v_mission.id AND type_creneau = 'EFFECTIF' AND fin IS NULL ORDER BY debut DESC LIMIT 1;
    IF v_creneau_id IS NULL THEN RAISE EXCEPTION 'Aucun créneau effectif ouvert à fermer.' USING ERRCODE = 'no_data_found'; END IF;

    -- Minimum 15-min slot: if arrondi <= debut, push to debut + 15min
    IF v_arrondi <= v_creneau_debut THEN
      v_arrondi := v_creneau_debut + INTERVAL '15 minutes';
    END IF;

    UPDATE mission_creneaux SET fin = v_arrondi WHERE id = v_creneau_id;

    SELECT MAX(fin) INTO v_dernier_prevu FROM mission_creneaux WHERE mission_id = v_mission.id AND type_creneau = 'PREVISIONNEL';
    v_validation_requise := (v_dernier_prevu IS NOT NULL AND v_now > v_dernier_prevu + INTERVAL '24 hours');

    INSERT INTO scans_pointage (mission_id, soignant_id, code_saisi, numero_scan, type_scan, scanne_le, horodatage_arrondi, creneau_effectif_id, est_en_avance, validation_etab_requise, latitude, longitude, precision_gps_m, id_terminal, ip_address)
    VALUES (v_mission.id, auth.uid(), p_code, v_scan_numero, 'FERMETURE', v_now, v_arrondi, v_creneau_id, false, v_validation_requise,
      (p_metadata->>'latitude')::numeric, (p_metadata->>'longitude')::numeric, (p_metadata->>'precision_gps_m')::numeric, p_metadata->>'id_terminal', (p_metadata->>'ip_address')::inet);

    -- PONT : mettre à jour le résumé presences (départ = dernière fermeture,
    -- heures_reelles = somme des segments EFFECTIF travaillés, hors pauses).
    UPDATE presences SET
      pointage_depart_le = v_arrondi,
      depart_lat = (p_metadata->>'latitude')::numeric,
      depart_lng = (p_metadata->>'longitude')::numeric,
      methode_pointage_depart = 'CODE',
      heures_reelles = (
        SELECT COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)::numeric, 2), 0)
        FROM mission_creneaux
        WHERE mission_id = v_mission.id AND type_creneau = 'EFFECTIF'
          AND fin IS NOT NULL AND NOT est_pause
      ),
      modifie_le = now()
    WHERE mission_id = v_mission.id AND soignant_id = auth.uid();
  END IF;

  v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  WHILE EXISTS (SELECT 1 FROM missions WHERE code_pointage_actif = v_new_code AND id != v_mission.id AND statut IN ('ASSIGNEE','EN_COURS')) LOOP
    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  END LOOP;
  v_new_hmac := CASE WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL
    THEN encode(extensions.hmac(v_mission.id::text || ':' || v_new_code, current_setting('app.settings.hmac_secret', true), 'sha256'), 'hex') ELSE NULL END;

  UPDATE missions SET code_pointage_actif = v_new_code, code_pointage_hmac = v_new_hmac,
    prochain_type_scan = CASE WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE' ELSE 'OUVERTURE' END,
    nb_scans = v_scan_numero WHERE id = v_mission.id;

  RETURN jsonb_build_object('nouveau_code', v_new_code, 'nouveau_hmac', v_new_hmac,
    'type_scan_effectue', v_mission.prochain_type_scan,
    'prochain_type_scan', CASE WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE' ELSE 'OUVERTURE' END,
    'creneau_effectif_id', v_creneau_id, 'horodatage_arrondi', v_arrondi,
    'numero_scan', v_scan_numero, 'validation_etab_requise', v_validation_requise);
END;
$function$;
