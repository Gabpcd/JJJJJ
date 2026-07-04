-- Anti-triche GPS : pénalité automatique sur téléportation détectée.
--
-- Avant : fn_detecter_teleportations ne faisait QUE flaguer
-- (presences.alerte_teleportation = true + journaux_audit + alerte admin).
-- Aucune conséquence automatique sur le score de fiabilité du soignant.
--
-- Après :
--  1. Le type d'événement 'FRAUDE_GPS' est autorisé dans evenements_score_soignant.
--  2. fn_calculer_score_fiabilite_v2 intègre un malus piloté par les événements
--     FRAUDE_GPS non annulés (points_corriges prime si l'admin a tranché une
--     réclamation), plafonné à -30 sur 12 mois glissants.
--  3. fn_detecter_teleportations crée, pour chaque téléportation, un événement
--     FRAUDE_GPS CONTESTABLE (-10 pts, dédoublonné par présence destination) puis
--     recalcule le score du soignant.
--
-- Le caractère CONTESTABLE permet à l'admin de neutraliser le malus via le
-- système de réclamation existant (points_corriges) : la résolution admin
-- retire automatiquement la pénalité au prochain recalcul.

-- 1. Autoriser le type FRAUDE_GPS
ALTER TABLE public.evenements_score_soignant
  DROP CONSTRAINT IF EXISTS evenements_score_soignant_type_evenement_check;
ALTER TABLE public.evenements_score_soignant
  ADD CONSTRAINT evenements_score_soignant_type_evenement_check
  CHECK (type_evenement = ANY (ARRAY[
    'ANNULATION_12_24H'::text, 'ANNULATION_1_12H'::text, 'ASAP_ANNULEE_APRES_FENETRE'::text,
    'NO_SHOW'::text, 'LITIGE_TORT_RECONNU'::text, 'NOTE_BASSE_RECUE'::text,
    'EVALUATION_NEGATIVE'::text, 'BONUS_AMBASSADEUR'::text, 'BONUS_FIDELITE'::text,
    'FRAUDE_GPS'::text, 'AUTRE'::text]));

