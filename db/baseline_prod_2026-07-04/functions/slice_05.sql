CREATE OR REPLACE FUNCTION public.fn_ecrire_audit(p_acteur_id uuid, p_type_acteur text, p_action text, p_type_ressource text DEFAULT NULL::text, p_id_ressource uuid DEFAULT NULL::uuid, p_cle_s3 text DEFAULT NULL::text, p_details jsonb DEFAULT NULL::jsonb, p_ip inet DEFAULT NULL::inet, p_navigateur text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_id UUID;
BEGIN
    INSERT INTO journaux_audit (
        acteur_id, type_acteur, ip_acteur, navigateur_acteur,
        action, type_ressource, id_ressource, cle_s3_ressource, details
    ) VALUES (
        p_acteur_id, p_type_acteur, p_ip, p_navigateur,
        p_action, p_type_ressource, p_id_ressource, p_cle_s3, p_details
    ) RETURNING id INTO v_id;
    RETURN v_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_ecrire_audit_safe(p_acteur_id uuid, p_type_acteur text, p_action text, p_type_ressource text, p_id_ressource uuid, p_cle_s3 text DEFAULT NULL::text, p_details jsonb DEFAULT NULL::jsonb, p_ip inet DEFAULT NULL::inet, p_navigateur text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_uid uuid := auth.uid();
  v_is_service boolean := COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_acteur_id uuid := p_acteur_id;
BEGIN
  -- Iter3 sec fix : empêcher impersonation cross-user dans audit log
  IF NOT v_is_service AND NOT est_admin() THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
    END IF;
    v_acteur_id := v_uid;
  END IF;

  INSERT INTO journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3, details, ip, navigateur
  ) VALUES (
    v_acteur_id, p_type_acteur, p_action, p_type_ressource, p_id_ressource,
    p_cle_s3, p_details, p_ip, p_navigateur
  ) RETURNING id INTO v_id;
  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_email_documents_expirants()
 RETURNS TABLE(email text, prenom text, type_document text, date_expiration text, soignant_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (s.id, ds.type_document)
        s.email, s.prenom, ds.type_document::TEXT,
        TO_CHAR(ds.valide_jusqua, 'DD/MM/YYYY'), s.id
    FROM documents_soignants ds
    JOIN soignants s ON s.id = ds.soignant_id
    WHERE ds.valide_jusqua BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
      AND ds.statut_verification = 'VERIFIE'
      AND ds.supprime_le IS NULL AND s.email IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM emails_envoyes ee
          WHERE ee.destinataire_id = s.id AND ee.type = 'DOCUMENT_EXPIRANT'
            AND ee.cree_le > NOW() - INTERVAL '7 days'
      );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_email_factures_impayees()
 RETURNS TABLE(email text, nom_etablissement text, numero_facture text, montant_ttc text, jours_depuis integer, etablissement_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT e.telephone, e.nom, f.numero_facture,
        ROUND(f.montant_ttc, 2)::TEXT,
        EXTRACT(DAY FROM NOW() - f.cree_le)::INTEGER, e.id
    FROM factures f
    JOIN etablissements e ON e.id = f.etablissement_id
    WHERE f.statut = 'EMISE'
      AND f.cree_le + INTERVAL '15 days' < NOW()
      AND NOT EXISTS (
          SELECT 1 FROM emails_envoyes ee
          WHERE ee.type = 'RAPPEL_FACTURE'
            AND ee.sujet LIKE '%' || f.numero_facture || '%'
            AND ee.cree_le > NOW() - INTERVAL '7 days'
      );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_email_eligible_liberal()
 RETURNS TABLE(email text, prenom text, soignant_id uuid, heures numeric, taux_prise_en_charge integer, montant_offert numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.email, s.prenom, s.id, s.heures_plateforme,
        CASE
            WHEN s.heures_plateforme >= 3200 THEN 100
            WHEN s.heures_plateforme >= 2400 THEN 75
            WHEN s.heures_plateforme >= 1600 THEN 50
            WHEN s.heures_plateforme >= 800 THEN 25
            ELSE 0
        END,
        ROUND(450.0 * (CASE
            WHEN s.heures_plateforme >= 3200 THEN 1.0
            WHEN s.heures_plateforme >= 2400 THEN 0.75
            WHEN s.heures_plateforme >= 1600 THEN 0.5
            WHEN s.heures_plateforme >= 800 THEN 0.25
            ELSE 0
        END), 2)
    FROM soignants s
    WHERE s.heures_plateforme >= 800
      AND s.statut_liberal = 'NON_LIBERAL'
      AND s.supprime_le IS NULL AND s.email IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM emails_envoyes ee
          WHERE ee.destinataire_id = s.id AND ee.type = 'ELIGIBLE_LIBERAL'
      )
      AND s.profession IN (SELECT profession FROM professions_liberal_eligible);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_doit_notifier(p_utilisateur_id uuid, p_type_evenement type_evenement_notification, p_canal canal_notification)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_canal_global boolean;
  v_pref_event boolean;
BEGIN
  -- URGENCE : toujours notifier (non désactivable)
  IF p_type_evenement = 'URGENCE' THEN RETURN true; END IF;

  -- Vérifier le canal global
  SELECT CASE p_canal
    WHEN 'EMAIL' THEN canal_email
    WHEN 'SMS' THEN canal_sms
    WHEN 'PUSH' THEN canal_push
    WHEN 'IN_APP' THEN canal_in_app
  END INTO v_canal_global
  FROM preferences_notifications WHERE utilisateur_id = p_utilisateur_id;

  -- Si pas de row : default ON sauf SMS
  IF v_canal_global IS NULL THEN
    v_canal_global := CASE p_canal WHEN 'SMS' THEN false ELSE true END;
  END IF;

  IF NOT v_canal_global THEN RETURN false; END IF;

  -- Préférence par événement (default true)
  SELECT actif INTO v_pref_event
  FROM preferences_notifications_par_evenement
  WHERE utilisateur_id = p_utilisateur_id
    AND type_evenement = p_type_evenement
    AND canal = p_canal;

  RETURN COALESCE(v_pref_event, true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_donner_consentement_ping_gps(p_consent boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  INSERT INTO public.consentements_ping_gps (soignant_id, consenti, consenti_le, retire_le, maj_le)
  VALUES (
    v_uid,
    p_consent,
    CASE WHEN p_consent THEN now() ELSE NULL END,
    CASE WHEN NOT p_consent THEN now() ELSE NULL END,
    now()
  )
  ON CONFLICT (soignant_id) DO UPDATE SET
    consenti = EXCLUDED.consenti,
    consenti_le = CASE WHEN EXCLUDED.consenti THEN COALESCE(public.consentements_ping_gps.consenti_le, now()) ELSE public.consentements_ping_gps.consenti_le END,
    retire_le = CASE WHEN NOT EXCLUDED.consenti THEN now() ELSE NULL END,
    maj_le = now();

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'RGPD_CONSENTEMENT_DONNE', 'consentement_ping_gps', v_uid,
    jsonb_build_object(
      'type', 'PING_GPS_BACKGROUND',
      'consenti', p_consent,
      'horodatage', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'consenti', p_consent,
    'horodatage', now()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_documents_ok_pour_mission(p_soignant_id uuid, p_type_contrat text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profession type_profession;
  v_identite_verifiee BOOLEAN;
  v_regime_liberal BOOLEAN;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN false; END IF;
  SELECT profession, (COALESCE(rpps_verifie, false) OR COALESCE(adeli_verifie, false))
    INTO v_profession, v_identite_verifiee
    FROM soignants WHERE id = p_soignant_id;
  v_regime_liberal := (p_type_contrat = 'LIBERAL');
  RETURN NOT EXISTS(
    SELECT 1 FROM documents_requis_par_profession drp
    WHERE drp.profession = v_profession AND drp.est_critique = true
      AND (drp.type_exercice_requis = 'TOUS'
          OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_regime_liberal)
          OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND NOT v_regime_liberal))
      AND NOT (v_identite_verifiee AND drp.type_document IN ('DIPLOME', 'RPPS_ADELI'))
      AND NOT EXISTS (
          SELECT 1 FROM documents_soignants ds
          WHERE ds.soignant_id = p_soignant_id AND ds.type_document = drp.type_document
            AND ds.statut_verification = 'VERIFIE' AND ds.supprime_le IS NULL
            AND (drp.a_expiration = false OR ds.valide_jusqua IS NULL OR ds.valide_jusqua > NOW())));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_email_rappels_j1()
 RETURNS TABLE(email text, prenom text, mission text, etablissement text, heure_debut text, soignant_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.email, s.prenom, m.intitule, e.nom,
        TO_CHAR(m.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI'), s.id
    FROM missions m
    JOIN soignants s ON s.id = m.soignant_assigne_id
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'ASSIGNEE'
      AND m.debut_le::DATE = (CURRENT_DATE + INTERVAL '1 day')
      AND s.email IS NOT NULL;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_email_recap_hebdo()
 RETURNS TABLE(email text, prenom text, soignant_id uuid, missions_terminees bigint, heures_semaine numeric, gains_semaine numeric, score numeric, heures_totales numeric, missions_dispo bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.email, s.prenom, s.id,
        COUNT(m.id) FILTER (WHERE m.statut = 'TERMINEE' AND m.fin_le > NOW() - INTERVAL '7 days'),
        COALESCE(SUM(m.duree_heures) FILTER (WHERE m.statut = 'TERMINEE' AND m.fin_le > NOW() - INTERVAL '7 days'), 0),
        COALESCE(SUM(m.net_a_payer) FILTER (WHERE m.statut = 'TERMINEE' AND m.fin_le > NOW() - INTERVAL '7 days'), 0),
        s.score_fiabilite, s.heures_cumulees,
        (SELECT COUNT(*) FROM missions mo WHERE mo.statut = 'OUVERTE' AND mo.profession_requise = s.profession)
    FROM soignants s
    LEFT JOIN missions m ON m.soignant_assigne_id = s.id
    WHERE s.supprime_le IS NULL AND s.email IS NOT NULL
      AND s.derniere_activite_le > NOW() - INTERVAL '30 days'
    GROUP BY s.id, s.email, s.prenom, s.score_fiabilite, s.heures_cumulees, s.profession;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_enregistrer_siret_liberal(p_siret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF LENGTH(p_siret) != 14 THEN
        RETURN '{"error":"Le SIRET doit contenir 14 chiffres"}'::JSONB;
    END IF;
    UPDATE soignants SET
        siret_liberal = p_siret,
        statut_liberal = 'EN_COURS',
        modifie_le = NOW()
    WHERE id = auth.uid();
    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_emettre_alerte_monitoring(p_type text, p_severite text, p_source text, p_message text, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_id UUID; v_existing UUID;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  SELECT id INTO v_existing FROM alertes_systeme
  WHERE type_alerte = p_type AND source = p_source AND resolu_le IS NULL
    AND cree_le > NOW() - INTERVAL '1 hour'
  LIMIT 1;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;

  INSERT INTO alertes_systeme (type_alerte, severite, source, message, details)
  VALUES (p_type, p_severite, p_source, p_message, p_details)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_enregistrer_numero_dpae(p_contrat_id uuid, p_dpae_numero text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_numero_trim text;
  v_soignant_id uuid;
  v_mission_id uuid;
  v_soignant_prenom text;
  v_etab_nom text;
  v_mission_intitule text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_dpae_numero IS NULL OR length(trim(p_dpae_numero)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Numéro DPAE requis');
  END IF;

  v_numero_trim := trim(p_dpae_numero);

  IF v_numero_trim !~ '^[A-Za-z0-9]{8,30}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : 8 à 30 caractères alphanumériques (lettres et chiffres) requis. Aucun espace ni ponctuation.'
    );
  END IF;

  IF v_numero_trim !~ '[0-9]' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Format invalide : le numéro DPAE doit contenir au moins un chiffre.'
    );
  END IF;

  SELECT cm.etablissement_id, cm.soignant_id, cm.mission_id
    INTO v_etab_id, v_soignant_id, v_mission_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE public.contrats_mission
  SET dpae_numero = v_numero_trim,
      dpae_effectuee = true,
      dpae_effectuee_le = COALESCE(dpae_effectuee_le, NOW()),
      modifie_le = NOW()
  WHERE id = p_contrat_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'contrat_mission', p_contrat_id,
    jsonb_build_object(
      'evenement', 'DPAE_NUMERO_ENREGISTRE',
      'dpae_numero', v_numero_trim,
      'enregistre_le', NOW()::text
    )
  );

  IF v_soignant_id IS NOT NULL AND v_mission_id IS NOT NULL THEN
    SELECT prenom INTO v_soignant_prenom FROM public.soignants WHERE id = v_soignant_id;
    SELECT nom INTO v_etab_nom FROM public.etablissements WHERE id = v_etab_id;
    SELECT intitule INTO v_mission_intitule FROM public.missions WHERE id = v_mission_id;

    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'type', 'DPAE_DECLAREE_SOIGNANT',
          'destinataire_id', v_soignant_id,
          'data', jsonb_build_object(
            'prenom', COALESCE(v_soignant_prenom, ''),
            'etablissement_nom', COALESCE(v_etab_nom, 'L''établissement'),
            'mission_intitule', COALESCE(v_mission_intitule, 'votre mission'),
            'dpae_numero', v_numero_trim,
            'contrat_id', p_contrat_id::text
          )
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'dpae_numero', v_numero_trim);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_enregistrer_pings_gps(p_mission_id uuid, p_pings jsonb, p_terminal_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission record;
  v_consent record;
  v_ping jsonb;
  v_inserts integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_pings IS NULL OR jsonb_typeof(p_pings) != 'array' OR jsonb_array_length(p_pings) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'PINGS_VIDE');
  END IF;

  -- Limite anti-flood : max 200 pings par batch
  IF jsonb_array_length(p_pings) > 200 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_PINGS');
  END IF;

  -- Mission + soignant assigné
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;
  IF v_mission.soignant_assigne_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Consentement RGPD strict
  SELECT * INTO v_consent FROM public.consentements_ping_gps WHERE soignant_id = v_uid;
  IF v_consent IS NULL OR NOT v_consent.consenti THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONSENTEMENT_MANQUANT');
  END IF;

  -- Fenêtre temporelle : pings acceptés uniquement entre debut_le -1h et fin_le +2h
  -- (au-delà : ignoré silencieusement, le client recevra success=true mais 0 insertions)
  FOR v_ping IN SELECT * FROM jsonb_array_elements(p_pings)
  LOOP
    DECLARE
      v_h timestamptz := (v_ping->>'horodatage')::timestamptz;
      v_lat numeric := (v_ping->>'lat')::numeric;
      v_lng numeric := (v_ping->>'lng')::numeric;
      v_prec numeric := NULLIF(v_ping->>'precision_m', '')::numeric;
      v_vit numeric := NULLIF(v_ping->>'vitesse_ms', '')::numeric;
      v_cap numeric := NULLIF(v_ping->>'cap_deg', '')::numeric;
      v_alt numeric := NULLIF(v_ping->>'altitude_m', '')::numeric;
      v_src text := COALESCE(v_ping->>'source', 'BACKGROUND');
      v_mock boolean := COALESCE((v_ping->>'mock_detected')::boolean, false);
    BEGIN
      IF v_h IS NULL OR v_lat IS NULL OR v_lng IS NULL THEN
        CONTINUE;
      END IF;
      IF v_h < v_mission.debut_le - INTERVAL '1 hour' OR v_h > v_mission.fin_le + INTERVAL '2 hours' THEN
        CONTINUE;
      END IF;
      IF v_lat < -90 OR v_lat > 90 OR v_lng < -180 OR v_lng > 180 THEN
        CONTINUE;
      END IF;

      INSERT INTO public.pings_gps_mission (
        mission_id, soignant_id, lat, lng, precision_m, vitesse_ms, cap_deg, altitude_m,
        source, mock_detected, horodatage, terminal_id
      ) VALUES (
        p_mission_id, v_uid, v_lat, v_lng, v_prec, v_vit, v_cap, v_alt,
        v_src, v_mock, v_h, p_terminal_id
      );
      v_inserts := v_inserts + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'inserts', v_inserts,
    'ignores', jsonb_array_length(p_pings) - v_inserts
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_enregistrer_mon_iban(p_iban text, p_titulaire text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_iban TEXT;
  v_last4 TEXT;
  v_ancien_iban TEXT;
  v_action TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  -- Normaliser : majuscules, supprimer espaces
  v_iban := UPPER(REGEXP_REPLACE(TRIM(p_iban), '\s+', '', 'g'));

  -- Validation format IBAN basique (2 lettres + 2 chiffres + 10-30 alphanum)
  IF v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$' THEN
    RETURN jsonb_build_object('error', 'Format IBAN invalide. Exemple : FR7630006000011234567890189');
  END IF;

  -- Validation checksum IBAN (ISO 7064 mod-97)
  DECLARE
    v_rearranged TEXT;
    v_numeric TEXT := '';
    v_char TEXT;
    v_remainder NUMERIC;
  BEGIN
    -- Déplacer les 4 premiers chars à la fin
    v_rearranged := SUBSTRING(v_iban FROM 5) || SUBSTRING(v_iban FROM 1 FOR 4);
    -- Convertir lettres en chiffres (A=10, B=11, ..., Z=35)
    FOR i IN 1..LENGTH(v_rearranged) LOOP
      v_char := SUBSTRING(v_rearranged FROM i FOR 1);
      IF v_char ~ '[A-Z]' THEN
        v_numeric := v_numeric || (ASCII(v_char) - 55)::TEXT;
      ELSE
        v_numeric := v_numeric || v_char;
      END IF;
    END LOOP;
    -- Mod 97 (traitement par blocs pour éviter overflow)
    v_remainder := 0;
    FOR i IN 1..LENGTH(v_numeric) LOOP
      v_remainder := (v_remainder * 10 + SUBSTRING(v_numeric FROM i FOR 1)::INT) % 97;
    END LOOP;
    IF v_remainder <> 1 THEN
      RETURN jsonb_build_object('error', 'IBAN invalide (checksum incorrecte). Vérifiez votre saisie.');
    END IF;
  END;

  IF TRIM(COALESCE(p_titulaire, '')) = '' THEN
    RETURN jsonb_build_object('error', 'Le nom du titulaire est obligatoire.');
  END IF;

  v_last4 := RIGHT(v_iban, 4);

  -- Vérifier si c'est un ajout ou une modification
  SELECT iban_virement INTO v_ancien_iban FROM soignants WHERE id = v_uid;
  v_action := CASE WHEN v_ancien_iban IS NULL OR v_ancien_iban = '' THEN 'IBAN_RENSEIGNE' ELSE 'IBAN_MODIFIE' END;

  UPDATE soignants
  SET iban_virement = v_iban,
      iban_titulaire = TRIM(p_titulaire),
      iban_last4 = v_last4
  WHERE id = v_uid;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := v_action,
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('iban_last4', v_last4, 'titulaire', TRIM(p_titulaire))
  );

  RETURN jsonb_build_object(
    'success', true,
    'iban_last4', v_last4,
    'titulaire', TRIM(p_titulaire),
    'message', 'IBAN enregistré. Il sera utilisé pour le versement de vos primes.'
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(p_mission_id uuid, p_direction text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_direction swipe_direction;
  v_swipe_id uuid;
  v_mission RECORD;
  v_soignant RECORD;
  v_candidature_id uuid;
  v_choix_contrat text;
  v_choix_effectif text;
  v_rcp_valide boolean;
  v_planning jsonb;
  v_warning text;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_direction = 'SUPER_LIKE' THEN
    p_direction := 'FAVORI';
  END IF;

  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'FAVORI') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;

  v_direction := p_direction::swipe_direction;

  IF v_direction = 'LIKE' THEN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    SELECT * INTO v_soignant FROM soignants WHERE id = v_soignant_id;

    IF v_mission.id IS NOT NULL AND v_soignant.id IS NOT NULL
       AND v_mission.statut = 'OUVERTE'
       AND fn_soignant_compatible_mission(
             v_soignant.profession, v_soignant.specialite_medicale,
             v_mission.profession_requise, v_mission.specialite_medicale_requise,
             v_mission.accepte_non_specialises)
       AND NOT fn_est_exclu(v_soignant_id, v_mission.etablissement_id)
       AND NOT EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = v_soignant_id)
    THEN
      IF v_mission.type_contrat_recherche = 'SALARIE'
         AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Cette mission est réservée aux salariés.');
      END IF;
      IF v_mission.type_contrat_recherche = 'LIBERAL'
         AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Cette mission est réservée aux libéraux.');
      END IF;

      v_planning := fn_conflit_planning_soignant(v_soignant_id, p_mission_id);
      IF (v_planning->>'conflit')::boolean THEN
        RETURN jsonb_build_object('ok', false, 'error', v_planning->>'message', 'conflit_planning', true);
      END IF;
      v_warning := v_planning->>'warning';

      IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Veuillez choisir votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD)'),
              jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
      END IF;

      IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_contrat := 'SALARIE';
      ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_contrat := 'LIBERAL';
      ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_contrat := v_choix_effectif;
      ELSE v_choix_contrat := COALESCE(v_soignant.type_exercice, 'SALARIE');
      END IF;

      IF v_choix_contrat = 'LIBERAL' THEN
        SELECT EXISTS(SELECT 1 FROM documents_soignants
          WHERE soignant_id = v_soignant_id AND type_document = 'RCP_ASSURANCE'
            AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
            AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_valide;
        IF NOT v_rcp_valide THEN
          RETURN jsonb_build_object('ok', false, 'error',
            'Assurance RCP manquante ou expirée — obligatoire pour candidater en libéral. Téléversez-la dans vos documents (ou choisissez salarié si la mission le permet).');
        END IF;
      END IF;
    END IF;
  END IF;

  INSERT INTO public.swipes (soignant_id, mission_id, direction)
    VALUES (v_soignant_id, p_mission_id, v_direction)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING
    RETURNING id INTO v_swipe_id;

  IF v_swipe_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  IF v_direction = 'FAVORI' THEN
    INSERT INTO public.missions_sauvegardees (soignant_id, mission_id)
    VALUES (v_soignant_id, p_mission_id)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING;

    RETURN jsonb_build_object('ok', true, 'swipe_id', v_swipe_id, 'direction', 'FAVORI', 'sauvegardee', true);
  END IF;

  IF v_direction = 'LIKE' AND v_choix_contrat IS NOT NULL THEN
    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, v_soignant_id, NULL, 'EN_ATTENTE', v_choix_contrat)
    RETURNING id INTO v_candidature_id;

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES (
      v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
      '📋 Nouvelle candidature reçue',
      COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' || v_mission.intitule || ' ».',
      '/etablissement/missions/' || p_mission_id
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'swipe_id', v_swipe_id,
    'direction', p_direction,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_choix_contrat,
    'warning', v_warning
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_envoyer_message(p_conversation_id uuid, p_contenu text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_conv RECORD;
BEGIN
    -- ★ Vérifier longueur
    IF p_contenu IS NULL OR LENGTH(TRIM(p_contenu)) < 1 THEN
        RETURN jsonb_build_object('error', 'Le message ne peut pas être vide.');
    END IF;
    IF LENGTH(p_contenu) > 5000 THEN
        RETURN jsonb_build_object('error', 'Le message est trop long (5000 caractères max).');
    END IF;

    SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
    IF v_conv IS NULL THEN RETURN '{"error":"Conversation introuvable"}'::JSONB; END IF;

    IF v_conv.participant_1_id != auth.uid()
       AND v_conv.participant_2_id != auth.uid()
       AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    -- ★ XSS protection
    INSERT INTO messages_chat (conversation_id, auteur_id, contenu, est_admin)
    VALUES (p_conversation_id, auth.uid(), fn_html_escape(p_contenu), est_admin());

    UPDATE conversations SET dernier_message_le = NOW() WHERE id = p_conversation_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_litiges()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_litige RECORD;
  v_destinataire_id UUID;
  v_destinataire_type TEXT;
  v_age_h INT;
  v_rappel_key TEXT;
  v_rappel_libelle TEXT;
  v_nb_rappels INT := 0;
BEGIN
  FOR v_litige IN
    SELECT l.id, l.mission_id, l.soignant_id, l.etablissement_id,
           l.initie_par, l.cree_le, l.reponse, l.type_litige,
           l.derniers_rappels_envoyes
      FROM public.litiges l
     WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION')
       AND NOT l.est_informatif
       AND l.escalade_auto_le IS NULL
       AND (l.reponse IS NULL OR length(trim(l.reponse)) = 0)
  LOOP
    v_age_h := EXTRACT(EPOCH FROM NOW() - v_litige.cree_le)::INT / 3600;

    IF v_age_h >= 120 AND NOT (v_litige.derniers_rappels_envoyes ? 'J+5') THEN
      v_rappel_key := 'J+5';
      v_rappel_libelle := 'Rappel litige 5 jours — dernière relance';
    ELSIF v_age_h >= 72 AND NOT (v_litige.derniers_rappels_envoyes ? 'J+3') THEN
      v_rappel_key := 'J+3';
      v_rappel_libelle := 'Rappel litige 3 jours';
    ELSIF v_age_h >= 24 AND NOT (v_litige.derniers_rappels_envoyes ? 'J+1') THEN
      v_rappel_key := 'J+1';
      v_rappel_libelle := 'Rappel litige 1 jour';
    ELSE
      CONTINUE;
    END IF;

    IF v_litige.initie_par = 'SOIGNANT' THEN
      v_destinataire_id := v_litige.etablissement_id;
      v_destinataire_type := 'ETABLISSEMENT';
    ELSE
      v_destinataire_id := v_litige.soignant_id;
      v_destinataire_type := 'SOIGNANT';
    END IF;

    IF v_destinataire_id IS NULL THEN
      CONTINUE;
    END IF;

    PERFORM public.fn_litige_push_notification(
      v_destinataire_id,
      v_destinataire_type,
      'LITIGE_RAPPEL_' || REPLACE(v_rappel_key, '+', ''),
      v_rappel_libelle,
      'Un litige est en attente de votre réponse depuis ' || v_age_h || 'h. Répondez pour éviter l''escalade.',
      v_litige.id,
      jsonb_build_object(
        'type_litige', v_litige.type_litige,
        'mission_id', v_litige.mission_id,
        'age_heures', v_age_h,
        'rappel', v_rappel_key
      )
    );

    UPDATE public.litiges
       SET derniers_rappels_envoyes = derniers_rappels_envoyes
         || jsonb_build_object(v_rappel_key, NOW())
     WHERE id = v_litige.id;

    v_nb_rappels := v_nb_rappels + 1;
  END LOOP;

  RETURN jsonb_build_object('rappels_envoyes', v_nb_rappels);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_notation_j1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_url TEXT;
  v_token TEXT;
  v_mission RECORD;
  v_count_etab INT := 0;
  v_count_soignant INT := 0;
  v_send_email_called BOOLEAN;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  BEGIN
    v_url := public.fn_lire_secret_cron('supabase_url');
    v_token := public.fn_lire_secret_cron('service_role_key');
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL; v_token := NULL;
  END;

  FOR v_mission IN
    SELECT m.id, m.intitule, m.fin_le, m.etablissement_id, m.soignant_assigne_id
    FROM missions m
    WHERE m.statut = 'TERMINEE'
      AND m.fin_le >= NOW() - INTERVAL '48 hours'
      AND m.fin_le < NOW() - INTERVAL '24 hours'
      AND m.soignant_assigne_id IS NOT NULL
  LOOP
    -- Côté étab
    IF NOT EXISTS (SELECT 1 FROM notifications_notation_j1 WHERE mission_id = v_mission.id AND sens = 'ETAB_VERS_SOIGNANT')
       AND NOT EXISTS (SELECT 1 FROM notations_missions WHERE mission_id = v_mission.id AND sens = 'ETAB_VERS_SOIGNANT')
       AND public.fn_doit_notifier(v_mission.etablissement_id, 'NOTATION_RAPPEL'::type_evenement_notification, 'EMAIL'::canal_notification) THEN
      v_send_email_called := false;
      IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-email',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_token),
            body := jsonb_build_object(
              'type', 'RAPPEL_NOTATION_ETAB',
              'destinataire_id', v_mission.etablissement_id,
              'data', jsonb_build_object('mission_id', v_mission.id, 'mission_intitule', v_mission.intitule, 'fin_le', v_mission.fin_le)
            )
          );
          v_send_email_called := true;
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
      VALUES (v_mission.id, 'ETAB_VERS_SOIGNANT', v_mission.etablissement_id)
      ON CONFLICT (mission_id, sens) DO NOTHING;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_mission.etablissement_id, p_type_acteur := 'SYSTEME',
        p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
        p_details := jsonb_build_object('sens', 'ETAB_VERS_SOIGNANT', 'send_email_called', v_send_email_called)
      );
      v_count_etab := v_count_etab + 1;
    END IF;

    -- Côté soignant
    IF NOT EXISTS (SELECT 1 FROM notifications_notation_j1 WHERE mission_id = v_mission.id AND sens = 'SOIGNANT_VERS_ETAB')
       AND NOT EXISTS (SELECT 1 FROM notations_missions WHERE mission_id = v_mission.id AND sens = 'SOIGNANT_VERS_ETAB')
       AND public.fn_doit_notifier(v_mission.soignant_assigne_id, 'NOTATION_RAPPEL'::type_evenement_notification, 'EMAIL'::canal_notification) THEN
      v_send_email_called := false;
      IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-email',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_token),
            body := jsonb_build_object(
              'type', 'RAPPEL_NOTATION_SOIGNANT',
              'destinataire_id', v_mission.soignant_assigne_id,
              'data', jsonb_build_object('mission_id', v_mission.id, 'mission_intitule', v_mission.intitule, 'fin_le', v_mission.fin_le)
            )
          );
          v_send_email_called := true;
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      INSERT INTO notifications_notation_j1 (mission_id, sens, destinataire_id)
      VALUES (v_mission.id, 'SOIGNANT_VERS_ETAB', v_mission.soignant_assigne_id)
      ON CONFLICT (mission_id, sens) DO NOTHING;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_mission.soignant_assigne_id, p_type_acteur := 'SYSTEME',
        p_action := 'RAPPEL_NOTATION_J1_ENVOYE', p_type_ressource := 'mission', p_id_ressource := v_mission.id,
        p_details := jsonb_build_object('sens', 'SOIGNANT_VERS_ETAB', 'send_email_called', v_send_email_called)
      );
      v_count_soignant := v_count_soignant + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count_etab', v_count_etab, 'count_soignant', v_count_soignant);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_signature(p_contrat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_contrat RECORD; v_role text; v_otp text; v_otp_hash text;
  v_telephone text; v_sig_existante RECORD; v_sms_count int; v_sms_window_start timestamptz;
  v_ip inet; v_rate_check jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;
  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_rate_check := public.fn_check_rate_limit_ip_signature(v_ip);
  IF NOT (v_rate_check->>'allowed')::boolean THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_SMS_IP',
      'error', 'Trop de demandes de signature depuis votre IP. Réessayez dans 1h.',
      'envois_courant', v_rate_check->>'envois_courant', 'max', v_rate_check->>'max');
  END IF;
  SELECT cm.id, cm.soignant_id, cm.etablissement_id, cm.contenu_html, cm.statut,
         cm.signature_soignant, cm.signature_etablissement
  INTO v_contrat FROM public.contrats_mission cm WHERE cm.id = p_contrat_id;
  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE', 'error', 'Contrat introuvable');
  END IF;
  IF v_contrat.statut IN ('ANNULE', 'EXPIRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INACTIF',
      'error', 'Ce contrat n''est plus actif (statut : ' || v_contrat.statut || ').');
  END IF;
  IF v_contrat.statut = 'SIGNE_COMPLET' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_DEJA_COMPLET',
      'error', 'Ce contrat est déjà entièrement signé.');
  END IF;
  IF v_contrat.soignant_id = v_uid THEN
    v_role := 'soignant';
    SELECT telephone INTO v_telephone FROM public.soignants WHERE id = v_uid;
  ELSIF v_contrat.etablissement_id = v_uid OR mon_etablissement_id() = v_contrat.etablissement_id THEN
    v_role := 'etablissement';
    SELECT telephone_contact INTO v_telephone FROM public.etablissements WHERE id = v_contrat.etablissement_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE', 'error', 'Non autorisé à signer ce contrat');
  END IF;
  IF v_role = 'etablissement' AND v_contrat.signature_soignant IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ETAB_AVANT_SOIGNANT',
      'error', 'Le soignant doit signer en premier. Vous serez notifié(e) par email dès qu''il aura signé.');
  END IF;
  IF v_telephone IS NULL OR v_telephone = '' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TELEPHONE_MANQUANT',
      'error', 'Numéro de téléphone manquant. Mettez à jour votre profil avant de signer.');
  END IF;
  SELECT sms_envoyes_count, sms_premier_envoi_a, statut_signature INTO v_sig_existante
  FROM public.signatures_contrats WHERE contrat_id = p_contrat_id AND signataire_role = v_role;
  IF FOUND THEN
    IF v_sig_existante.statut_signature = 'signe' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_SIGNE', 'error', 'Vous avez déjà signé ce contrat.');
    END IF;
    IF v_sig_existante.sms_premier_envoi_a IS NULL OR v_sig_existante.sms_premier_envoi_a < NOW() - INTERVAL '24 hours' THEN
      v_sms_count := 1; v_sms_window_start := NOW();
    ELSE
      v_sms_count := COALESCE(v_sig_existante.sms_envoyes_count, 0) + 1;
      v_sms_window_start := v_sig_existante.sms_premier_envoi_a;
      IF v_sms_count > 3 THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_SMS',
          'error', 'Trop de SMS envoyés (3 max / 24h).',
          'sms_envoyes', v_sms_count - 1,
          'reset_le', (v_sig_existante.sms_premier_envoi_a + INTERVAL '24 hours')::text);
      END IF;
    END IF;
  ELSE
    v_sms_count := 1; v_sms_window_start := NOW();
  END IF;
  v_otp := lpad(floor(random() * 1000000)::text, 6, '0');
  v_otp_hash := encode(digest(v_otp || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');
  INSERT INTO public.signatures_contrats (
    contrat_id, signataire_user_id, signataire_role,
    otp_envoye_a, otp_code_hash, statut_signature, audit_trail,
    sms_envoyes_count, sms_premier_envoi_a
  ) VALUES (
    p_contrat_id, v_uid, v_role, NOW(), v_otp_hash, 'otp_envoye',
    jsonb_build_object('otp_envoye_le', NOW()::text, 'sms_count', v_sms_count, 'ip', v_ip::text),
    v_sms_count, v_sms_window_start
  )
  ON CONFLICT (contrat_id, signataire_role) DO UPDATE SET
    otp_envoye_a = NOW(), otp_code_hash = EXCLUDED.otp_code_hash,
    otp_tentatives = 0, statut_signature = 'otp_envoye',
    sms_envoyes_count = v_sms_count, sms_premier_envoi_a = v_sms_window_start,
    modifie_le = NOW(),
    audit_trail = COALESCE(signatures_contrats.audit_trail, '{}'::jsonb) ||
      jsonb_build_object('otp_renvoye_le', NOW()::text, 'sms_count', v_sms_count, 'ip', v_ip::text);
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-sms',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
      body := jsonb_build_object('telephone', v_telephone, 'type', 'OTP_SIGNATURE',
        'contenu', 'Code de signature Jolene : ' || v_otp || ' (valide 10 min). Ne le partagez avec personne.',
        'destinataire_id', v_uid, 'prefix_type', 'SIGNATURE')
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN jsonb_build_object('success', true, 'role', v_role,
    'telephone_masked', regexp_replace(v_telephone, '\d(?=\d{2})', '*', 'g'),
    'expire_dans_minutes', 10,
    'sms_envoyes', v_sms_count, 'sms_restants', GREATEST(0, 3 - v_sms_count));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_telephone(p_telephone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_code text;
  v_code_hash text;
  v_otp_id uuid;
  v_count_24h int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  -- Format téléphone E164 simplifié (sans pays pour MVP, regex large)
  IF p_telephone IS NULL OR p_telephone !~ '^\+?[0-9 ]{9,15}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TELEPHONE_INVALIDE',
                                'error', 'Téléphone invalide. Format attendu : +33 6 12 34 56 78');
  END IF;

  -- Rate limit 3 SMS / 24h par user (anti-abus)
  SELECT COUNT(*) INTO v_count_24h FROM public.otps_telephone
  WHERE user_id = v_uid AND cree_le > NOW() - INTERVAL '24 hours';
  IF v_count_24h >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RATE_LIMIT',
                                'error', 'Trop d''envois (3 SMS / 24h max). Réessayez plus tard.');
  END IF;

  -- Génération code 6 chiffres
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  -- Hash bcrypt pour stockage (jamais le code en clair)
  v_code_hash := extensions.crypt(v_code, extensions.gen_salt('bf', 8));

  INSERT INTO public.otps_telephone (user_id, telephone, code_hash)
  VALUES (v_uid, p_telephone, v_code_hash)
  RETURNING id INTO v_otp_id;

  -- Mémoriser le numéro en attente sur le profil
  UPDATE public.soignants SET telephone_en_attente_verification = p_telephone WHERE id = v_uid;
  UPDATE public.etablissements SET telephone_en_attente_verification = p_telephone
    WHERE id = public.mon_etablissement_id();

  -- Audit + déclenchement Twilio via externalisation_actions
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('SMS_NOTIF', jsonb_build_object(
    'telephone', p_telephone,
    'type', 'OTP_VERIFICATION_TELEPHONE',
    'data', jsonb_build_object('code', v_code, 'expire_min', 10)
  ), 'AUTRE', v_otp_id);

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'otp_telephone', v_otp_id,
    jsonb_build_object('evenement', 'OTP_TELEPHONE_ENVOYE', 'telephone', p_telephone)
  );

  RETURN jsonb_build_object('success', true, 'otp_id', v_otp_id, 'expire_min', 10);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_est_contexte_cron_ou_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    auth.uid() IS NULL
    OR public.est_admin()
    OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role';
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_escalade_remplacement_non_pourvu()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_s uuid;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
  v_escalades int := 0;
  v_notifies int := 0;
  v_notifies_mission int;
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL; END;

  FOR v_m IN
    SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng, e.adresse_ville AS etab_ville
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.remplacement_de_mission_id IS NOT NULL
      AND m.est_urgente = TRUE
      AND m.statut = 'OUVERTE'
      AND m.cree_le < NOW() - INTERVAL '20 minutes'
      AND m.cree_le > NOW() - INTERVAL '4 hours'
      AND m.debut_le > NOW() - INTERVAL '15 minutes'
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id)
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.type_destinataire = 'ADMIN' AND n.type = 'SYSTEM'
          AND n.titre LIKE 'Remplacement non pourvu%'
          AND n.id_ressource = m.id
          AND n.cree_le > NOW() - INTERVAL '4 hours')
  LOOP
    v_escalades := v_escalades + 1;
    v_notifies_mission := 0;
    v_corps := fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', URGENT à ' ||
               COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. Toujours disponible, acceptez en 1 clic !';

    -- 1. Élargissement : tous compatibles dans un rayon élargi (jusqu'à 80 km),
    --    pas encore notifiés pour cette mission (dédup sur la ressource, tous canaux).
    FOR v_s IN
      SELECT s.id
      FROM soignants s
      WHERE s.profession = v_m.profession_requise
        AND s.supprime_le IS NULL
        AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
        AND COALESCE(s.tous_documents_valides, false)
        AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
        AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng) <= 80000)
        AND NOT EXISTS (
          SELECT 1 FROM notifications n2
          WHERE n2.destinataire_id = s.id
            AND n2.type_ressource = 'mission' AND n2.id_ressource = v_m.id)
      LIMIT 300
    LOOP
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
      VALUES (v_s, 'POOL_URGENCE', '🚨 Remplacement urgent — toujours à pourvoir',
        v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT', 'mission', v_m.id);
      v_notifies_mission := v_notifies_mission + 1;

      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_s, 'type_evenement', 'MISSION_URGENTE',
              'titre', '🚨 Remplacement urgent à pourvoir', 'corps', v_corps,
              'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/pool-urgence')
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;
    END LOOP;
    v_notifies := v_notifies + v_notifies_mission;

    -- 2. Alerte admin (admins via auth.users meta role). Enveloppée pour ne pas tuer la boucle.
    BEGIN
      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
      SELECT uid, 'ADMIN', 'SYSTEM',
        'Remplacement non pourvu — action requise 🚨',
        'La mission de remplacement "' || fn_html_escape(v_m.intitule) || '" (' || COALESCE(v_m.etab_ville, '') ||
        ') reste SANS candidat 20 min après diffusion. Rayon élargi à 80 km + pool relancé. Une intervention manuelle (appel, pool dédié) est conseillée.',
        '/admin/missions', 'mission', v_m.id
      FROM unnest(ARRAY(SELECT id FROM public.fn_list_admin_user_ids())) AS uid;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_m.etablissement_id, p_type_acteur := 'SYSTEME',
      p_action := 'REMPLACEMENT_ESCALADE', p_type_ressource := 'mission', p_id_ressource := v_m.id,
      p_details := jsonb_build_object('notifies_elargis', v_notifies_mission, 'rayon_km', 80)
    );
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'escalades', v_escalades, 'notifies', v_notifies);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_envoyer_message_contact(p_sujet text, p_corps text, p_source text DEFAULT 'aide'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_role text; v_nom text; v_email text;
  v_msg_id uuid;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  IF p_sujet IS NULL OR length(trim(p_sujet)) = 0 OR p_corps IS NULL OR length(trim(p_corps)) = 0 THEN
    RETURN jsonb_build_object('error', 'Sujet et message obligatoires');
  END IF;

  SELECT prenom || ' ' || nom, email INTO v_nom, v_email FROM soignants WHERE id = v_uid;
  IF v_nom IS NOT NULL THEN
    v_role := 'SOIGNANT';
  ELSE
    SELECT nom, email_contact INTO v_nom, v_email FROM etablissements WHERE id = v_uid;
    IF v_nom IS NOT NULL THEN v_role := 'ETABLISSEMENT'; END IF;
  END IF;

  INSERT INTO messages_contact (expediteur_id, expediteur_role, expediteur_nom, expediteur_email, sujet, corps, source)
  VALUES (v_uid, COALESCE(v_role, 'INCONNU'), v_nom, v_email,
          fn_html_escape(trim(p_sujet)), fn_html_escape(trim(p_corps)), COALESCE(p_source, 'aide'))
  RETURNING id INTO v_msg_id;

  -- Notif in-app admins (auth.users meta role). Enveloppée : une erreur de notif ne
  -- doit jamais faire perdre le message de contact.
  BEGIN
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    SELECT uid, 'ADMIN', 'MESSAGE_ADMIN',
      '✉️ Nouveau message — ' || COALESCE(v_nom, 'utilisateur'),
      left(trim(p_corps), 140),
      '/admin/messages-contact', 'message_contact', v_msg_id
    FROM unnest(ARRAY(SELECT id FROM public.fn_list_admin_user_ids())) AS uid;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
    IF v_token IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-support',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
        body := jsonb_build_object(
          'sujet', trim(p_sujet), 'corps', trim(p_corps),
          'expediteur_nom', v_nom, 'expediteur_email', v_email,
          'source', 'Contact ' || COALESCE(v_role, ''), 'lien', '/admin/messages-contact'
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('success', true, 'message_id', v_msg_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_est_jour_ferie(p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM jours_feries_fr WHERE date_ferie = p_date
    );
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etablissement_pour_soignant(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- Verify caller is a soignant with a mission at this establishment
  IF NOT est_soignant() THEN
    RAISE EXCEPTION 'Accès réservé aux soignants';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM missions
    WHERE etablissement_id = p_etablissement_id
      AND soignant_assigne_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Aucune mission associée à cet établissement';
  END IF;

  SELECT jsonb_build_object(
    'id', e.id,
    'nom', e.nom,
    'type', e.type,
    'adresse_rue', e.adresse_rue,
    'adresse_ville', e.adresse_ville,
    'adresse_code_postal', e.adresse_code_postal,
    'adresse_departement', e.adresse_departement,
    'adresse_lat', e.adresse_lat,
    'adresse_lng', e.adresse_lng,
    'telephone_contact', e.telephone_contact,
    'email_contact', e.email_contact
  ) INTO v_result
  FROM etablissements e
  WHERE e.id = p_etablissement_id AND e.supprime_le IS NULL;

  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_est_exclu_par_etablissement(p_etablissement_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM exclusions
    WHERE (exclu_id = auth.uid() AND exclu_par = p_etablissement_id)
       OR (exclu_par = auth.uid() AND exclu_id = p_etablissement_id)
  )
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_est_exclu(p_soignant_id uuid, p_etablissement_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM exclusions
        WHERE (exclu_par = p_etablissement_id AND exclu_id = p_soignant_id)
           OR (exclu_par = p_soignant_id AND exclu_id = p_etablissement_id)
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etablissement_pour_mission(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT EXISTS(
        SELECT 1 FROM missions 
        WHERE etablissement_id = p_etablissement_id 
        AND (statut = 'OUVERTE' OR soignant_assigne_id = auth.uid())
    ) AND mon_etablissement_id() != p_etablissement_id AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT jsonb_build_object(
        'id', id, 'nom', nom, 'type', type::TEXT,
        'adresse_ville', adresse_ville, 'adresse_code_postal', adresse_code_postal,
        'adresse_departement', adresse_departement, 'adresse_rue', adresse_rue,
        'adresse_lat', adresse_lat, 'adresse_lng', adresse_lng,
        'note_moyenne', note_moyenne, 'convention_collective', convention_collective,
        'est_secteur_public', est_secteur_public, 'finess', finess
    ) INTO v_result
    FROM etablissements WHERE id = p_etablissement_id AND supprime_le IS NULL;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Établissement introuvable'));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etablissement_public(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN (
        SELECT jsonb_build_object(
            'id', id, 'nom', nom, 'type', type::TEXT,
            'adresse_ville', adresse_ville, 'adresse_code_postal', adresse_code_postal,
            'adresse_departement', adresse_departement, 'adresse_rue', adresse_rue,
            'adresse_lat', adresse_lat, 'adresse_lng', adresse_lng,
            'note_moyenne', note_moyenne, 'convention_collective', convention_collective,
            'est_secteur_public', est_secteur_public, 'finess', finess,
            'logo_url', logo_url, 'couleur_theme', couleur_theme
        )
        FROM etablissements 
        WHERE id = p_etablissement_id AND supprime_le IS NULL
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etab_valider_acceptation_urgence(p_candidature_id uuid, p_action text, p_motif_refus text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID;
  v_cand RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_action NOT IN ('VALIDER', 'REFUSER') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Action invalide (VALIDER ou REFUSER)');
  END IF;

  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
    END IF;
  END IF;

  SELECT c.*, m.etablissement_id, m.statut AS mission_statut, m.intitule AS mission_intitule
  INTO v_cand
  FROM candidatures c
  JOIN missions m ON m.id = c.mission_id
  WHERE c.id = p_candidature_id;

  IF v_cand IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Candidature introuvable');
  END IF;

  IF NOT est_admin() AND v_cand.etablissement_id <> v_etab_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cette candidature n''appartient pas à votre étab');
  END IF;

  IF v_cand.statut <> 'EN_ATTENTE_VALIDATION_ETAB' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Candidature déjà traitée (statut: ' || v_cand.statut || ')');
  END IF;

  IF p_action = 'VALIDER' THEN
    IF v_cand.mission_statut <> 'OUVERTE' THEN
      RETURN jsonb_build_object('success', false, 'error', 'Mission n''est plus disponible');
    END IF;

    UPDATE missions
    SET statut = 'ASSIGNEE',
        soignant_assigne_id = v_cand.soignant_id
    WHERE id = v_cand.mission_id;

    UPDATE candidatures
    SET statut = 'ACCEPTEE', traite_le = NOW()
    WHERE id = p_candidature_id;

    UPDATE candidatures
    SET statut = 'REFUSEE', traite_le = NOW(),
        motif_refus = COALESCE(motif_refus, 'Mission attribuée à un autre soignant')
    WHERE mission_id = v_cand.mission_id
      AND id <> p_candidature_id
      AND statut IN ('EN_ATTENTE','EN_ATTENTE_VALIDATION_ETAB','PROPOSEE');

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_cand.soignant_id, 'SOIGNANT', 'MISSION_ASSIGNEE',
      '✅ Mission urgente confirmée',
      'L''établissement a validé votre acceptation. Mission "' || v_cand.mission_intitule || '" assignée.',
      '/soignant/missions/' || v_cand.mission_id::text,
      'mission', v_cand.mission_id
    );

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_uid,
      p_type_acteur := 'ADMIN_ETABLISSEMENT',
      p_action := 'POOL_URGENCE_VALIDATION_ETAB',
      p_type_ressource := 'candidature',
      p_id_ressource := p_candidature_id,
      p_details := jsonb_build_object('mission_id', v_cand.mission_id, 'soignant_id', v_cand.soignant_id)
    );

    RETURN jsonb_build_object('success', true, 'action', 'VALIDER', 'mission_id', v_cand.mission_id);
  ELSE
    UPDATE candidatures
    SET statut = 'REFUSEE', traite_le = NOW(),
        motif_refus = COALESCE(p_motif_refus, 'Candidature refusée par l''établissement')
    WHERE id = p_candidature_id;

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    VALUES (
      v_cand.soignant_id, 'SOIGNANT', 'CANDIDATURE_REFUSEE',
      'Acceptation pool urgence refusée',
      'L''établissement a refusé votre acceptation. Motif : '
        || COALESCE(p_motif_refus, 'non précisé') || '.',
      '/soignant/pool-urgence',
      'candidature', p_candidature_id
    );

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_uid,
      p_type_acteur := 'ADMIN_ETABLISSEMENT',
      p_action := 'POOL_URGENCE_REFUS_ETAB',
      p_type_ressource := 'candidature',
      p_id_ressource := p_candidature_id,
      p_details := jsonb_build_object('mission_id', v_cand.mission_id, 'motif', p_motif_refus)
    );

    RETURN jsonb_build_object('success', true, 'action', 'REFUSER');
  END IF;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_est_etab_test(p_etab_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM etablissements e WHERE e.id = p_etab_id AND e.est_compte_test);
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_evaluer_etablissement(p_mission_id uuid, p_note integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'TERMINEE' THEN RETURN jsonb_build_object('error', 'La mission doit être terminée pour évaluer'); END IF;
    IF v_mission.soignant_assigne_id != auth.uid() THEN RETURN jsonb_build_object('error', 'Non autorisé'); END IF;
    IF p_note < 1 OR p_note > 5 THEN RETURN jsonb_build_object('error', 'La note doit être entre 1 et 5'); END IF;

    IF EXISTS (SELECT 1 FROM evaluations WHERE mission_id = p_mission_id AND evaluateur_id = auth.uid()) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà évalué cette mission');
    END IF;

    INSERT INTO evaluations (mission_id, evaluateur_id, evalue_id, type_evaluateur, note, commentaire, visible)
    VALUES (p_mission_id, auth.uid(), v_mission.etablissement_id, 'SOIGNANT', p_note, p_commentaire, TRUE);

    RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etablissements_avec_missions_ouvertes()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', e.id, 'nom', e.nom, 'type', e.type::TEXT,
            'adresse_ville', e.adresse_ville, 'adresse_code_postal', e.adresse_code_postal,
            'adresse_departement', e.adresse_departement, 'adresse_rue', e.adresse_rue,
            'adresse_lat', e.adresse_lat, 'adresse_lng', e.adresse_lng,
            'note_moyenne', e.note_moyenne, 'convention_collective', e.convention_collective,
            'est_secteur_public', e.est_secteur_public, 'finess', e.finess
        )), '[]'::JSONB)
        FROM etablissements e
        WHERE e.supprime_le IS NULL
        AND e.statut_verification = 'VERIFIE'
        AND EXISTS(SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE')
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_evaluer_alertes_filtres(p_frequence text DEFAULT NULL::text)
 RETURNS TABLE(filtre_id uuid, utilisateur_id uuid, audience filtre_audience, nom text, nb_nouveaux integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  r RECORD;
  v_count integer;
BEGIN
  FOR r IN
    SELECT * FROM filtres_sauvegardes
    WHERE alerte_active = true
      AND (
        (p_frequence IS NULL OR frequence_alerte::text = p_frequence)
        AND (
          (frequence_alerte = 'QUOTIDIENNE'   AND dernier_check_le < now() - interval '23 hours') OR
          (frequence_alerte = 'HEBDOMADAIRE'  AND dernier_check_le < now() - interval '6 days 23 hours') OR
          (frequence_alerte = 'IMMEDIATE'     AND dernier_check_le < now() - interval '55 minutes')
        )
      )
  LOOP
    v_count := fn_compter_nouveaux_pour_filtre(r.id, r.dernier_check_le);
    UPDATE filtres_sauvegardes
    SET dernier_check_le = now(),
        nb_resultats_dernier_check = v_count
    WHERE id = r.id;
    IF v_count > 0 THEN
      -- 6c.4 : notification in-app/push (soignant) avec deep-link direct dans
      -- le deck de swipe. L'email (pipeline existant) part en parallèle via
      -- les lignes retournées par cette fonction.
      -- 7d-A2 : CAP DE FRÉQUENCE — au plus une notification MISSION_A_POURVOIR
      -- par 20 h et par soignant, toutes recherches confondues (anti-spam).
      IF r.audience = 'SOIGNANT_RECHERCHE_MISSIONS' AND NOT EXISTS (
        SELECT 1 FROM notifications n
         WHERE n.destinataire_id = r.utilisateur_id
           AND n.type = 'MISSION_A_POURVOIR'
           AND n.cree_le > now() - interval '20 hours'
      ) THEN
        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
        VALUES (
          r.utilisateur_id, 'SOIGNANT', 'MISSION_A_POURVOIR',
          '✨ ' || v_count || ' nouvelle' || CASE WHEN v_count > 1 THEN 's' ELSE '' END
            || ' mission' || CASE WHEN v_count > 1 THEN 's' ELSE '' END
            || ' pour « ' || r.nom || ' »',
          'De nouvelles missions correspondent à ta recherche sauvegardée — découvre-les avant les autres.',
          '/soignant/recherche-missions?vue=swipe'
        );
      END IF;

      filtre_id := r.id;
      utilisateur_id := r.utilisateur_id;
      audience := r.audience;
      nom := r.nom;
      nb_nouveaux := v_count;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_evaluer_coherence_pointage(p_pointage_arrivee timestamp with time zone, p_pointage_depart timestamp with time zone, p_mission_debut timestamp with time zone, p_mission_fin timestamp with time zone, p_duree_nette_min numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE v_incidents jsonb := '[]'::jsonb;
BEGIN
  IF p_pointage_arrivee IS NOT NULL AND p_pointage_arrivee < p_mission_debut - INTERVAL '1 hour' THEN
    v_incidents := v_incidents || jsonb_build_object('code', 'ARRIVEE_TROP_PRECOCE', 'severite', 'WARNING',
      'message', 'Arrivée pointée plus d''1h avant le début prévu',
      'ecart_min', EXTRACT(EPOCH FROM (p_mission_debut - p_pointage_arrivee))/60);
  END IF;
  IF p_pointage_arrivee IS NOT NULL AND p_pointage_arrivee > p_mission_fin THEN
    v_incidents := v_incidents || jsonb_build_object('code', 'ARRIVEE_APRES_FIN', 'severite', 'CRITICAL',
      'message', 'Arrivée pointée après l''heure de fin de mission',
      'ecart_min', EXTRACT(EPOCH FROM (p_pointage_arrivee - p_mission_fin))/60);
  END IF;
  IF p_pointage_arrivee IS NOT NULL AND p_pointage_depart IS NOT NULL
     AND p_pointage_depart < p_pointage_arrivee THEN
    v_incidents := v_incidents || jsonb_build_object('code', 'DEPART_AVANT_ARRIVEE', 'severite', 'CRITICAL',
      'message', 'Heure de départ antérieure à l''arrivée');
  END IF;
  IF p_pointage_depart IS NOT NULL AND p_pointage_depart < p_mission_fin - INTERVAL '4 hours' THEN
    v_incidents := v_incidents || jsonb_build_object('code', 'DEPART_TRES_ANTICIPE', 'severite', 'WARNING',
      'message', 'Départ pointé plus de 4h avant la fin prévue',
      'ecart_min', EXTRACT(EPOCH FROM (p_mission_fin - p_pointage_depart))/60);
  END IF;
  IF p_pointage_depart IS NOT NULL AND p_pointage_depart > p_mission_fin + INTERVAL '4 hours' THEN
    v_incidents := v_incidents || jsonb_build_object('code', 'DEPART_TRES_TARDIF', 'severite', 'WARNING',
      'message', 'Départ pointé plus de 4h après la fin prévue',
      'ecart_min', EXTRACT(EPOCH FROM (p_pointage_depart - p_mission_fin))/60);
  END IF;
  IF p_duree_nette_min IS NOT NULL THEN
    IF p_duree_nette_min <= 0 THEN
      v_incidents := v_incidents || jsonb_build_object('code', 'DUREE_NULLE', 'severite', 'CRITICAL',
        'message', 'Durée nette de mission <= 0 minutes');
    ELSIF p_duree_nette_min > 1440 THEN
      v_incidents := v_incidents || jsonb_build_object('code', 'DUREE_EXCESSIVE', 'severite', 'WARNING',
        'message', 'Durée nette de mission > 24h', 'duree_min', p_duree_nette_min);
    END IF;
  END IF;
  RETURN v_incidents;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etat_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_etapes jsonb;
  v_termine_le timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    SELECT onboarding_etapes_completees, onboarding_termine_le
    INTO v_etapes, v_termine_le
    FROM public.soignants WHERE id = v_uid;
    RETURN jsonb_build_object('success', true, 'role', 'SOIGNANT',
                                'etapes', v_etapes,
                                'termine_le', v_termine_le);
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    SELECT onboarding_etapes_completees, onboarding_termine_le
    INTO v_etapes, v_termine_le
    FROM public.etablissements WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', true, 'role', 'ETAB',
                                'etapes', v_etapes,
                                'termine_le', v_termine_le);
  END IF;

  RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_evaluer_rattachement_etablissement(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab RECORD;
  v_methode text := 'ADMIN';
  v_verifie boolean := false;
  v_match boolean := false;
BEGIN
  IF NOT (est_admin() OR p_etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT finess_est_public, dirigeants, representant_nom, representant_prenom,
         representant_identite_verifiee, justificatif_fonction_verifie
  INTO v_etab FROM public.etablissements WHERE id = p_etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  -- 1) AUTO_DIRIGEANT : identité vérifiée + match avec un dirigeant personne physique.
  IF v_etab.representant_identite_verifiee IS TRUE
     AND v_etab.representant_nom IS NOT NULL
     AND v_etab.dirigeants IS NOT NULL THEN
    SELECT TRUE INTO v_match
    FROM jsonb_array_elements(v_etab.dirigeants) AS d
    WHERE public.fn_normaliser_nom(d->>'type_dirigeant') LIKE '%physique%'
      AND public.fn_normaliser_nom(d->>'nom') = public.fn_normaliser_nom(v_etab.representant_nom)
      AND (
        v_etab.representant_prenom IS NULL
        OR public.fn_normaliser_nom(d->>'prenoms') LIKE '%' || public.fn_normaliser_nom(v_etab.representant_prenom) || '%'
      )
    LIMIT 1;
    IF v_match IS TRUE THEN
      v_methode := 'AUTO_DIRIGEANT'; v_verifie := TRUE;
    END IF;
  END IF;

  -- 2) JUSTIFICATIF : identité vérifiée + justificatif de fonction authentifié IA
  --    (cas du non-dirigeant : RH, chef de service, délégataire).
  IF NOT v_verifie
     AND v_etab.representant_identite_verifiee IS TRUE
     AND v_etab.justificatif_fonction_verifie IS TRUE THEN
    v_methode := 'JUSTIFICATIF'; v_verifie := TRUE;
  END IF;

  -- 3) sinon ADMIN (revue manuelle).

  UPDATE public.etablissements SET
    rattachement_methode = v_methode,
    rattachement_verifie = v_verifie,
    rattachement_verifie_le = CASE WHEN v_verifie THEN now() ELSE NULL END
  WHERE id = p_etablissement_id;

  RETURN jsonb_build_object('success', true, 'methode', v_methode, 'verifie', v_verifie, 'match_dirigeant', COALESCE(v_match, false));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etat_pointage_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_etablissements_safe(p_ids uuid[])
 RETURNS TABLE(id uuid, nom text, adresse_rue text, adresse_code_postal text, adresse_ville text, adresse_departement text, adresse_lat numeric, adresse_lng numeric, type text, finess text, taux_majoration_nuit_pourcent numeric, taux_majoration_dimanche_pourcent numeric, taux_majoration_ferie_pourcent numeric, logo_url text, couleur_theme text, paiement_rapide boolean, jour_paie_habituel smallint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        e.id, e.nom::TEXT, e.adresse_rue::TEXT, e.adresse_code_postal::TEXT,
        e.adresse_ville::TEXT, e.adresse_departement::TEXT, e.adresse_lat, e.adresse_lng,
        e.type::TEXT, e.finess::TEXT,
        e.taux_majoration_nuit_pourcent, e.taux_majoration_dimanche_pourcent,
        e.taux_majoration_ferie_pourcent, e.logo_url::TEXT, e.couleur_theme::TEXT,
        -- 7c : capacité ⚡ de l'ÉTABLISSEMENT (flag + SEPA). La condition mission
        -- LIBERAL est appliquée par le consommateur (le régime est une propriété
        -- de la mission, jamais de l'établissement).
        (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1
         AND e.mode_paiement_commission = 'SEPA_DEBIT'
         AND e.stripe_sepa_payment_method_id IS NOT NULL) AS paiement_rapide,
        e.jour_paie_habituel
    FROM etablissements e
    WHERE e.id = ANY(p_ids)
      AND (
        EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.soignant_assigne_id = auth.uid())
        OR EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE')
        OR e.id = mon_etablissement_id()
        OR est_admin()
      );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_exclure_utilisateur(p_exclu_id uuid, p_type text, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid := auth.uid();
  v_type_acteur text;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  IF p_type NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Type invalide');
  END IF;

  -- Prevent self-exclusion
  IF v_caller_id = p_exclu_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Impossible de s''exclure soi-même');
  END IF;

  -- Check duplicate
  IF EXISTS (SELECT 1 FROM exclusions WHERE exclu_par = v_caller_id AND exclu_id = p_exclu_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Exclusion déjà existante');
  END IF;

  INSERT INTO exclusions (exclu_id, exclu_par, type_exclu_par, motif)
  VALUES (p_exclu_id, v_caller_id, p_type, p_motif);

  -- Determine actor type
  IF p_type = 'ETABLISSEMENT' THEN
    v_type_acteur := 'ADMIN_ETABLISSEMENT';
  ELSE
    v_type_acteur := 'SOIGNANT';
  END IF;

  -- Audit
  PERFORM fn_ecrire_audit_safe(
    v_caller_id, v_type_acteur, 'EXCLUSION_CREEE',
    'exclusion', p_exclu_id, NULL,
    jsonb_build_object('type_exclu_par', p_type, 'motif', COALESCE(p_motif, '')),
    NULL, 'rpc'
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_evaluer_soignant(p_mission_id uuid, p_note integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_etab_id UUID;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN RETURN jsonb_build_object('error', 'Non autorisé'); END IF;

    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'TERMINEE' THEN RETURN jsonb_build_object('error', 'La mission doit être terminée pour évaluer'); END IF;
    IF v_mission.etablissement_id != v_etab_id AND NOT est_admin() THEN RETURN jsonb_build_object('error', 'Non autorisé'); END IF;
    IF v_mission.soignant_assigne_id IS NULL THEN RETURN jsonb_build_object('error', 'Aucun soignant assigné'); END IF;
    IF p_note < 1 OR p_note > 5 THEN RETURN jsonb_build_object('error', 'La note doit être entre 1 et 5'); END IF;

    -- Vérifier pas déjà évalué
    IF EXISTS (SELECT 1 FROM evaluations WHERE mission_id = p_mission_id AND evaluateur_id = v_etab_id) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà évalué cette mission');
    END IF;

    INSERT INTO evaluations (mission_id, evaluateur_id, evalue_id, type_evaluateur, note, commentaire, visible)
    VALUES (p_mission_id, v_etab_id, v_mission.soignant_assigne_id, 'ETABLISSEMENT', p_note, p_commentaire, TRUE);

    -- Notifier le soignant
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_mission.soignant_assigne_id, 'SYSTEM', 
        '⭐ Nouvelle évaluation',
        'Vous avez reçu une évaluation ' || p_note || '/5 pour la mission "' || v_mission.intitule || '".',
        '/soignant/evaluations', 'SOIGNANT');

    RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_export_fec(p_annee integer)
 RETURNS TABLE(journal_code text, journal_libelle text, ecriture_num text, ecriture_date text, compte_num text, compte_libelle text, comp_aux_num text, comp_aux_libelle text, piece_ref text, piece_date text, ecriture_libelle text, debit numeric, credit numeric, montant numeric, devise text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        'VE'::TEXT, 'Ventes'::TEXT,
        f.numero_facture,
        TO_CHAR(f.date_emission, 'YYYYMMDD'),
        '706000'::TEXT, 'Prestations de services'::TEXT,
        e.siret::TEXT, e.nom,
        f.numero_facture, TO_CHAR(f.date_emission, 'YYYYMMDD'),
        'Commission Jolene'::TEXT,
        0::NUMERIC, f.montant_ht,
        f.montant_ttc, 'EUR'::TEXT
    FROM factures f
    JOIN etablissements e ON e.id = f.etablissement_id
    WHERE EXTRACT(YEAR FROM f.date_emission) = p_annee
    ORDER BY f.date_emission;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_evolution_missions_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID;
  v_result JSONB;
  v_six_mois_ago DATE;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  END IF;

  v_six_mois_ago := DATE_TRUNC('month', NOW() - INTERVAL '5 months')::DATE;

  WITH mois_serie AS (
    SELECT (v_six_mois_ago + (n || ' months')::interval)::date AS mois_debut,
           (v_six_mois_ago + ((n+1) || ' months')::interval)::date AS mois_fin,
           TO_CHAR(v_six_mois_ago + (n || ' months')::interval, 'YYYY-MM') AS mois_label
    FROM generate_series(0, 5) AS n
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', ms.mois_label,
    'publiees', (
      SELECT COUNT(*) FROM missions m
      WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
        AND m.cree_le >= ms.mois_debut AND m.cree_le < ms.mois_fin
    ),
    'assignees', (
      SELECT COUNT(*) FROM missions m
      WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
        AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE')
        AND m.cree_le >= ms.mois_debut AND m.cree_le < ms.mois_fin
    ),
    'terminees', (
      SELECT COUNT(*) FROM missions m
      WHERE (v_etab_id IS NULL OR m.etablissement_id = v_etab_id)
        AND m.statut = 'TERMINEE'
        AND m.fin_le >= ms.mois_debut AND m.fin_le < ms.mois_fin
    )
  ) ORDER BY ms.mois_label), '[]'::jsonb)
  INTO v_result
  FROM mois_serie ms;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_evolution_score_soignant(p_limit integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
  v_limit INT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 6), 1), 50);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', mois_label, 'score', ROUND(score::numeric, 1),
    'niveau', niveau, 'cree_le', cree_le
  ) ORDER BY mois_label ASC), '[]'::jsonb) INTO v_result
  FROM (
    SELECT DISTINCT ON (TO_CHAR(cree_le, 'YYYY-MM'))
      TO_CHAR(cree_le, 'YYYY-MM') AS mois_label,
      score_total AS score, niveau::text AS niveau, cree_le
    FROM scoring_breakdown
    WHERE soignant_id = v_uid AND cree_le >= NOW() - (v_limit || ' months')::interval
    ORDER BY TO_CHAR(cree_le, 'YYYY-MM'), cree_le DESC
  ) t;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_expirer_parrainages_inactifs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_count INT := 0;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  WITH expired AS (
    UPDATE parrainages SET statut = 'EXPIRED'
    WHERE statut = 'EN_ATTENTE'
      AND cree_le < NOW() - INTERVAL '12 months'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_count FROM expired;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_executer_modifications_litige(p_litige_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_litige RECORD;
  v_payload jsonb;
  v_type text;
  v_mods jsonb;
  v_presence_id uuid;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_h_arrivee timestamptz;
  v_h_depart timestamptz;
  v_uid uuid := auth.uid();
BEGIN
  -- GATE : admin OU contexte interne explicitement autorisé.
  IF NOT (public.est_admin() OR COALESCE(current_setting('jolene.litige_exec_ok', true), '') = 'true') THEN
    RETURN jsonb_build_object('success', false,
      'error', 'Exécution réservée à l''administrateur (autorisation des mouvements financiers).');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  IF v_litige.modifications_executees THEN
    RETURN jsonb_build_object('success', true, 'already_executed', true,
                                'executees_a', v_litige.modifications_executees_a);
  END IF;

  IF NOT (COALESCE(v_litige.accord_soignant, false) AND COALESCE(v_litige.accord_etablissement, false)) THEN
    IF v_litige.statut NOT IN ('RESOLU', 'RESOLU_ADMIN', 'CLOTURE') THEN
      RETURN jsonb_build_object('success', false, 'error', 'Litige sans double accord ni résolution admin');
    END IF;
  END IF;

  v_payload := v_litige.payload_modifications;
  IF v_payload IS NULL THEN
    UPDATE public.litiges SET
      modifications_executees = true, modifications_executees_a = NOW(), modifications_executees_par = v_uid
    WHERE id = p_litige_id;
    RETURN jsonb_build_object('success', true, 'type', 'ACCORD_SANS_MODIFICATION');
  END IF;

  v_type := v_payload->>'type';
  v_mods := COALESCE(v_payload->'modifications', '{}'::jsonb);
  SELECT id INTO v_presence_id FROM public.presences WHERE mission_id = v_litige.mission_id LIMIT 1;

  IF v_type = 'ACCORD_SANS_MODIFICATION' THEN
    v_results := v_results || jsonb_build_object('type', v_type, 'success', true);
  ELSIF v_type = 'MODIFICATION_HORAIRES' AND v_presence_id IS NOT NULL THEN
    v_h_arrivee := (v_mods->>'pointage_arrivee_le')::timestamptz;
    v_h_depart := (v_mods->>'pointage_depart_le')::timestamptz;
    IF v_h_arrivee IS NULL OR v_h_depart IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'pointage_arrivee_le et pointage_depart_le requis pour MODIFICATION_HORAIRES');
    END IF;
    v_result := public.fn_modifier_horaires_presence(v_presence_id, v_h_arrivee, v_h_depart, v_payload->>'justification');
    v_results := v_results || v_result;
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'AJUSTEMENT_HORAIRES', 'motif_avoir', 'MODIFICATION_HORAIRES'), 'LITIGE_EXEC', p_litige_id);
  ELSIF v_type = 'ANNULATION_TOTALE' THEN
    v_result := public.fn_annuler_mission_complete(v_litige.mission_id, v_payload->>'justification', p_litige_id);
    v_results := v_results || v_result;
  ELSIF v_type = 'COMPENSATION_PARTIELLE' THEN
    v_result := public.fn_appliquer_compensation_partielle(v_litige.mission_id, (v_mods->>'pourcentage_compensation')::numeric, v_payload->>'justification', p_litige_id);
    v_results := v_results || v_result;
  ELSIF v_type = 'MODIFICATION_MONTANT' THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'MODIFICATION_MONTANT', 'nouveau_montant', v_mods->>'montant_total_corrige', 'motif_avoir', 'MODIFICATION_HORAIRES'), 'LITIGE_EXEC', p_litige_id);
    v_results := v_results || jsonb_build_object('type', v_type, 'success', true, 'nouveau_montant', v_mods->>'montant_total_corrige');
  ELSIF v_type = 'MIXTE' THEN
    IF v_presence_id IS NOT NULL AND v_mods ? 'pointage_arrivee_le' AND v_mods ? 'pointage_depart_le' THEN
      v_h_arrivee := (v_mods->>'pointage_arrivee_le')::timestamptz;
      v_h_depart := (v_mods->>'pointage_depart_le')::timestamptz;
      v_result := public.fn_modifier_horaires_presence(v_presence_id, v_h_arrivee, v_h_depart, v_payload->>'justification');
      v_results := v_results || v_result;
    END IF;
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    VALUES ('AVOIR_PDF_GENERATION', jsonb_build_object('mission_id', v_litige.mission_id, 'type', 'MIXTE', 'motif_avoir', 'LITIGE_ACCORD_MUTUEL'), 'LITIGE_EXEC', p_litige_id);
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Type de modification non supporté : ' || COALESCE(v_type, 'NULL'));
  END IF;

  UPDATE public.litiges SET
    modifications_executees = true, modifications_executees_a = NOW(), modifications_executees_par = v_uid
  WHERE id = p_litige_id;

  INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (COALESCE(v_uid, '00000000-0000-0000-0000-000000000000'),
    CASE WHEN v_uid IS NULL THEN 'SYSTEME' ELSE 'SYSTEM' END,
    'SYSTEM', 'litige', p_litige_id,
    jsonb_build_object('evenement', 'LITIGE_MODIFICATIONS_EXECUTEES', 'type', v_type, 'mission_id', v_litige.mission_id, 'results', v_results));

  RETURN jsonb_build_object('success', true, 'type', v_type, 'results', v_results);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_expirer_candidatures_missions_demarrees()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_nb integer;
