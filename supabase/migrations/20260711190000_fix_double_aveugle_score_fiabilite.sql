-- Finding #3 (revue de clôture Lots 13-17) — FUITE DU DOUBLE-AVEUGLE côté soignant.
--
-- `fn_calculer_score_fiabilite_v2` agrège les notes ETAB_VERS_SOIGNANT qui
-- alimentent le score_fiabilite PUBLIC du soignant en filtrant `masque = false`
-- mais PAS `publie_le IS NOT NULL` — alors que les 3 autres surfaces du
-- double-aveugle (fn_calculer_score_etablissement, fn_lister_notations_recues,
-- trigger fn_trg_recalculer_score_v2) le filtrent. Conséquence : une note
-- d'établissement NON PUBLIÉE (publie_le NULL, D8) déplace quand même le score
-- public du soignant dès qu'un AUTRE recalcul le déclenche (mission TERMINEE,
-- pénalité GPS, annulation) → le soignant infère la note avant de réciproquer.
-- Vecteur de représailles que D8 prétend fermer, et de façon ASYMÉTRIQUE (le
-- score établissement, lui, est protégé). Aucun euro n'en dépend ; bug latent
-- (0 note non publiée en prod au 11/07) — corrigé avant de garantir le
-- double-aveugle côté soignant.
--
-- Redéfinition partant de la définition LIVE (règle 9.0), seul le filtre de
-- visibilité est ajouté. Vue canonique `evaluations_publiees` posée comme source
-- unique des agrégations publiques (pattern « publication différée = filtre de
-- visibilité centralisé, jamais répété par surface » — cf. CLAUDE.md). La
-- migration de TOUTES les surfaces vers cette vue est un suivi Lot 19 (les 3
-- autres filtrent déjà correctement en inline, donc non bloquant).

-- Vue canonique : la seule source « publiée + non masquée » des notations.
CREATE OR REPLACE VIEW public.evaluations_publiees AS
  SELECT * FROM public.notations_missions
  WHERE publie_le IS NOT NULL AND masque = false;

COMMENT ON VIEW public.evaluations_publiees IS
  'Source canonique des notations visibles (double-aveugle). Toute agrégation publique de score DOIT lire ici (ou répliquer publie_le IS NOT NULL AND masque = false), jamais notations_missions brute. Cf. Finding #3 / pattern CLAUDE.md publication différée.';

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

  -- FIX Finding #3 : double-aveugle — n'agréger que les notes PUBLIÉES
  -- (publie_le IS NOT NULL), comme les 3 autres surfaces. Une note non publiée
  -- ne doit JAMAIS déplacer le score public du soignant avant réciprocité.
  SELECT COUNT(*),
    SUM(((critere_1 + critere_2 + critere_3 + critere_4) / 4.0) * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))) /
    NULLIF(SUM(GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))), 0)
  INTO v_nb_notations, v_notation_etab
  FROM notations_missions
  WHERE note_id = p_soignant_id AND sens = 'ETAB_VERS_SOIGNANT'
    AND cree_le >= v_since AND masque = false AND publie_le IS NOT NULL;

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