-- 2. Score : intégration du malus FRAUDE_GPS
CREATE OR REPLACE FUNCTION public.fn_calculer_score_fiabilite_v2(p_soignant_id uuid, p_raison text DEFAULT 'recalcul'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_soignant RECORD;
  v_since TIMESTAMPTZ;
  v_total_missions_terminees INT;
  v_notation_etab NUMERIC;
  v_presentisme NUMERIC;
  v_ponctualite NUMERIC;
  v_reactivite NUMERIC;
  v_anciennete_volume NUMERIC;
  v_notation_par_soignant NUMERIC;
  v_p_notation_etab NUMERIC := 35;
  v_p_presentisme NUMERIC := 20;
  v_p_ponctualite NUMERIC := 15;
  v_p_reactivite NUMERIC := 10;
  v_p_anciennete_volume NUMERIC := 10;
  v_p_notation_par_soignant NUMERIC := 10;
  v_pe_notation_etab NUMERIC;
  v_pe_presentisme NUMERIC;
  v_pe_ponctualite NUMERIC;
  v_pe_reactivite NUMERIC;
  v_pe_anciennete_volume NUMERIC;
  v_pe_notation_par_soignant NUMERIC;
  v_total_poids_actifs NUMERIC := 0;
  v_facteur_redistribution NUMERIC := 1;
  v_litiges_malus NUMERIC := 0;
  v_absence_malus NUMERIC := 0;
  v_fraude_gps_malus NUMERIC := 0;
  v_bonus_super_actif NUMERIC := 0;
  v_bonus_urgence NUMERIC := 0;
  v_score NUMERIC := 0;
  v_niveau public.niveau_qualitatif;
  v_probatoire BOOLEAN;
  v_actives_count INT := 0;
  v_inactives_json JSONB := '[]'::jsonb;
  v_breakdown_id UUID;
  v_nb_terminees_12m INT;
  v_nb_litiges INT;
  v_nb_absences INT;
  v_nb_decisions_cand INT;
  v_delai_moyen_h NUMERIC;
  v_nb_notations INT;
  v_nb_notations_par_soignant INT;
  v_pct_notations_donnees NUMERIC;
BEGIN
  v_since := NOW() - INTERVAL '12 months';

  SELECT id, prevoyance_inscrit INTO v_soignant FROM soignants WHERE id = p_soignant_id;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  SELECT COUNT(*) INTO v_total_missions_terminees FROM missions
  WHERE soignant_assigne_id = p_soignant_id AND statut = 'TERMINEE';

  v_probatoire := v_total_missions_terminees < 3;

  SELECT COUNT(*) INTO v_nb_terminees_12m FROM missions
  WHERE soignant_assigne_id = p_soignant_id AND statut = 'TERMINEE' AND fin_le >= v_since;

  SELECT COUNT(*),
    SUM(((critere_1 + critere_2 + critere_3 + critere_4) / 4.0) * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))) /
    NULLIF(SUM(GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))), 0)
  INTO v_nb_notations, v_notation_etab
  FROM notations_missions
  WHERE note_id = p_soignant_id AND sens = 'ETAB_VERS_SOIGNANT'
    AND cree_le >= v_since AND masque = false;

  IF v_nb_notations < 3 OR v_notation_etab IS NULL THEN
    v_notation_etab := NULL;
  ELSE
    v_notation_etab := GREATEST(0, LEAST(100, (v_notation_etab - 1) * 25));
  END IF;

  IF v_nb_terminees_12m < 3 THEN
    v_presentisme := NULL;
  ELSE
    DECLARE v_total_engagements INT;
    BEGIN
      SELECT COUNT(*) INTO v_total_engagements FROM missions
      WHERE soignant_assigne_id = p_soignant_id
        AND statut IN ('TERMINEE','ANNULEE_PAR_SOIGNANT','ABSENCE')
        AND COALESCE(fin_le, debut_le) >= v_since;
      IF v_total_engagements > 0 THEN
        v_presentisme := (v_nb_terminees_12m::NUMERIC / v_total_engagements) * 100;
      ELSE v_presentisme := NULL; END IF;
    END;
  END IF;

  DECLARE v_nb_pointages INT; v_total_score NUMERIC := 0;
  BEGIN
    SELECT COUNT(*),
      SUM(CASE
        WHEN COALESCE(retard_min, 0) <= 0 THEN 100
        WHEN retard_min < 5 THEN 90
        WHEN retard_min < 10 THEN 75
        WHEN retard_min < 30 THEN 50
        ELSE 25
      END)
    INTO v_nb_pointages, v_total_score
    FROM presences p JOIN missions m ON m.id = p.mission_id
    WHERE p.soignant_id = p_soignant_id AND p.pointage_arrivee_le >= v_since AND p.pointage_arrivee_le IS NOT NULL;
    IF v_nb_pointages < 3 THEN v_ponctualite := NULL;
    ELSE v_ponctualite := v_total_score / v_nb_pointages; END IF;
  END;

  SELECT COUNT(*), AVG(EXTRACT(EPOCH FROM (traite_le - cree_le)) / 3600.0)
  INTO v_nb_decisions_cand, v_delai_moyen_h
  FROM candidatures
  WHERE soignant_id = p_soignant_id AND statut IN ('ACCEPTEE','REFUSEE')
    AND traite_le IS NOT NULL AND cree_le >= v_since;

  IF v_nb_decisions_cand < 3 OR v_delai_moyen_h IS NULL THEN
    v_reactivite := NULL;
  ELSE
    v_reactivite := CASE
      WHEN v_delai_moyen_h < 1 THEN 100
      WHEN v_delai_moyen_h < 3 THEN 90
      WHEN v_delai_moyen_h < 12 THEN 80
      WHEN v_delai_moyen_h < 24 THEN 70
      WHEN v_delai_moyen_h < 48 THEN 60
      ELSE 50
    END;
  END IF;

  v_anciennete_volume := CASE
    WHEN v_nb_terminees_12m = 0 THEN 0
    WHEN v_nb_terminees_12m <= 2 THEN 30
    WHEN v_nb_terminees_12m <= 9 THEN 50
    WHEN v_nb_terminees_12m <= 29 THEN 75
    WHEN v_nb_terminees_12m <= 49 THEN 90
    ELSE 100
  END;

  IF v_nb_terminees_12m = 0 THEN
    v_notation_par_soignant := NULL;
  ELSE
    SELECT COUNT(*) INTO v_nb_notations_par_soignant
    FROM notations_missions
    WHERE notateur_id = p_soignant_id AND sens = 'SOIGNANT_VERS_ETAB' AND cree_le >= v_since;
    v_pct_notations_donnees := (v_nb_notations_par_soignant::NUMERIC / v_nb_terminees_12m) * 100;
    v_notation_par_soignant := CASE
      WHEN v_pct_notations_donnees >= 50 THEN 100
      WHEN v_pct_notations_donnees >= 25 THEN 75
      WHEN v_pct_notations_donnees >= 10 THEN 50
      ELSE 0
    END;
  END IF;

  v_total_poids_actifs := 0;
  IF v_notation_etab IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_notation_etab; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','notation_etab_soignant','poids_initial',v_p_notation_etab); END IF;
  IF v_presentisme IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_presentisme; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','presentisme','poids_initial',v_p_presentisme); END IF;
  IF v_ponctualite IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_ponctualite; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','ponctualite','poids_initial',v_p_ponctualite); END IF;
  IF v_reactivite IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_reactivite; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','reactivite','poids_initial',v_p_reactivite); END IF;
  IF v_anciennete_volume IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_anciennete_volume; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','anciennete_volume','poids_initial',v_p_anciennete_volume); END IF;
  IF v_notation_par_soignant IS NOT NULL THEN v_total_poids_actifs := v_total_poids_actifs + v_p_notation_par_soignant; v_actives_count := v_actives_count + 1;
    ELSE v_inactives_json := v_inactives_json || jsonb_build_object('composante','notation_soignant_etab','poids_initial',v_p_notation_par_soignant); END IF;

  IF v_total_poids_actifs > 0 THEN
    v_facteur_redistribution := 100.0 / v_total_poids_actifs;
  ELSE v_facteur_redistribution := 0; END IF;

  v_pe_notation_etab := CASE WHEN v_notation_etab IS NOT NULL THEN v_p_notation_etab * v_facteur_redistribution ELSE 0 END;
  v_pe_presentisme := CASE WHEN v_presentisme IS NOT NULL THEN v_p_presentisme * v_facteur_redistribution ELSE 0 END;
  v_pe_ponctualite := CASE WHEN v_ponctualite IS NOT NULL THEN v_p_ponctualite * v_facteur_redistribution ELSE 0 END;
  v_pe_reactivite := CASE WHEN v_reactivite IS NOT NULL THEN v_p_reactivite * v_facteur_redistribution ELSE 0 END;
  v_pe_anciennete_volume := CASE WHEN v_anciennete_volume IS NOT NULL THEN v_p_anciennete_volume * v_facteur_redistribution ELSE 0 END;
  v_pe_notation_par_soignant := CASE WHEN v_notation_par_soignant IS NOT NULL THEN v_p_notation_par_soignant * v_facteur_redistribution ELSE 0 END;

  v_score := COALESCE(v_notation_etab, 0) * v_pe_notation_etab / 100
           + COALESCE(v_presentisme, 0) * v_pe_presentisme / 100
           + COALESCE(v_ponctualite, 0) * v_pe_ponctualite / 100
           + COALESCE(v_reactivite, 0) * v_pe_reactivite / 100
           + COALESCE(v_anciennete_volume, 0) * v_pe_anciennete_volume / 100
           + COALESCE(v_notation_par_soignant, 0) * v_pe_notation_par_soignant / 100;

  SELECT LEAST(2, COUNT(*)) * 10 INTO v_nb_litiges
  FROM litiges
  WHERE soignant_id = p_soignant_id
    AND statut IN ('RESOLU_ETABLISSEMENT', 'RESOLU_FAVEUR_ETAB')
    AND COALESCE(resolu_le, NOW()) >= v_since;
  v_litiges_malus := -COALESCE(v_nb_litiges, 0);

  SELECT LEAST(1, COUNT(*)) * 30 INTO v_nb_absences
  FROM missions
  WHERE soignant_assigne_id = p_soignant_id AND statut = 'ABSENCE'
    AND COALESCE(fin_le, debut_le) >= v_since;
  v_absence_malus := -COALESCE(v_nb_absences, 0);

  -- ★ Malus anti-triche GPS : piloté par les événements FRAUDE_GPS non annulés
  --   (points_corriges prime si l'admin a tranché une réclamation). Cap -30.
  SELECT GREATEST(-30, COALESCE(SUM(COALESCE(points_corriges, points)), 0))
  INTO v_fraude_gps_malus
  FROM evenements_score_soignant
  WHERE soignant_id = p_soignant_id AND type_evenement = 'FRAUDE_GPS' AND cree_le >= v_since;
  v_fraude_gps_malus := COALESCE(v_fraude_gps_malus, 0);

  IF v_nb_terminees_12m > 50 THEN v_bonus_super_actif := 5; END IF;

  IF EXISTS (
    SELECT 1 FROM missions m
    WHERE m.soignant_assigne_id = p_soignant_id
      AND COALESCE(m.est_urgente, false) = true
      AND m.statut IN ('ASSIGNEE', 'EN_COURS')
  ) OR EXISTS (
    SELECT 1 FROM candidatures c JOIN missions m ON m.id = c.mission_id
    WHERE c.soignant_id = p_soignant_id
      AND COALESCE(m.est_urgente, false) = true
      AND c.statut = 'EN_ATTENTE_VALIDATION_ETAB'
      AND m.statut = 'OUVERTE'
  ) THEN
    v_bonus_urgence := 5;
  END IF;

  v_score := v_score + v_litiges_malus + v_absence_malus + v_fraude_gps_malus + v_bonus_super_actif + v_bonus_urgence;
  v_score := GREATEST(0, LEAST(100, v_score));

  v_score := ROUND(v_score, 2);

  v_niveau := CASE
    WHEN v_score >= 90 THEN 'PLATINE'
    WHEN v_score >= 70 THEN 'OR'
    WHEN v_score >= 50 THEN 'ARGENT'
    ELSE 'BRONZE'
  END::public.niveau_qualitatif;

  INSERT INTO scoring_breakdown (
    soignant_id, score_total, niveau, en_periode_probatoire,
    notation_etab_soignant_pct, notation_etab_soignant_poids,
    presentisme_pct, presentisme_poids,
    ponctualite_pct, ponctualite_poids,
    reactivite_pct, reactivite_poids,
    anciennete_volume_pct, anciennete_volume_poids,
    notation_soignant_etab_pct, notation_soignant_etab_poids,
    litiges_malus, absence_sans_prevenir_malus, bonus_super_actif,
    composantes_inactives_json, composantes_actives_count, redistribution_json,
    raison_recalcul
  ) VALUES (
    p_soignant_id, v_score, v_niveau, v_probatoire,
    v_notation_etab, v_pe_notation_etab,
    v_presentisme, v_pe_presentisme,
    v_ponctualite, v_pe_ponctualite,
    v_reactivite, v_pe_reactivite,
    v_anciennete_volume, v_pe_anciennete_volume,
    v_notation_par_soignant, v_pe_notation_par_soignant,
    v_litiges_malus, v_absence_malus, v_bonus_super_actif,
    v_inactives_json, v_actives_count,
    jsonb_build_object('facteur', v_facteur_redistribution, 'total_poids_actifs', v_total_poids_actifs, 'bonus_urgence', v_bonus_urgence, 'fraude_gps_malus', v_fraude_gps_malus),
    p_raison
  ) RETURNING id INTO v_breakdown_id;

  UPDATE soignants SET
    score_fiabilite = CASE WHEN v_total_missions_terminees = 0 THEN NULL ELSE v_score END, niveau = v_niveau,
    en_periode_probatoire = v_probatoire,
    score_breakdown_id = v_breakdown_id, modifie_le = NOW()
  WHERE id = p_soignant_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := p_soignant_id, p_type_acteur := 'SYSTEME',
    p_action := 'SCORE_RECALCULE_V2', p_type_ressource := 'soignant', p_id_ressource := p_soignant_id,
    p_details := jsonb_build_object('score', v_score, 'niveau', v_niveau::text, 'breakdown_id', v_breakdown_id, 'raison', p_raison, 'bonus_urgence', v_bonus_urgence, 'fraude_gps_malus', v_fraude_gps_malus)
  );

  RETURN jsonb_build_object('success', true, 'score', CASE WHEN v_total_missions_terminees = 0 THEN NULL ELSE v_score END, 'niveau', v_niveau,
    'breakdown_id', v_breakdown_id, 'en_periode_probatoire', v_probatoire,
    'composantes_actives', v_actives_count, 'bonus_urgence', v_bonus_urgence, 'fraude_gps_malus', v_fraude_gps_malus);