BEGIN
  UPDATE candidatures c
  SET statut = 'EXPIREE'
  FROM missions m
  WHERE m.id = c.mission_id
    AND c.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB')
    AND m.debut_le <= now();
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_exporter_rgpd_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;

    SELECT jsonb_build_object(
        'etablissement', (SELECT row_to_json(e) FROM (
            SELECT nom, type::TEXT, siret, finess, email_contact, telephone_contact,
                adresse_rue, adresse_code_postal, adresse_ville, convention_collective,
                cree_le, modifie_le
            FROM etablissements WHERE id = v_etab_id
        ) e),
        'missions', (SELECT COALESCE(jsonb_agg(row_to_json(m)), '[]') FROM (
            SELECT id, intitule, statut::TEXT, debut_le, fin_le, taux_horaire_base, total_brut, cree_le
            FROM missions WHERE etablissement_id = v_etab_id ORDER BY cree_le DESC LIMIT 200
        ) m),
        'factures', (SELECT COALESCE(jsonb_agg(row_to_json(f)), '[]') FROM (
            SELECT numero_facture, montant_ht, montant_ttc, statut, date_emission, date_paiement
            FROM factures WHERE etablissement_id = v_etab_id ORDER BY date_emission DESC
        ) f),
        'contrats', (SELECT COALESCE(jsonb_agg(row_to_json(c)), '[]') FROM (
            SELECT type_contrat, statut, cree_le, modifie_le
            FROM contrats_mission WHERE etablissement_id = v_etab_id ORDER BY cree_le DESC LIMIT 200
        ) c),
        'export_date', NOW()
    ) INTO v_result;

    RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_factor_advances_modifie_le()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN NEW.modifie_le = now(); RETURN NEW; END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_fh_auto_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN INSERT INTO invoice_audit_log (invoice_id, action, actor_id, payload_before, payload_after) VALUES (NEW.id, CASE WHEN TG_OP = 'INSERT' THEN 'CREATED' WHEN OLD.statut IS DISTINCT FROM NEW.statut THEN 'STATUS_CHANGE:' || OLD.statut || '->' || NEW.statut ELSE 'UPDATED' END, COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid), CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END, to_jsonb(NEW)); RETURN NEW; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_fh_detect_public_sector()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN IF NEW.etablissement_id IS NOT NULL THEN SELECT est_secteur_public INTO NEW.is_public_sector FROM etablissements WHERE id = NEW.etablissement_id; END IF; RETURN NEW; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_fenetre_contestation_ouverte(p_type_litige type_litige, p_mission_id uuid, p_facture_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_presence_validee TIMESTAMPTZ;
  v_facture_emise    TIMESTAMPTZ;
  v_facture_payee    TIMESTAMPTZ;
  v_mission_fin      TIMESTAMPTZ;
  v_est_salarie      BOOLEAN;
  v_type_applique    public.type_contrat_applique_enum;
  v_soignant_id      UUID;
  v_delai_pointage   INTEGER;
  v_delai_liberal    INTEGER;
  v_delai_salarie    INTEGER;
  v_delai_compo_mois INTEGER;
BEGIN
  IF p_type_litige IN ('SECURITE_DANGER', 'NON_PAIEMENT', 'AUTRE') THEN
    RETURN TRUE;
  END IF;

  SELECT valeur::INTEGER INTO v_delai_pointage   FROM public.parametres_litiges WHERE cle = 'delai_contestation_pointage_h';
  SELECT valeur::INTEGER INTO v_delai_liberal    FROM public.parametres_litiges WHERE cle = 'delai_contestation_facture_liberal_h';
  SELECT valeur::INTEGER INTO v_delai_salarie    FROM public.parametres_litiges WHERE cle = 'delai_contestation_paiement_salarie_j';
  SELECT valeur::INTEGER INTO v_delai_compo_mois FROM public.parametres_litiges WHERE cle = 'delai_comportement_mois';

  IF p_type_litige IN ('ABSENCE_SOIGNANT', 'DEPART_ANTICIPE', 'RETARD_IMPORTANT', 'DESACCORD_HEURES_POINTAGE') THEN
    SELECT valide_le INTO v_presence_validee
      FROM public.presences
     WHERE mission_id = p_mission_id
       AND valide_le IS NOT NULL
     ORDER BY valide_le DESC
     LIMIT 1;
    IF v_presence_validee IS NULL THEN
      RETURN TRUE;
    END IF;
    RETURN v_presence_validee + make_interval(hours => v_delai_pointage) > NOW();
  END IF;

  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'FRAIS_COMPLEMENTAIRES') THEN
    IF p_facture_id IS NULL THEN
      RETURN TRUE;
    END IF;

    SELECT f.date_emission, f.date_paiement
      INTO v_facture_emise, v_facture_payee
      FROM public.factures_honoraires f
     WHERE f.id = p_facture_id;

    IF v_facture_emise IS NULL THEN
      RETURN FALSE;
    END IF;

    SELECT m.soignant_assigne_id, m.type_contrat_applique
      INTO v_soignant_id, v_type_applique
      FROM public.missions m WHERE m.id = p_mission_id;

    IF v_type_applique = 'SALARIE' THEN
      v_est_salarie := TRUE;
    ELSIF v_type_applique = 'LIBERAL' THEN
      v_est_salarie := FALSE;
    ELSE
      SELECT COALESCE(s.est_salarie_etablissement, FALSE) INTO v_est_salarie
        FROM public.soignants s WHERE s.id = v_soignant_id;
    END IF;

    IF v_est_salarie AND v_facture_payee IS NOT NULL THEN
      RETURN v_facture_payee + make_interval(days => v_delai_salarie) > NOW();
    ELSE
      RETURN v_facture_emise + make_interval(hours => v_delai_liberal) > NOW();
    END IF;
  END IF;

  IF p_type_litige IN ('COMPORTEMENT_SOIGNANT', 'COMPORTEMENT_ETABLISSEMENT', 'CONDITIONS_MISSION_NON_RESPECTEES') THEN
    SELECT m.fin_le INTO v_mission_fin FROM public.missions m WHERE m.id = p_mission_id;
    IF v_mission_fin IS NULL THEN
      RETURN TRUE;
    END IF;
    RETURN v_mission_fin + make_interval(months => v_delai_compo_mois) > NOW();
  END IF;

  RETURN TRUE;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_externalisations_a_traiter(p_limit integer DEFAULT 50, p_worker_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actions jsonb; v_count int;
  v_worker text := COALESCE(p_worker_id, 'worker_' || substring(md5(random()::text), 1, 8));
BEGIN
  WITH selectionnees AS (
    SELECT id FROM public.externalisation_actions
    WHERE ((statut = 'PENDING' AND (next_retry_at IS NULL OR next_retry_at < NOW()))
        OR (statut = 'PENDING_AIFE' AND next_retry_at IS NOT NULL AND next_retry_at < NOW())
        OR (statut = 'PROCESSING' AND cron_lock_at < NOW() - INTERVAL '10 minutes'))
    ORDER BY cree_le ASC LIMIT p_limit FOR UPDATE SKIP LOCKED
  )
  UPDATE public.externalisation_actions a
  SET statut = 'PROCESSING', cron_lock_at = NOW(), cron_lock_par = v_worker
  FROM selectionnees s WHERE a.id = s.id;

  SELECT jsonb_agg(jsonb_build_object(
    'id', id, 'type_action', type_action, 'payload', payload,
    'source', source, 'source_id', source_id, 'tentatives', tentatives
  )), COUNT(*) INTO v_actions, v_count
  FROM public.externalisation_actions
  WHERE cron_lock_par = v_worker AND statut = 'PROCESSING'
    AND cron_lock_at > NOW() - INTERVAL '5 seconds';

  RETURN jsonb_build_object('success', true, 'worker_id', v_worker,
    'count', COALESCE(v_count, 0), 'actions', COALESCE(v_actions, '[]'::jsonb));
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_externalisation_succes(p_id uuid, p_resultat jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN
  UPDATE public.externalisation_actions SET
    statut = 'DONE', traite_le = NOW(), resultat = COALESCE(p_resultat, '{}'::jsonb),
    derniere_erreur = NULL, cron_lock_at = NULL, cron_lock_par = NULL
  WHERE id = p_id;
  RETURN jsonb_build_object('success', true);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_externalisation_echec(p_id uuid, p_erreur text, p_special_statut text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_action RECORD; v_new_tentatives int; v_new_statut text; v_next_retry timestamptz;
BEGIN
  SELECT tentatives, type_action INTO v_action FROM public.externalisation_actions WHERE id = p_id;
  IF p_special_statut = 'PENDING_AIFE' THEN
    v_new_statut := 'PENDING_AIFE'; v_next_retry := NOW() + INTERVAL '24 hours';
    v_new_tentatives := v_action.tentatives;
  ELSE
    v_new_tentatives := COALESCE(v_action.tentatives, 0) + 1;
    IF v_new_tentatives >= 3 THEN v_new_statut := 'ERROR'; v_next_retry := NULL;
    ELSIF v_new_tentatives = 1 THEN v_new_statut := 'PENDING'; v_next_retry := NOW() + INTERVAL '1 minute';
    ELSIF v_new_tentatives = 2 THEN v_new_statut := 'PENDING'; v_next_retry := NOW() + INTERVAL '5 minutes';
    ELSE v_new_statut := 'PENDING'; v_next_retry := NOW() + INTERVAL '30 minutes'; END IF;
  END IF;
  UPDATE public.externalisation_actions SET
    statut = v_new_statut, tentatives = v_new_tentatives, derniere_tentative_le = NOW(),
    derniere_erreur = LEFT(p_erreur, 1000), next_retry_at = v_next_retry,
    cron_lock_at = NULL, cron_lock_par = NULL,
    traite_le = CASE WHEN v_new_statut = 'ERROR' THEN NOW() ELSE traite_le END
  WHERE id = p_id;
  IF v_new_statut = 'ERROR' THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'externalisation_action', p_id,
      jsonb_build_object('evenement', 'EXTERNALISATION_ECHEC_DEFINITIF',
                          'type_action', v_action.type_action, 'tentatives', v_new_tentatives,
                          'derniere_erreur', LEFT(p_erreur, 200)));
  END IF;
  RETURN jsonb_build_object('success', true, 'statut', v_new_statut, 'tentatives', v_new_tentatives);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_code_parrainage()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_code TEXT;
BEGIN
    v_code := 'JO-' || UPPER(SUBSTRING(encode(extensions.gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    WHILE EXISTS (SELECT 1 FROM soignants WHERE code_parrainage = v_code) LOOP
        v_code := 'JO-' || UPPER(SUBSTRING(encode(extensions.gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    END LOOP;
    RETURN v_code;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_facture(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_facture_id UUID;
    v_numero TEXT;
    v_annee TEXT := to_char(NOW(), 'YYYY');
    v_seq INTEGER;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;
    IF v_mission.statut != 'TERMINEE' THEN
        RETURN '{"error":"La mission doit être TERMINEE"}'::JSONB;
    END IF;
    IF EXISTS (SELECT 1 FROM factures WHERE mission_id = p_mission_id) THEN
        RETURN '{"error":"Facture déjà existante"}'::JSONB;
    END IF;

    SELECT COALESCE(MAX(CAST(SUBSTRING(numero_facture FROM '\d+$') AS INTEGER)), 0) + 1
    INTO v_seq FROM factures WHERE numero_facture LIKE 'JOL-' || v_annee || '-%';
    v_numero := 'JOL-' || v_annee || '-' || LPAD(v_seq::TEXT, 5, '0');

    INSERT INTO factures (
        numero_facture, etablissement_id, mission_id,
        montant_ht, taux_tva, montant_tva, montant_ttc,
        nombre_missions, statut, date_emission, date_echeance
    ) VALUES (
        v_numero, v_mission.etablissement_id, p_mission_id,
        COALESCE(v_mission.montant_commission_ht, 0),
        20,
        COALESCE(v_mission.montant_commission_tva, 0),
        COALESCE(v_mission.montant_commission_ttc, 0),
        1, 'EMISE', NOW(), (NOW() + INTERVAL '30 days')::DATE
    ) RETURNING id INTO v_facture_id;

    UPDATE missions SET commission_facturee = TRUE, modifie_le = NOW() WHERE id = p_mission_id;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_mission.etablissement_id, 'FACTURE_EMISE', 'Facture ' || v_numero,
        'Montant TTC : ' || COALESCE(v_mission.montant_commission_ttc, 0) || '€',
        '/etablissement/facturation', 'ETABLISSEMENT');

    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_facture_honoraires_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_numero TEXT;
    v_facture_id UUID;
    v_existing_id UUID;
    v_periode_debut DATE;
    v_periode_fin DATE;
BEGIN
    SELECT m.*, e.nom AS etab_nom
    INTO v_mission
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_mission_id AND m.statut = 'TERMINEE';

    IF v_mission IS NULL THEN
        RETURN '{"error":"Mission introuvable ou non terminée"}'::JSONB;
    END IF;

    IF v_mission.soignant_assigne_id IS NULL THEN
        RETURN '{"error":"Aucun soignant assigné"}'::JSONB;
    END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;
    IF v_soignant IS NULL THEN
        RETURN '{"error":"Soignant introuvable"}'::JSONB;
    END IF;

    IF NOT COALESCE(v_soignant.mandat_facturation_signe, FALSE) THEN
        RETURN '{"error":"Le soignant n''a pas encore signé le mandat de facturation"}'::JSONB;
    END IF;

    SELECT id INTO v_existing_id FROM factures_honoraires WHERE mission_id = p_mission_id LIMIT 1;
    IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'facture_id', v_existing_id, 'message', 'Facture déjà existante');
    END IF;

    v_numero := 'FH-' || to_char(now(), 'YYYY-MM') || '-' || lpad(
        (COALESCE((SELECT COUNT(*) FROM factures_honoraires WHERE date_emission >= date_trunc('month', now())), 0) + 1)::TEXT,
        4, '0'
    );

    -- Période de la facture = bornes de la mission (NOT NULL en base)
    v_periode_debut := COALESCE(v_mission.debut_le::date, CURRENT_DATE);
    v_periode_fin := COALESCE(v_mission.fin_le::date, v_mission.debut_le::date, CURRENT_DATE);

    INSERT INTO factures_honoraires (
        numero_facture, soignant_id, etablissement_id, mission_id,
        montant_ht, montant_tva, montant_ttc, taux_tva, exoneration_tva,
        date_emission, date_echeance, statut, mandat_version,
        periode_debut, periode_fin,
        numero_semaine_iso, annee_iso
    ) VALUES (
        v_numero,
        v_mission.soignant_assigne_id,
        v_mission.etablissement_id,
        p_mission_id,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0),
        0,
        TRUE,
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days',
        'EMISE',
        v_soignant.mandat_facturation_version,
        v_periode_debut,
        v_periode_fin,
        EXTRACT(WEEK FROM v_periode_debut)::smallint,
        EXTRACT(ISOYEAR FROM v_periode_debut)::smallint
    ) RETURNING id INTO v_facture_id;

    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_fh_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_geler_mission_a_assignation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab RECORD;
  v_groupe_taux numeric;
  v_taux_comm_resolved numeric;
  v_champ_modifie text;
  v_new_code text;
  v_duree_jours integer;
  v_strategie public.strategie_facturation;
BEGIN
  IF OLD.statut = 'OUVERTE' AND NEW.statut = 'ASSIGNEE' THEN
    SELECT
      COALESCE(e.taux_majoration_nuit_pourcent, 25) AS taux_nuit,
      COALESCE(e.taux_majoration_dimanche_pourcent, 25) AS taux_dim,
      COALESCE(e.taux_majoration_ferie_pourcent, 50) AS taux_fer,
      COALESCE(e.heure_debut_nuit, '21:00'::time) AS h_debut_nuit,
      COALESCE(e.heure_fin_nuit, '06:00'::time) AS h_fin_nuit,
      e.taux_commission_negocie AS taux_comm_etab,
      e.groupe_sante_id AS groupe_id
    INTO v_etab
    FROM etablissements e WHERE e.id = NEW.etablissement_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Établissement % introuvable', NEW.etablissement_id USING ERRCODE = 'foreign_key_violation'; END IF;

    -- Cascade taux commission : etab > groupe > 15
    IF v_etab.taux_comm_etab IS NOT NULL THEN
      v_taux_comm_resolved := v_etab.taux_comm_etab;
    ELSIF v_etab.groupe_id IS NOT NULL THEN
      SELECT taux_commission_negocie INTO v_groupe_taux
      FROM groupes_sante WHERE id = v_etab.groupe_id;
      v_taux_comm_resolved := COALESCE(v_groupe_taux, 15);
    ELSE
      v_taux_comm_resolved := 15;
    END IF;

    NEW.taux_horaire_base_fige := NEW.taux_horaire_base;
    NEW.taux_majoration_nuit_fige := v_etab.taux_nuit;
    NEW.taux_majoration_dimanche_fige := v_etab.taux_dim;
    NEW.taux_majoration_ferie_fige := v_etab.taux_fer;
    NEW.heure_debut_nuit_fige := v_etab.h_debut_nuit;
    NEW.heure_fin_nuit_fige := v_etab.h_fin_nuit;
    NEW.taux_commission_fige := v_taux_comm_resolved;
    NEW.fige_le := now();

    -- Step A : figer strategie_facturation selon durée
    -- (NEW.fin_le::date - NEW.debut_le::date) = nombre de jours civils.
    -- Mission lun→dim de la même semaine = 6 jours. Mission lun S1 → mar S2 = 8 jours.
    v_duree_jours := (NEW.fin_le::date - NEW.debut_le::date);
    v_strategie := CASE
      WHEN v_duree_jours > 7 THEN 'HEBDO_ET_FINALE'::public.strategie_facturation
      ELSE 'FINALE_UNIQUE'::public.strategie_facturation
    END;
    NEW.strategie_facturation := v_strategie;

    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
    WHILE EXISTS (SELECT 1 FROM missions WHERE code_pointage_actif = v_new_code AND id != NEW.id AND statut IN ('ASSIGNEE','EN_COURS')) LOOP
      v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
    END LOOP;
    NEW.code_pointage_actif := v_new_code;
    NEW.code_pointage_hmac := CASE WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL
      THEN encode(extensions.hmac(NEW.id::text || ':' || v_new_code, current_setting('app.settings.hmac_secret', true), 'sha256'), 'hex') ELSE NULL END;
    NEW.prochain_type_scan := 'OUVERTURE';
    NEW.nb_scans := 0;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'SYSTEME', 'GEL_APPLIED', 'mission', NEW.id,
      jsonb_build_object('snapshot', jsonb_build_object(
        'taux_horaire_base_fige', NEW.taux_horaire_base_fige,
        'taux_majoration_nuit_fige', NEW.taux_majoration_nuit_fige,
        'taux_majoration_dimanche_fige', NEW.taux_majoration_dimanche_fige,
        'taux_majoration_ferie_fige', NEW.taux_majoration_ferie_fige,
        'heure_debut_nuit_fige', NEW.heure_debut_nuit_fige,
        'heure_fin_nuit_fige', NEW.heure_fin_nuit_fige,
        'taux_commission_fige', NEW.taux_commission_fige,
        'taux_commission_source', CASE
          WHEN v_etab.taux_comm_etab IS NOT NULL THEN 'etablissement'
          WHEN v_groupe_taux IS NOT NULL THEN 'groupe'
          ELSE 'defaut_15' END,
        'strategie_facturation', NEW.strategie_facturation,
        'duree_jours', v_duree_jours
      ),
      'code_pointage_genere', true,
      'soignant_assigne_id', NEW.soignant_assigne_id));
    RETURN NEW;
  END IF;

  -- Dégel : remet strategie_facturation au défaut FINALE_UNIQUE
  -- (sera re-figée au prochain gel).
  IF NEW.statut = 'OUVERTE' AND OLD.statut != 'OUVERTE' AND OLD.fige_le IS NOT NULL THEN
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'SYSTEME', 'DEGEL_APPLIED', 'mission', OLD.id,
      jsonb_build_object('old_snapshot', jsonb_build_object(
        'taux_horaire_base_fige', OLD.taux_horaire_base_fige,
        'taux_majoration_nuit_fige', OLD.taux_majoration_nuit_fige,
        'taux_majoration_dimanche_fige', OLD.taux_majoration_dimanche_fige,
        'taux_majoration_ferie_fige', OLD.taux_majoration_ferie_fige,
        'heure_debut_nuit_fige', OLD.heure_debut_nuit_fige,
        'heure_fin_nuit_fige', OLD.heure_fin_nuit_fige,
        'taux_commission_fige', OLD.taux_commission_fige,
        'strategie_facturation', OLD.strategie_facturation,
        'fige_le', OLD.fige_le),
      'old_statut', OLD.statut, 'new_statut', 'OUVERTE',
      'nb_scans_before_degel', OLD.nb_scans));
    PERFORM set_config('jolene.sync_in_progress', 'true', true);
    DELETE FROM mission_creneaux WHERE mission_id = OLD.id AND type_creneau = 'EFFECTIF';
    PERFORM set_config('jolene.sync_in_progress', 'false', true);
    NEW.taux_horaire_base_fige := NULL; NEW.taux_majoration_nuit_fige := NULL;
    NEW.taux_majoration_dimanche_fige := NULL; NEW.taux_majoration_ferie_fige := NULL;
    NEW.heure_debut_nuit_fige := NULL; NEW.heure_fin_nuit_fige := NULL;
    NEW.taux_commission_fige := NULL; NEW.fige_le := NULL;
    NEW.code_pointage_actif := NULL; NEW.code_pointage_hmac := NULL;
    NEW.prochain_type_scan := NULL; NEW.nb_scans := 0;
    NEW.debut_effectif := NULL; NEW.fin_effective := NULL; NEW.duree_heures_effective := NULL;
    NEW.strategie_facturation := 'FINALE_UNIQUE'::public.strategie_facturation;
    RETURN NEW;
  END IF;

  -- Block des modifs post-gel (logique inchangée) — strategie_facturation
  -- ajoutée à la liste des champs protégés (D8 figée à l'assignation).
  IF OLD.fige_le IS NOT NULL THEN
    IF current_setting('jolene.admin_override_gel', true) = OLD.id::text
       AND COALESCE(current_setting('jolene.admin_override_reason', true), '') != '' THEN
      DECLARE v_fm jsonb := '{}'::jsonb; v_or text := current_setting('jolene.admin_override_reason', true);
      BEGIN
        IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base THEN v_fm := v_fm || jsonb_build_object('taux_horaire_base', jsonb_build_object('old', OLD.taux_horaire_base, 'new', NEW.taux_horaire_base)); END IF;
        IF NEW.intitule IS DISTINCT FROM OLD.intitule THEN v_fm := v_fm || jsonb_build_object('intitule', jsonb_build_object('old', OLD.intitule, 'new', NEW.intitule)); END IF;
        IF NEW.profession_requise IS DISTINCT FROM OLD.profession_requise THEN v_fm := v_fm || jsonb_build_object('profession_requise', jsonb_build_object('old', OLD.profession_requise, 'new', NEW.profession_requise)); END IF;
        IF NEW.taux_horaire_base_fige IS DISTINCT FROM OLD.taux_horaire_base_fige THEN v_fm := v_fm || jsonb_build_object('taux_horaire_base_fige', jsonb_build_object('old', OLD.taux_horaire_base_fige, 'new', NEW.taux_horaire_base_fige)); END IF;
        IF NEW.taux_majoration_nuit_fige IS DISTINCT FROM OLD.taux_majoration_nuit_fige THEN v_fm := v_fm || jsonb_build_object('taux_majoration_nuit_fige', jsonb_build_object('old', OLD.taux_majoration_nuit_fige, 'new', NEW.taux_majoration_nuit_fige)); END IF;
        IF NEW.taux_majoration_dimanche_fige IS DISTINCT FROM OLD.taux_majoration_dimanche_fige THEN v_fm := v_fm || jsonb_build_object('taux_majoration_dimanche_fige', jsonb_build_object('old', OLD.taux_majoration_dimanche_fige, 'new', NEW.taux_majoration_dimanche_fige)); END IF;
        IF NEW.taux_majoration_ferie_fige IS DISTINCT FROM OLD.taux_majoration_ferie_fige THEN v_fm := v_fm || jsonb_build_object('taux_majoration_ferie_fige', jsonb_build_object('old', OLD.taux_majoration_ferie_fige, 'new', NEW.taux_majoration_ferie_fige)); END IF;
        IF NEW.heure_debut_nuit_fige IS DISTINCT FROM OLD.heure_debut_nuit_fige THEN v_fm := v_fm || jsonb_build_object('heure_debut_nuit_fige', jsonb_build_object('old', OLD.heure_debut_nuit_fige, 'new', NEW.heure_debut_nuit_fige)); END IF;
        IF NEW.heure_fin_nuit_fige IS DISTINCT FROM OLD.heure_fin_nuit_fige THEN v_fm := v_fm || jsonb_build_object('heure_fin_nuit_fige', jsonb_build_object('old', OLD.heure_fin_nuit_fige, 'new', NEW.heure_fin_nuit_fige)); END IF;
        IF NEW.taux_commission_fige IS DISTINCT FROM OLD.taux_commission_fige THEN v_fm := v_fm || jsonb_build_object('taux_commission_fige', jsonb_build_object('old', OLD.taux_commission_fige, 'new', NEW.taux_commission_fige)); END IF;
        IF NEW.strategie_facturation IS DISTINCT FROM OLD.strategie_facturation THEN v_fm := v_fm || jsonb_build_object('strategie_facturation', jsonb_build_object('old', OLD.strategie_facturation, 'new', NEW.strategie_facturation)); END IF;
        IF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN v_fm := v_fm || jsonb_build_object('fige_le', jsonb_build_object('old', OLD.fige_le, 'new', NEW.fige_le)); END IF;
        IF v_fm != '{}'::jsonb THEN INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
          VALUES (auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_CHAMP_POST_GEL', 'mission', OLD.id, jsonb_build_object('reason', v_or, 'fields_modified', v_fm)); END IF;
      END;
      RETURN NEW;
    ELSE
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
      ELSIF NEW.strategie_facturation IS DISTINCT FROM OLD.strategie_facturation THEN v_champ_modifie := 'strategie_facturation';
      ELSIF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN v_champ_modifie := 'fige_le';
      END IF;
      IF v_champ_modifie IS NOT NULL THEN
        RAISE EXCEPTION 'Modification du champ "%" interdite après assignation (gel du %). Pour corriger, override admin tracé requis.',
          v_champ_modifie, OLD.fige_le USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_code_parrainage_etab()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_code TEXT;
BEGIN
  LOOP
    v_code := 'ETB-' || UPPER(substring(encode(gen_random_bytes(6), 'base64') FROM 1 FOR 6));
    v_code := REGEXP_REPLACE(v_code, '[^A-Z0-9-]', '', 'g');
    WHILE LENGTH(v_code) < 10 LOOP
      v_code := v_code || UPPER(substring(encode(gen_random_bytes(2), 'base64') FROM 1 FOR 2));
      v_code := REGEXP_REPLACE(v_code, '[^A-Z0-9-]', '', 'g');
    END LOOP;
    v_code := substring(v_code FROM 1 FOR 10);
    EXIT WHEN NOT EXISTS (SELECT 1 FROM etablissements WHERE code_parrainage = v_code);
  END LOOP;
  RETURN v_code;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_donnees_dpae(p_contrat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_payload jsonb;
  v_etab_id uuid;
  v_manquants text[] := ARRAY[]::text[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT cm.etablissement_id INTO v_etab_id
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin() OR v_etab_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  SELECT jsonb_build_object(
    'success', true,
    'contrat_id', cm.id,
    'type_contrat', cm.type_contrat,
    'etablissement', jsonb_build_object(
      'nom', e.nom,
      'siret', e.siret,
      'naf', e.siret_code_naf,
      'adresse_rue', e.adresse_rue,
      'adresse_ville', e.adresse_ville,
      'adresse_code_postal', e.adresse_code_postal,
      'telephone', e.telephone_contact,
      'email', e.email_contact,
      'organisme_protection_sociale', 'URSSAF'
    ),
    'salarie', jsonb_build_object(
      'nom', s.nom,
      'prenom', s.prenom,
      'sexe', s.sexe,
      'date_naissance', s.date_naissance,
      'lieu_naissance_commune', s.lieu_naissance_commune,
      'lieu_naissance_departement', s.lieu_naissance_departement,
      'pays_naissance', COALESCE(s.pays_naissance, 'France'),
      'nationalite', COALESCE(s.nationalite, 'Française'),
      'numero_securite_sociale', COALESCE(s.numero_securite_sociale, s.numero_secu),
      'adresse_rue', s.adresse_rue,
      'adresse_code_postal', s.adresse_code_postal,
      'adresse_ville', s.adresse_ville,
      'profession', s.profession,
      'champs_a_completer_sur_net_entreprises', (
        SELECT COALESCE(jsonb_agg(m), '[]'::jsonb) FROM (
          SELECT 'sexe' AS m WHERE s.sexe IS NULL
          UNION ALL SELECT 'lieu_naissance_commune' WHERE s.lieu_naissance_commune IS NULL AND COALESCE(s.pays_naissance, 'France') = 'France'
          UNION ALL SELECT 'lieu_naissance_departement' WHERE s.lieu_naissance_departement IS NULL AND COALESCE(s.pays_naissance, 'France') = 'France'
          UNION ALL SELECT 'pays_naissance' WHERE s.pays_naissance IS NULL
          UNION ALL SELECT 'nationalite' WHERE s.nationalite IS NULL
          UNION ALL SELECT 'numero_securite_sociale' WHERE COALESCE(s.numero_securite_sociale, s.numero_secu) IS NULL
        ) t
      )
    ),
    'embauche', jsonb_build_object(
      'date_prevue', m.debut_le,
      'heure_prevue', to_char(m.debut_le, 'HH24:MI'),
      'date_fin', m.fin_le,
      'type_contrat', cm.type_contrat,
      'duree_heures_prevues', m.duree_heures
    ),
    'urssaf_url', 'https://www.net-entreprises.fr/declaration-prealable-embauche/',
    'note', 'Copiez ces données dans le formulaire DPAE Net-Entreprises. Les champs marqués dans champs_a_completer_sur_net_entreprises ne sont pas encore renseignés par le soignant — demandez-lui de compléter son profil ou saisissez-les manuellement.'
  )
  INTO v_payload
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  JOIN public.etablissements e ON e.id = cm.etablissement_id
  JOIN public.soignants s ON s.id = cm.soignant_id
  WHERE cm.id = p_contrat_id;

  RETURN v_payload;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_code_secours_mission(p_mission_id uuid, p_type text DEFAULT 'UNIVERSEL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_code text;
  v_code_hash text;
  v_expire_le timestamptz;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, fin_le, statut INTO v_mission FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;
  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  -- Invalider codes précédents non utilisés du même type
  UPDATE public.codes_secours_mission
  SET utilise = true, utilise_le = NOW()
  WHERE mission_id = p_mission_id AND type = p_type AND utilise = false;

  -- Générer 6 chiffres aléatoires (uniformément distribués 0-999999)
  v_code := lpad((floor(random() * 1000000))::text, 6, '0');
  v_code_hash := crypt(v_code, gen_salt('bf'));

  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.codes_secours_mission (mission_id, code_hash, type, expire_le, cree_par)
  VALUES (p_mission_id, v_code_hash, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_id;

  -- Audit (sans le code en clair !)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'code_secours_mission', v_id,
    jsonb_build_object('evenement', 'CODE_SECOURS_GENERE',
                        'mission_id', p_mission_id, 'type', p_type,
                        'expire_le', v_expire_le)
  );

  -- Retourne le code EN CLAIR (une seule fois — jamais re-affiché)
  RETURN jsonb_build_object(
    'success', true,
    'id', v_id,
    'code', v_code,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_jours_feries(p_annee integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_paques DATE;
    v_a INT; v_b INT; v_c INT; v_d INT; v_e INT;
    v_f INT; v_g INT; v_h INT; v_i INT; v_j INT;
    v_k INT; v_l INT; v_mois INT; v_jour INT;
BEGIN
    -- Calcul de Pâques (algorithme de Meeus/Jones/Butcher)
    v_a := p_annee % 19;
    v_b := p_annee / 100;
    v_c := p_annee % 100;
    v_d := v_b / 4;
    v_e := v_b % 4;
    v_f := (v_b + 8) / 25;
    v_g := (v_b - v_f + 1) / 3;
    v_h := (19 * v_a + v_b - v_d - v_g + 15) % 30;
    v_i := v_c / 4;
    v_j := v_c % 4;
    v_k := (32 + 2 * v_e + 2 * v_i - v_h - v_j) % 7;
    v_l := (v_a + 11 * v_h + 22 * v_k) / 451;
    v_mois := (v_h + v_k - 7 * v_l + 114) / 31;
    v_jour := ((v_h + v_k - 7 * v_l + 114) % 31) + 1;
    v_paques := make_date(p_annee, v_mois, v_jour);

    INSERT INTO jours_feries_fr (date_ferie, nom, annee) VALUES
        (make_date(p_annee, 1, 1),   'Jour de l''An',           p_annee),
        (v_paques + 1,               'Lundi de Pâques',         p_annee),
        (make_date(p_annee, 5, 1),   'Fête du Travail',         p_annee),
        (make_date(p_annee, 5, 8),   'Victoire 1945',           p_annee),
        (v_paques + 39,              'Ascension',               p_annee),
        (v_paques + 50,              'Lundi de Pentecôte',      p_annee),
        (make_date(p_annee, 7, 14),  'Fête Nationale',          p_annee),
        (make_date(p_annee, 8, 15),  'Assomption',              p_annee),
        (make_date(p_annee, 11, 1),  'Toussaint',               p_annee),
        (make_date(p_annee, 11, 11), 'Armistice',               p_annee),
        (make_date(p_annee, 12, 25), 'Noël',                    p_annee)
    ON CONFLICT (date_ferie) DO NOTHING;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_numero_facture()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_annee TEXT; v_mois TEXT; v_seq INTEGER; v_numero TEXT;
BEGIN
    v_annee := TO_CHAR(NOW(), 'YYYY');
    v_mois := TO_CHAR(NOW(), 'MM');
    SELECT COUNT(*) + 1 INTO v_seq
    FROM factures WHERE (numero_facture LIKE 'JOL-' || v_annee || v_mois || '-%' 
                      OR numero_facture LIKE 'SD-' || v_annee || v_mois || '-%');
    v_numero := 'JOL-' || v_annee || v_mois || '-' || LPAD(v_seq::TEXT, 4, '0');
    RETURN v_numero;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_numero_contrat(p_type text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_prefix TEXT;
    v_annee TEXT;
    v_seq INTEGER;
BEGIN
    v_prefix := CASE p_type
        WHEN 'CDD' THEN 'CDD'
        WHEN 'VACATION' THEN 'VAC'
        WHEN 'REMPLACEMENT_LIBERAL' THEN 'LIB'
        WHEN 'CDD' THEN 'CDD'
        ELSE 'CTR'
    END;
    v_annee := TO_CHAR(NOW(), 'YYYY');
    SELECT COUNT(*) + 1 INTO v_seq
    FROM contrats_mission
    WHERE numero_contrat LIKE v_prefix || '-' || v_annee || '-%';
    RETURN v_prefix || '-' || v_annee || '-' || LPAD(v_seq::TEXT, 5, '0');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_numero_contrat_safe(p_type text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN fn_generer_numero_contrat(p_type);
EXCEPTION WHEN OTHERS THEN
    RETURN 'ERR-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_facture_mensuelle(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_total_ht NUMERIC; v_total_tva NUMERIC; v_total_ttc NUMERIC;
    v_nb INT; v_numero TEXT; v_facture_id UUID;
BEGIN
    IF p_etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;
    SELECT COALESCE(SUM(montant_commission_ht), 0), COALESCE(SUM(montant_commission_tva), 0),
           COALESCE(SUM(montant_commission_ttc), 0), COUNT(*)
    INTO v_total_ht, v_total_tva, v_total_ttc, v_nb
    FROM missions WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND commission_facturee = FALSE;
    IF v_total_ht = 0 THEN RETURN '{"error":"Aucune mission à facturer"}'::JSONB; END IF;
    v_numero := fn_generer_numero_facture();
    INSERT INTO factures (etablissement_id, numero_facture, statut, montant_ht, taux_tva, montant_tva, montant_ttc,
        nombre_missions, date_emission, date_echeance, periode_debut, periode_fin)
    VALUES (p_etablissement_id, v_numero, 'EMISE', v_total_ht, 20, v_total_tva, v_total_ttc,
        v_nb, NOW(), (NOW() + INTERVAL '30 days')::DATE,
        DATE_TRUNC('month', NOW())::DATE, (DATE_TRUNC('month', NOW()) + INTERVAL '1 month' - INTERVAL '1 day')::DATE)
    RETURNING id INTO v_facture_id;
    UPDATE missions SET commission_facturee = TRUE, facture_id = v_facture_id
    WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND commission_facturee = FALSE;
    RETURN jsonb_build_object('success', true, 'facture_id', v_facture_id, 'numero', v_numero, 'montant_ttc', v_total_ttc, 'nb_missions', v_nb);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_numero_note_honoraires()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_compteur INTEGER;
    v_numero TEXT;
BEGIN
    UPDATE soignants SET compteur_notes_honoraires = compteur_notes_honoraires + 1
    WHERE id = auth.uid()
    RETURNING compteur_notes_honoraires INTO v_compteur;

    v_numero := 'NH-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD(v_compteur::TEXT, 3, '0');
    RETURN v_numero;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_facture_rate_limited()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_etab_id UUID := mon_etablissement_id();
    v_allowed BOOLEAN;
BEGIN
    IF v_user_id IS NULL OR v_etab_id IS NULL THEN 
        RETURN jsonb_build_object('error', 'Non authentifié'); 
    END IF;
    v_allowed := fn_verifier_rate_limit(v_user_id::TEXT, 'facture', 5, 3600);
    IF NOT v_allowed THEN 
        RETURN jsonb_build_object('error', 'Trop de tentatives. Réessayez dans quelques minutes.'); 
    END IF;
    RETURN fn_generer_facture_mensuelle(v_etab_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_generer_qr_mission(p_mission_id uuid, p_type text DEFAULT 'UNIVERSEL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission RECORD;
  v_token text;
  v_expire_le timestamptz;
  v_qr_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_type NOT IN ('ARRIVEE', 'DEPART', 'UNIVERSEL') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE');
  END IF;

  SELECT id, etablissement_id, debut_le, fin_le, statut INTO v_mission
  FROM public.missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE');
  END IF;

  -- Auth : étab admin de la mission ou admin Jolene
  IF NOT (est_admin() OR v_mission.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF v_mission.statut IN ('LITIGE', 'ANNULEE_PAR_ETABLISSEMENT', 'TERMINEE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INACTIVE');
  END IF;

  -- Désactiver les QR actifs précédents du même type
  UPDATE public.qr_codes_mission SET actif = false
  WHERE mission_id = p_mission_id AND type = p_type AND actif = true;

  -- Token = UUID v4 + suffix 16 chars random cryptographique
  v_token := gen_random_uuid()::text || '_' ||
             encode(extensions.gen_random_bytes(8), 'hex');

  -- Expiration : min(date_fin + 2h, NOW() + 7j)
  v_expire_le := LEAST(
    COALESCE(v_mission.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
    NOW() + INTERVAL '7 days'
  );

  INSERT INTO public.qr_codes_mission (mission_id, token, type, expire_le, cree_par)
  VALUES (p_mission_id, v_token, p_type, v_expire_le, v_uid)
  RETURNING id INTO v_qr_id;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'SYSTEM', 'qr_code_mission', v_qr_id,
    jsonb_build_object('evenement', 'QR_GENERE',
                        'mission_id', p_mission_id,
                        'type', p_type, 'expire_le', v_expire_le)
  );

  RETURN jsonb_build_object(
    'success', true,
    'qr_id', v_qr_id,
    'token', v_token,
    'type', p_type,
    'expire_le', v_expire_le
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_health_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignants INTEGER;
    v_missions INTEGER;
    v_dernier_audit TIMESTAMPTZ;
BEGIN
    SELECT COUNT(*) INTO v_soignants FROM soignants WHERE supprime_le IS NULL;
    SELECT COUNT(*) INTO v_missions FROM missions WHERE statut = 'OUVERTE';
    SELECT MAX(cree_le) INTO v_dernier_audit FROM journaux_audit;

    INSERT INTO health_check (service, statut, details)
    VALUES ('API', 'OK', jsonb_build_object(
        'soignants_actifs', v_soignants,
        'missions_ouvertes', v_missions,
        'dernier_audit', v_dernier_audit,
        'timestamp', NOW()
    ));

    RETURN jsonb_build_object(
        'status', 'OK',
        'soignants', v_soignants,
        'missions_ouvertes', v_missions,
        'dernier_audit', v_dernier_audit
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_get_my_role()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role TEXT;
    v_etab_id TEXT;
    v_uid UUID;
BEGIN
    v_uid := auth.uid();

    SELECT 
        raw_app_meta_data ->> 'role',
        raw_app_meta_data ->> 'etablissement_id'
    INTO v_role, v_etab_id
    FROM auth.users
    WHERE id = v_uid;

    -- Fallback: if role is ADMIN_ETABLISSEMENT or ETABLISSEMENT but no explicit etablissement_id, use auth.uid()
    IF v_etab_id IS NULL AND v_role IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT') THEN
        v_etab_id := v_uid::TEXT;
    END IF;

    RETURN jsonb_build_object(
        'user_id', v_uid,
        'role', COALESCE(v_role, 'INCONNU'),
        'etablissement_id', v_etab_id
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_html_escape(p_text text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(
        COALESCE(p_text, ''),
        '&', '&amp;'),
        '<', '&lt;'),
        '>', '&gt;'),
        '"', '&quot;');
    -- Apostrophes intentionnellement non encodées
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_get_stripe_account_soignant(p_soignant_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_account TEXT;
BEGIN
    SELECT stripe_account_id INTO v_account FROM stripe_connect_onboarding
    WHERE soignant_id = p_soignant_id AND onboarding_complete = TRUE AND statut = 'COMPLET';
    RETURN v_account;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_gerer_blocage_etabs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_paiements_retard_nb INT;
    v_paiements_retard_montant NUMERIC;
    v_factures_retard_nb INT;
    v_factures_retard_montant NUMERIC;
    v_raisons JSONB;
    v_blocages INT := 0;
    v_deblocages INT := 0;
    v_seuil_j integer := (public.fn_param_num('seuil_blocage_retard_j', 45))::integer;
    v_seuil interval := (v_seuil_j::text || ' days')::interval;
BEGIN
    FOR v_etab IN
        SELECT id, nom, email_contact
        FROM public.etablissements
        WHERE bloque_auto_le IS NULL
          AND statut_verification = 'VERIFIE'
          AND supprime_le IS NULL
    LOOP
        SELECT COUNT(*), COALESCE(SUM(COALESCE(m.net_a_payer, m.total_brut, 0)), 0)
        INTO v_paiements_retard_nb, v_paiements_retard_montant
        FROM public.missions m
        WHERE m.etablissement_id = v_etab.id
          AND m.type_contrat_applique = 'SALARIE'
          AND m.statut = 'TERMINEE'
          AND m.fin_le IS NOT NULL
          AND m.fin_le < NOW() - v_seuil
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        SELECT COUNT(*), COALESCE(SUM(f.montant_ttc), 0)
        INTO v_factures_retard_nb, v_factures_retard_montant
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.date_emission IS NOT NULL
          AND f.date_emission < NOW() - v_seuil;

        IF v_paiements_retard_nb > 0 OR v_factures_retard_nb > 0 THEN
            v_raisons := jsonb_build_object(
                'paiements_retard_nb', v_paiements_retard_nb,
                'paiements_retard_montant', ROUND(v_paiements_retard_montant, 2),
                'factures_retard_nb', v_factures_retard_nb,
                'factures_retard_montant', ROUND(v_factures_retard_montant, 2),
                'seuil_jours', v_seuil_j
            );

            UPDATE public.etablissements
            SET bloque_auto_le = NOW(),
                bloque_auto_raisons = v_raisons
            WHERE id = v_etab.id;

            INSERT INTO public.historique_blocages_etablissements (etablissement_id, action, raisons)
            VALUES (v_etab.id, 'BLOCAGE', v_raisons);

            IF v_etab.email_contact IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PUBLICATION_SUSPENDUE', v_etab.id, v_etab.email_contact,
                    jsonb_build_object(
                        'etablissement_nom', v_etab.nom,
                        'obligations_en_cours',
                          CASE WHEN v_paiements_retard_nb > 0 THEN v_paiements_retard_nb || ' paiement(s) soignant(s) en retard (' || ROUND(v_paiements_retard_montant, 2) || ' EUR)' ELSE '' END
                          || CASE WHEN v_paiements_retard_nb > 0 AND v_factures_retard_nb > 0 THEN '<br/>' ELSE '' END
                          || CASE WHEN v_factures_retard_nb > 0 THEN v_factures_retard_nb || ' facture(s) commission en retard (' || ROUND(v_factures_retard_montant, 2) || ' EUR)' ELSE '' END,
                        'total_montant_du', ROUND(v_paiements_retard_montant + v_factures_retard_montant, 2),
                        'date_blocage', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY')
                    ));
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_etab.id, 'SYSTEM',
                'Publication de missions suspendue',
                'Regularisez vos obligations (paiements soignants et factures commission) pour reactiver votre compte.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT');

            v_blocages := v_blocages + 1;
        END IF;
    END LOOP;

    FOR v_etab IN
        SELECT id, nom, email_contact
        FROM public.etablissements
        WHERE bloque_auto_le IS NOT NULL
          AND supprime_le IS NULL
    LOOP
        SELECT COUNT(*) INTO v_paiements_retard_nb
        FROM public.missions m
        WHERE m.etablissement_id = v_etab.id
          AND m.type_contrat_applique = 'SALARIE'
          AND m.statut = 'TERMINEE'
          AND m.fin_le < NOW() - v_seuil
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        SELECT COUNT(*) INTO v_factures_retard_nb
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.date_emission < NOW() - v_seuil;

        IF v_paiements_retard_nb = 0 AND v_factures_retard_nb = 0 THEN
            UPDATE public.etablissements
            SET bloque_auto_le = NULL,
                bloque_auto_raisons = NULL
            WHERE id = v_etab.id;

            INSERT INTO public.historique_blocages_etablissements (etablissement_id, action)
            VALUES (v_etab.id, 'DEBLOCAGE');

            IF v_etab.email_contact IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PUBLICATION_REACTIVEE', v_etab.id, v_etab.email_contact,
                    jsonb_build_object(
                        'etablissement_nom', v_etab.nom,
                        'debloque_le', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI')
                    ));
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_etab.id, 'SYSTEM',
                'Publication de missions reactivee',
                'Votre compte est a nouveau autorise a publier des missions.',
                '/etablissement/dashboard', 'ETABLISSEMENT');

            v_deblocages := v_deblocages + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'blocages', v_blocages,
        'deblocages', v_deblocages
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_get_or_create_parcours_liberal(p_soignant_id uuid DEFAULT NULL::uuid)
 RETURNS parcours_liberal_soignants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_id UUID;
  v_parcours public.parcours_liberal_soignants;
BEGIN
  v_soignant_id := COALESCE(p_soignant_id, auth.uid());
  IF v_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;
  IF v_soignant_id != auth.uid() AND NOT est_admin() THEN
    RAISE EXCEPTION 'Accès non autorisé';
  END IF;

  SELECT * INTO v_parcours FROM public.parcours_liberal_soignants WHERE soignant_id = v_soignant_id;

  IF NOT FOUND THEN
    INSERT INTO public.parcours_liberal_soignants (soignant_id, etapes)
    VALUES (v_soignant_id, '{}'::jsonb)
    RETURNING * INTO v_parcours;
  END IF;

  RETURN v_parcours;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_haversine_distance_m(p_lat1 numeric, p_lng1 numeric, p_lat2 numeric, p_lng2 numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_r constant numeric := 6371000;
  v_phi1 numeric; v_phi2 numeric; v_dphi numeric; v_dlambda numeric;
  v_a numeric; v_c numeric;
BEGIN
  IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN RETURN NULL; END IF;
  v_phi1 := radians(p_lat1); v_phi2 := radians(p_lat2);
  v_dphi := radians(p_lat2 - p_lat1); v_dlambda := radians(p_lng2 - p_lng1);
  v_a := sin(v_dphi/2) * sin(v_dphi/2) + cos(v_phi1) * cos(v_phi2) * sin(v_dlambda/2) * sin(v_dlambda/2);
  v_c := 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
  RETURN round(v_r * v_c);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_init_proprietaire_etab(p_etablissement_id uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_uid uuid;
  v_membre_id uuid;
BEGIN
  IF v_caller IS NULL THEN
    -- Appel serveur (register-etablissement en service_role)
    v_uid := p_user_id;
    IF v_uid IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
    END IF;
  ELSE
    -- Appel client authentifié : on ignore p_user_id et on vérifie la revendication
    v_uid := v_caller;
    IF NOT (
      est_admin()
      OR EXISTS (
        SELECT 1 FROM auth.users u
        WHERE u.id = v_caller
          AND (u.raw_app_meta_data ->> 'etablissement_id') = p_etablissement_id::text
      )
    ) THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.membres_etablissement
    WHERE etablissement_id = p_etablissement_id AND actif = true
  ) THEN
    RETURN jsonb_build_object('success', true, 'message', 'Membres déjà présents');
  END IF;

  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, accepte_le, actif
  ) VALUES (
    p_etablissement_id, v_uid, 'PROPRIETAIRE', now(), true
  )
  RETURNING id INTO v_membre_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', v_membre_id,
    jsonb_build_object(
      'evenement', 'PROPRIETAIRE_INITIALISE',
      'etablissement_id', p_etablissement_id
    )
  );

  RETURN jsonb_build_object('success', true, 'membre_id', v_membre_id);
END;
$function$
