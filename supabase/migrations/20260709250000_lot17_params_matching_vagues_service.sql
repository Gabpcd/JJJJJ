-- Lot 17 — Matching alert-first : paramétrage en config + vagues toutes-missions
-- + critère « service » dans le scoring.
--
-- Constats (09/07/2026, définitions LIVE — règle 9.0) :
--   1. Toutes les mécaniques A2/A3/A4 avaient leurs seuils EN DUR dans le SQL
--      (tailles de vague 10/30/60, délais 15/30 min, caps 3/24 h et 20 h,
--      fenêtres J-1 12-36 h / relance 2-12 h / alerte étab 6 h, no-show 30 min).
--      Exigence roadmap : mécaniques livrées, paramètres en configuration.
--   2. Les vagues de notification ne couvraient QUE les missions urgentes —
--      une mission non urgente sans candidature n'était jamais poussée.
--   3. Le champ `service` (libellés normalisés Lot 12) n'était PAS un critère
--      de matching : profession seule en filtre dur, service jamais scoré.

-- ── 1. Paramètres (défauts = valeurs live actuelles ; ON CONFLICT préserve tout réglage manuel)
INSERT INTO parametres_systeme (cle, valeur, label, description, unite, categorie, val_min, val_max, cablee)
VALUES
  ('vague_taille_1', 10,
   'Vague urgente — taille 1',
   'A3 — nombre de soignants notifiés à la première vague (mission urgente < délai 2).',
   'soignants', 'GENERAL', 1, 500, true),
  ('vague_taille_2', 30,
   'Vague urgente — taille 2',
   'A3 — taille de la deuxième vague (mission urgente plus ancienne que le délai 2).',
   'soignants', 'GENERAL', 1, 500, true),
  ('vague_taille_3', 60,
   'Vague urgente — taille 3',
   'A3 — taille des vagues suivantes (mission urgente plus ancienne que le délai 3).',
   'soignants', 'GENERAL', 1, 1000, true),
  ('vague_delai_2_min', 15,
   'Vague urgente — délai 2 (min)',
   'A3 — ancienneté de la mission au-delà de laquelle la vague passe à la taille 2.',
   'minutes', 'GENERAL', 1, 1440, true),
  ('vague_delai_3_min', 30,
   'Vague urgente — délai 3 (min)',
   'A3 — ancienneté au-delà de laquelle la vague passe à la taille 3.',
   'minutes', 'GENERAL', 1, 2880, true),
  ('vague_cap_push_24h', 3,
   'Vague urgente — cap pushs / 24 h',
   'A3 — nombre maximal de notifications MISSION_URGENTE par soignant sur 24 h (anti-spam).',
   'pushs', 'GENERAL', 1, 20, true),
  ('vague_fenetre_urgente_h', 48,
   'Vague urgente — fenêtre (h)',
   'A3 — les vagues urgentes ne concernent que les missions démarrant dans moins de N heures.',
   'heures', 'GENERAL', 1, 168, true),
  ('vague_non_urgente_delai_h', 4,
   'Vague non urgente — délai (h)',
   'A3 — une mission NON urgente sans aucune candidature déclenche une vague unique N heures après sa publication.',
   'heures', 'GENERAL', 1, 168, true),
  ('vague_non_urgente_taille', 20,
   'Vague non urgente — taille',
   'A3 — nombre de soignants notifiés par la vague unique d''une mission non urgente.',
   'soignants', 'GENERAL', 1, 500, true),
  ('vague_non_urgente_cap_24h', 2,
   'Vague non urgente — cap / 24 h',
   'A3 — nombre maximal de notifications MISSION_A_POURVOIR par soignant sur 24 h (toutes missions non urgentes confondues).',
   'pushs', 'GENERAL', 1, 20, true),
  ('alerte_filtre_cap_h', 20,
   'Alertes recherches — cap (h)',
   'A2 — au plus une notification MISSION_A_POURVOIR par soignant par N heures (recherches sauvegardées + matching inversé).',
   'heures', 'GENERAL', 1, 168, true),
  ('confirmation_j1_min_h', 12,
   'Confirmation J-1 — borne basse (h)',
   'A4 — la demande « Je serai là ✓ » part quand la mission démarre entre N heures et la borne haute.',
   'heures', 'GENERAL', 1, 72, true),
  ('confirmation_j1_max_h', 36,
   'Confirmation J-1 — borne haute (h)',
   'A4 — borne haute de la fenêtre de demande de confirmation.',
   'heures', 'GENERAL', 2, 96, true),
  ('relance_presence_max_h', 12,
   'Relance présence — borne haute (h)',
   'A4 — la relance part quand la mission démarre entre 2 h et N heures sans confirmation.',
   'heures', 'GENERAL', 3, 48, true),
  ('alerte_etab_presence_h', 6,
   'Alerte étab présence — seuil (h)',
   'A4 — l''établissement est prévenu quand la mission démarre dans moins de N heures sans confirmation.',
   'heures', 'GENERAL', 2, 24, true),
  ('noshow_detection_min', 30,
   'No-show — détection (min)',
   'A4 — minutes après le début de mission sans pointage avant déclenchement de la procédure no-show.',
   'minutes', 'GENERAL', 5, 240, true),
  ('matching_bonus_service', 4,
   'Matching — bonus service connu',
   'A1 — points ajoutés au score quand le soignant a déjà réalisé une mission dans le même service (libellés normalisés Lot 12).',
   'points', 'GENERAL', 0, 15, true)