END;
$function$;

-- 3. Détection : crée l'événement FRAUDE_GPS contestable + recalcule le score
CREATE OR REPLACE FUNCTION public.fn_detecter_teleportations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_alertes_count int := 0;
  v_rec RECORD;
  v_vitesse jsonb;
  v_admin_ids uuid[];
  v_soignants_affectes uuid[] := ARRAY[]::uuid[];
  v_sid uuid;
BEGIN
  FOR v_rec IN
    WITH pointages_recents AS (
      SELECT p.soignant_id, p.pointage_arrivee_le AS ts, p.arrivee_lat AS lat, p.arrivee_lng AS lng,
        p.mission_id, p.id AS presence_id, 'arrivee' AS type_p
      FROM public.presences p
      WHERE p.pointage_arrivee_le > NOW() - INTERVAL '24 hours'
        AND p.arrivee_lat IS NOT NULL AND p.arrivee_lng IS NOT NULL
      UNION ALL
      SELECT p.soignant_id, p.pointage_depart_le AS ts, p.depart_lat AS lat, p.depart_lng AS lng,
        p.mission_id, p.id AS presence_id, 'depart' AS type_p
      FROM public.presences p
      WHERE p.pointage_depart_le > NOW() - INTERVAL '24 hours'
        AND p.depart_lat IS NOT NULL AND p.depart_lng IS NOT NULL
    ),
    paires AS (
      SELECT a.soignant_id, a.ts AS ts1, a.lat AS lat1, a.lng AS lng1, a.mission_id AS mission1, a.type_p AS type1,
        LEAD(a.ts) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS ts2,
        LEAD(a.lat) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS lat2,
        LEAD(a.lng) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS lng2,
        LEAD(a.mission_id) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS mission2,
        LEAD(a.type_p) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS type2,
        LEAD(a.presence_id) OVER (PARTITION BY a.soignant_id ORDER BY a.ts) AS presence2
      FROM pointages_recents a
    )
    SELECT * FROM paires
    WHERE ts2 IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.journaux_audit ja
        WHERE ja.action = 'SYSTEM'
          AND ja.details->>'evenement' = 'TELEPORTATION_DETECTED'
          AND ja.details->>'presence_id_destination' = paires.presence2::text)
  LOOP
    v_vitesse := public.fn_vitesse_entre_pointages(v_rec.lat1, v_rec.lng1, v_rec.ts1, v_rec.lat2, v_rec.lng2, v_rec.ts2);
    IF (v_vitesse->>'calculable')::boolean AND (v_vitesse->>'teleportation')::boolean THEN
      INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
      VALUES (v_rec.soignant_id, 'SOIGNANT', 'SYSTEM', 'presence', v_rec.presence2,
        jsonb_build_object('evenement', 'TELEPORTATION_DETECTED', 'niveau', 'ALERTE',
          'soignant_id', v_rec.soignant_id, 'mission_id_source', v_rec.mission1,
          'mission_id_destination', v_rec.mission2, 'type_pointage_source', v_rec.type1,
          'type_pointage_destination', v_rec.type2, 'presence_id_destination', v_rec.presence2,
          'ts_source', v_rec.ts1, 'ts_destination', v_rec.ts2,
          'distance_m', v_vitesse->>'distance_m', 'duree_h', v_vitesse->>'duree_h', 'vitesse_kmh', v_vitesse->>'vitesse_kmh'));
      UPDATE public.presences SET alerte_teleportation = true, modifie_le = now() WHERE id = v_rec.presence2;

      -- Pénalité automatique anti-triche : événement de score CONTESTABLE (-10 pts).
      -- Garde anti-doublon : un seul FRAUDE_GPS par présence destination.
      IF NOT EXISTS (
        SELECT 1 FROM public.evenements_score_soignant e
        WHERE e.type_evenement = 'FRAUDE_GPS'
          AND e.details->>'presence_id_destination' = v_rec.presence2::text
      ) THEN
        INSERT INTO public.evenements_score_soignant
          (soignant_id, type_evenement, points, motif, contestable, mission_id, details)
        VALUES (v_rec.soignant_id, 'FRAUDE_GPS', -10,
          'Téléportation détectée (vitesse > 200 km/h entre deux pointages GPS)', true, v_rec.mission2,
          jsonb_build_object('presence_id_destination', v_rec.presence2,
            'mission_id_source', v_rec.mission1, 'mission_id_destination', v_rec.mission2,
            'vitesse_kmh', v_vitesse->>'vitesse_kmh', 'distance_m', v_vitesse->>'distance_m',
            'duree_h', v_vitesse->>'duree_h', 'ts_source', v_rec.ts1, 'ts_destination', v_rec.ts2));
        IF NOT (v_rec.soignant_id = ANY(v_soignants_affectes)) THEN
          v_soignants_affectes := array_append(v_soignants_affectes, v_rec.soignant_id);
        END IF;
      END IF;

      v_alertes_count := v_alertes_count + 1;
    END IF;
  END LOOP;

  -- Recalcul du score de fiabilité pour chaque soignant pénalisé.
  IF array_length(v_soignants_affectes, 1) > 0 THEN
    FOREACH v_sid IN ARRAY v_soignants_affectes LOOP
      BEGIN
        PERFORM public.fn_calculer_score_fiabilite_v2(v_sid, 'fraude_gps');
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
  END IF;

  IF v_alertes_count > 0 THEN
    v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());
    IF array_length(v_admin_ids, 1) > 0 THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      SELECT 'EMAIL_NOTIF', jsonb_build_object('destinataire_id', uid, 'type', 'ALERTE_TELEPORTATION',
        'data', jsonb_build_object('count', v_alertes_count,
          'lien_admin', 'https://app.jolene.app/admin/journaux-audit?evenement=TELEPORTATION_DETECTED')), 'CRON_ANTI_TRICHE', NULL FROM unnest(v_admin_ids) AS uid;
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      SELECT 'PUSH_NOTIF', jsonb_build_object('destinataire_id', uid, 'type_evenement', 'ALERTE_ADMIN',
        'titre', '⚠️ ' || v_alertes_count || ' téléportation' || CASE WHEN v_alertes_count > 1 THEN 's' ELSE '' END || ' détectée' || CASE WHEN v_alertes_count > 1 THEN 's' ELSE '' END,
        'corps', 'Vitesse > 200 km/h entre pointages. Pénalité -10 appliquée (contestable). Vérification requise.', 'lien', '/admin/journaux-audit'), 'CRON_ANTI_TRICHE', NULL FROM unnest(v_admin_ids) AS uid;
    END IF;
  END IF;
  RETURN jsonb_build_object('success', true, 'alertes_count', v_alertes_count, 'soignants_penalises', COALESCE(array_length(v_soignants_affectes, 1), 0));
END;
$function$;
