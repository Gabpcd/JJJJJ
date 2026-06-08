-- Pool urgence — diffusion à TOUT le pool compatible + exclusion des soignants
-- déjà en mission sur le créneau + suppression du code mort.
--
-- Demande produit : quand une mission urgente est créée, l'offre doit partir
-- automatiquement à TOUS les soignants du pool urgence de la bonne profession et
-- dans le bon périmètre géographique, SAUF ceux déjà en mission à ces dates.
--
-- Avant : fn_trg_auto_notify_mission_urgente plafonnait à LIMIT 50 (les 50 plus
-- proches) et ne vérifiait pas les chevauchements de créneaux.
-- Après : plus de plafond + exclusion NOT EXISTS chevauchement (même logique que
-- dec_refuser_chevauchement_soignant : ASSIGNEE/EN_COURS, debut < fin AND fin > debut).
--
-- Bonus cleanup : DROP fn_trg_auto_proposition_pool_urgence — fonction orpheline
-- (jamais attachée comme trigger), version inférieure SANS filtre géo (LIMIT 10).

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
  v_url TEXT;
  v_token TEXT;
  v_should_fire BOOLEAN := false;
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
  INTO v_etab
  FROM etablissements
  WHERE id = NEW.etablissement_id;

  BEGIN
    v_url := public.fn_lire_secret_cron('supabase_url');
    v_token := public.fn_lire_secret_cron('service_role_key');
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL;
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
      AND NOT EXISTS (
        SELECT 1 FROM candidatures c
        WHERE c.mission_id = NEW.id AND c.soignant_id = s.id
      )
      -- Exclure les soignants déjà en mission sur le créneau (même logique que
      -- dec_refuser_chevauchement_soignant). Inutile de leur proposer.
      AND NOT EXISTS (
        SELECT 1 FROM missions m2
        WHERE m2.soignant_assigne_id = s.id
          AND m2.id <> NEW.id
          AND m2.statut IN ('ASSIGNEE', 'EN_COURS')
          AND m2.debut_le < NEW.fin_le
          AND m2.fin_le > NEW.debut_le
      )
      AND (COALESCE(s.type_exercice, 'SALARIE') NOT IN ('LIBERAL','MIXTE')
           OR COALESCE(s.mandat_facturation_signe, false) = true)
      AND (s.profession::text IN ('AS','AES')
           OR COALESCE(s.rpps_verifie, false) = true)
      AND (
        v_etab.adresse_lat IS NULL OR s.adresse_lat IS NULL OR
        (6371 * 2 * asin(sqrt(
          power(sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2), 2) +
          cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
          power(sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2), 2)
        ))) <= COALESCE(s.urgence_rayon_km, 30)
      )
    ORDER BY distance_km ASC NULLS LAST, COALESCE(s.score_fiabilite, 0) DESC
    -- Plus de LIMIT : on notifie TOUT le pool compatible dans le périmètre.
  LOOP
    INSERT INTO notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    ) VALUES (
      v_soignant.id, 'SOIGNANT', 'MISSION_URGENTE',
      '🚨 Mission urgente près de chez vous',
      'Mission ' || COALESCE(NEW.intitule, NEW.profession_requise::text)
        || ' à ' || COALESCE(v_etab.adresse_ville, 'votre zone')
        || CASE WHEN v_soignant.distance_km IS NOT NULL THEN ' (' || ROUND(v_soignant.distance_km::numeric, 1) || ' km)' ELSE '' END
        || ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h. Acceptez en 1 clic.',
      '/soignant/pool-urgence',
      'mission', NEW.id
    );

    IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'type', 'MISSION_URGENTE_POOL',
            'destinataire_id', v_soignant.id,
            'data', jsonb_build_object(
              'prenom', v_soignant.prenom,
              'mission_id', NEW.id,
              'mission_intitule', NEW.intitule,
              'profession', NEW.profession_requise::text,
              'ville', v_etab.adresse_ville,
              'distance_km', v_soignant.distance_km,
              'taux_horaire', NEW.taux_horaire_base,
              'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;

      IF v_soignant.sms_opt_in = true AND COALESCE(v_soignant.telephone, '') <> '' THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-sms',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
            body := jsonb_build_object(
              'destinataire_id', v_soignant.id,
              'telephone', v_soignant.telephone,
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
      p_acteur_id := NEW.etablissement_id,
      p_type_acteur := 'SYSTEME',
      p_action := 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES',
      p_type_ressource := 'mission',
      p_id_ressource := NEW.id,
      p_details := jsonb_build_object(
        'count', v_count,
        'mission_intitule', NEW.intitule,
        'event', TG_OP,
        'transition', CASE WHEN TG_OP = 'UPDATE' THEN OLD.statut::text || ' -> ' || NEW.statut::text ELSE 'INSERT' END
      )
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- Cleanup : suppression de la fonction orpheline (jamais attachée, version sans géo)
DROP FUNCTION IF EXISTS public.fn_trg_auto_proposition_pool_urgence();
