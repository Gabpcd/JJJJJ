-- Bonus urgence à l'acceptation — réversible et durable (intégré à la FORMULE).
--
-- Demande produit : récompenser le soignant qui accepte une mission en urgence,
-- bonus RETIRÉ s'il annule.
--
-- Pourquoi dans la formule et pas un +5 incrémental : fn_calculer_score_fiabilite_v2
-- recalcule score_fiabilite from-scratch (formule pondérée). Tout +5 incrémental
-- serait écrasé au prochain recalcul. La SEULE façon durable = ajouter une
-- composante à la formule, qui lit l'ÉTAT COURANT → naturellement réversible :
-- dès que le soignant n'a plus d'engagement urgent actif (annulation / refus étab),
-- le recalcul retire le +5.
--
-- Anti-farm : +5 FORFAITAIRE (flat), pas +5 par candidature. Un soignant avec 1 ou
-- 5 missions urgentes actives a +5, pas +25.
--
-- Définition « engagement urgence actif » :
--   - mission urgente dont il est le soignant assigné (ASSIGNEE / EN_COURS), OU
--   - candidature urgente en attente de validation étab (EN_ATTENTE_VALIDATION_ETAB)
--     sur une mission urgente encore OUVERTE.
--
-- Le bonus +10 à la complétion (dec_bonus_urgence) reste inchangé.

-- 1. Formule : ajout de la composante v_bonus_urgence (stockée dans redistribution_json,
--    pas de changement de schéma).
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

  IF v_nb_terminees_12m > 50 THEN v_bonus_super_actif := 5; END IF;

  -- ★ Bonus engagement urgence (+5 forfaitaire, réversible : lit l'état courant)
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

  v_score := v_score + v_litiges_malus + v_absence_malus + v_bonus_super_actif + v_bonus_urgence;
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
    jsonb_build_object('facteur', v_facteur_redistribution, 'total_poids_actifs', v_total_poids_actifs, 'bonus_urgence', v_bonus_urgence),
    p_raison
  ) RETURNING id INTO v_breakdown_id;

  UPDATE soignants SET
    score_fiabilite = v_score, niveau = v_niveau,
    en_periode_probatoire = v_probatoire,
    score_breakdown_id = v_breakdown_id, modifie_le = NOW()
  WHERE id = p_soignant_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := p_soignant_id, p_type_acteur := 'SYSTEME',
    p_action := 'SCORE_RECALCULE_V2', p_type_ressource := 'soignant', p_id_ressource := p_soignant_id,
    p_details := jsonb_build_object('score', v_score, 'niveau', v_niveau::text, 'breakdown_id', v_breakdown_id, 'raison', p_raison, 'bonus_urgence', v_bonus_urgence)
  );

  RETURN jsonb_build_object('success', true, 'score', v_score, 'niveau', v_niveau,
    'breakdown_id', v_breakdown_id, 'en_periode_probatoire', v_probatoire,
    'composantes_actives', v_actives_count, 'bonus_urgence', v_bonus_urgence);
END;
$function$;

-- 2. Trigger sur candidatures : recalcul du score quand une candidature à une
--    mission URGENTE change (création = acceptation, ANNULEE/REFUSEE = retrait du bonus).
--    Borne au cas urgent → pas de recalcul superflu.
CREATE OR REPLACE FUNCTION public.fn_trg_recompute_score_urgence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM missions m WHERE m.id = NEW.mission_id AND COALESCE(m.est_urgente, false) = true) THEN
    IF TG_OP = 'INSERT' OR NEW.statut IS DISTINCT FROM OLD.statut THEN
      PERFORM public.fn_calculer_score_fiabilite_v2(NEW.soignant_id, 'engagement_urgence');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_recompute_score_urgence ON public.candidatures;
CREATE TRIGGER trg_recompute_score_urgence
  AFTER INSERT OR UPDATE ON public.candidatures
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_recompute_score_urgence();

-- 3. fn_annuler_mission_soignant : recalcul du score en fin de fonction pour retirer
--    le bonus (cette annulation passe par la mission, pas par la candidature → le
--    trigger ci-dessus ne suffit pas).
CREATE OR REPLACE FUNCTION public.fn_annuler_mission_soignant(p_mission_id uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_heures_avant NUMERIC;
    v_est_tardive BOOLEAN;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;

    IF v_mission.soignant_assigne_id != auth.uid() THEN
        RETURN '{"error":"Cette mission ne vous est pas assignée"}'::JSONB;
    END IF;
    IF v_mission.statut NOT IN ('ASSIGNEE') THEN
        RETURN '{"error":"Annulation impossible dans cet état. Si la mission est en cours, ouvrez un litige."}'::JSONB;
    END IF;

    v_heures_avant := EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 3600;
    v_est_tardive := v_heures_avant < 24;

    UPDATE missions SET
        statut = 'OUVERTE',
        soignant_assigne_id = NULL,
        annulee_par = auth.uid(),
        annulee_le = NOW(),
        motif_annulation = COALESCE(p_motif, 'Annulée par le soignant'),
        modifie_le = NOW()
    WHERE id = p_mission_id;

    IF v_est_tardive THEN
        UPDATE soignants SET
            total_missions_annulees = COALESCE(total_missions_annulees, 0) + 1,
            score_fiabilite = GREATEST(0, COALESCE(score_fiabilite, 50) - 8),
            modifie_le = NOW()
        WHERE id = auth.uid();
    ELSE
        UPDATE soignants SET
            total_missions_annulees = COALESCE(total_missions_annulees, 0) + 1,
            modifie_le = NOW()
        WHERE id = auth.uid();
    END IF;

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (v_mission.etablissement_id, 'SYSTEM',
        CASE WHEN v_est_tardive THEN '⚠️ Annulation tardive' ELSE '❌ Mission annulée' END,
        'Le soignant a annulé la mission "' || v_mission.intitule || '"' ||
        CASE WHEN v_est_tardive THEN ' à moins de 24h du début.' ELSE '.' END ||
        CASE WHEN p_motif IS NOT NULL THEN ' Motif : ' || p_motif ELSE '' END ||
        ' La mission est remise en ligne.',
        '/etablissement/missions', 'ETABLISSEMENT');

    PERFORM fn_ecrire_audit_safe(
        auth.uid(), 'SOIGNANT', 'MISSION_ANNULEE_PAR_SOIGNANT', 'mission', p_mission_id, NULL,
        jsonb_build_object('tardive', v_est_tardive, 'heures_avant', ROUND(v_heures_avant, 1), 'motif', p_motif)
    );

    -- Recalcul du score pour retirer le bonus engagement urgence si la mission était urgente.
    IF COALESCE(v_mission.est_urgente, false) = true THEN
        PERFORM public.fn_calculer_score_fiabilite_v2(auth.uid(), 'annulation_mission_urgente');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'annulation_tardive', v_est_tardive,
        'penalite_score', CASE WHEN v_est_tardive THEN -8 ELSE 0 END
    );
END;
$function$;
