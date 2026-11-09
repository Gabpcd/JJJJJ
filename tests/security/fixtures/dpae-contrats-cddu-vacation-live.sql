-- Corps LIVE de production (prosrc relus le 08/11/2026 en lecture seule, md5
-- identiques à supabase/schema/public.sql avant la migration 20261108223500),
-- en-têtes pg_get_functiondef LIVE. Chargés par le banc PG17 isolé AVANT la
-- vraie migration ; jamais exécutés hors banc. Généré, ne pas éditer à la main :
-- tests/node/dpae-contrats-cddu-vacation.node.mjs vérifie que chaque corps est
-- celui de la migration où l'appel au helper est ramené à l'ancienne liste.
CREATE OR REPLACE FUNCTION public.fn_mes_dpae()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_mes_dpae$
DECLARE
  v_uid uuid := auth.uid();
  v_dpae jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'contrat_id', cm.id,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'etablissement_id', m.etablissement_id,
    'etablissement_nom', e.nom,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'type_contrat', cm.type_contrat,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_numero', cm.dpae_numero,
    'dpae_effectuee_le', cm.dpae_effectuee_le,
    'rappel_dpae_affiche', cm.rappel_dpae_affiche,
    'rappel_dpae_affiche_le', cm.rappel_dpae_affiche_le,
    'statut_contrat', cm.statut
  ) ORDER BY m.debut_le DESC), '[]'::jsonb)
  INTO v_dpae
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE cm.soignant_id = v_uid
    AND cm.type_contrat IN ('CDD', 'CDD', 'SALARIE')
    AND cm.statut IN ('SIGNE_COMPLET', 'SIGNE_PARTIEL');

  RETURN jsonb_build_object('success', true, 'dpae', v_dpae);
END;
$fn_mes_dpae$;

CREATE OR REPLACE FUNCTION public.fn_rappel_dpae_quotidien()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_rappel_dpae_quotidien$
DECLARE v_contrat RECORD; v_count int := 0;
BEGIN
  FOR v_contrat IN
    SELECT cm.id, cm.numero_contrat, cm.etablissement_id
    FROM public.contrats_mission cm
    WHERE cm.statut = 'SIGNE_COMPLET' AND cm.type_contrat IN ('CDD', 'CDD', 'SALARIE')
      AND COALESCE(cm.dpae_effectuee, false) = false
      AND cm.signature_soignant_le > NOW() - INTERVAL '7 days'
      AND cm.signature_soignant_le < NOW() - INTERVAL '1 day'
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
        body := jsonb_build_object('destinataire_id', v_contrat.etablissement_id,
          'type_evenement', 'DPAE_RAPPEL', 'titre', 'Rappel DPAE',
          'corps', 'Contrat ' || COALESCE(v_contrat.numero_contrat, '') ||
                   ' : la DPAE URSSAF doit être déclarée avant la prise de poste.',
          'data', jsonb_build_object('contrat_id', v_contrat.id,
            'lien', 'https://jolene.app/contrat/' || v_contrat.id::text))
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    v_count := v_count + 1;
  END LOOP;
  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'cron', NULL,
      jsonb_build_object('evenement', 'DPAE_RAPPEL_QUOTIDIEN', 'count', v_count, 'exec_le', NOW()));
  END IF;
  RETURN jsonb_build_object('success', true, 'count', v_count);
END; $fn_rappel_dpae_quotidien$;

