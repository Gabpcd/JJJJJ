-- Fix : un soignant SANS mission terminée ne doit pas afficher un score (0/100).
-- Règle produit : tant qu'il n'y a pas de réelle base d'évaluation (aucune mission
-- réalisée), on n'affiche PAS de score → l'UI montre « Pas encore d'évaluation »
-- (elle teste déjà score_fiabilite IS NULL).
--
-- Cause : la formule donnait anciennete_volume = 0 (composante active) pour 0 mission
-- → score calculé = 0 au lieu de NULL. Fix : score_fiabilite = NULL si 0 mission
-- terminée (le breakdown garde la valeur numérique pour traçabilité interne).

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
    score_fiabilite = CASE WHEN v_total_missions_terminees = 0 THEN NULL ELSE v_score END, niveau = v_niveau,
    en_periode_probatoire = v_probatoire,
    score_breakdown_id = v_breakdown_id, modifie_le = NOW()
  WHERE id = p_soignant_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := p_soignant_id, p_type_acteur := 'SYSTEME',
    p_action := 'SCORE_RECALCULE_V2', p_type_ressource := 'soignant', p_id_ressource := p_soignant_id,
    p_details := jsonb_build_object('score', v_score, 'niveau', v_niveau::text, 'breakdown_id', v_breakdown_id, 'raison', p_raison, 'bonus_urgence', v_bonus_urgence)
  );

  RETURN jsonb_build_object('success', true, 'score', CASE WHEN v_total_missions_terminees = 0 THEN NULL ELSE v_score END, 'niveau', v_niveau,
    'breakdown_id', v_breakdown_id, 'en_periode_probatoire', v_probatoire,
    'composantes_actives', v_actives_count, 'bonus_urgence', v_bonus_urgence);
END;
$function$;


-- Backfill : repasser à NULL les scores des soignants sans aucune mission terminée.
UPDATE public.soignants s
SET score_fiabilite = NULL, modifie_le = NOW()
WHERE s.score_fiabilite IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.soignant_assigne_id = s.id AND m.statut = 'TERMINEE'
  );
