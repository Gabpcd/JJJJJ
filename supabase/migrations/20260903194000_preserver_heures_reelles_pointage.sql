-- Les heures de présence et de paie doivent rester les heures réellement
-- pointées. L'arrondi au quart d'heure est conservé uniquement comme donnée
-- d'audit dans scans_pointage.horodatage_arrondi : il ne doit jamais déplacer
-- un début ou une fin EFFECTIF dans le futur, ni fabriquer 15 minutes.

CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage(
  p_code text,
  p_metadata jsonb DEFAULT NULL::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_now timestamptz := now();
  v_arrondi_audit timestamptz;
  v_dernier_scan timestamptz;
  v_premier_prevu timestamptz;
  v_dernier_prevu timestamptz;
  v_est_en_avance boolean := false;
  v_validation_requise boolean := false;
  v_creneau_id uuid;
  v_creneau_debut timestamptz;
  v_new_code text;
  v_new_hmac text;
  v_scan_numero smallint;
BEGIN
  SELECT id, soignant_assigne_id, code_pointage_actif, prochain_type_scan, nb_scans, statut
  INTO v_mission
  FROM missions
  WHERE code_pointage_actif = p_code
    AND statut IN ('ASSIGNEE', 'EN_COURS')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Code de pointage invalide ou expiré.' USING ERRCODE = 'no_data_found';
  END IF;
  IF auth.uid() != v_mission.soignant_assigne_id THEN
    RAISE EXCEPTION 'Vous n''êtes pas assigné(e) à cette mission.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT scanne_le INTO v_dernier_scan
  FROM scans_pointage
  WHERE mission_id = v_mission.id
  ORDER BY numero_scan DESC
  LIMIT 1;

  IF v_dernier_scan IS NOT NULL AND v_now - v_dernier_scan < INTERVAL '2 minutes' THEN
    RAISE EXCEPTION 'Scan déjà pris en compte. Prochain scan possible dans % secondes.',
      CEIL(EXTRACT(EPOCH FROM (v_dernier_scan + INTERVAL '2 minutes' - v_now)))
      USING ERRCODE = 'check_violation';
  END IF;

  v_scan_numero := COALESCE(v_mission.nb_scans, 0) + 1;
  v_arrondi_audit := fn_arrondir_quart_heure(v_now);

  IF v_mission.prochain_type_scan = 'OUVERTURE' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM contrats_mission
      WHERE mission_id = v_mission.id
        AND statut = 'SIGNE_COMPLET'
    ) THEN
      RAISE EXCEPTION 'Le contrat doit être signé avant le pointage.' USING ERRCODE = 'check_violation';
    END IF;

    SELECT MIN(debut) INTO v_premier_prevu
    FROM mission_creneaux
    WHERE mission_id = v_mission.id
      AND type_creneau = 'PREVISIONNEL';

    IF v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'Pointage trop tôt. Mission commence à %. Possible à partir de %.',
        TO_CHAR(v_premier_prevu AT TIME ZONE 'Europe/Paris', 'HH24:MI'),
        TO_CHAR((v_premier_prevu - INTERVAL '15 minutes') AT TIME ZONE 'Europe/Paris', 'HH24:MI')
        USING ERRCODE = 'check_violation';
    END IF;

    v_est_en_avance := v_premier_prevu IS NOT NULL AND v_now < v_premier_prevu;

    SELECT MAX(fin) INTO v_dernier_prevu
    FROM mission_creneaux
    WHERE mission_id = v_mission.id
      AND type_creneau = 'PREVISIONNEL';

    v_validation_requise := v_est_en_avance
      OR (v_dernier_prevu IS NOT NULL AND v_now > v_dernier_prevu + INTERVAL '24 hours');

    INSERT INTO mission_creneaux (
      mission_id, debut, fin, est_pause, ordre, type_creneau
    ) VALUES (
      v_mission.id,
      v_now,
      NULL,
      false,
      COALESCE((
        SELECT MAX(ordre) + 1
        FROM mission_creneaux
        WHERE mission_id = v_mission.id
      ), 1),
      'EFFECTIF'
    )
    RETURNING id INTO v_creneau_id;

    INSERT INTO scans_pointage (
      mission_id, soignant_id, code_saisi, numero_scan, type_scan,
      scanne_le, horodatage_arrondi, creneau_effectif_id,
      est_en_avance, validation_etab_requise,
      latitude, longitude, precision_gps_m, id_terminal, ip_address
    ) VALUES (
      v_mission.id, auth.uid(), p_code, v_scan_numero, 'OUVERTURE',
      v_now, v_arrondi_audit, v_creneau_id,
      v_est_en_avance, v_validation_requise,
      (p_metadata->>'latitude')::numeric,
      (p_metadata->>'longitude')::numeric,
      (p_metadata->>'precision_gps_m')::numeric,
      p_metadata->>'id_terminal',
      (p_metadata->>'ip_address')::inet
    );

    IF NOT EXISTS (
      SELECT 1
      FROM presences
      WHERE mission_id = v_mission.id
        AND soignant_id = auth.uid()
    ) THEN
      INSERT INTO presences (
        mission_id, soignant_id, pointage_arrivee_le,
        arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
        arrivee_id_terminal, methode_pointage_arrivee
      ) VALUES (
        v_mission.id, auth.uid(), v_now,
        (p_metadata->>'latitude')::numeric,
        (p_metadata->>'longitude')::numeric,
        (p_metadata->>'precision_gps_m')::numeric,
        p_metadata->>'id_terminal',
        'CODE'
      );

      UPDATE missions
      SET statut = 'EN_COURS', modifie_le = now()
      WHERE id = v_mission.id
        AND statut = 'ASSIGNEE';
    ELSE
      UPDATE presences
      SET pointage_depart_le = NULL,
          modifie_le = now()
      WHERE mission_id = v_mission.id
        AND soignant_id = auth.uid();
    END IF;

  ELSE
    SELECT id, debut INTO v_creneau_id, v_creneau_debut
    FROM mission_creneaux
    WHERE mission_id = v_mission.id
      AND type_creneau = 'EFFECTIF'
      AND fin IS NULL
    ORDER BY debut DESC
    LIMIT 1;

    IF v_creneau_id IS NULL THEN
      RAISE EXCEPTION 'Aucun créneau effectif ouvert à fermer.' USING ERRCODE = 'no_data_found';
    END IF;
    IF v_now <= v_creneau_debut THEN
      RAISE EXCEPTION 'La fin réelle doit être postérieure au début réel du créneau.' USING ERRCODE = 'check_violation';
    END IF;

    UPDATE mission_creneaux
    SET fin = v_now
    WHERE id = v_creneau_id;

    SELECT MAX(fin) INTO v_dernier_prevu
    FROM mission_creneaux
    WHERE mission_id = v_mission.id
      AND type_creneau = 'PREVISIONNEL';

    v_validation_requise := v_dernier_prevu IS NOT NULL
      AND v_now > v_dernier_prevu + INTERVAL '24 hours';

    INSERT INTO scans_pointage (
      mission_id, soignant_id, code_saisi, numero_scan, type_scan,
      scanne_le, horodatage_arrondi, creneau_effectif_id,
      est_en_avance, validation_etab_requise,
      latitude, longitude, precision_gps_m, id_terminal, ip_address
    ) VALUES (
      v_mission.id, auth.uid(), p_code, v_scan_numero, 'FERMETURE',
      v_now, v_arrondi_audit, v_creneau_id,
      false, v_validation_requise,
      (p_metadata->>'latitude')::numeric,
      (p_metadata->>'longitude')::numeric,
      (p_metadata->>'precision_gps_m')::numeric,
      p_metadata->>'id_terminal',
      (p_metadata->>'ip_address')::inet
    );

    UPDATE presences
    SET pointage_depart_le = v_now,
        depart_lat = (p_metadata->>'latitude')::numeric,
        depart_lng = (p_metadata->>'longitude')::numeric,
        methode_pointage_depart = 'CODE',
        heures_reelles = (
          SELECT COALESCE(
            ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)::numeric, 2),
            0
          )
          FROM mission_creneaux
          WHERE mission_id = v_mission.id
            AND type_creneau = 'EFFECTIF'
            AND fin IS NOT NULL
            AND NOT est_pause
        ),
        modifie_le = now()
    WHERE mission_id = v_mission.id
      AND soignant_id = auth.uid();
  END IF;

  v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  WHILE EXISTS (
    SELECT 1
    FROM missions
    WHERE code_pointage_actif = v_new_code
      AND id != v_mission.id
      AND statut IN ('ASSIGNEE', 'EN_COURS')
  ) LOOP
    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  END LOOP;

  v_new_hmac := CASE
    WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL THEN
      encode(
        extensions.hmac(
          v_mission.id::text || ':' || v_new_code,
          current_setting('app.settings.hmac_secret', true),
          'sha256'
        ),
        'hex'
      )
    ELSE NULL
  END;

  UPDATE missions
  SET code_pointage_actif = v_new_code,
      code_pointage_hmac = v_new_hmac,
      prochain_type_scan = CASE
        WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE'
        ELSE 'OUVERTURE'
      END,
      nb_scans = v_scan_numero
  WHERE id = v_mission.id;

  RETURN jsonb_build_object(
    'nouveau_code', v_new_code,
    'nouveau_hmac', v_new_hmac,
    'type_scan_effectue', v_mission.prochain_type_scan,
    'prochain_type_scan', CASE
      WHEN v_mission.prochain_type_scan = 'OUVERTURE' THEN 'FERMETURE'
      ELSE 'OUVERTURE'
    END,
    'creneau_effectif_id', v_creneau_id,
    'horodatage_effectif', v_now,
    'horodatage_arrondi', v_arrondi_audit,
    'numero_scan', v_scan_numero,
    'validation_etab_requise', v_validation_requise
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_declarer_fin_retroactive(
  p_mission_id uuid,
  p_heure_fin timestamptz,
  p_raison text DEFAULT 'Oubli de scan'::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_creneau_id uuid;
  v_creneau_debut timestamptz;
  v_arrondi_audit timestamptz;
  v_scan_numero smallint;
  v_new_code text;
  v_new_hmac text;
  v_caller_is_soignant boolean;
  v_caller_is_etab_admin boolean;
BEGIN
  SELECT id, soignant_assigne_id, etablissement_id, nb_scans, statut
  INTO v_mission
  FROM missions
  WHERE id = p_mission_id
    AND statut IN ('ASSIGNEE', 'EN_COURS')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable ou dans un statut incompatible.', p_mission_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_caller_is_soignant := auth.uid() = v_mission.soignant_assigne_id;
  v_caller_is_etab_admin := est_admin_etablissement()
    AND mon_etablissement_id() = v_mission.etablissement_id;

  IF NOT (v_caller_is_soignant OR v_caller_is_etab_admin OR est_admin()) THEN
    RAISE EXCEPTION 'Vous n''êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT id, debut INTO v_creneau_id, v_creneau_debut
  FROM mission_creneaux
  WHERE mission_id = v_mission.id
    AND type_creneau = 'EFFECTIF'
    AND fin IS NULL
  ORDER BY debut DESC
  LIMIT 1;

  IF v_creneau_id IS NULL THEN
    RAISE EXCEPTION 'Aucun créneau effectif ouvert à fermer pour cette mission.'
      USING ERRCODE = 'no_data_found';
  END IF;
  IF p_heure_fin <= v_creneau_debut THEN
    RAISE EXCEPTION 'L''heure de fin (%) doit être postérieure au début du créneau (%).',
      p_heure_fin, v_creneau_debut USING ERRCODE = 'check_violation';
  END IF;

  v_arrondi_audit := fn_arrondir_quart_heure(p_heure_fin);

  UPDATE mission_creneaux
  SET fin = p_heure_fin
  WHERE id = v_creneau_id;

  v_scan_numero := COALESCE(v_mission.nb_scans, 0) + 1;
  INSERT INTO scans_pointage (
    mission_id, soignant_id, code_saisi, numero_scan, type_scan,
    scanne_le, horodatage_arrondi, creneau_effectif_id,
    est_en_avance, validation_etab_requise
  ) VALUES (
    v_mission.id, v_mission.soignant_assigne_id, 'RETROACTIF', v_scan_numero, 'FERMETURE',
    now(), v_arrondi_audit, v_creneau_id,
    false, true
  );

  UPDATE presences
  SET pointage_depart_le = p_heure_fin,
      heures_reelles = (
        SELECT COALESCE(
          ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)::numeric, 2),
          0
        )
        FROM mission_creneaux
        WHERE mission_id = v_mission.id
          AND type_creneau = 'EFFECTIF'
          AND fin IS NOT NULL
          AND NOT est_pause
      ),
      modifie_le = now()
  WHERE mission_id = v_mission.id
    AND soignant_id = v_mission.soignant_assigne_id;

  v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  WHILE EXISTS (
    SELECT 1
    FROM missions
    WHERE code_pointage_actif = v_new_code
      AND id != v_mission.id
      AND statut IN ('ASSIGNEE', 'EN_COURS')
  ) LOOP
    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  END LOOP;

  v_new_hmac := CASE
    WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL THEN
      encode(
        extensions.hmac(
          v_mission.id::text || ':' || v_new_code,
          current_setting('app.settings.hmac_secret', true),
          'sha256'
        ),
        'hex'
      )
    ELSE NULL
  END;

  UPDATE missions
  SET code_pointage_actif = v_new_code,
      code_pointage_hmac = v_new_hmac,
      prochain_type_scan = 'OUVERTURE',
      nb_scans = v_scan_numero
  WHERE id = v_mission.id;

  INSERT INTO journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    auth.uid(),
    CASE
      WHEN v_caller_is_soignant THEN 'SOIGNANT'
      WHEN v_caller_is_etab_admin THEN 'ADMIN_ETABLISSEMENT'
      ELSE 'ADMIN_PLATEFORME'
    END,
    'POINTAGE',
    'mission',
    v_mission.id,
    jsonb_build_object(
      'sous_action', 'FIN_RETROACTIVE',
      'raison', p_raison,
      'creneau_effectif_id', v_creneau_id,
      'debut_creneau', v_creneau_debut,
      'heure_fin_declaree', p_heure_fin,
      'horodatage_arrondi_audit', v_arrondi_audit,
      'validation_etab_requise', true
    )
  );

  RETURN jsonb_build_object(
    'creneau_effectif_id', v_creneau_id,
    'debut_creneau', v_creneau_debut,
    'fin_declaree', p_heure_fin,
    'horodatage_arrondi', v_arrondi_audit,
    'validation_etab_requise', true,
    'nouveau_code', v_new_code,
    'nouveau_hmac', v_new_hmac,
    'prochain_type_scan', 'OUVERTURE',
    'numero_scan', v_scan_numero
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_scanner_code_pointage(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_scanner_code_pointage(text, jsonb) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.fn_declarer_fin_retroactive(uuid, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_declarer_fin_retroactive(uuid, timestamptz, text) TO authenticated, service_role;

WITH reviewed(signature, qualified_signature, categorie, justification) AS (
  VALUES
    (
      'fn_scanner_code_pointage(text,jsonb)',
      'public.fn_scanner_code_pointage(text,jsonb)',
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'RPC soignant authentifié : conserve l heure réellement scannée comme source de présence et de paie; l arrondi reste une trace d audit distincte.'
    ),
    (
      'fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)',
      'public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)',
      'MIXTE_TENANT_ADMIN',
      'RPC mixte tenant/admin : clôture à l heure réellement déclarée, synchronise la présence et trace séparément l arrondi d audit.'
    )
)
INSERT INTO private.security_definer_inventory (
  signature, categorie, definition_md5, justification, recense_le
)
SELECT
  r.signature,
  r.categorie,
  pg_catalog.md5(p.prosrc),
  r.justification,
  pg_catalog.now()
FROM reviewed r
JOIN pg_catalog.pg_proc p
  ON p.oid = pg_catalog.to_regprocedure(r.qualified_signature)
WHERE p.prosecdef IS TRUE
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_pointage_exact_security$
DECLARE
  v_invalide text;
BEGIN
  WITH reviewed(signature, qualified_signature) AS (
    VALUES
      ('fn_scanner_code_pointage(text,jsonb)', 'public.fn_scanner_code_pointage(text,jsonb)'),
      ('fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)', 'public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)')
  )
  SELECT pg_catalog.string_agg(r.signature, ', ' ORDER BY r.signature)
  INTO v_invalide
  FROM reviewed r
  LEFT JOIN pg_catalog.pg_proc p
    ON p.oid = pg_catalog.to_regprocedure(r.qualified_signature)
  LEFT JOIN private.security_definer_inventory i
    ON i.signature = r.signature
  WHERE p.oid IS NULL
     OR p.prosecdef IS NOT TRUE
     OR i.signature IS NULL
     OR i.definition_md5 IS DISTINCT FROM pg_catalog.md5(p.prosrc);

  IF v_invalide IS NOT NULL THEN
    RAISE EXCEPTION 'Inventaire SECURITY DEFINER pointage exact incomplet ou périmé : %', v_invalide;
  END IF;

  IF has_function_privilege('anon', 'public.fn_scanner_code_pointage(text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.fn_scanner_code_pointage(text,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Privilèges des RPC de pointage exact invalides';
  END IF;
END;
$assert_pointage_exact_security$;

NOTIFY pgrst, 'reload schema';