CREATE OR REPLACE FUNCTION public.fn_pointer_arrivee(p_mission_id uuid, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_precision numeric DEFAULT NULL::numeric, p_terminal_id text DEFAULT NULL::text, p_modele text DEFAULT NULL::text, p_code_arrivee text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_pointer_arrivee$
DECLARE
  v_mission RECORD;
  v_contrat RECORD;
  v_etab RECORD;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_methode text;
  v_warnings jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
  IF v_mission.soignant_assigne_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
  IF v_mission.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN '{"error":"Mission non active"}'::JSONB; END IF;

  SELECT * INTO v_contrat FROM contrats_mission WHERE mission_id = p_mission_id AND statut = 'SIGNE_COMPLET';
  IF v_contrat IS NULL THEN RETURN '{"error":"Le contrat doit être signé avant le pointage."}'::JSONB; END IF;

  IF EXISTS (SELECT 1 FROM presences WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
    RETURN '{"error":"Vous avez déjà pointé votre arrivée."}'::JSONB;
  END IF;

  SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 500) AS tolerance_m
    INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

  IF p_code_arrivee IS NOT NULL THEN
    IF p_code_arrivee != v_mission.code_arrivee THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT', 'error', 'Code de pointage incorrect.');
    END IF;
    v_methode := 'CODE';
    v_perimetre_ok := true;
    v_distance_m := NULL;
  ELSE
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'GPS_MANQUANT',
        'error', 'Coordonnées GPS requises (ou utilisez le code de secours).');
    END IF;
    IF v_etab.adresse_lat IS NULL OR v_etab.adresse_lng IS NULL THEN
      v_distance_m := NULL;
      v_perimetre_ok := false;
    ELSE
      v_distance_m := public.fn_haversine_distance_m(p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= v_etab.tolerance_m;
      IF NOT v_perimetre_ok THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'HORS_PERIMETRE',
          'error', 'Vous êtes à ' || v_distance_m::int || 'm de l''établissement (tolérance ' || v_etab.tolerance_m || 'm). Utilisez le code fourni par l''établissement.',
          'distance_m', v_distance_m, 'tolerance_m', v_etab.tolerance_m);
      END IF;
    END IF;
    v_methode := 'GPS';
  END IF;

  IF v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')
     AND COALESCE(v_contrat.dpae_numero, '') = '' THEN
    v_warnings := v_warnings || jsonb_build_object(
      'code', 'DPAE_NON_REGULARISEE',
      'message', 'Votre DPAE URSSAF n''est pas encore enregistrée dans Jolene. L''établissement doit régulariser la déclaration auprès de l''URSSAF et saisir le numéro dans la plateforme.',
      'severite', 'warning'
    );

    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'destinataire_id', v_mission.etablissement_id,
          'type_evenement', 'DPAE_NON_REGULARISEE_POINTAGE',
          'titre', '⚠️ DPAE à régulariser',
          'corps', 'Le soignant vient de pointer sur le contrat ' || COALESCE(v_contrat.numero_contrat, '') || ' mais le numéro URSSAF n''est pas saisi. À régulariser sous 24h.',
          'data', jsonb_build_object('contrat_id', v_contrat.id::text, 'mission_id', p_mission_id::text)
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  INSERT INTO presences (
    mission_id, soignant_id, pointage_arrivee_le,
    arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
    arrivee_id_terminal, arrivee_modele_terminal,
    methode_pointage_arrivee, distance_etablissement_m, perimetre_gps_valide
  ) VALUES (
    p_mission_id, auth.uid(), NOW(), p_lat, p_lng, p_precision,
    p_terminal_id, p_modele, v_methode, v_distance_m, v_perimetre_ok
  );

  UPDATE missions SET statut = 'EN_COURS', modifie_le = NOW()
   WHERE id = p_mission_id AND statut = 'ASSIGNEE';

  RETURN jsonb_build_object(
    'success', true,
    'methode', v_methode,
    'distance_m', v_distance_m,
    'perimetre_valide', v_perimetre_ok,
    'warnings', v_warnings
  );
END;
$fn_pointer_arrivee$;