ON CONFLICT (cle) DO NOTHING;

-- ── 2. A3 : vagues urgentes paramétrées + vague unique missions non urgentes ─
-- Base = définition LIVE ; ajouts marqués Lot 17. La vague non urgente est
-- UNIQUE par mission (dès qu'une notification MISSION_A_POURVOIR existe pour la
-- mission, plus jamais de nouvelle vague — dédup mission ET soignant garantie).
CREATE OR REPLACE FUNCTION public.fn_vagues_notification_urgentes()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_s RECORD;
  v_taille int;
  v_envoyes int := 0;
  v_missions int := 0;
  v_nu_missions int := 0;
  v_nu_envoyes int := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
  -- Lot 17 : seuils en configuration (défauts = anciennes valeurs en dur).
  v_t1 int := GREATEST(1, fn_param_num('vague_taille_1', 10)::int);
  v_t2 int := GREATEST(1, fn_param_num('vague_taille_2', 30)::int);
  v_t3 int := GREATEST(1, fn_param_num('vague_taille_3', 60)::int);
  v_d2 int := GREATEST(1, fn_param_num('vague_delai_2_min', 15)::int);
  v_d3 int := GREATEST(1, fn_param_num('vague_delai_3_min', 30)::int);
  v_cap int := GREATEST(1, fn_param_num('vague_cap_push_24h', 3)::int);
  v_fenetre_h int := GREATEST(1, fn_param_num('vague_fenetre_urgente_h', 48)::int);
  v_nu_delai_h int := GREATEST(1, fn_param_num('vague_non_urgente_delai_h', 4)::int);
  v_nu_taille int := GREATEST(1, fn_param_num('vague_non_urgente_taille', 20)::int);
  v_nu_cap int := GREATEST(1, fn_param_num('vague_non_urgente_cap_24h', 2)::int);
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
      AND m.debut_le BETWEEN NOW() AND NOW() + make_interval(hours => v_fenetre_h)
      AND m.intitule NOT LIKE '[%'                        -- jamais les missions de test
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id)
  LOOP
    v_missions := v_missions + 1;
    -- Taille de vague selon l'ancienneté de la mission (cron */15 → deltas).
    v_taille := CASE
      WHEN v_m.cree_le > NOW() - make_interval(mins => v_d2) THEN v_t1
      WHEN v_m.cree_le > NOW() - make_interval(mins => v_d3) THEN v_t2
      ELSE v_t3
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
        -- anti-spam : max N pushs urgents / 24 h / soignant (param)
        AND (SELECT COUNT(*) FROM notifications n2
             WHERE n2.destinataire_id = s.id AND n2.type = 'MISSION_URGENTE'
               AND n2.cree_le > NOW() - INTERVAL '24 hours') < v_cap
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

  -- Lot 17 (A3) : VAGUE UNIQUE pour les missions NON urgentes restées sans
  -- candidature N heures après publication. Une seule vague par mission :
  -- si une notification MISSION_A_POURVOIR pointe déjà vers la mission,
  -- elle n'est JAMAIS re-diffusée (dédup mission + soignant).
  FOR v_m IN
    SELECT m.id, m.intitule, m.profession_requise, m.taux_horaire_base,
           m.debut_le, m.etablissement_id,
           e.adresse_ville AS etab_ville, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND NOT m.est_urgente
      AND m.remplacement_de_mission_id IS NULL
      AND m.cree_le < NOW() - make_interval(hours => v_nu_delai_h)
      AND m.debut_le > NOW()
      AND m.intitule NOT LIKE '[%'
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id)
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.type = 'MISSION_A_POURVOIR'
          AND n.lien = '/soignant/missions/' || m.id)
  LOOP
    v_nu_missions := v_nu_missions + 1;
    v_corps := fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') ||
               ', débute le ' || TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
               ' à ' || COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. Personne n''a encore postulé.';

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
        AND (SELECT COUNT(*) FROM notifications n2
             WHERE n2.destinataire_id = s.id AND n2.type = 'MISSION_A_POURVOIR'
               AND n2.cree_le > NOW() - INTERVAL '24 hours') < v_nu_cap
      ORDER BY COALESCE(ms.score_global, 0) DESC,
               fn_haversine_distance_m(COALESCE(s.adresse_lat, 0), COALESCE(s.adresse_lng, 0),
                                       COALESCE(v_m.etab_lat, 0), COALESCE(v_m.etab_lng, 0)) ASC
      LIMIT v_nu_taille
    LOOP
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_s.soignant_id, 'MISSION_A_POURVOIR',
        '✨ Une mission sélectionnée pour toi',
        v_corps, '/soignant/missions/' || v_m.id, 'SOIGNANT');

      IF v_token IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_s.soignant_id, 'type_evenement', 'MISSION_A_POURVOIR',
              'titre', '✨ Une mission sélectionnée pour toi', 'corps', v_corps,
              'data', jsonb_build_object('mission_id', v_m.id, 'lien', '/soignant/missions/' || v_m.id)
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      v_nu_envoyes := v_nu_envoyes + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'missions', v_missions, 'notifications', v_envoyes,
                            'missions_non_urgentes', v_nu_missions, 'notifications_non_urgentes', v_nu_envoyes);
