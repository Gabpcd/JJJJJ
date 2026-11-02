-- B9 — lot 2 B1 (app iOS native) : les deux RPC de pointage appelables par le
-- soignant ne lui renvoient plus le code de pointage suivant (`nouveau_code`)
-- ni son HMAC (`nouveau_hmac`) :
--   * fn_scanner_code_pointage (scan d'OUVERTURE ou de FERMETURE) ;
--   * fn_declarer_fin_retroactive (oubli du scan de fin). Le soignant assigné
--     peut l'appeler lui-même en PostgREST (branche v_caller_is_soignant,
--     EXECUTE accordé à authenticated) ; le web ne l'appelle que depuis l'écran
--     établissement (AffichageCodeRotatifEtab.tsx), qui ne lit que `error` puis
--     relit l'état.
-- Avec ce code, un soignant pouvait fermer ou rouvrir un segment hors de
-- l'établissement sans relire le code affiché. Le web soignant
-- (PointageRotatifSoignant.tsx) ne lit que `type_scan_effectue`.
--
-- GAP CONNU, NON FERMÉ PAR B1 (PR B9 séparée « B1-ter », go de Gabrielle) : la
-- colonne missions.code_pointage_actif (comme code_pointage_hmac) reste lisible
-- par le soignant assigné en PostgREST direct
-- (GET /rest/v1/missions?id=eq.<id>&select=code_pointage_actif) : SELECT de
-- table accordé à authenticated (supabase/schema/public.sql l.86259) et RLS
-- pol_mission_select (l.79361, branche soignant_assigne_id = auth.uid()). Le
-- filtre CASE WHEN v_is_etab de fn_etat_pointage_mission ne vaut qu'à l'étage
-- RPC. Relu en lecture seule le 2026-11-02 : has_column_privilege pour
-- authenticated sur missions.code_pointage_actif et code_pointage_hmac = true.
-- B1 retire seulement le code des réponses RPC. Instruction et proposition :
-- docs/POINTAGE_CODE_ROTATIF_VISIBILITE.md.
--
-- Sources : définitions LIVE production relues le 2026-11-02 (lecture seule,
-- prosrc et pg_get_function_arguments) :
--   * fn_scanner_code_pointage : MD5 a2af098e60488cbef102c80594b74d10,
--     identique au corps de 20261017165819 ;
--   * fn_declarer_fin_retroactive : MD5 845c6a3fd6dd3aa4ef7b2fcd19108d88,
--     identique au corps de 20260903194000 ;
-- toutes deux identiques à supabase/schema/public.sql. Différences, et seules
-- différences :
--   1. pour les deux RPC, retrait des deux clés du jsonb_build_object final ;
--   2. pour fn_declarer_fin_retroactive, verrou de sa garde d'autorisation.
--      `IF NOT (v_caller_is_soignant OR v_caller_is_etab_admin OR est_admin())`
--      vaut NULL pour un compte authentifié sans lien avec la mission
--      (est_admin_etablissement() et mon_etablissement_id() renvoient NULL,
--      définitions LIVE identiques au dump) et un IF NULL ne lève pas : un
--      autre soignant pouvait fermer le segment ouvert du soignant assigné à
--      l'heure de son choix (heures réelles, facturation), recevoir le code
--      suivant, et l'audit le classait ADMIN_PLATEFORME. Les NULL valent
--      désormais false ; le contexte système (auth.uid() NULL : service_role,
--      tests SQL) garde le comportement LIVE. Aucun appelant légitime ne
--      change : soignant assigné, propriétaire/ADMIN_GROUPE/RH de
--      l'établissement de la mission, administrateur plateforme.
-- Rotation du code, HMAC stocké dans missions.code_pointage_hmac, horodatage,
-- contrôles, exceptions, journal d'audit, propriétaire et ACL inchangés
-- (CREATE OR REPLACE, aucun GRANT). Toutes les gardes « avant » précèdent la
-- première redéfinition : une seule source divergente refuse la migration
-- entière.
-- Banc : scripts/ci/scanner-code-sans-code-suivant-pg17.py.
DO $scanner_avant$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('public.fn_scanner_code_pointage(text,jsonb)');
  IF NOT FOUND OR pg_catalog.md5(p.prosrc) <> 'a2af098e60488cbef102c80594b74d10'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 'v'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres'
    OR pg_catalog.pg_get_function_arguments(p.oid) <> 'p_code text, p_metadata jsonb DEFAULT NULL::jsonb'
    OR (SELECT count(*) FROM private.security_definer_inventory i
        WHERE i.signature = 'fn_scanner_code_pointage(text,jsonb)'
          AND i.categorie = 'RPC_UTILISATEUR_AUTH_INTERNE'
          AND i.definition_md5 = 'a2af098e60488cbef102c80594b74d10') <> 1
    OR EXISTS (SELECT FROM private.security_definer_inventory i
               WHERE i.signature = 'public.fn_scanner_code_pointage(text,jsonb)')
  THEN RAISE EXCEPTION 'POINTAGE_SANS_CODE_SUIVANT_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT'; END IF;
  IF pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    OR EXISTS (SELECT FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
               WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  THEN RAISE EXCEPTION 'POINTAGE_SANS_CODE_SUIVANT_ACL_AVANT_DIVERGENTE'; END IF;
END;
$scanner_avant$;

DO $fin_avant$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)');
  IF NOT FOUND OR pg_catalog.md5(p.prosrc) <> '845c6a3fd6dd3aa4ef7b2fcd19108d88'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 'v'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres'
    OR pg_catalog.pg_get_function_arguments(p.oid) <> 'p_mission_id uuid, p_heure_fin timestamp with time zone, p_raison text DEFAULT ''Oubli de scan''::text'
    OR (SELECT count(*) FROM private.security_definer_inventory i
        WHERE i.signature = 'fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)'
          AND i.categorie = 'MIXTE_TENANT_ADMIN'
          AND i.definition_md5 = '845c6a3fd6dd3aa4ef7b2fcd19108d88') <> 1
    OR EXISTS (SELECT FROM private.security_definer_inventory i
               WHERE i.signature = 'public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)')
  THEN RAISE EXCEPTION 'FIN_RETROACTIVE_SANS_CODE_SUIVANT_SOURCE_AVANT_OU_INVENTAIRE_DIVERGENT'; END IF;
  IF pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    OR EXISTS (SELECT FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
               WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  THEN RAISE EXCEPTION 'FIN_RETROACTIVE_SANS_CODE_SUIVANT_ACL_AVANT_DIVERGENTE'; END IF;
END;
$fin_avant$;

CREATE OR REPLACE FUNCTION public.fn_scanner_code_pointage(p_code text, p_metadata jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
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
  WHILE v_new_code = v_mission.code_pointage_actif
    OR EXISTS (
      SELECT 1
      FROM scans_pointage sp
      WHERE sp.mission_id = v_mission.id
        AND sp.code_saisi = v_new_code
    )
    OR EXISTS (
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

  -- Logique ternaire : pour un compte authentifié sans lien avec la mission
  -- (soignant non assigné, compte sans établissement), est_admin_etablissement()
  -- et mon_etablissement_id() valent NULL ; NOT (false OR NULL OR false) vaut
  -- NULL et ce IF laissait passer l'appel. Le contexte système (auth.uid() NULL :
  -- service_role, tests SQL) reste inchangé.
  IF auth.uid() IS NOT NULL
     AND NOT (COALESCE(v_caller_is_soignant, false)
              OR COALESCE(v_caller_is_etab_admin, false)
              OR COALESCE(est_admin(), false)) THEN
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
    'prochain_type_scan', 'OUVERTURE',
    'numero_scan', v_scan_numero
  );
END;
$function$;

-- CREATE OR REPLACE conserve propriétaire et ACL ; aucun GRANT supplémentaire.
-- La classification et la justification d'inventaire existantes sont conservées.
DO $scanner_apres$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('public.fn_scanner_code_pointage(text,jsonb)');
  IF NOT FOUND OR pg_catalog.md5(p.prosrc) <> '4568c8a01be5be24587cffa9bdd9c1c3'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 'v'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres'
    OR pg_catalog.pg_get_function_arguments(p.oid) <> 'p_code text, p_metadata jsonb DEFAULT NULL::jsonb'
    OR pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    OR EXISTS (SELECT FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
               WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  THEN RAISE EXCEPTION 'POINTAGE_SANS_CODE_SUIVANT_SOURCE_OU_ACL_PROPOSEE_DIVERGENTE'; END IF;
  UPDATE private.security_definer_inventory i
  SET definition_md5 = pg_catalog.md5(p.prosrc), recense_le = now()
  WHERE i.signature = 'fn_scanner_code_pointage(text,jsonb)'
    AND i.categorie = 'RPC_UTILISATEUR_AUTH_INTERNE'
    AND i.definition_md5 = 'a2af098e60488cbef102c80594b74d10';
  IF NOT FOUND OR (SELECT count(*) FROM private.security_definer_inventory i
      WHERE i.signature = 'fn_scanner_code_pointage(text,jsonb)'
        AND i.categorie = 'RPC_UTILISATEUR_AUTH_INTERNE'
        AND i.definition_md5 = pg_catalog.md5(p.prosrc)) <> 1
  THEN RAISE EXCEPTION 'POINTAGE_SANS_CODE_SUIVANT_INVENTAIRE_NON_MIS_A_JOUR'; END IF;
END;
$scanner_apres$;

DO $fin_apres$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('public.fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)');
  IF NOT FOUND OR pg_catalog.md5(p.prosrc) <> '2e238a0d6cea02bce6802c77835defe2'
    OR p.prosecdef IS DISTINCT FROM true OR p.provolatile <> 'v'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR pg_catalog.pg_get_userbyid(p.proowner) <> 'postgres'
    OR pg_catalog.pg_get_function_arguments(p.oid) <> 'p_mission_id uuid, p_heure_fin timestamp with time zone, p_raison text DEFAULT ''Oubli de scan''::text'
    OR pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    OR EXISTS (SELECT FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
               WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  THEN RAISE EXCEPTION 'FIN_RETROACTIVE_SANS_CODE_SUIVANT_SOURCE_OU_ACL_PROPOSEE_DIVERGENTE'; END IF;
  UPDATE private.security_definer_inventory i
  SET definition_md5 = pg_catalog.md5(p.prosrc), recense_le = now()
  WHERE i.signature = 'fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)'
    AND i.categorie = 'MIXTE_TENANT_ADMIN'
    AND i.definition_md5 = '845c6a3fd6dd3aa4ef7b2fcd19108d88';
  IF NOT FOUND OR (SELECT count(*) FROM private.security_definer_inventory i
      WHERE i.signature = 'fn_declarer_fin_retroactive(uuid,timestamp with time zone,text)'
        AND i.categorie = 'MIXTE_TENANT_ADMIN'
        AND i.definition_md5 = pg_catalog.md5(p.prosrc)) <> 1
  THEN RAISE EXCEPTION 'FIN_RETROACTIVE_SANS_CODE_SUIVANT_INVENTAIRE_NON_MIS_A_JOUR'; END IF;
END;
$fin_apres$;

NOTIFY pgrst, 'reload schema';
