-- Urgence/remplacement plus robuste :
-- 1. Le broadcast no-show pousse désormais un PUSH natif à TOUS les soignants
--    compatibles proches (hors pool disponible_urgence déjà couvert par le
--    trigger fn_trg_auto_notify_mission_urgente avec push+email+sms). Avant, les
--    non-pool ne recevaient qu'une notif in-app (vue seulement en ouvrant l'app).
-- 2. Nouvelle escalade : si la mission de remplacement reste sans candidat 20 min
--    après diffusion → rayon élargi à 80 km + re-push aux compatibles non encore
--    notifiés + ALERTE ADMIN. Cron toutes les 10 min.

CREATE OR REPLACE FUNCTION public.fn_detecter_noshow_et_remplacer()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_remplacement_id uuid;
  v_traites int := 0;
  v_remplacements int := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_s uuid;
  v_corps text;
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL; END;

  FOR v_m IN
    SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng, e.adresse_ville AS etab_ville
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND m.soignant_assigne_id IS NOT NULL
      AND m.debut_le < NOW() - INTERVAL '30 minutes'
      AND m.debut_le > NOW() - INTERVAL '4 hours'
      AND m.fin_le > NOW() + INTERVAL '1 hour'
      AND NOT EXISTS (SELECT 1 FROM presences p WHERE p.mission_id = m.id AND p.soignant_id = m.soignant_assigne_id)
      AND NOT EXISTS (SELECT 1 FROM missions r WHERE r.remplacement_de_mission_id = m.id)
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.destinataire_id = m.etablissement_id AND n.type = 'SYSTEM'
          AND n.lien = '/etablissement/missions/' || m.id
          AND n.titre LIKE 'Aucun pointage%'
          AND n.cree_le > NOW() - INTERVAL '6 hours')
  LOOP
    v_traites := v_traites + 1;

    IF v_m.garantie_remplacement THEN
      INSERT INTO missions (
        etablissement_id, intitule, description, service,
        profession_requise, specialite_medicale_requise, accepte_non_specialises,
        debut_le, fin_le, duree_heures, taux_horaire_base,
        type_contrat_recherche, statut, mode_attribution,
        est_urgente, niveau_urgence, remplacement_de_mission_id
      ) VALUES (
        v_m.etablissement_id,
        'REMPLACEMENT URGENT — ' || v_m.intitule,
        COALESCE(v_m.description, '') || E'\n\n[Mission de remplacement générée automatiquement — garantie Jolene]',
        v_m.service,
        v_m.profession_requise, v_m.specialite_medicale_requise, v_m.accepte_non_specialises,
        GREATEST(v_m.debut_le, NOW() + INTERVAL '15 minutes'), v_m.fin_le,
        ROUND(EXTRACT(EPOCH FROM (v_m.fin_le - GREATEST(v_m.debut_le, NOW() + INTERVAL '15 minutes'))) / 3600.0, 2),
        v_m.type_contrat_recherche, 'OUVERTE', 'PREMIER_ARRIVE',
        TRUE, 3, v_m.id
      ) RETURNING id INTO v_remplacement_id;

      v_corps := fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', MAINTENANT à ' ||
                 COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. Acceptez en 1 clic.';

      FOR v_s IN
        SELECT s.id FROM soignants s
        WHERE s.profession = v_m.profession_requise
          AND s.supprime_le IS NULL
          AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
          AND COALESCE(s.tous_documents_valides, false)
          AND COALESCE(s.disponible_urgence, false) = false
          AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
          AND s.id != v_m.soignant_assigne_id
          AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
               OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
                  <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
        LIMIT 200
      LOOP
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_s, 'POOL_URGENCE', '🚨 Remplacement immédiat — premier arrivé, premier servi',
          v_corps, '/soignant/missions/' || v_remplacement_id, 'SOIGNANT');

        IF v_token IS NOT NULL THEN
          BEGIN
            PERFORM net.http_post(
              url := v_url || '/functions/v1/send-push',
              headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
              body := jsonb_build_object(
                'destinataire_id', v_s, 'type_evenement', 'MISSION_URGENTE',
                'titre', '🚨 Remplacement immédiat près de chez vous', 'corps', v_corps,
                'data', jsonb_build_object('mission_id', v_remplacement_id, 'lien', '/soignant/pool-urgence')
              )
            );
          EXCEPTION WHEN OTHERS THEN NULL; END;
        END IF;
      END LOOP;

      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_m.etablissement_id, 'SYSTEM', 'Aucun pointage — remplacement lancé 🚨',
        'Aucun pointage détecté 30 min après le début de "' || fn_html_escape(v_m.intitule) ||
        '". Garantie remplacement activée : une mission de remplacement urgente vient d''être diffusée au pool de soignants disponibles.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');

      UPDATE missions SET statut = 'ABSENCE', absence_sans_prevenir = TRUE, modifie_le = NOW()
       WHERE id = v_m.id;

      v_remplacements := v_remplacements + 1;
    ELSE
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_m.etablissement_id, 'SYSTEM', 'Aucun pointage détecté ⚠️',
        'Aucun pointage 30 min après le début de "' || fn_html_escape(v_m.intitule) ||
        '". Contactez le soignant, ou alertez le pool d''urgence depuis la mission.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');
    END IF;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.soignant_assigne_id, 'SYSTEM', 'Aucun pointage détecté sur votre mission',
      'Votre mission "' || fn_html_escape(v_m.intitule) || '" a démarré il y a 30 min sans pointage. ' ||
      'Pointez immédiatement ou contactez l''établissement — une absence non justifiée impacte fortement votre score de fiabilité.',
      '/soignant/presences', 'SOIGNANT');
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'detectes', v_traites, 'remplacements', v_remplacements);
END;
$function$;

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
    v_corps := fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', URGENT à ' ||
               COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. Toujours disponible, acceptez en 1 clic !';

    FOR v_s IN
      SELECT s.id FROM soignants s
      WHERE s.profession = v_m.profession_requise
        AND s.supprime_le IS NULL
        AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
        AND COALESCE(s.tous_documents_valides, false)
        AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
        AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng) <= 80000)
        AND NOT EXISTS (
          SELECT 1 FROM notifications n2
          WHERE n2.destinataire_id = s.id AND n2.lien = '/soignant/missions/' || v_m.id)
      LIMIT 300
    LOOP
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_s, 'POOL_URGENCE', '🚨 Remplacement urgent — toujours à pourvoir',
        v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT');
      v_notifies := v_notifies + 1;

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

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
    SELECT a.id, 'ADMIN', 'SYSTEM',
      'Remplacement non pourvu — action requise 🚨',
      'La mission de remplacement "' || fn_html_escape(v_m.intitule) || '" (' || COALESCE(v_m.etab_ville, '') ||
      ') reste SANS candidat 20 min après diffusion. Rayon élargi à 80 km + pool relancé. Une intervention manuelle (appel, pool dédié) est conseillée.',
      '/admin/missions', 'mission', v_m.id
    FROM soignants a
    WHERE a.role = 'ADMIN_PLATEFORME' AND a.supprime_le IS NULL
    LIMIT 5;

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_m.etablissement_id, p_type_acteur := 'SYSTEME',
      p_action := 'REMPLACEMENT_ESCALADE', p_type_ressource := 'mission', p_id_ressource := v_m.id,
      p_details := jsonb_build_object('notifies_elargis', v_notifies, 'rayon_km', 80)
    );
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'escalades', v_escalades, 'notifies', v_notifies);
END;
$function$;

SELECT cron.schedule('escalade-remplacement-non-pourvu', '*/10 * * * *', 'SELECT fn_escalade_remplacement_non_pourvu()');