END;
$function$;

-- ── 3. A4 : fenêtres de confirmation présence paramétrées ────────────────────
-- Base = définition LIVE ; seuls les intervalles passent en fn_param_num.
CREATE OR REPLACE FUNCTION public.fn_demander_confirmations_presence()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_nb int := 0;
  v_relances int := 0;
  v_alertes_etab int := 0;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_corps text;
  -- Lot 17 : fenêtres en configuration (défauts = anciennes valeurs en dur).
  v_j1_min int := GREATEST(1, fn_param_num('confirmation_j1_min_h', 12)::int);
  v_j1_max int := GREATEST(2, fn_param_num('confirmation_j1_max_h', 36)::int);
  v_relance_max int := GREATEST(3, fn_param_num('relance_presence_max_h', 12)::int);
  v_alerte_etab int := GREATEST(2, fn_param_num('alerte_etab_presence_h', 6)::int);
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
      AND m.debut_le BETWEEN NOW() + make_interval(hours => v_j1_min) AND NOW() + make_interval(hours => v_j1_max)
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
      AND m.debut_le BETWEEN NOW() + INTERVAL '2 hours' AND NOW() + make_interval(hours => v_relance_max)
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
      AND m.debut_le BETWEEN NOW() + INTERVAL '2 hours' AND NOW() + make_interval(hours => v_alerte_etab)
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
$function$;

-- ── 4. A4 : seuil de détection no-show paramétré ──────────────────────────────
-- Base = définition LIVE ; seul le seuil « 30 minutes » passe en paramètre
-- (condition + textes de notification interpolés).
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
  -- Lot 17 : seuil en configuration (défaut = ancienne valeur en dur).
  v_seuil_min int := GREATEST(5, fn_param_num('noshow_detection_min', 30)::int);
