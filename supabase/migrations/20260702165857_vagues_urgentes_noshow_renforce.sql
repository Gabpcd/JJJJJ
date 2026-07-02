-- 7d-B (Lot 7 v2 — A3 vagues urgentes + A4 no-show renforcé).
--
-- A3 — vagues de notification pour les missions urgentes (<48 h) : push aux
-- N meilleurs matchs d'abord, élargissement toutes les ~15 min sans
-- candidature. Le push paraît exclusif, l'établissement remplit vite,
-- personne n'est spammé. ADDITIF : le pool opt-in disponible_urgence et la
-- chaîne remplacement no-show existants ne changent pas.
--   vague 1 (création)   : top 10 par score de matching
--   vague 2 (T+15 min)   : top 30
--   vague 3 (T+30 min)   : top 60
-- La taille de vague dépend du temps écoulé ; la dédup par (soignant, mission)
-- fait que chaque passage du cron (*/15) n'envoie que le delta.
-- Anti-spam : max 3 pushs urgents / 24 h / soignant, jamais aux exclus ni aux
-- soignants ayant déjà swipé la mission.
--
-- A4 — prédiction no-show :
--   1. la demande de confirmation J-1 (existante) envoie désormais AUSSI un
--      push natif (« Ta mission demain — Je serai là ✓ »)
--   2. relance H-12→H-2 si non confirmée (notification + push)
--   3. alerte préventive à l'établissement à H-6 si toujours pas confirmée
--   4. au no-show avéré : les candidats NON RETENUS de la mission originale
--      sont recontactés EN PRIORITÉ avant le broadcast général (backup).

-- ── A3 : vagues de notification urgentes ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_vagues_notification_urgentes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_m RECORD;
  v_s RECORD;
  v_taille int;
  v_envoyes int := 0;
  v_missions int := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL; END;

  FOR v_m IN
    SELECT m.id, m.intitule, m.profession_requise, m.taux_horaire_base,
           m.debut_le, m.cree_le, m.etablissement_id,
           e.adresse_ville AS etab_ville, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.est_urgente
      AND m.remplacement_de_mission_id IS NULL           -- la chaîne remplacement a sa propre diffusion
      AND m.debut_le BETWEEN NOW() AND NOW() + INTERVAL '48 hours'
      AND m.intitule NOT LIKE '[%'                        -- jamais les missions de test
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id)
  LOOP
    v_missions := v_missions + 1;
    -- Taille de vague selon l'ancienneté de la mission (cron */15 → deltas).
    v_taille := CASE
      WHEN v_m.cree_le > NOW() - INTERVAL '15 minutes' THEN 10
      WHEN v_m.cree_le > NOW() - INTERVAL '30 minutes' THEN 30
      ELSE 60
    END;

    v_corps := fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') ||
               ', débute le ' || TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
               ' à ' || COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h.';

    FOR v_s IN
      SELECT s.id AS soignant_id
      FROM soignants s
      LEFT JOIN matching_scores ms ON ms.soignant_id = s.id AND ms.mission_id = v_m.id
      WHERE s.profession = v_m.profession_requise
        AND s.supprime_le IS NULL
        AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
        AND COALESCE(s.tous_documents_valides, false)
        AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
        AND NOT EXISTS (SELECT 1 FROM swipes sw WHERE sw.mission_id = v_m.id AND sw.soignant_id = s.id)
        AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
             OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
                <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
        -- dédup par (soignant, mission) : chaque cron n'envoie que le delta
        AND NOT EXISTS (
          SELECT 1 FROM notifications n
          WHERE n.destinataire_id = s.id AND n.type = 'MISSION_URGENTE'
            AND n.lien = '/soignant/missions/' || v_m.id)
        -- anti-spam : max 3 pushs urgents / 24 h / soignant
        AND (SELECT COUNT(*) FROM notifications n2
             WHERE n2.destinataire_id = s.id AND n2.type = 'MISSION_URGENTE'
               AND n2.cree_le > NOW() - INTERVAL '24 hours') < 3
      ORDER BY COALESCE(ms.score_global, 0) DESC,
               fn_haversine_distance_m(COALESCE(s.adresse_lat, 0), COALESCE(s.adresse_lng, 0),
                                       COALESCE(v_m.etab_lat, 0), COALESCE(v_m.etab_lng, 0)) ASC
      LIMIT v_taille
    LOOP
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_s.soignant_id, 'MISSION_URGENTE',
        '⚡ Mission urgente sélectionnée pour toi',
        v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT');

      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_s.soignant_id, 'type_evenement', 'MISSION_URGENTE',
              'titre', '⚡ Mission urgente sélectionnée pour toi', 'corps', v_corps,
              'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/missions/' || v_m.id)
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      v_envoyes := v_envoyes + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'missions', v_missions, 'notifications', v_envoyes);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_vagues_notification_urgentes() TO service_role;

DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('vagues-notification-urgentes')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'vagues-notification-urgentes');
    PERFORM cron.schedule('vagues-notification-urgentes', '*/15 * * * *',
      'SELECT public.fn_vagues_notification_urgentes()');
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'schedule vagues-notification-urgentes: %', SQLERRM;
END
$do$;

-- ── A4.1-3 : confirmation J-1 avec push natif + relance H-12 + alerte étab ──
CREATE OR REPLACE FUNCTION public.fn_demander_confirmations_presence()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_m RECORD;
  v_nb int := 0;
  v_relances int := 0;
  v_alertes_etab int := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL; END;

  -- ① Demande J-1 (existant) — désormais avec PUSH NATIF (A4).
  FOR v_m IN
    SELECT m.id, m.intitule, m.debut_le, m.soignant_assigne_id
    FROM missions m
    WHERE m.statut = 'ASSIGNEE'
      AND m.soignant_assigne_id IS NOT NULL
      AND m.presence_confirmee_le IS NULL
      AND m.debut_le BETWEEN NOW() + INTERVAL '12 hours' AND NOW() + INTERVAL '36 hours'
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.destinataire_id = m.soignant_assigne_id AND n.type = 'RAPPEL_MISSION'
          AND n.lien = '/soignant/missions/' || m.id
          AND n.cree_le > NOW() - INTERVAL '20 hours')
  LOOP
    v_corps := '"' || fn_html_escape(v_m.intitule) || '" démarre le ' ||
      TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
      '. Confirme ta présence en 1 clic — l''établissement compte sur toi.';

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.soignant_assigne_id, 'RAPPEL_MISSION', 'Ta mission demain — Je serai là ✓',
      v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT');

    IF v_token IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'destinataire_id', v_m.soignant_assigne_id, 'type_evenement', 'RAPPEL_MISSION',
            'titre', 'Ta mission demain — Je serai là ✓', 'corps', v_corps,
            'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/missions/' || v_m.id)
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    v_nb := v_nb + 1;
  END LOOP;

  -- ② Relance H-12 → H-2 si toujours pas confirmée (A4).
  FOR v_m IN
    SELECT m.id, m.intitule, m.debut_le, m.soignant_assigne_id
    FROM missions m
    WHERE m.statut = 'ASSIGNEE'
      AND m.soignant_assigne_id IS NOT NULL
      AND m.presence_confirmee_le IS NULL
      AND m.debut_le BETWEEN NOW() + INTERVAL '2 hours' AND NOW() + INTERVAL '12 hours'
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.destinataire_id = m.soignant_assigne_id AND n.type = 'RAPPEL_MISSION'
          AND n.lien = '/soignant/missions/' || m.id || '?relance=1'
          AND n.cree_le > NOW() - INTERVAL '10 hours')
  LOOP
    v_corps := 'Toujours partante pour "' || fn_html_escape(v_m.intitule) || '" (' ||
      TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'HH24:MI') ||
      ') ? Confirme en 1 clic — sans nouvelle de ta part, l''établissement sera prévenu.';

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.soignant_assigne_id, 'RAPPEL_MISSION', '⏰ Dernière ligne droite — confirme ta mission',
      v_corps, '/soignant/missions/' || v_m.id || '?relance=1', 'SOIGNANT');

    IF v_token IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'destinataire_id', v_m.soignant_assigne_id, 'type_evenement', 'RAPPEL_MISSION',
            'titre', '⏰ Dernière ligne droite — confirme ta mission', 'corps', v_corps,
            'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/missions/' || v_m.id)
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    v_relances := v_relances + 1;
  END LOOP;

  -- ③ Alerte préventive ÉTABLISSEMENT à H-6 si toujours rien (A4).
  FOR v_m IN
    SELECT m.id, m.intitule, m.debut_le, m.etablissement_id
    FROM missions m
    WHERE m.statut = 'ASSIGNEE'
      AND m.soignant_assigne_id IS NOT NULL
      AND m.presence_confirmee_le IS NULL
      AND m.debut_le BETWEEN NOW() + INTERVAL '2 hours' AND NOW() + INTERVAL '6 hours'
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.destinataire_id = m.etablissement_id AND n.type = 'SYSTEM'
          AND n.lien = '/etablissement/missions/' || m.id
          AND n.titre LIKE 'Présence non confirmée%'
          AND n.cree_le > NOW() - INTERVAL '10 hours')
  LOOP
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.etablissement_id, 'SYSTEM', 'Présence non confirmée ⚠️',
      'Le soignant de "' || fn_html_escape(v_m.intitule) || '" (' ||
      TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI') ||
      ') n''a pas confirmé sa présence malgré nos relances. En cas d''absence, un remplacement sera proposé en priorité aux candidats de la mission.',
      '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');
    v_alertes_etab := v_alertes_etab + 1;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'demandes', v_nb, 'relances', v_relances, 'alertes_etab', v_alertes_etab);