CREATE OR REPLACE FUNCTION public.fn_annuler_candidature_soignant(p_candidature_id uuid, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn_annuler_candidature_soignant$
DECLARE
  v_uid uuid := auth.uid();
  v_candidature RECORD;
  v_mission RECORD;
  v_contrat RECORD;
  v_penalite jsonb;
  v_event_id uuid;
  v_points int;
  v_motif_event text;
  v_signalement boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  IF p_motif_categorie IS NULL OR p_motif_categorie NOT IN (
    'URGENCE_PERSONNELLE', 'URGENCE_MEDICALE', 'DEUIL',
    'PROBLEME_TRANSPORT', 'CHANGEMENT_AVIS', 'AUTRE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif requis (URGENCE_PERSONNELLE, URGENCE_MEDICALE, DEUIL, PROBLEME_TRANSPORT, CHANGEMENT_AVIS, AUTRE)');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 10 caractères)');
  END IF;

  SELECT * INTO v_candidature FROM public.candidatures WHERE id = p_candidature_id;
  IF v_candidature IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CANDIDATURE_INTROUVABLE', 'error', 'Candidature introuvable');
  END IF;

  IF v_candidature.soignant_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas le soignant de cette candidature');
  END IF;

  IF v_candidature.statut NOT IN ('ACCEPTEE', 'EN_ATTENTE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'STATUT_INVALIDE',
                                'error', 'Candidature pas dans un état annulable (statut : ' || v_candidature.statut || ')');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_candidature.mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE', 'error', 'Mission introuvable');
  END IF;

  PERFORM set_config('jolene.annulation_soignant_ctx', 'true', true);

  IF v_candidature.statut = 'EN_ATTENTE' THEN
    UPDATE public.candidatures SET
      statut = 'ANNULEE',
      traite_le = NOW(),
      motif_refus = p_texte_libre
    WHERE id = p_candidature_id;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      v_uid, 'SOIGNANT', 'SYSTEM', 'candidature', p_candidature_id,
      jsonb_build_object('evenement', 'CANDIDATURE_ANNULEE_PAR_SOIGNANT',
                          'motif_categorie', p_motif_categorie,
                          'texte_libre', p_texte_libre,
                          'libre', true,
                          'statut_initial', v_candidature.statut)
    );

    RETURN jsonb_build_object('success', true, 'libre', true, 'points', 0,
                                'message', 'Candidature retirée sans impact');
  END IF;

  v_penalite := public.fn_calculer_penalite_annulation_soignant(
    v_candidature.acceptee_a, v_mission.debut_le, v_mission.est_asap
  );

  v_points := (v_penalite->>'points')::int;
  v_motif_event := v_penalite->>'motif';
  v_signalement := COALESCE((v_penalite->>'signalement_admin')::boolean, false);

  UPDATE public.candidatures SET
    statut = 'ANNULEE',
    traite_le = NOW(),
    motif_refus = p_motif_categorie || ' : ' || p_texte_libre
  WHERE id = p_candidature_id;

  UPDATE public.missions SET
    statut = 'OUVERTE',
    soignant_assigne_id = NULL,
    modifie_le = NOW()
  WHERE id = v_candidature.mission_id AND statut IN ('ASSIGNEE', 'EN_COURS');

  SELECT * INTO v_contrat FROM public.contrats_mission
  WHERE mission_id = v_candidature.mission_id LIMIT 1;
  IF FOUND THEN
    UPDATE public.contrats_mission SET
      statut = 'RUPTURE_SOIGNANT',
      modifie_le = NOW()
    WHERE id = v_contrat.id;

    IF v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')
       AND v_contrat.statut = 'SIGNE_COMPLET' THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      VALUES ('DPAE_ANNULATION',
              jsonb_build_object('contrat_id', v_contrat.id, 'mission_id', v_candidature.mission_id,
                                  'motif', 'ANNULATION_SOIGNANT', 'echeance_legale_h', 48),
              'ANNULATION_MISSION', p_candidature_id);
    END IF;
  END IF;

  IF v_points < 0 THEN
    INSERT INTO public.evenements_score_soignant (
      soignant_id, type_evenement, points, motif, contestable,
      mission_id, candidature_id, justificatif_storage_path,
      details
    ) VALUES (
      v_uid, v_motif_event, v_points,
      p_motif_categorie || ' : ' || left(p_texte_libre, 200),
      true,
      v_candidature.mission_id, p_candidature_id, p_justificatif_storage_path,
      jsonb_build_object(
        'motif_categorie', p_motif_categorie,
        'texte_libre', p_texte_libre,
        'delta_mission_h', EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 3600,
        'delta_retract_min', EXTRACT(EPOCH FROM (NOW() - v_candidature.acceptee_a)) / 60,
        'est_asap', v_mission.est_asap,
        'signalement_admin', v_signalement
      )
    ) RETURNING id INTO v_event_id;

    IF v_signalement THEN
      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_uid, 'SOIGNANT', 'SYSTEM', 'soignant', v_uid,
        jsonb_build_object('evenement', 'ALERTE_ADMIN_NO_SHOW',
                            'mission_id', v_candidature.mission_id,
                            'event_score_id', v_event_id,
                            'motif_categorie', p_motif_categorie,
                            'action_requise', 'REVISION_MANUELLE_ADMIN')
      );
    END IF;
  END IF;

  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('EMAIL_NOTIF', jsonb_build_object(
      'destinataire_id', v_mission.etablissement_id,
      'type', 'CANDIDATURE_ANNULEE_SOIGNANT',
      'data', jsonb_build_object(
        'mission_id', v_mission.id,
        'motif_categorie', p_motif_categorie,
        'libre', v_points = 0
      )
    ), 'ANNULATION_MISSION', p_candidature_id),
    ('PUSH_NOTIF', jsonb_build_object(
      'destinataire_id', v_mission.etablissement_id,
      'type_evenement', 'CANDIDATURE_ANNULEE_SOIGNANT',
      'titre', 'Le soignant a annulé',
      'corps', 'La mission est de nouveau disponible. Notifications envoyées aux soignants matching.'
    ), 'ANNULATION_MISSION', p_candidature_id);

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'candidature', p_candidature_id,
    jsonb_build_object(
      'evenement', 'CANDIDATURE_ANNULEE_PAR_SOIGNANT',
      'motif_categorie', p_motif_categorie,
      'texte_libre', p_texte_libre,
      'points', v_points,
      'motif_score', v_motif_event,
      'event_score_id', v_event_id,
      'mission_id', v_mission.id,
      'signalement_admin', v_signalement
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'libre', v_points = 0,
    'points', v_points,
    'motif_score', v_motif_event,
    'event_score_id', v_event_id,
    'contestable', v_points < 0,
    'signalement_admin', v_signalement
  );