BEGIN
  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_token := NULL; END;

  FOR v_m IN
    SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng, e.adresse_ville AS etab_ville
    FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
      AND m.soignant_assigne_id IS NOT NULL
      AND m.debut_le < NOW() - make_interval(mins => v_seuil_min)
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
        'Aucun pointage détecté ' || v_seuil_min || ' min après le début de "' || fn_html_escape(v_m.intitule) ||
        '". Garantie remplacement activée : une mission de remplacement urgente vient d''être diffusée au pool de soignants disponibles.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');

      UPDATE missions SET statut = 'ABSENCE', absence_sans_prevenir = TRUE, modifie_le = NOW()
       WHERE id = v_m.id;

      v_remplacements := v_remplacements + 1;
    ELSE
      INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
      VALUES (v_m.etablissement_id, 'SYSTEM', 'Aucun pointage détecté ⚠️',
        'Aucun pointage ' || v_seuil_min || ' min après le début de "' || fn_html_escape(v_m.intitule) ||
        '". Contactez le soignant, ou alertez le pool d''urgence depuis la mission.',
        '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');
    END IF;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_m.soignant_assigne_id, 'SYSTEM', 'Aucun pointage détecté sur votre mission',
      'Votre mission "' || fn_html_escape(v_m.intitule) || '" a démarré il y a ' || v_seuil_min || ' min sans pointage. ' ||
      'Pointez immédiatement ou contactez l''établissement — une absence non justifiée impacte fortement votre score de fiabilité.',
      '/soignant/presences', 'SOIGNANT');
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'detectes', v_traites, 'remplacements', v_remplacements);
END;
$function$;