END;
$body$;

-- Le cron existant (confirmations-presence-j1, 17h) ne couvre pas les relances
-- intra-journée : passage à un cadencement horaire (dédups internes = pas de spam).
DO $do2$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('confirmations-presence-j1')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'confirmations-presence-j1');
    PERFORM cron.schedule('confirmations-presence-j1', '10 * * * *',
      'SELECT public.fn_demander_confirmations_presence()');
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'schedule confirmations-presence-j1: %', SQLERRM;
END
$do2$;

-- ── A4.4 : backup d'abord au no-show (fonction complète re-déployée avec le
--          bloc backup + exclusion du broadcast — base : 20260627100000) ─────
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

      -- 7d-B (A4) : BACKUP D'ABORD — les candidats non retenus de la mission
      -- originale sont recontactés en PRIORITÉ (ils voulaient déjà cette
      -- mission : meilleur taux de conversion, zéro spam de découverte).
      FOR v_s IN
        SELECT c.soignant_id FROM candidatures c
        WHERE c.mission_id = v_m.id
          AND c.soignant_id IS NOT NULL
          AND c.soignant_id != v_m.soignant_assigne_id
          AND c.statut::text NOT IN ('ACCEPTEE', 'RETIREE', 'ANNULEE')
          AND NOT fn_est_exclu(c.soignant_id, v_m.etablissement_id)
      LOOP
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_s, 'POOL_URGENCE', '🎯 Une mission où tu avais postulé se libère — priorité à toi',
          v_corps, '/soignant/missions/' || v_remplacement_id, 'SOIGNANT');

        IF v_token IS NOT NULL THEN
          BEGIN
            PERFORM net.http_post(
              url := v_url || '/functions/v1/send-push',
              headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
              body := jsonb_build_object(
                'destinataire_id', v_s, 'type_evenement', 'MISSION_URGENTE',
                'titre', '🎯 Une mission où tu avais postulé se libère', 'corps', v_corps,
                'data', jsonb_build_object('mission_id', v_remplacement_id, 'lien', '/soignant/missions/' || v_remplacement_id)
              )
            );
          EXCEPTION WHEN OTHERS THEN NULL; END;
        END IF;
      END LOOP;


      FOR v_s IN
        SELECT s.id FROM soignants s
        WHERE s.profession = v_m.profession_requise
          AND s.supprime_le IS NULL
          AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
          AND COALESCE(s.tous_documents_valides, false)
          AND COALESCE(s.disponible_urgence, false) = false
          AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
          AND s.id != v_m.soignant_assigne_id
          -- 7d-B : déjà notifiés en priorité par le bloc backup ci-dessus
          AND NOT EXISTS (SELECT 1 FROM candidatures cb
                          WHERE cb.mission_id = v_m.id AND cb.soignant_id = s.id
                            AND cb.statut::text NOT IN ('ACCEPTEE', 'RETIREE', 'ANNULEE'))
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
