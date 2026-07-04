-- FIX CRITIQUE : le broadcast pool urgence + favoris n'envoyait JAMAIS d'email/SMS.
--
-- Cause : fn_trg_auto_notify_mission_urgente et fn_trg_favori_nouvelle_mission
-- lisaient les secrets via public.fn_lire_secret_cron('supabase_url') /
-- ('service_role_key'). Or fn_lire_secret_cron ne prend AUCUN argument → ces
-- appels levaient une exception, attrapée par le bloc EXCEPTION → v_url/v_token
-- restaient NULL → toutes les branches net.http_post (email/SMS) étaient sautées.
-- Seule la notification in-app partait réellement.
--
-- Correctif : on lit le token directement depuis vault.decrypted_secrets (pattern
-- fonctionnel, cf. dec_push_contrat_a_signer) et on fige l'URL du projet.
-- Bonus : ajout du PUSH natif (send-push) au broadcast urgence — canal le plus
-- immédiat, totalement absent jusqu'ici (seuls in-app/email/SMS étaient codés,
-- et même eux ne partaient pas).

CREATE OR REPLACE FUNCTION public.fn_trg_auto_notify_mission_urgente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab RECORD;
  v_count INT := 0;
  v_soignant RECORD;
  v_url TEXT := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token TEXT;
  v_should_fire BOOLEAN := false;
  v_corps TEXT;
BEGIN
  IF (TG_OP = 'INSERT' AND COALESCE(NEW.est_urgente, false) = true AND NEW.statut = 'OUVERTE') THEN
    v_should_fire := true;
  ELSIF (TG_OP = 'UPDATE' AND COALESCE(NEW.est_urgente, false) = true AND NEW.statut = 'OUVERTE'
         AND (
           COALESCE(OLD.est_urgente, false) IS DISTINCT FROM COALESCE(NEW.est_urgente, false)
           OR (OLD.statut = 'ASSIGNEE' AND NEW.statut = 'OUVERTE')
         )) THEN
    v_should_fire := true;
  END IF;

  IF NOT v_should_fire THEN
    RETURN NEW;
  END IF;

  SELECT id, nom, adresse_lat, adresse_lng, adresse_ville
  INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;

  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN
    v_token := NULL;
  END;

  FOR v_soignant IN
    SELECT s.id, s.email, s.prenom, s.telephone,
      COALESCE(s.pool_urgence_sms_opt_in, false) AS sms_opt_in,
      CASE
        WHEN v_etab.adresse_lat IS NOT NULL AND s.adresse_lat IS NOT NULL THEN
          (6371 * 2 * asin(sqrt(
            power(sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2), 2) +
            cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
            power(sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2), 2)
          )))
        ELSE NULL
      END AS distance_km
    FROM soignants s
    WHERE s.supprime_le IS NULL
      AND COALESCE(s.disponible_urgence, false) = true
      AND COALESCE(s.tous_documents_valides, false) = true
      AND public.fn_soignant_compatible_mission(
        s.profession, s.specialite_medicale,
        NEW.profession_requise, NEW.specialite_medicale_requise,
        COALESCE(NEW.accepte_non_specialises, true)
      ) = true
      AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = NEW.id AND c.soignant_id = s.id)
      AND NOT EXISTS (
        SELECT 1 FROM missions m2
        WHERE m2.soignant_assigne_id = s.id AND m2.id <> NEW.id
          AND m2.statut IN ('ASSIGNEE', 'EN_COURS')
          AND m2.debut_le < NEW.fin_le AND m2.fin_le > NEW.debut_le)
      AND (COALESCE(s.type_exercice, 'SALARIE') NOT IN ('LIBERAL','MIXTE')
           OR COALESCE(s.mandat_facturation_signe, false) = true)
      AND (s.profession::text IN ('AS','AES') OR COALESCE(s.rpps_verifie, false) = true)
      AND (
        v_etab.adresse_lat IS NULL OR s.adresse_lat IS NULL OR
        (6371 * 2 * asin(sqrt(
          power(sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2), 2) +
          cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
          power(sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2), 2)
        ))) <= COALESCE(s.urgence_rayon_km, 30)
      )
    ORDER BY distance_km ASC NULLS LAST, COALESCE(s.score_fiabilite, 0) DESC
  LOOP
    v_corps := 'Mission ' || COALESCE(NEW.intitule, NEW.profession_requise::text)
        || ' à ' || COALESCE(v_etab.adresse_ville, 'votre zone')
        || CASE WHEN v_soignant.distance_km IS NOT NULL THEN ' (' || ROUND(v_soignant.distance_km::numeric, 1) || ' km)' ELSE '' END
        || ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h. Acceptez en 1 clic.';

    INSERT INTO notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource
    ) VALUES (
      v_soignant.id, 'SOIGNANT', 'MISSION_URGENTE',
      '🚨 Mission urgente près de chez vous', v_corps,
      '/soignant/pool-urgence', 'mission', NEW.id
    );

    IF v_token IS NOT NULL THEN
      -- PUSH natif (canal le plus immédiat — était absent)
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'destinataire_id', v_soignant.id,
            'type_evenement', 'MISSION_URGENTE',
            'titre', '🚨 Mission urgente près de chez vous',
            'corps', v_corps,
            'data', jsonb_build_object('mission_id', NEW.id, 'lien', '/soignant/pool-urgence')
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;

      -- EMAIL
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'type', 'MISSION_URGENTE_POOL',
            'destinataire_id', v_soignant.id,
            'data', jsonb_build_object(
              'prenom', v_soignant.prenom, 'mission_id', NEW.id, 'mission_intitule', NEW.intitule,
              'profession', NEW.profession_requise::text, 'ville', v_etab.adresse_ville,
              'distance_km', v_soignant.distance_km, 'taux_horaire', NEW.taux_horaire_base, 'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;

      -- SMS (opt-in uniquement)
      IF v_soignant.sms_opt_in = true AND COALESCE(v_soignant.telephone, '') <> '' THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-sms',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_soignant.id, 'telephone', v_soignant.telephone,
              'message', 'URGENT - Mission ' || COALESCE(NEW.profession_requise::text, '')
                || ' ' || COALESCE(v_etab.adresse_ville, '')
                || ' ' || TO_CHAR(NEW.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24h')
                || ' - ' || COALESCE(NEW.taux_horaire_base::text, '?') || E'€/h - Acceptez sur jolene.app/pool-urgence'
            )
          );
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := NEW.etablissement_id, p_type_acteur := 'SYSTEME',
      p_action := 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES', p_type_ressource := 'mission', p_id_ressource := NEW.id,
      p_details := jsonb_build_object('count', v_count, 'mission_intitule', NEW.intitule, 'event', TG_OP,
        'canaux', jsonb_build_array('in_app', 'push', 'email', 'sms_opt_in'))
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- Même bug de secrets sur le broadcast "favori → nouvelle mission".
CREATE OR REPLACE FUNCTION public.fn_trg_favori_nouvelle_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab RECORD;
  v_soignant_id UUID;
  v_url TEXT := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token TEXT;