-- ── 5. A2 : cap de fréquence des alertes recherches paramétré ─────────────────
-- Base = définition LIVE ; seul le « 20 hours » passe en paramètre.
CREATE OR REPLACE FUNCTION public.fn_evaluer_alertes_filtres(p_frequence text DEFAULT NULL::text)
 RETURNS TABLE(filtre_id uuid, utilisateur_id uuid, audience filtre_audience, nom text, nb_nouveaux integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  r RECORD;
  v_count integer;
  -- Lot 17 : cap en configuration (défaut = ancienne valeur en dur).
  v_cap_h int := GREATEST(1, fn_param_num('alerte_filtre_cap_h', 20)::int);
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
      -- par N h (param) et par soignant, toutes recherches confondues (anti-spam).
      IF r.audience = 'SOIGNANT_RECHERCHE_MISSIONS' AND NOT EXISTS (
        SELECT 1 FROM notifications n
         WHERE n.destinataire_id = r.utilisateur_id
           AND n.type = 'MISSION_A_POURVOIR'
           AND n.cree_le > now() - make_interval(hours => v_cap_h)
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
$function$;

-- ── 6. A1 : critère « service » dans le scoring ───────────────────────────────
-- Base = définition LIVE (v3) ; ajout du bonus service (libellés normalisés
-- Lot 12, comparaison insensible casse/espaces) quand le soignant a déjà
-- réalisé une mission TERMINEE dans le même service — n'importe quel étab.
CREATE OR REPLACE FUNCTION public.fn_calculer_score_matching(p_soignant_id uuid, p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant record;
  v_mission record;
  v_etab record;
  v_prefs record;
  v_taux_median numeric;
  v_distance_km numeric;
  v_ratio numeric;
  v_est_nuit boolean;
  v_est_we boolean;
  v_score_tarif integer := 0;
  v_score_distance integer := 0;
  v_score_horaire integer := 0;
  v_score_etab integer := 0;
  v_score_urgence integer := 0;
  v_score_soignant_fiabilite integer := 0;
  v_bonus_fraicheur integer := 0;
  v_bonus_connaissance integer := 0;
  v_bonus_paiement_rapide integer := 0;
  v_bonus_boost integer := 0;
  v_bonus_service integer := 0;
  v_score_global integer := 0;
  v_breakdown jsonb;
BEGIN
  SELECT id, profession, adresse_lat, adresse_lng, score_fiabilite, type_contrat
    INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id;

  IF v_soignant.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'soignant_introuvable'));
  END IF;

  SELECT m.id, m.profession_requise, m.etablissement_id, m.taux_horaire_base,
         m.statut, m.est_urgente, m.debut_le, m.fin_le, m.duree_heures,
         m.cree_le, m.boostee_le, m.type_contrat_recherche, m.service
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id;

  IF v_mission.id IS NULL THEN
    RETURN jsonb_build_object('score', 0, 'breakdown', jsonb_build_object('error', 'mission_introuvable'));
  END IF;

  IF v_mission.profession_requise IS NOT NULL
     AND v_soignant.profession IS NOT NULL
     AND v_mission.profession_requise <> v_soignant.profession THEN
    RETURN jsonb_build_object(
      'score', 0,
      'breakdown', jsonb_build_object('filtre_dur_ko', 'profession_incompatible')
    );
  END IF;

  SELECT id, adresse_lat, adresse_lng, score_qualite,
         mode_paiement_commission, stripe_sepa_payment_method_id
    INTO v_etab
    FROM public.etablissements
   WHERE id = v_mission.etablissement_id;

  IF v_soignant.adresse_lat IS NOT NULL
     AND v_soignant.adresse_lng IS NOT NULL
     AND v_etab.adresse_lat IS NOT NULL
     AND v_etab.adresse_lng IS NOT NULL THEN
    v_distance_km := 6371 * acos(
      cos(radians(v_soignant.adresse_lat)) * cos(radians(v_etab.adresse_lat))
      * cos(radians(v_etab.adresse_lng) - radians(v_soignant.adresse_lng))
      + sin(radians(v_soignant.adresse_lat)) * sin(radians(v_etab.adresse_lat))
    );

    IF v_distance_km > 50 THEN
      RETURN jsonb_build_object(
        'score', 0,
        'breakdown', jsonb_build_object(
          'filtre_dur_ko', 'distance_excessive',
          'distance_km', round(v_distance_km, 1)
        )
      );
    END IF;
  ELSE
    v_distance_km := NULL;
  END IF;

  -- v3 : tarif RELATIF à la médiane de marché de la profession (90 j).
  -- ratio 0,7× → 2 pts, 1,0× → ~13 pts, ≥1,2× → 20 pts. Fallback ancien
  -- barème (seuil 30 €) si pas assez de données de marché.
  SELECT taux_median INTO v_taux_median
    FROM public.marche_taux_medians
   WHERE profession = v_mission.profession_requise::text;

  IF v_mission.taux_horaire_base IS NULL THEN
    v_score_tarif := 10;
  ELSIF v_taux_median IS NOT NULL AND v_taux_median > 0 THEN
    v_ratio := v_mission.taux_horaire_base / v_taux_median;
    v_score_tarif := LEAST(20, GREATEST(2, round(2 + (v_ratio - 0.7) / 0.5 * 18)::integer));
  ELSE
    v_score_tarif := LEAST(20, GREATEST(0,
      CASE WHEN v_mission.taux_horaire_base >= 30 THEN 20
           ELSE round(v_mission.taux_horaire_base / 30.0 * 20)::integer END));
  END IF;

  v_score_distance := CASE
    WHEN v_distance_km IS NULL THEN 10
    WHEN v_distance_km < 5 THEN 20
    WHEN v_distance_km >= 50 THEN 0
    ELSE round(20 * (1 - (v_distance_km - 5) / 45.0))::integer
  END;

  -- v3 : pattern horaire appris — 15 × moyenne(pref tranche-heure, pref
  -- tranche-semaine). Neutre (7-8 pts) sans historique de swipe.
  v_est_nuit := v_mission.debut_le IS NOT NULL AND (
    EXTRACT(HOUR FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') >= 20
    OR EXTRACT(HOUR FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') < 7);
  v_est_we := v_mission.debut_le IS NOT NULL
    AND EXTRACT(DOW FROM v_mission.debut_le AT TIME ZONE 'Europe/Paris') IN (0, 6);

  SELECT * INTO v_prefs
    FROM public.matching_preferences_soignant
   WHERE soignant_id = p_soignant_id;

  v_score_horaire := round(15 * (
    (CASE WHEN v_est_nuit THEN COALESCE(v_prefs.pref_nuit, 0.5) ELSE COALESCE(v_prefs.pref_jour, 0.5) END
     + CASE WHEN v_est_we THEN COALESCE(v_prefs.pref_weekend, 0.5) ELSE COALESCE(v_prefs.pref_semaine, 0.5) END
    ) / 2.0))::integer;

  v_score_etab := LEAST(15, GREATEST(0,
    CASE
      WHEN v_etab.score_qualite IS NULL THEN 7
      ELSE round(v_etab.score_qualite / 100.0 * 15)::integer
    END
  ));

  v_score_urgence := CASE WHEN v_mission.est_urgente THEN 10 ELSE 0 END;

  v_score_soignant_fiabilite := LEAST(10, GREATEST(0,
    CASE
      WHEN v_soignant.score_fiabilite IS NULL THEN 5
      ELSE round(COALESCE(v_soignant.score_fiabilite, 50) / 100.0 * 10)::integer
    END
  ));

  v_bonus_fraicheur := LEAST(5, GREATEST(0,
    5 - FLOOR(EXTRACT(EPOCH FROM (NOW() - COALESCE(v_mission.cree_le, NOW()))) / 86400)::integer
  ));

  -- v3 : bonus fort « tu connais cet établissement » (mission déjà réalisée).
  v_bonus_connaissance := CASE WHEN EXISTS (
    SELECT 1 FROM public.missions mh
     WHERE mh.soignant_assigne_id = p_soignant_id
       AND mh.etablissement_id = v_mission.etablissement_id
       AND mh.statut = 'TERMINEE'
  ) THEN 8 ELSE 0 END;

  -- Lot 17 (A1) : bonus « tu connais ce service » — mission TERMINEE dans le
  -- même service (libellé normalisé Lot 12), quel que soit l'établissement.
  v_bonus_service := CASE WHEN
    v_mission.service IS NOT NULL
    AND btrim(v_mission.service) <> ''
    AND EXISTS (
      SELECT 1 FROM public.missions mh
       WHERE mh.soignant_assigne_id = p_soignant_id
         AND mh.statut = 'TERMINEE'
         AND mh.service IS NOT NULL
         AND lower(btrim(mh.service)) = lower(btrim(v_mission.service))
    )
  THEN GREATEST(0, public.fn_param_num('matching_bonus_service', 4)::integer) ELSE 0 END;

  -- v3 : bonus ⚡ paiement rapide (même gating serveur que le badge 7c).
  v_bonus_paiement_rapide := CASE WHEN
    public.fn_param_num('feature_paiement_rapide_actif', 0) = 1
    AND v_mission.type_contrat_recherche = 'LIBERAL'
    AND v_etab.mode_paiement_commission = 'SEPA_DEBIT'
    AND v_etab.stripe_sepa_payment_method_id IS NOT NULL
  THEN 5 ELSE 0 END;

  v_bonus_boost := CASE
    WHEN v_mission.boostee_le IS NOT NULL AND v_mission.boostee_le > NOW() - INTERVAL '7 days' THEN 10
    ELSE 0
  END;

  v_score_global := v_score_tarif + v_score_distance + v_score_horaire + v_score_etab
                  + v_score_urgence + v_score_soignant_fiabilite
                  + v_bonus_fraicheur + v_bonus_connaissance + v_bonus_service
                  + v_bonus_paiement_rapide + v_bonus_boost;

  v_breakdown := jsonb_build_object(
    'tarif', v_score_tarif,
    'distance', v_score_distance,
    'horaire', v_score_horaire,
    'etablissement', v_score_etab,
    'urgence', v_score_urgence,
    'soignant_fiabilite', v_score_soignant_fiabilite,
    'fraicheur', v_bonus_fraicheur,
    'connaissance_etab', v_bonus_connaissance,
    'service', v_bonus_service,
    'paiement_rapide', v_bonus_paiement_rapide,
    'boost', v_bonus_boost,
    'distance_km', CASE WHEN v_distance_km IS NULL THEN NULL ELSE round(v_distance_km, 1) END,
    'taux_median', v_taux_median
  );

  RETURN jsonb_build_object(
    'score', LEAST(100, GREATEST(0, v_score_global)),
    'breakdown', v_breakdown
  );
END;
$function$;