END;
$fn_annuler_candidature_soignant$;

CREATE OR REPLACE FUNCTION public.dec_email_contrat_signe_complet()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $dec_email_contrat_signe_complet$
DECLARE
  v_lien text;
BEGIN
  IF private.fn_contrat_lie_compte_test(
       NEW.mission_id, NEW.soignant_id, NEW.etablissement_id
     ) IS NOT FALSE THEN
    RETURN NEW;
  END IF;

  -- Ne tirer que sur transition vers SIGNE_COMPLET
  IF OLD.statut = 'SIGNE_COMPLET' OR NEW.statut != 'SIGNE_COMPLET' THEN
    RETURN NEW;
  END IF;

  v_lien := 'https://jolene.app/contrat/' || NEW.id::text;

  -- Email soignant
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.soignant_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Email étab
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.etablissement_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', 'SYSTEME',
    'CONTRAT_SIGNE', 'contrat_mission', NEW.id,
    jsonb_build_object(
      'evenement', 'CONTRAT_SIGNE_COMPLET_AUTO',
      'numero_contrat', NEW.numero_contrat,
      'type_contrat', NEW.type_contrat,
      'mode_signature', NEW.mode_signature,
      'dpae_requise', (NEW.type_contrat IN ('CDD', 'CDD'))
    )
  );

  RETURN NEW;
END;
$dec_email_contrat_signe_complet$;
