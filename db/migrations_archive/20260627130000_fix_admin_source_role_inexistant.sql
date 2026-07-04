-- HOTFIX régression : la table public.soignants n'a PAS de colonne `role`.
-- Les admins plateforme sont identifiés par auth.users.raw_app_meta_data->>'role'
-- = 'ADMIN_PLATEFORME', exposé par la fonction public.fn_list_admin_user_ids().
--
-- Deux fonctions récentes filtraient `FROM soignants a WHERE a.role = 'ADMIN_PLATEFORME'`,
-- ce qui lève ERROR 42703 (undefined_column) AU RUNTIME (plpgsql ne valide pas les
-- références de colonnes à la création) :
--   1. fn_envoyer_message_contact  (migration 20260627110000, "Contacter Jolene")
--      → l'INSERT notif admin plantait et faisait ROLLBACK de TOUT le message :
--        la fonctionnalité entière était cassée (aucun message enregistré).
--   2. fn_escalade_remplacement_non_pourvu (migration 20260627100000, escalade no-show)
--      → l'alerte admin plantait, donc l'escalade ne notifiait jamais l'admin et
--        le cron passait `failed` au 1er remplacement réellement non pourvu.
--
-- Correctifs : admins via fn_list_admin_user_ids(), inserts notif admin enveloppés
-- (BEGIN/EXCEPTION) pour qu'un échec de notif ne casse jamais le flux principal.
-- Bonus escalade : v_notifies remis à zéro par mission (audit exact) + déduplication
-- des soignants sur (type_ressource, id_ressource) plutôt que sur la chaîne `lien`.

CREATE OR REPLACE FUNCTION public.fn_envoyer_message_contact(p_sujet text, p_corps text, p_source text DEFAULT 'aide')
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
$function$;