-- Finding #3 (2e surface, découverte par le grep exhaustif) — fuite DIRECTE du
-- double-aveugle. `fn_mes_notations_recues_avec_stats` liste au soignant ses
-- notes reçues (note + commentaire + établissement) + stats + évolution, en
-- filtrant `masque = false` mais PAS `publie_le` sur ses 5 lectures de
-- notations_missions. Un soignant y voit la note NON PUBLIÉE en clair avant
-- réciprocité — fuite plus directe que le score. Ajout de `n.publie_le IS NOT
-- NULL` aux 5 requêtes (les deux sens sont concernés : le soignant voit
-- ETAB_VERS_SOIGNANT, l'étab voit SOIGNANT_VERS_ETAB — double-aveugle bilatéral).
-- Redéfinition depuis la déf LIVE, seuls les filtres de visibilité sont ajoutés.
CREATE OR REPLACE FUNCTION public.fn_mes_notations_recues_avec_stats(p_periode text DEFAULT 'TOUT'::text, p_note_min integer DEFAULT NULL::integer, p_etablissement_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid := public.mon_etablissement_id();
  v_target_id uuid;
  v_target_sens public.sens_notation;
  v_seuil_periode timestamptz;
  v_total int;
  v_notations jsonb;
  v_stats jsonb;
  v_etabs_disponibles jsonb;
  v_evolution jsonb;
  v_limit int;
BEGIN
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);

  IF v_etab_id IS NOT NULL THEN
    v_target_id := v_etab_id;
    v_target_sens := 'SOIGNANT_VERS_ETAB';
  ELSIF v_uid IS NOT NULL THEN
    v_target_id := v_uid;
    v_target_sens := 'ETAB_VERS_SOIGNANT';
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_seuil_periode := CASE p_periode
    WHEN '3M' THEN now() - INTERVAL '3 months'
    WHEN '6M' THEN now() - INTERVAL '6 months'
    WHEN '12M' THEN now() - INTERVAL '12 months'
    ELSE '1900-01-01'::timestamptz
  END;

  -- Total filtré
  SELECT COUNT(*) INTO v_total
  FROM public.notations_missions n
  JOIN public.missions m ON m.id = n.mission_id
  WHERE n.note_id = v_target_id
    AND n.sens = v_target_sens
    AND n.masque = false
    AND n.publie_le IS NOT NULL
    AND n.cree_le > v_seuil_periode
    AND (p_note_min IS NULL OR ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1) >= p_note_min)
    AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id);

  -- Liste paginée
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'mission_id', x.mission_id,
    'mission_intitule', x.mission_intitule,
    'mission_fin_le', x.mission_fin_le,
    'etablissement_id', x.etablissement_id,
    'etablissement_nom', x.etablissement_nom,
    'critere_1', x.critere_1,
    'critere_2', x.critere_2,
    'critere_3', x.critere_3,
    'critere_4', x.critere_4,
    'note_moyenne', ROUND(((x.critere_1 + x.critere_2 + x.critere_3 + x.critere_4) / 4.0)::numeric, 1),
    'commentaire', x.commentaire,
    'signale', x.signale,
    'cree_le', x.cree_le
  ) ORDER BY x.cree_le DESC), '[]'::jsonb)
  INTO v_notations
  FROM (
    SELECT n.id, n.mission_id, m.intitule AS mission_intitule, m.fin_le AS mission_fin_le,
           m.etablissement_id, e.nom AS etablissement_nom,
           n.critere_1, n.critere_2, n.critere_3, n.critere_4, n.commentaire, n.signale, n.cree_le
    FROM public.notations_missions n
    JOIN public.missions m ON m.id = n.mission_id
    LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE n.note_id = v_target_id
      AND n.sens = v_target_sens
      AND n.masque = false
      AND n.publie_le IS NOT NULL
      AND n.cree_le > v_seuil_periode
      AND (p_note_min IS NULL OR ROUND(((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1) >= p_note_min)
      AND (p_etablissement_id IS NULL OR m.etablissement_id = p_etablissement_id)
    ORDER BY n.cree_le DESC
    LIMIT v_limit OFFSET p_offset
  ) x;

  -- Stats globales (toutes périodes, pas de filtres pour avoir une vue globale)
  SELECT jsonb_build_object(
    'note_moyenne_globale', COALESCE(ROUND(AVG((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0)::numeric, 1), 0),
    'total_evaluations', COUNT(*),
    'pct_5_etoiles', CASE WHEN COUNT(*) > 0
      THEN ROUND(100.0 * SUM(CASE WHEN (n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) >= 19 THEN 1 ELSE 0 END) / COUNT(*), 1)
      ELSE 0 END
  )
  INTO v_stats
  FROM public.notations_missions n
  WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false AND n.publie_le IS NOT NULL;

  -- Évolution 6 derniers mois (note moyenne par mois)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mois', to_char(x.mois, 'YYYY-MM'),
    'note_moyenne', ROUND(x.moyenne::numeric, 1),
    'nb', x.nb
  ) ORDER BY x.mois), '[]'::jsonb)
  INTO v_evolution
  FROM (
    SELECT date_trunc('month', n.cree_le) AS mois,
           AVG((n.critere_1 + n.critere_2 + n.critere_3 + n.critere_4) / 4.0) AS moyenne,
           COUNT(*) AS nb
    FROM public.notations_missions n
    WHERE n.note_id = v_target_id
      AND n.sens = v_target_sens
      AND n.masque = false
      AND n.publie_le IS NOT NULL
      AND n.cree_le > now() - INTERVAL '6 months'
    GROUP BY 1
  ) x;

  -- Liste étabs ayant évalué le soignant (pour dropdown filtre)
  IF v_target_sens = 'ETAB_VERS_SOIGNANT' THEN
    SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id', e.id, 'nom', e.nom)), '[]'::jsonb)
    INTO v_etabs_disponibles
    FROM public.notations_missions n
    JOIN public.missions m ON m.id = n.mission_id
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE n.note_id = v_target_id AND n.sens = v_target_sens AND n.masque = false AND n.publie_le IS NOT NULL;
  ELSE
    v_etabs_disponibles := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'limit', v_limit,
    'offset', p_offset,
    'notations', v_notations,
    'stats', v_stats,
    'evolution_6m', v_evolution,
    'etabs_disponibles', v_etabs_disponibles
  );
END;
$function$;