BEGIN
  IF TG_OP <> 'INSERT' OR NEW.statut <> 'OUVERTE' THEN RETURN NEW; END IF;

  SELECT id, nom, adresse_ville INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;

  BEGIN
    v_token := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN
    v_token := NULL;
  END;

  FOR v_soignant_id IN
    SELECT f.soignant_id FROM favoris_soignant_etab f
    JOIN soignants s ON s.id = f.soignant_id AND s.supprime_le IS NULL
    WHERE f.etablissement_id = NEW.etablissement_id
      AND public.fn_soignant_compatible_mission(
        s.profession, s.specialite_medicale,
        NEW.profession_requise, NEW.specialite_medicale_requise,
        COALESCE(NEW.accepte_non_specialises, true)
      ) = true
  LOOP
    IF public.fn_doit_notifier(v_soignant_id, 'FAVORI_NOUVELLE_MISSION'::type_evenement_notification, 'IN_APP'::canal_notification) THEN
      INSERT INTO notifications (
        destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource
      ) VALUES (
        v_soignant_id, 'SOIGNANT', 'FAVORI_NOUVELLE_MISSION',
        '⭐ Nouvelle mission chez ' || v_etab.nom,
        v_etab.nom || ' a publié "' || COALESCE(NEW.intitule, NEW.profession_requise::text)
          || '" à ' || COALESCE(v_etab.adresse_ville, 'votre zone')
          || ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h.',
        '/soignant/missions/' || NEW.id::text, 'mission', NEW.id
      );
    END IF;

    IF v_token IS NOT NULL
       AND public.fn_doit_notifier(v_soignant_id, 'FAVORI_NOUVELLE_MISSION'::type_evenement_notification, 'EMAIL'::canal_notification) THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'type', 'FAVORI_NOUVELLE_MISSION',
            'destinataire_id', v_soignant_id,
            'data', jsonb_build_object(
              'mission_id', NEW.id, 'mission_intitule', NEW.intitule,
              'etab_nom', v_etab.nom, 'etab_ville', v_etab.adresse_ville,
              'taux_horaire', NEW.taux_horaire_base, 'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;
