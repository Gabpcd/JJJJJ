CREATE OR REPLACE FUNCTION public.fn_calculer_heures_totales(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_heures_plateforme NUMERIC;
    v_heures_externes NUMERIC;
    v_heures_totales NUMERIC;
BEGIN
    SELECT COALESCE(heures_plateforme, 0) INTO v_heures_plateforme
    FROM soignants WHERE id = p_soignant_id;

    SELECT COALESCE(SUM(heures_declarees), 0) INTO v_heures_externes
    FROM heures_externes
    WHERE soignant_id = p_soignant_id AND statut = 'VALIDEE';

    v_heures_totales := v_heures_plateforme + v_heures_externes;

    -- Mettre à jour heures_cumulees
    UPDATE soignants SET
        heures_cumulees = v_heures_totales,
        modifie_le = NOW()
    WHERE id = p_soignant_id;

    RETURN jsonb_build_object(
        'heures_plateforme', v_heures_plateforme,
        'heures_externes_validees', v_heures_externes,
        'heures_totales', v_heures_totales,
        'eligible_3200h', v_heures_totales >= 3200
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_bfa_safe(p_etablissement_id uuid DEFAULT NULL::uuid, p_groupe_id uuid DEFAULT NULL::uuid, p_annee integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_annee INTEGER; v_missions INTEGER; v_commissions NUMERIC; v_palier RECORD;
    v_taux_bfa NUMERIC; v_montant_bfa NUMERIC; v_bfa_id UUID;
BEGIN
    v_annee := COALESCE(p_annee, EXTRACT(YEAR FROM NOW())::INTEGER - 1);

    IF p_groupe_id IS NOT NULL THEN
        SELECT COUNT(*), COALESCE(SUM(montant_commission_ht), 0) INTO v_missions, v_commissions
        FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
        WHERE e.groupe_sante_id = p_groupe_id AND m.statut = 'TERMINEE' AND EXTRACT(YEAR FROM m.fin_le) = v_annee;
    ELSIF p_etablissement_id IS NOT NULL THEN
        SELECT COUNT(*), COALESCE(SUM(montant_commission_ht), 0) INTO v_missions, v_commissions
        FROM missions WHERE etablissement_id = p_etablissement_id AND statut = 'TERMINEE' AND EXTRACT(YEAR FROM fin_le) = v_annee;
    ELSE
        RETURN jsonb_build_object('error', 'Paramètre manquant');
    END IF;

    SELECT * INTO v_palier FROM paliers_bfa
    WHERE est_actif = TRUE AND missions_min <= v_missions AND (missions_max IS NULL OR missions_max >= v_missions)
    ORDER BY ordre DESC LIMIT 1;

    IF NOT FOUND OR v_palier.id IS NULL THEN
        RETURN jsonb_build_object('annee', v_annee, 'missions', v_missions, 'commissions', v_commissions,
            'palier', 'AUCUN', 'taux_bfa', 0, 'montant_bfa', 0, 'eligible', FALSE);
    END IF;

    v_taux_bfa := v_palier.taux_bfa;
    v_montant_bfa := ROUND(v_commissions * v_taux_bfa / 100, 2);

    -- ★ UPPER pour correspondre au CHECK constraint (AUCUN/BRONZE/ARGENT/OR)
    IF p_groupe_id IS NOT NULL THEN
        INSERT INTO bfa_suivi (groupe_id, annee, missions_cumulees, commissions_cumulees, palier_bfa, taux_bfa, montant_bfa, bfa_verse, calcule_le)
        VALUES (p_groupe_id, v_annee, v_missions, v_commissions, UPPER(v_palier.nom), v_taux_bfa, v_montant_bfa, FALSE, NOW())
        ON CONFLICT (groupe_id, annee) DO UPDATE SET 
            missions_cumulees = EXCLUDED.missions_cumulees, commissions_cumulees = EXCLUDED.commissions_cumulees,
            palier_bfa = EXCLUDED.palier_bfa, taux_bfa = EXCLUDED.taux_bfa, montant_bfa = EXCLUDED.montant_bfa, calcule_le = NOW()
        RETURNING id INTO v_bfa_id;
    ELSE
        INSERT INTO bfa_suivi (etablissement_id, annee, missions_cumulees, commissions_cumulees, palier_bfa, taux_bfa, montant_bfa, bfa_verse, calcule_le)
        VALUES (p_etablissement_id, v_annee, v_missions, v_commissions, UPPER(v_palier.nom), v_taux_bfa, v_montant_bfa, FALSE, NOW())
        ON CONFLICT (etablissement_id, annee) DO UPDATE SET 
            missions_cumulees = EXCLUDED.missions_cumulees, commissions_cumulees = EXCLUDED.commissions_cumulees,
            palier_bfa = EXCLUDED.palier_bfa, taux_bfa = EXCLUDED.taux_bfa, montant_bfa = EXCLUDED.montant_bfa, calcule_le = NOW()
        RETURNING id INTO v_bfa_id;
    END IF;

    RETURN jsonb_build_object('annee', v_annee, 'missions', v_missions, 'commissions', v_commissions,
        'palier', UPPER(v_palier.nom), 'taux_bfa', v_taux_bfa, 'montant_bfa', v_montant_bfa, 'eligible', TRUE, 'bfa_id', v_bfa_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_financier_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_duree numeric;
  v_taux_effectif numeric;
  v_brut_base numeric;
  v_total_majorations numeric;
  v_total_brut numeric;
  v_etab record;
  v_commission_taux numeric;
  v_commission_ht numeric;
  v_commission_tva numeric;
  v_commission_ttc numeric;
  v_has_creneaux boolean;
  v_est_liberal boolean;
  v_taux_ifm numeric;
  v_taux_icp numeric;
BEGIN
  -- Mission LIBÉRALE : pas d'IFM/ICP (primes CDD salarié).
  v_est_liberal := COALESCE(NEW.type_contrat_applique::text, '') = 'LIBERAL'
                OR COALESCE(NEW.type_paiement_soignant::text, '') = 'NOTE_HONORAIRES'
                OR COALESCE(NEW.choix_contrat_soignant, '') = 'LIBERAL';

  SELECT GREATEST(
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause), 0),
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause), 0)
  )
  INTO v_duree
  FROM mission_creneaux WHERE mission_id = NEW.id;

  SELECT EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id) INTO v_has_creneaux;

  IF NOT v_has_creneaux THEN
    v_duree := COALESCE(NEW.duree_heures, EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0);
  END IF;

  NEW.duree_heures := v_duree;

  SELECT taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent,
         taux_majoration_ferie_pourcent, taux_commission_negocie,
         rist_plafond_actif, rist_taux_base_horaire
  INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;

  v_taux_effectif := NEW.taux_horaire_base;
  IF COALESCE(v_etab.rist_plafond_actif, true) AND NEW.taux_horaire_base > COALESCE(v_etab.rist_taux_base_horaire, 25) THEN
    NEW.rist_plafond_applique := true;
    NEW.taux_rist_plafonne := COALESCE(v_etab.rist_taux_base_horaire, 25);
    v_taux_effectif := NEW.taux_rist_plafonne;
  ELSE
    NEW.rist_plafond_applique := false;
    NEW.taux_rist_plafonne := NULL;
  END IF;

  v_brut_base := v_taux_effectif * v_duree;

  NEW.montant_majoration_nuit := ROUND(COALESCE(NEW.heures_nuit, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_nuit_pourcent, 25) / 100.0, 2);
  NEW.montant_majoration_dimanche := ROUND(COALESCE(NEW.heures_dimanche, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50) / 100.0, 2);
  NEW.montant_majoration_ferie := ROUND(COALESCE(NEW.heures_ferie, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_ferie_pourcent, 100) / 100.0, 2);

  v_total_majorations := COALESCE(NEW.montant_majoration_nuit, 0) + COALESCE(NEW.montant_majoration_dimanche, 0) + COALESCE(NEW.montant_majoration_ferie, 0);
  v_total_brut := ROUND(v_brut_base + v_total_majorations, 2);
  NEW.total_brut := v_total_brut;

  -- IFM/ICP : 0 en libéral, sinon 10 %/10 % (plat).
  v_taux_ifm := CASE WHEN v_est_liberal THEN 0 ELSE COALESCE(NEW.taux_ifm, 0.10) END;
  v_taux_icp := CASE WHEN v_est_liberal THEN 0 ELSE COALESCE(NEW.taux_icp, 0.10) END;
  NEW.taux_ifm := v_taux_ifm;
  NEW.taux_icp := v_taux_icp;
  NEW.montant_ifm := ROUND(v_total_brut * v_taux_ifm, 2);
  NEW.montant_icp := ROUND(v_total_brut * v_taux_icp, 2);
  NEW.net_a_payer := ROUND(v_total_brut + NEW.montant_ifm + NEW.montant_icp, 2);
  NEW.net_estime := ROUND(NEW.net_a_payer * 0.78, 2);

  -- Commission Jolene : TOUJOURS 15 % (ou taux négocié) sur le montant total
  -- (net_a_payer), salarié ET libéral. Aligné sur dec_calculer_commission : plus
  -- de "salarié→0" (qui pouvait remettre la commission à 0 en éditant une mission
  -- salarié déjà terminée), plus de base total_brut divergente.
  v_commission_taux := COALESCE(NEW.taux_commission_fige, NEW.taux_commission,
                                v_etab.taux_commission_negocie,
                                public.fn_param_num('commission_defaut_pct', 15));
  NEW.taux_commission := v_commission_taux;
  v_commission_ht := ROUND(NEW.net_a_payer * v_commission_taux / 100.0, 2);
  v_commission_tva := ROUND(v_commission_ht * 0.20, 2);
  v_commission_ttc := ROUND(v_commission_ht + v_commission_tva, 2);
  NEW.montant_commission_ht := v_commission_ht;
  NEW.montant_commission_tva := v_commission_tva;
  NEW.montant_commission_ttc := v_commission_ttc;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_cotisations(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD; v_soignant RECORD; v_brut NUMERIC; v_type TEXT;
    v_pmss CONSTANT NUMERIC := 3864;
    v_csg_base NUMERIC; v_csg_ded NUMERIC; v_csg_non_ded NUMERIC; v_crds NUMERIC;
    v_ss_maladie NUMERIC; v_ss_vieillesse_p NUMERIC; v_ss_vieillesse_d NUMERIC;
    v_retraite_t1 NUMERIC; v_retraite_t2 NUMERIC; v_chomage NUMERIC; v_ceg NUMERIC;
    v_ifm NUMERIC; v_icp NUMERIC; v_total_sal NUMERIC; v_total_pat NUMERIC; v_net NUMERIC;
    v_pat_ss NUMERIC; v_pat_af NUMERIC; v_pat_at NUMERIC; v_pat_ret NUMERIC;
    v_pat_chom NUMERIC; v_pat_fnal NUMERIC; v_pat_form NUMERIC; v_pat_transport NUMERIC;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;

    v_brut := COALESCE(v_mission.taux_horaire_base * v_mission.duree_heures, 0)
        + COALESCE(v_mission.montant_majoration_nuit, 0) + COALESCE(v_mission.montant_majoration_dimanche, 0)
        + COALESCE(v_mission.montant_majoration_ferie, 0);

    v_type := CASE WHEN COALESCE(v_soignant.type_exercice, 'SALARIE') = 'LIBERAL' THEN 'REMPLACEMENT_LIBERAL' ELSE 'CDD' END;

    IF v_type = 'CDD' THEN
        v_ifm := COALESCE(v_mission.montant_ifm, ROUND(v_brut * 0.10, 2));
        v_icp := COALESCE(v_mission.montant_icp, ROUND((v_brut + v_ifm) * 0.10, 2));
    ELSE v_ifm := 0; v_icp := 0; END IF;

    v_brut := v_brut + v_ifm + v_icp;
    v_csg_base := ROUND(v_brut * 0.9825, 2);

    IF v_type = 'REMPLACEMENT_LIBERAL' THEN
        -- Libéral: 0 cotisations (gère via URSSAF/CARPIMKO)
        v_csg_ded:=0; v_csg_non_ded:=0; v_crds:=0; v_ss_maladie:=0; v_ss_vieillesse_p:=0;
        v_ss_vieillesse_d:=0; v_retraite_t1:=0; v_retraite_t2:=0; v_chomage:=0; v_ceg:=0;
        v_total_sal:=0; v_pat_ss:=0; v_pat_af:=0; v_pat_at:=0; v_pat_ret:=0;
        v_pat_chom:=0; v_pat_fnal:=0; v_pat_form:=0; v_pat_transport:=0; v_total_pat:=0;
        v_net := v_brut;
    ELSE
        -- CDD salarié
        v_csg_ded := ROUND(v_csg_base * 0.0680, 2);
        v_csg_non_ded := ROUND(v_csg_base * 0.0240, 2);
        v_crds := ROUND(v_csg_base * 0.0050, 2);
        v_ss_maladie := 0; -- 0% salarié depuis 2018
        v_ss_vieillesse_p := ROUND(LEAST(v_brut, v_pmss) * 0.0690, 2);
        v_ss_vieillesse_d := ROUND(v_brut * 0.0040, 2);
        v_retraite_t1 := ROUND(LEAST(v_brut, v_pmss) * 0.0386, 2);
        v_retraite_t2 := ROUND(GREATEST(0, v_brut - v_pmss) * 0.1021, 2);
        v_chomage := 0; -- 0% salarié depuis 2018
        v_ceg := ROUND(LEAST(v_brut, v_pmss) * 0.0086, 2);
        v_total_sal := v_csg_ded + v_csg_non_ded + v_crds + v_ss_maladie + v_ss_vieillesse_p
            + v_ss_vieillesse_d + v_retraite_t1 + v_retraite_t2 + v_chomage + v_ceg;
        v_pat_ss := ROUND(v_brut * 0.1305, 2);
        v_pat_af := ROUND(v_brut * 0.0525, 2);
        v_pat_at := ROUND(v_brut * 0.0100, 2);
        v_pat_ret := ROUND(LEAST(v_brut, v_pmss) * 0.0601, 2);
        v_pat_chom := ROUND(v_brut * 0.0405, 2);
        v_pat_fnal := ROUND(v_brut * 0.0050, 2);
        v_pat_form := ROUND(v_brut * 0.0055, 2);
        v_pat_transport := ROUND(v_brut * 0.0175, 2);
        v_total_pat := v_pat_ss + v_pat_af + v_pat_at + v_pat_ret + v_pat_chom + v_pat_fnal + v_pat_form + v_pat_transport;
        v_net := v_brut - v_total_sal;
    END IF;

    DELETE FROM cotisations_sociales WHERE mission_id = p_mission_id;
    INSERT INTO cotisations_sociales (
        mission_id, soignant_id, type_contrat, salaire_brut, csg_deductible, csg_non_deductible, crds,
        securite_sociale_maladie, securite_sociale_vieillesse_plafonnee, securite_sociale_vieillesse_deplafonnee,
        retraite_complementaire_t1, retraite_complementaire_t2, assurance_chomage, contribution_equilibre_general,
        patronal_securite_sociale, patronal_allocations_familiales, patronal_accident_travail,
        patronal_retraite_complementaire, patronal_chomage, patronal_fnal, patronal_formation, patronal_transport,
        total_cotisations_salariales, total_cotisations_patronales, net_avant_impot, cout_total_employeur, ifm, icp
    ) VALUES (
        p_mission_id, v_mission.soignant_assigne_id, v_type, v_brut, v_csg_ded, v_csg_non_ded, v_crds,
        v_ss_maladie, v_ss_vieillesse_p, v_ss_vieillesse_d, v_retraite_t1, v_retraite_t2, v_chomage, v_ceg,
        v_pat_ss, v_pat_af, v_pat_at, v_pat_ret, v_pat_chom, v_pat_fnal, v_pat_form, v_pat_transport,
        v_total_sal, v_total_pat, v_net, v_brut + v_total_pat, v_ifm, v_icp
    );

    RETURN jsonb_build_object('success', true, 'type_contrat', v_type, 'brut', v_brut, 'ifm', v_ifm, 'icp', v_icp,
        'cotisations_salariales', v_total_sal, 'cotisations_patronales', v_total_pat,
        'net_avant_impot', v_net, 'cout_total_employeur', v_brut + v_total_pat);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_bfa_tous()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_annee INTEGER := EXTRACT(YEAR FROM NOW()) - 1; -- année précédente
    v_groupe RECORD;
    v_etab RECORD;
    v_count INTEGER := 0;
BEGIN
    -- Calculer pour tous les groupes
    FOR v_groupe IN SELECT id FROM groupes_sante WHERE supprime_le IS NULL
    LOOP
        PERFORM fn_calculer_bfa(NULL, v_groupe.id, v_annee);
        v_count := v_count + 1;
    END LOOP;

    -- Calculer pour les établissements SANS groupe
    FOR v_etab IN SELECT id FROM etablissements WHERE groupe_sante_id IS NULL AND supprime_le IS NULL
    LOOP
        PERFORM fn_calculer_bfa(v_etab.id, NULL, v_annee);
        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'annee', v_annee, 'calculs', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_heures_majorees(p_debut timestamp with time zone, p_fin timestamp with time zone)
 RETURNS TABLE(heures_nuit numeric, heures_dimanche numeric, heures_ferie numeric)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
    v_cursor TIMESTAMPTZ;
    v_step INTERVAL := '30 minutes';
    v_nuit NUMERIC := 0;
    v_dim NUMERIC := 0;
    v_fer NUMERIC := 0;
    v_heure INT;
    v_dow INT;
    v_date DATE;
BEGIN
    v_cursor := p_debut;
    WHILE v_cursor < p_fin LOOP
        v_heure := EXTRACT(HOUR FROM v_cursor);
        v_dow := EXTRACT(DOW FROM v_cursor); -- 0 = dimanche
        v_date := v_cursor::DATE;

        -- Nuit : 21h → 6h
        IF v_heure >= 21 OR v_heure < 6 THEN
            v_nuit := v_nuit + 0.5;
        END IF;

        -- Dimanche (DOW = 0)
        IF v_dow = 0 THEN
            v_dim := v_dim + 0.5;
        END IF;

        -- Jours fériés français (table jours_feries_fr si existe, sinon liste statique)
        IF EXISTS (SELECT 1 FROM jours_feries_fr WHERE date_ferie = v_date) THEN
            v_fer := v_fer + 0.5;
        END IF;

        v_cursor := v_cursor + v_step;
    END LOOP;

    RETURN QUERY SELECT v_nuit, v_dim, v_fer;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_montant_periode(p_mission_id uuid, p_periode_debut date DEFAULT NULL::date, p_periode_fin date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_mission RECORD;
  v_duree_periode numeric;
  v_duree_totale numeric;
  v_montant_ht_total numeric;
  v_montant_ht_periode numeric;
  v_ratio numeric;
BEGIN
  SELECT id, debut_le, fin_le, taux_horaire_base_fige,
         total_brut, net_a_payer
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable', p_mission_id;
  END IF;

  SELECT COALESCE(ROUND(GREATEST(
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='PREVISIONNEL' AND NOT est_pause),
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)
  )::numeric, 2), 0)
  INTO v_duree_periode
  FROM mission_creneaux
  WHERE mission_id = p_mission_id
    AND (
      p_periode_debut IS NULL
      OR (debut::date <= p_periode_fin AND COALESCE(fin::date, debut::date) >= p_periode_debut)
    );

  SELECT COALESCE(ROUND(GREATEST(
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='PREVISIONNEL' AND NOT est_pause),
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau='EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)
  )::numeric, 2), 0)
  INTO v_duree_totale
  FROM mission_creneaux
  WHERE mission_id = p_mission_id;

  v_montant_ht_total := COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0);

  IF p_periode_debut IS NULL OR v_duree_totale = 0 THEN
    v_montant_ht_periode := v_montant_ht_total;
    v_ratio := 1.0;
  ELSE
    v_ratio := v_duree_periode / v_duree_totale;
    v_montant_ht_periode := ROUND(v_montant_ht_total * v_ratio, 2);
  END IF;

  RETURN jsonb_build_object(
    'mission_id', p_mission_id,
    'periode_debut', p_periode_debut,
    'periode_fin', p_periode_fin,
    'duree_periode_heures', v_duree_periode,
    'duree_totale_mission_heures', v_duree_totale,
    'ratio_periode', v_ratio,
    'montant_ht_total_mission', v_montant_ht_total,
    'montant_ht_periode', v_montant_ht_periode,
    'taux_horaire_base_fige', v_mission.taux_horaire_base_fige
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_indemnite_annulation_etab(p_type_contrat text, p_montant_total numeric, p_duree_heures numeric, p_taux_horaire numeric, p_delta_mission interval)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_montant numeric := 0;
  v_motif text := 'aucune_indemnite';
  v_base text;
BEGIN
  IF p_type_contrat IN ('CDD', 'CDD', 'SALARIE') THEN
    -- Code travail : salaire brut + indemnité précarité 10%
    v_montant := COALESCE(p_duree_heures, 0) * COALESCE(p_taux_horaire, 0) * 1.10;
    v_motif := 'INDEMNITE_CDD_SIGNE_L1243_8';
    v_base := 'duree × taux × 1.10 (salaire + précarité 10%)';
  ELSIF p_type_contrat IN ('REMPLACEMENT_LIBERAL', 'LIBERAL') THEN
    -- Code civil 1231-5 : clause pénale dégressive
    IF p_delta_mission < INTERVAL '24 hours' THEN
      v_montant := COALESCE(p_montant_total, 0) * 0.50;
      v_motif := 'CLAUSE_PENALE_LIBERAL_24H';
      v_base := 'montant × 50% (annulation < 24h)';
    ELSIF p_delta_mission < INTERVAL '48 hours' THEN
      v_montant := COALESCE(p_montant_total, 0) * 0.30;
      v_motif := 'CLAUSE_PENALE_LIBERAL_24_48H';
      v_base := 'montant × 30% (annulation 24-48h)';
    ELSE
      v_montant := COALESCE(p_montant_total, 0) * 0.10;
      v_motif := 'CLAUSE_PENALE_LIBERAL_48H_PLUS';
      v_base := 'montant × 10% (annulation > 48h)';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'montant', ROUND(v_montant, 2),
    'motif', v_motif,
    'base_calcul', v_base,
    'type_contrat', p_type_contrat
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_remuneration_mission(p_debut timestamp with time zone, p_fin timestamp with time zone, p_taux_base numeric, p_etablissement_id uuid, p_soignant_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_contrat type_contrat := 'CDD';
    v_exercice text := 'SALARIE';
    v_curseur TIMESTAMPTZ;
    v_fin_creneau TIMESTAMPTZ;
    v_date_heure DATE;
    v_heure_du_jour INTEGER;
    v_jour_semaine INTEGER;
    v_heures_totales NUMERIC := 0;
    v_heures_nuit NUMERIC := 0;
    v_heures_dimanche NUMERIC := 0;
    v_heures_ferie NUMERIC := 0;
    v_heures_normales NUMERIC := 0;
    v_montant_base NUMERIC := 0;
    v_majoration_nuit NUMERIC := 0;
    v_majoration_dimanche NUMERIC := 0;
    v_majoration_ferie NUMERIC := 0;
    v_total_brut NUMERIC := 0;
    v_ifm NUMERIC := 0;
    v_icp NUMERIC := 0;
    v_net_a_payer NUMERIC := 0;
    v_taux_ifm NUMERIC := 0;
    v_taux_icp NUMERIC := 0;
BEGIN
    SELECT e.taux_majoration_nuit_pourcent,
           e.taux_majoration_dimanche_pourcent,
           e.taux_majoration_ferie_pourcent
    INTO v_etab
    FROM etablissements e WHERE e.id = p_etablissement_id;

    IF p_soignant_id IS NOT NULL THEN
        SELECT s.type_contrat, COALESCE(s.type_exercice, 'SALARIE')
        INTO v_contrat, v_exercice
        FROM soignants s WHERE s.id = p_soignant_id;
    END IF;

    v_curseur := p_debut;
    WHILE v_curseur < p_fin LOOP
        v_fin_creneau := LEAST(v_curseur + INTERVAL '1 hour', p_fin);
        DECLARE
            v_duree_creneau NUMERIC := EXTRACT(EPOCH FROM (v_fin_creneau - v_curseur)) / 3600.0;
            v_est_nuit BOOLEAN;
            v_est_dimanche BOOLEAN;
            v_est_ferie BOOLEAN;
        BEGIN
            v_date_heure := (v_curseur AT TIME ZONE 'Europe/Paris')::DATE;
            v_heure_du_jour := EXTRACT(HOUR FROM (v_curseur AT TIME ZONE 'Europe/Paris'));
            v_jour_semaine := EXTRACT(ISODOW FROM (v_curseur AT TIME ZONE 'Europe/Paris'));
            v_est_nuit := (v_heure_du_jour >= 21 OR v_heure_du_jour < 6);
            v_est_dimanche := (v_jour_semaine = 7);
            v_est_ferie := fn_est_jour_ferie(v_date_heure);
            v_heures_totales := v_heures_totales + v_duree_creneau;
            IF v_est_nuit THEN v_heures_nuit := v_heures_nuit + v_duree_creneau; END IF;
            IF v_est_dimanche THEN v_heures_dimanche := v_heures_dimanche + v_duree_creneau; END IF;
            IF v_est_ferie THEN v_heures_ferie := v_heures_ferie + v_duree_creneau; END IF;
            IF NOT v_est_nuit AND NOT v_est_dimanche AND NOT v_est_ferie THEN
                v_heures_normales := v_heures_normales + v_duree_creneau;
            END IF;
        END;
        v_curseur := v_fin_creneau;
    END LOOP;

    v_montant_base := v_heures_totales * p_taux_base;
    v_majoration_nuit := v_heures_nuit * p_taux_base * (COALESCE(v_etab.taux_majoration_nuit_pourcent, 25) / 100.0);
    v_majoration_dimanche := v_heures_dimanche * p_taux_base * (COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50) / 100.0);
    v_majoration_ferie := v_heures_ferie * p_taux_base * (COALESCE(v_etab.taux_majoration_ferie_pourcent, 100) / 100.0);
    v_total_brut := v_montant_base + v_majoration_nuit + v_majoration_dimanche + v_majoration_ferie;

    -- IFM + ICP : primes d'un CDD salarié uniquement. Un soignant en exercice
    -- LIBÉRAL ne perçoit pas ces indemnités (il facture des honoraires) — sinon sa
    -- note d'honoraires et la commission seraient gonflées de ~21 %.
    IF v_contrat = 'CDD' AND COALESCE(v_exercice, 'SALARIE') <> 'LIBERAL' THEN
        v_taux_ifm := 0.10;
        v_taux_icp := 0.10;
        v_ifm := v_total_brut * v_taux_ifm;
        v_icp := (v_total_brut + v_ifm) * v_taux_icp;
    END IF;

    v_net_a_payer := v_total_brut + v_ifm + v_icp;

    RETURN jsonb_build_object(
        'heures_totales', ROUND(v_heures_totales, 2),
        'heures_normales', ROUND(v_heures_normales, 2),
        'heures_nuit', ROUND(v_heures_nuit, 2),
        'heures_dimanche', ROUND(v_heures_dimanche, 2),
        'heures_ferie', ROUND(v_heures_ferie, 2),
        'taux_horaire_base', p_taux_base,
        'montant_base', ROUND(v_montant_base, 2),
        'majoration_nuit_pourcent', COALESCE(v_etab.taux_majoration_nuit_pourcent, 25),
        'montant_majoration_nuit', ROUND(v_majoration_nuit, 2),
        'majoration_dimanche_pourcent', COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50),
        'montant_majoration_dimanche', ROUND(v_majoration_dimanche, 2),
        'majoration_ferie_pourcent', COALESCE(v_etab.taux_majoration_ferie_pourcent, 100),
        'montant_majoration_ferie', ROUND(v_majoration_ferie, 2),
        'total_brut', ROUND(v_total_brut, 2),
        'taux_ifm', v_taux_ifm,
        'montant_ifm', ROUND(v_ifm, 2),
        'taux_icp', v_taux_icp,
        'montant_icp', ROUND(v_icp, 2),
        'net_a_payer', ROUND(v_net_a_payer, 2),
        'type_contrat', v_contrat::TEXT
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_taux_free_transition(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_heures_plateforme NUMERIC;
    v_taux INTEGER;
    v_montant NUMERIC;
BEGIN
    SELECT COALESCE(heures_plateforme, 0) INTO v_heures_plateforme
    FROM soignants WHERE id = p_soignant_id;

    -- Grille dégressive basée sur les heures SUR la plateforme
    IF v_heures_plateforme >= 3200 THEN
        v_taux := 100;
    ELSIF v_heures_plateforme >= 2400 THEN
        v_taux := 75;
    ELSIF v_heures_plateforme >= 1600 THEN
        v_taux := 50;
    ELSIF v_heures_plateforme >= 800 THEN
        v_taux := 25;
    ELSE
        v_taux := 0;
    END IF;

    -- Coût total Free Transition : ~450€
    v_montant := ROUND(450.00 * (v_taux / 100.0), 2);

    RETURN jsonb_build_object(
        'soignant_id', p_soignant_id,
        'heures_plateforme', v_heures_plateforme,
        'taux_prise_en_charge', v_taux,
        'montant_pris_en_charge', v_montant,
        'eligible', v_heures_plateforme >= 800
    );
END;
$function$


---FIN-FONCTION---

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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_score_etablissement(p_etab_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_since TIMESTAMPTZ := NOW() - INTERVAL '12 months';
  v_notation_pct NUMERIC;
  v_paiement_pct NUMERIC;
  v_litiges_malus NUMERIC := 0;
  v_score NUMERIC := 0;
  v_niveau public.niveau_qualitatif;
  v_nb_notations INT;
  v_nb_litiges INT;
  v_total_factures INT;
  v_factures_a_temps INT;
BEGIN
  SELECT COUNT(*),
    SUM(((critere_1 + critere_2 + critere_3 + critere_4) / 4.0) * GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))) /
    NULLIF(SUM(GREATEST(0, 1 - EXTRACT(EPOCH FROM (NOW() - cree_le))/(365.0*86400))), 0)
  INTO v_nb_notations, v_notation_pct
  FROM notations_missions
  WHERE note_id = p_etab_id AND sens = 'SOIGNANT_VERS_ETAB' AND cree_le >= v_since AND masque = false;

  IF v_nb_notations < 3 OR v_notation_pct IS NULL THEN
    v_notation_pct := NULL;
  ELSE
    v_notation_pct := GREATEST(0, LEAST(100, (v_notation_pct - 1) * 25));
  END IF;

  SELECT COUNT(*), COUNT(*) FILTER (WHERE date_paiement IS NOT NULL AND date_paiement <= date_echeance)
  INTO v_total_factures, v_factures_a_temps
  FROM factures
  WHERE etablissement_id = p_etab_id AND statut = 'PAYEE' AND COALESCE(date_emission, cree_le) >= v_since;

  IF v_total_factures = 0 THEN v_paiement_pct := NULL;
  ELSE v_paiement_pct := (v_factures_a_temps::NUMERIC / v_total_factures) * 100; END IF;

  SELECT LEAST(2, COUNT(*)) * 10 INTO v_nb_litiges
  FROM litiges
  WHERE etablissement_id = p_etab_id
    AND statut IN ('RESOLU_SOIGNANT', 'RESOLU_FAVEUR_SOIGNANT')
    AND COALESCE(resolu_le, NOW()) >= v_since;
  v_litiges_malus := -COALESCE(v_nb_litiges, 0);

  DECLARE v_total_poids NUMERIC := 0; v_facteur NUMERIC;
  BEGIN
    IF v_notation_pct IS NOT NULL THEN v_total_poids := v_total_poids + 50; END IF;
    IF v_paiement_pct IS NOT NULL THEN v_total_poids := v_total_poids + 30; END IF;
    IF v_total_poids > 0 THEN
      v_facteur := 80.0 / v_total_poids;
      v_score := COALESCE(v_notation_pct, 0) * 50 * v_facteur / 100
               + COALESCE(v_paiement_pct, 0) * 30 * v_facteur / 100
               + 20 + v_litiges_malus;
    ELSE v_score := 50 + v_litiges_malus; END IF;
    v_score := GREATEST(0, LEAST(100, v_score));
  END;

  v_niveau := CASE
    WHEN v_score >= 90 THEN 'PLATINE'
    WHEN v_score >= 70 THEN 'OR'
    WHEN v_score >= 50 THEN 'ARGENT'
    ELSE 'BRONZE'
  END::public.niveau_qualitatif;

  UPDATE etablissements SET score_qualite = v_score, niveau = v_niveau WHERE id = p_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := p_etab_id, p_type_acteur := 'SYSTEME',
    p_action := 'SCORE_ETAB_RECALCULE', p_type_ressource := 'etablissement', p_id_ressource := p_etab_id,
    p_details := jsonb_build_object('score', v_score, 'niveau', v_niveau::text, 'notation_pct', v_notation_pct, 'paiement_pct', v_paiement_pct, 'litiges_malus', v_litiges_malus)
  );

  RETURN jsonb_build_object('success', true, 'score', v_score, 'niveau', v_niveau);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_penalite_annulation_soignant(p_acceptee_a timestamp with time zone, p_debut_mission timestamp with time zone, p_est_asap boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_delta_retract interval;
  v_delta_mission interval;
  v_points int := 0;
  v_motif text := 'aucun';
  v_libre boolean := false;
BEGIN
  v_delta_retract := NOW() - p_acceptee_a;
  v_delta_mission := p_debut_mission - NOW();

  -- Fenêtre rétractation 30 min : annulation libre
  IF v_delta_retract < INTERVAL '30 minutes' THEN
    RETURN jsonb_build_object('libre', true, 'points', 0, 'motif', 'fenetre_retractation_30min');
  END IF;

  -- ASAP annulée après fenêtre rétractation
  IF p_est_asap AND v_delta_mission < INTERVAL '2 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -25,
                                'motif', 'ASAP_ANNULEE_APRES_FENETRE');
  END IF;

  -- No-show ou annulation last-minute (< 1h)
  IF v_delta_mission < INTERVAL '1 hour' THEN
    RETURN jsonb_build_object('libre', false, 'points', -30,
                                'motif', 'NO_SHOW', 'signalement_admin', true);
  END IF;

  -- 1-12h avant
  IF v_delta_mission < INTERVAL '12 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -10,
                                'motif', 'ANNULATION_1_12H');
  END IF;

  -- 12-24h avant
  IF v_delta_mission < INTERVAL '24 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -5,
                                'motif', 'ANNULATION_12_24H');
  END IF;

  -- > 24h : neutre
  RETURN jsonb_build_object('libre', true, 'points', 0, 'motif', 'neutre_delai_long');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_score_soignant(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant RECORD;
  v_note_moyenne numeric;
  v_note_count int;
  v_note_pts int := 0;
  v_evt_penalites int;
  v_evt_bonus int;
  v_comportement_pts int;
  v_mois_inscription int;
  v_anciennete_pts int;
  v_score_total int;
BEGIN
  SELECT id, cree_le INTO v_soignant FROM public.soignants WHERE id = p_soignant_id;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Soignant introuvable');
  END IF;

  -- Composante 1 : note moyenne (40 pts max) — basée sur notes reçues
  SELECT AVG(note), COUNT(*) INTO v_note_moyenne, v_note_count
  FROM public.notations
  WHERE cible_id = p_soignant_id AND cible_type = 'SOIGNANT'
    AND masquee_par_admin IS NOT TRUE
    AND cree_le > NOW() - INTERVAL '12 months';
  IF v_note_count IS NULL OR v_note_count = 0 THEN
    v_note_pts := 28;  -- valeur par défaut neutre (3.5/5 × 8)
  ELSE
    v_note_pts := LEAST(40, GREATEST(0, ROUND(COALESCE(v_note_moyenne, 0) * 8)));
  END IF;

  -- Composante 2 : comportement contractuel (40 pts max)
  -- Base 40 — somme des points pénalités (négatifs) - somme bonus (positifs)
  -- Sur 12 derniers mois, en excluant les events ANNULES par admin
  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_penalites
  FROM public.evenements_score_soignant
  WHERE soignant_id = p_soignant_id
    AND points < 0
    AND cree_le > NOW() - INTERVAL '12 months';

  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_bonus
  FROM public.evenements_score_soignant
  WHERE soignant_id = p_soignant_id
    AND points > 0
    AND cree_le > NOW() - INTERVAL '12 months';

  v_comportement_pts := GREATEST(0, LEAST(40, 40 + v_evt_penalites + v_evt_bonus));

  -- Composante 3 : ancienneté (20 pts max, 1 pt par mois)
  v_mois_inscription := EXTRACT(EPOCH FROM (NOW() - v_soignant.cree_le)) / (30.44 * 86400);
  v_anciennete_pts := LEAST(20, GREATEST(0, v_mois_inscription));

  v_score_total := LEAST(100, GREATEST(0, v_note_pts + v_comportement_pts + v_anciennete_pts));

  RETURN jsonb_build_object(
    'success', true,
    'score_total', v_score_total,
    'composantes', jsonb_build_object(
      'note_moyenne_pts', v_note_pts,
      'note_moyenne_valeur', COALESCE(v_note_moyenne, 0),
      'note_count', COALESCE(v_note_count, 0),
      'comportement_pts', v_comportement_pts,
      'comportement_penalites', v_evt_penalites,
      'comportement_bonus', v_evt_bonus,
      'anciennete_pts', v_anciennete_pts,
      'anciennete_mois', v_mois_inscription
    ),
    'calcul_le', NOW()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_score_etab(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab RECORD;
  v_note_moyenne numeric;
  v_note_count int;
  v_note_pts int := 0;
  v_evt_penalites int;
  v_evt_bonus int;
  v_comportement_pts int;
  v_delai_moyen_jours numeric;
  v_delai_paiement_pts int;
  v_score_total int;
BEGIN
  SELECT id, cree_le INTO v_etab FROM public.etablissements WHERE id = p_etablissement_id;
  IF v_etab IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  -- Composante 1 : note moyenne donnée par les soignants (40 pts max)
  SELECT AVG(note), COUNT(*) INTO v_note_moyenne, v_note_count
  FROM public.evaluations
  WHERE evalue_id = p_etablissement_id AND type_evaluateur = 'SOIGNANT'
    AND visible IS NOT FALSE
    AND cree_le > NOW() - INTERVAL '12 months';
  IF v_note_count IS NULL OR v_note_count = 0 THEN
    v_note_pts := 28;
  ELSE
    v_note_pts := LEAST(40, GREATEST(0, ROUND(COALESCE(v_note_moyenne, 0) * 8)));
  END IF;

  -- Composante 2 : comportement contractuel (40 pts max)
  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_penalites
  FROM public.evenements_score_etab
  WHERE etablissement_id = p_etablissement_id
    AND points < 0
    AND cree_le > NOW() - INTERVAL '12 months';

  SELECT
    COALESCE(SUM(CASE
      WHEN decision_admin = 'ANNULER' THEN 0
      WHEN decision_admin = 'REDUIRE' THEN COALESCE(points_corriges, points)
      ELSE points
    END), 0) INTO v_evt_bonus
  FROM public.evenements_score_etab
  WHERE etablissement_id = p_etablissement_id
    AND points > 0
    AND cree_le > NOW() - INTERVAL '12 months';

  v_comportement_pts := GREATEST(0, LEAST(40, 40 + v_evt_penalites + v_evt_bonus));

  -- Composante 3 : délai moyen de paiement (20 pts max)
  -- Sur les 12 derniers mois, écart entre date_emission et date_paiement
  SELECT AVG(EXTRACT(EPOCH FROM (date_paiement - date_emission)) / 86400)
  INTO v_delai_moyen_jours
  FROM public.factures
  WHERE etablissement_id = p_etablissement_id
    AND date_paiement IS NOT NULL
    AND date_emission IS NOT NULL
    AND date_emission > NOW() - INTERVAL '12 months';

  v_delai_paiement_pts := CASE
    WHEN v_delai_moyen_jours IS NULL THEN 15  -- défaut neutre si pas de data
    WHEN v_delai_moyen_jours <= 7 THEN 20
    WHEN v_delai_moyen_jours <= 15 THEN 15
    WHEN v_delai_moyen_jours <= 30 THEN 10
    ELSE 5
  END;

  v_score_total := LEAST(100, GREATEST(0, v_note_pts + v_comportement_pts + v_delai_paiement_pts));

  RETURN jsonb_build_object(
    'success', true,
    'score_total', v_score_total,
    'composantes', jsonb_build_object(
      'note_moyenne_pts', v_note_pts,
      'note_moyenne_valeur', COALESCE(v_note_moyenne, 0),
      'note_count', COALESCE(v_note_count, 0),
      'comportement_pts', v_comportement_pts,
      'comportement_penalites', v_evt_penalites,
      'comportement_bonus', v_evt_bonus,
      'delai_paiement_pts', v_delai_paiement_pts,
      'delai_paiement_jours_moy', v_delai_moyen_jours
    ),
    'calcul_le', NOW()
  );
END;
$function$


---FIN-FONCTION---

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
         m.cree_le, m.boostee_le, m.type_contrat_recherche
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
                  + v_bonus_fraicheur + v_bonus_connaissance
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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_taux_free_transition_safe(p_soignant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN fn_calculer_taux_free_transition(p_soignant_id);
EXCEPTION WHEN OTHERS THEN
    RETURN '{"error": "Calcul indisponible."}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_charger_demo_investisseur()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_etab1 UUID := uuid_generate_v4();
    v_etab2 UUID := uuid_generate_v4();
    v_etab3 UUID := uuid_generate_v4();
    v_etab4 UUID := uuid_generate_v4();
    v_s UUID;
    v_m UUID;
    v_count_s INTEGER := 0;
    v_count_m INTEGER := 0;
    v_prenoms TEXT[] := ARRAY['Marie','Sophie','Claire','Julie','Emma','Léa','Camille','Sarah','Laura','Chloé','Lucas','Thomas'];
    v_noms TEXT[] := ARRAY['Martin','Bernard','Dubois','Moreau','Laurent','Simon','Michel','Garcia','Lefebvre','Roux','Mercier','Girard'];
BEGIN
    IF NOT est_admin() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;

    -- 4 Établissements
    INSERT INTO etablissements (id, nom, type, siret, adresse_rue, adresse_ville, adresse_code_postal, adresse_lat, adresse_lng)
    VALUES
        (v_etab1, 'Pharmacie du Centre', 'PHARMACIE_OFFICINE', '44306184100023', '12 Rue de la Paix', 'Paris', '75002', 48.8698, 2.3298),
        (v_etab2, 'Clinique des Lilas', 'CLINIQUE_PRIVEE', '53208865400019', '41 Avenue Gambetta', 'Les Lilas', '93260', 48.8801, 2.4168),
        (v_etab3, 'EHPAD Résidence Soleil', 'EHPAD', '81751293200015', '8 Rue des Fleurs', 'Vincennes', '94300', 48.8473, 2.4392),
        (v_etab4, 'Pharmacie Leader Santé Bastille', 'PHARMACIE_OFFICINE', '90215847300011', '25 Rue de la Roquette', 'Paris', '75011', 48.8534, 2.3716);

    -- 12 Soignants avec des profils variés
    FOR i IN 1..12 LOOP
        v_s := uuid_generate_v4();
        INSERT INTO soignants (
            id, prenom, nom, email, profession, score_fiabilite,
            heures_cumulees, total_missions_terminees, tous_documents_valides,
            rpps_verifie, adresse_ville, adresse_lat, adresse_lng,
            attestation_vaccinations, attestation_vaccinations_le
        ) VALUES (
            v_s,
            v_prenoms[((i - 1) % 12) + 1],
            v_noms[((i - 1) % 12) + 1],
            'demo.soignant.' || i || '@jolene.app',
            CASE
                WHEN i <= 4 THEN 'INFIRMIER_DE'::type_profession
                WHEN i <= 6 THEN 'AIDE_SOIGNANT'::type_profession
                WHEN i <= 8 THEN 'PHARMACIEN'::type_profession
                WHEN i <= 10 THEN 'KINESITHERAPEUTE'::type_profession
                ELSE 'PREPARATEUR_PHARMA'::type_profession
            END,
            50 + (i * 4),
            200 + (i * 150),
            i * 3,
            TRUE, TRUE,
            'Paris',
            48.85 + (random() * 0.05),
            2.33 + (random() * 0.1),
            TRUE, NOW() - INTERVAL '30 days'
        );
        v_count_s := v_count_s + 1;
    END LOOP;

    -- 35 Missions variées
    FOR i IN 1..35 LOOP
        INSERT INTO missions (
            etablissement_id, intitule, profession_requise, service,
            debut_le, fin_le, taux_horaire_base, statut,
            duree_heures
        ) VALUES (
            CASE
                WHEN i % 4 = 0 THEN v_etab1
                WHEN i % 4 = 1 THEN v_etab2
                WHEN i % 4 = 2 THEN v_etab3
                ELSE v_etab4
            END,
            CASE
                WHEN i % 5 = 0 THEN 'Remplacement infirmier(ère) de jour'
                WHEN i % 5 = 1 THEN 'Garde de nuit — service gériatrie'
                WHEN i % 5 = 2 THEN 'Remplacement pharmacien titulaire'
                WHEN i % 5 = 3 THEN 'Renfort aide-soignant(e) week-end'
                ELSE 'Vacation kinésithérapie respiratoire'
            END,
            CASE
                WHEN i % 5 = 0 THEN 'INFIRMIER_DE'::type_profession
                WHEN i % 5 = 1 THEN 'INFIRMIER_DE'::type_profession
                WHEN i % 5 = 2 THEN 'PHARMACIEN'::type_profession
                WHEN i % 5 = 3 THEN 'AIDE_SOIGNANT'::type_profession
                ELSE 'KINESITHERAPEUTE'::type_profession
            END,
            CASE
                WHEN i % 3 = 0 THEN 'Médecine générale'
                WHEN i % 3 = 1 THEN 'Gériatrie'
                ELSE 'Officine'
            END,
            NOW() + (i || ' days')::INTERVAL + INTERVAL '8 hours',
            NOW() + (i || ' days')::INTERVAL + INTERVAL '20 hours',
            CASE
                WHEN i % 5 = 2 THEN 45.00
                WHEN i % 5 = 3 THEN 18.50
                ELSE 28.00
            END,
            CASE
                WHEN i <= 10 THEN 'TERMINEE'
                WHEN i <= 20 THEN 'OUVERTE'
                WHEN i <= 25 THEN 'ASSIGNEE'
                ELSE 'OUVERTE'
            END,
            12
        );
        v_count_m := v_count_m + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'etablissements', 4,
        'soignants', v_count_s,
        'missions', v_count_m
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_cession_existe(p_facture_honoraire_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS(
        SELECT 1 FROM cessions_creance
        WHERE facture_honoraire_id = p_facture_honoraire_id
        AND soignant_id = auth.uid()
    );
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_choisir_parcours_kine(p_parcours text)
 RETURNS parcours_liberal_soignants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parcours public.parcours_liberal_soignants;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;
  IF p_parcours IS NOT NULL AND p_parcours NOT IN ('HEURES_2240', 'ZONE_SOUS_DOTEE') THEN
    RAISE EXCEPTION 'Parcours kiné invalide';
  END IF;

  PERFORM public.fn_get_or_create_parcours_liberal();

  UPDATE public.parcours_liberal_soignants
  SET parcours_kine = p_parcours
  WHERE soignant_id = auth.uid()
  RETURNING * INTO v_parcours;

  RETURN v_parcours;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_check_crons_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_results jsonb := '[]'::jsonb; v_cron RECORD; v_dernier_run TIMESTAMPTZ;
  v_dernier_statut TEXT; v_dernier_msg TEXT; v_intervalle_attendu INTERVAL;
  v_retard BOOLEAN; v_alertes_emises INT := 0;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  FOR v_cron IN SELECT jobid, jobname, schedule FROM cron.job WHERE active = true LOOP
    SELECT end_time, status, return_message INTO v_dernier_run, v_dernier_statut, v_dernier_msg
    FROM cron.job_run_details WHERE jobid = v_cron.jobid ORDER BY end_time DESC LIMIT 1;
    v_intervalle_attendu := CASE
      WHEN v_cron.schedule LIKE '*/5%' THEN INTERVAL '15 minutes'
      WHEN v_cron.schedule LIKE '*/10%' THEN INTERVAL '30 minutes'
      WHEN v_cron.schedule LIKE '*/15%' THEN INTERVAL '45 minutes'
      WHEN v_cron.schedule LIKE '0 * * * *' THEN INTERVAL '90 minutes'
      WHEN v_cron.schedule LIKE '15 * * * *' THEN INTERVAL '90 minutes'
      WHEN v_cron.schedule LIKE '0 % * * *' THEN INTERVAL '26 hours'
      WHEN v_cron.schedule LIKE '0 % % * *' THEN INTERVAL '32 days'
      WHEN v_cron.schedule LIKE '0 % * * 0' THEN INTERVAL '8 days'
      ELSE INTERVAL '40 days' END;
    -- Un cron JAMAIS exécuté (v_dernier_run IS NULL) n'est « en retard » que s'il est
    -- assez fréquent pour avoir déjà dû tourner (intervalle <= 2 jours). Sinon (mensuel,
    -- annuel, hebdo) c'est normal qu'il n'ait pas encore tourné après sa création — on
    -- évite ainsi le bruit de faux positifs qui noyait les vraies alertes (auto-facturation
    -- mensuelle, recalcul paliers, calcul BFA annuel). Un échec réel reste capté par la
    -- branche 'failed' dès la première exécution.
    v_retard := (v_dernier_run IS NOT NULL AND v_dernier_run < NOW() - v_intervalle_attendu)
             OR (v_dernier_run IS NULL AND v_intervalle_attendu <= INTERVAL '2 days');
    IF v_dernier_statut = 'failed' THEN
      PERFORM fn_emettre_alerte_monitoring('CRON_FAILED', 'CRITICAL', v_cron.jobname,
        format('Cron "%s" a échoué : %s', v_cron.jobname, COALESCE(SUBSTRING(v_dernier_msg, 1, 200), '?')),
        jsonb_build_object('jobid', v_cron.jobid, 'schedule', v_cron.schedule, 'dernier_run', v_dernier_run));
      v_alertes_emises := v_alertes_emises + 1;
    ELSIF v_retard AND v_cron.jobname NOT IN ('calculer-bfa-annuel') THEN
      PERFORM fn_emettre_alerte_monitoring('CRON_RETARD', 'WARNING', v_cron.jobname,
        format('Cron "%s" en retard (dernier run : %s)', v_cron.jobname, COALESCE(v_dernier_run::text, 'jamais')),
        jsonb_build_object('jobid', v_cron.jobid, 'schedule', v_cron.schedule, 'dernier_run', v_dernier_run));
      v_alertes_emises := v_alertes_emises + 1;
    END IF;
    v_results := v_results || jsonb_build_object('jobid', v_cron.jobid, 'jobname', v_cron.jobname,
      'schedule', v_cron.schedule, 'dernier_run', v_dernier_run, 'dernier_statut', v_dernier_statut,
      'retard', v_retard, 'echec', v_dernier_statut = 'failed');
  END LOOP;
  RETURN jsonb_build_object('success', true, 'crons', v_results, 'alertes_emises', v_alertes_emises);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_check_stripe_webhook_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_total_24h INT; v_avec_erreur INT; v_non_traites_24h INT; v_taux_erreur NUMERIC;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  SELECT COUNT(*) INTO v_total_24h FROM stripe_webhook_events WHERE recu_le > NOW() - INTERVAL '24 hours';
  SELECT COUNT(*) INTO v_avec_erreur FROM stripe_webhook_events WHERE recu_le > NOW() - INTERVAL '24 hours' AND erreur IS NOT NULL;
  SELECT COUNT(*) INTO v_non_traites_24h FROM stripe_webhook_events WHERE recu_le > NOW() - INTERVAL '24 hours' AND traite_le IS NULL;
  v_taux_erreur := CASE WHEN v_total_24h > 0 THEN ROUND(v_avec_erreur * 100.0 / v_total_24h, 1) ELSE 0 END;
  IF v_total_24h > 0 AND v_taux_erreur > 5 THEN
    PERFORM fn_emettre_alerte_monitoring('WEBHOOK_ERROR_RATE', 'WARNING', 'stripe-webhook',
      format('Taux erreur webhook Stripe %s%% sur 24h (%s/%s)', v_taux_erreur, v_avec_erreur, v_total_24h),
      jsonb_build_object('total', v_total_24h, 'avec_erreur', v_avec_erreur, 'non_traites', v_non_traites_24h));
  END IF;
  RETURN jsonb_build_object('success', true, 'total_24h', v_total_24h, 'avec_erreur', v_avec_erreur, 'non_traites', v_non_traites_24h, 'taux_erreur_pct', v_taux_erreur);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_check_rate_limit_ip_signature(p_ip inet)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int; v_max constant int := 5;
BEGIN
  IF p_ip IS NULL THEN RETURN jsonb_build_object('allowed', true, 'reason', 'no_ip'); END IF;
  DELETE FROM public.signature_rate_limit_ip WHERE derniere_action < NOW() - INTERVAL '2 hours';
  SELECT COALESCE(SUM(nb_envois), 0) INTO v_count
  FROM public.signature_rate_limit_ip
  WHERE ip_signature = p_ip AND fenetre_debut > NOW() - INTERVAL '1 hour';
  IF v_count >= v_max THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'rate_limit_exceeded',
      'envois_courant', v_count, 'max', v_max);
  END IF;
  INSERT INTO public.signature_rate_limit_ip (ip_signature, fenetre_debut, nb_envois, derniere_action)
  VALUES (p_ip, date_trunc('hour', NOW()), 1, NOW())
  ON CONFLICT (ip_signature, fenetre_debut) DO UPDATE SET
    nb_envois = signature_rate_limit_ip.nb_envois + 1,
    derniere_action = NOW();
  RETURN jsonb_build_object('allowed', true, 'envois_courant', v_count + 1, 'max', v_max);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_calculer_tous_documents_valides(p_soignant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rpps_verifie BOOLEAN; v_adeli_verifie BOOLEAN; v_identite_verifiee BOOLEAN;
  v_est_liberal_pur BOOLEAN; v_est_salarie BOOLEAN;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN; END IF;
  SELECT COALESCE(rpps_verifie, false), COALESCE(adeli_verifie, false),
         (type_exercice = 'LIBERAL'), (type_exercice IS DISTINCT FROM 'LIBERAL')
    INTO v_rpps_verifie, v_adeli_verifie, v_est_liberal_pur, v_est_salarie
    FROM soignants WHERE id = p_soignant_id;
  v_identite_verifiee := v_rpps_verifie OR v_adeli_verifie;
  UPDATE soignants SET tous_documents_valides = NOT EXISTS(
      SELECT 1 FROM documents_requis_par_profession drp
      WHERE drp.profession = (SELECT profession FROM soignants WHERE id = p_soignant_id)
        AND drp.est_critique = true
        AND (drp.type_exercice_requis = 'TOUS'
            OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_est_liberal_pur)
            OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND v_est_salarie))
        AND NOT (v_identite_verifiee AND drp.type_document IN ('DIPLOME', 'RPPS_ADELI'))
        AND NOT EXISTS (
            SELECT 1 FROM documents_soignants ds
            WHERE ds.soignant_id = p_soignant_id AND ds.type_document = drp.type_document
              AND ds.statut_verification = 'VERIFIE' AND ds.supprime_le IS NULL
              AND (drp.a_expiration = false OR ds.valide_jusqua IS NULL OR ds.valide_jusqua > NOW()))
  ), modifie_le = NOW() WHERE id = p_soignant_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_codes_pointage_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
BEGIN
  SELECT id, code_arrivee, code_depart, etablissement_id
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès interdit');
  END IF;

  IF v_mission.code_arrivee IS NULL THEN
    UPDATE missions SET
      code_arrivee = lpad(floor(random() * 1000000)::text, 6, '0'),
      code_depart = lpad(floor(random() * 1000000)::text, 6, '0')
    WHERE id = p_mission_id
    RETURNING code_arrivee, code_depart INTO v_mission.code_arrivee, v_mission.code_depart;
  END IF;

  RETURN jsonb_build_object(
    'code_arrivee', v_mission.code_arrivee,
    'code_depart', v_mission.code_depart
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_commission_info_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_palier RECORD;
    v_paliers JSONB;
    v_missions_mois INT;
BEGIN
    SELECT e.*, p.nom AS palier_nom FROM etablissements e
    LEFT JOIN paliers_commission p ON p.id = e.palier_commission_id
    INTO v_etab WHERE e.id = mon_etablissement_id();

    IF v_etab IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;

    -- Missions du mois en cours
    SELECT COUNT(*) INTO v_missions_mois FROM missions
    WHERE etablissement_id = v_etab.id AND statut = 'TERMINEE'
    AND fin_le >= DATE_TRUNC('month', NOW()) AND fin_le < DATE_TRUNC('month', NOW()) + INTERVAL '1 month';

    -- Tous les paliers pour affichage
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'nom', nom, 'taux', taux_commission, 'missions_min', missions_min, 'missions_max', missions_max,
        'actuel', (v_etab.palier_commission_id = id)
    ) ORDER BY ordre), '[]'::JSONB) INTO v_paliers FROM paliers_commission WHERE est_actif = TRUE;

    RETURN jsonb_build_object(
        'taux_actuel', COALESCE(v_etab.taux_commission_negocie, 15),
        'palier_actuel', COALESCE(v_etab.palier_nom, 'Découverte'),
        'missions_mois_en_cours', v_missions_mois,
        'missions_mois_precedent', COALESCE(v_etab.missions_mois_precedent, 0),
        'palier_recalcule_le', v_etab.palier_recalcule_le,
        'paliers', v_paliers,
        'explication', 'Votre commission est recalculée le 1er de chaque mois en fonction du nombre de missions terminées le mois précédent. Plus vous utilisez Jolene, plus votre taux baisse.'
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_cloturer_litige(p_litige_id uuid, p_resolution text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_litige RECORD;
    v_qui TEXT;
BEGIN
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    IF v_litige.statut = 'CLOTURE' THEN RETURN jsonb_build_object('error', 'Déjà clôturé.'); END IF;
    
    IF auth.uid() = v_litige.soignant_id THEN
        v_qui := 'soignant';
        UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
    ELSIF mon_etablissement_id() = v_litige.etablissement_id THEN
        v_qui := 'etablissement';
        UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
    ELSIF est_admin() THEN
        -- Admin peut clôturer directement
        UPDATE litiges SET statut = 'CLOTURE', resolu_par = 'ADMIN', resolution = COALESCE(p_resolution, 'Clôturé par l''équipe Jolene'), resolu_le = NOW() WHERE id = p_litige_id;
        RETURN jsonb_build_object('success', TRUE, 'statut', 'CLOTURE');
    ELSE
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    -- Vérifier si les 2 parties sont d'accord
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige.accord_soignant = TRUE AND v_litige.accord_etablissement = TRUE THEN
        UPDATE litiges SET statut = 'CLOTURE', resolu_par = 'ACCORD_MUTUEL', 
            resolution = COALESCE(p_resolution, 'Clôturé par accord mutuel'), resolu_le = NOW()
        WHERE id = p_litige_id;
        RETURN jsonb_build_object('success', TRUE, 'statut', 'CLOTURE', 'resolution', 'accord_mutuel');
    END IF;
    
    RETURN jsonb_build_object('success', TRUE, 'accord_' || v_qui, TRUE, 'en_attente', 
        CASE WHEN v_qui = 'soignant' THEN 'établissement' ELSE 'soignant' END);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_compter_nouveaux_pour_filtre(p_filtre_id uuid, p_since timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filtre RECORD;
  v_count integer := 0;
  v_profession text;
  v_taux_min numeric;
  v_urgentes_only boolean;
BEGIN
  SELECT * INTO v_filtre FROM filtres_sauvegardes WHERE id = p_filtre_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  IF v_filtre.audience = 'SOIGNANT_RECHERCHE_MISSIONS' THEN
    v_profession := v_filtre.filtres->>'profession';
    v_taux_min := COALESCE((v_filtre.filtres->>'tauxMin')::numeric, 0);
    v_urgentes_only := COALESCE((v_filtre.filtres->>'urgentesOnly')::boolean, false);
    SELECT count(*) INTO v_count FROM missions m
    WHERE m.statut = 'OUVERTE'
      AND m.cree_le > p_since
      AND (v_profession IS NULL OR v_profession = '' OR m.profession_requise::text = v_profession)
      AND COALESCE(m.taux_horaire_base, 0) >= v_taux_min
      AND (NOT v_urgentes_only OR COALESCE(m.est_urgente, false) = true);
  ELSIF v_filtre.audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    v_profession := v_filtre.filtres->>'profession';
    SELECT count(*) INTO v_count FROM soignants s
    WHERE s.cree_le > p_since
      AND COALESCE(s.tous_documents_valides, false) = true
      AND (v_profession IS NULL OR v_profession = '' OR s.profession::text = v_profession);
  END IF;

  RETURN COALESCE(v_count, 0);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_compter_missions_sans_notation(p_role text DEFAULT 'auto'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID;
  v_role TEXT;
  v_count INT := 0;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('count', 0); END IF;

  v_etab_id := mon_etablissement_id();
  v_role := CASE
    WHEN p_role = 'auto' THEN
      CASE WHEN v_etab_id IS NOT NULL THEN 'ETAB' ELSE 'SOIGNANT' END
    ELSE p_role
  END;

  IF v_role = 'ETAB' AND v_etab_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_count FROM missions m
    WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE'
      AND m.soignant_assigne_id IS NOT NULL
      AND m.fin_le >= NOW() - INTERVAL '30 days'
      AND NOT EXISTS (SELECT 1 FROM notations_missions n WHERE n.mission_id = m.id AND n.sens = 'ETAB_VERS_SOIGNANT');
  ELSE
    SELECT COUNT(*) INTO v_count FROM missions m
    WHERE m.soignant_assigne_id = v_uid AND m.statut = 'TERMINEE'
      AND m.fin_le >= NOW() - INTERVAL '30 days'
      AND NOT EXISTS (SELECT 1 FROM notations_missions n WHERE n.mission_id = m.id AND n.sens = 'SOIGNANT_VERS_ETAB');
  END IF;

  RETURN jsonb_build_object('count', v_count, 'role', v_role);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_avec_payload(p_litige_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_litige RECORD;
  v_role text;
  v_other_role text;
  v_exec_result jsonb;
  v_type text;
  v_financier boolean;
  v_admin_ids uuid[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable');
  END IF;

  IF v_litige.soignant_id = v_uid THEN
    v_role := 'soignant'; v_other_role := 'etablissement';
  ELSIF v_litige.etablissement_id = v_uid OR mon_etablissement_id() = v_litige.etablissement_id THEN
    v_role := 'etablissement'; v_other_role := 'soignant';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  UPDATE public.litiges SET
    payload_modifications = p_payload,
    accord_soignant = CASE WHEN v_role = 'soignant' THEN true ELSE accord_soignant END,
    accord_soignant_le = CASE WHEN v_role = 'soignant' THEN NOW() ELSE accord_soignant_le END,
    accord_etablissement = CASE WHEN v_role = 'etablissement' THEN true ELSE accord_etablissement END,
    accord_etablissement_le = CASE WHEN v_role = 'etablissement' THEN NOW() ELSE accord_etablissement_le END
  WHERE id = p_litige_id;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF COALESCE(v_litige.accord_soignant, false) AND COALESCE(v_litige.accord_etablissement, false) THEN
    v_type := v_litige.payload_modifications->>'type';
    v_financier := (v_litige.payload_modifications IS NOT NULL
                    AND COALESCE(v_type, 'ACCORD_SANS_MODIFICATION') <> 'ACCORD_SANS_MODIFICATION');

    IF v_financier THEN
      -- Mouvement financier : accord des parties enregistré, mais EN ATTENTE de validation admin.
      UPDATE public.litiges SET
        statut = 'REVUE_ADMIN',
        resolution = COALESCE(p_payload->>'justification', 'Accord des parties — validation admin requise')
      WHERE id = p_litige_id;

      -- Notifier les admins qu'un accord financier attend leur validation.
      v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());
      IF array_length(v_admin_ids, 1) > 0 THEN
        INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
        SELECT 'PUSH_NOTIF', jsonb_build_object(
          'destinataire_id', uid, 'type_evenement', 'ALERTE_ADMIN',
          'titre', '⚖️ Accord financier à valider',
          'corps', 'Les parties se sont accordées sur un ajustement financier (' || COALESCE(v_type, '?') || '). Validation admin requise.',
          'lien', '/admin/litiges'
        ), 'LITIGE_ACCORD_FINANCIER', p_litige_id FROM unnest(v_admin_ids) AS uid;
      END IF;

      RETURN jsonb_build_object('success', true, 'statut', 'EN_ATTENTE_VALIDATION_ADMIN',
                                'type', v_type, 'payload_propose', v_litige.payload_modifications);
    ELSE
      -- Accord sans impact financier : clôture auto + exécution no-op.
      UPDATE public.litiges SET
        statut = 'RESOLU',
        resolu_le = COALESCE(resolu_le, NOW()),
        resolu_par = v_uid,
        resolution = COALESCE(p_payload->>'justification', 'Accord mutuel sans modification')
      WHERE id = p_litige_id;

      PERFORM set_config('jolene.litige_exec_ok', 'true', true);
      v_exec_result := public.fn_executer_modifications_litige(p_litige_id);
      RETURN jsonb_build_object('success', true, 'statut', 'RESOLU', 'execution', v_exec_result);
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'statut', 'EN_ATTENTE_ACCORD_AUTRE_PARTIE',
                            'role_en_attente', v_other_role, 'payload_propose', p_payload);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_classifier_canal(p_utm_source text, p_utm_medium text, p_referrer text, p_ref_code text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  s text := lower(coalesce(p_utm_source, ''));
  m text := lower(coalesce(p_utm_medium, ''));
  r text := lower(coalesce(p_referrer, ''));
BEGIN
  IF coalesce(p_ref_code, '') <> '' THEN RETURN 'PARRAINAGE'; END IF;
  IF m IN ('cpc','ppc','paid','paidsearch','paid-search','paid_search','ads','display','cpm','retargeting') THEN RETURN 'PAID'; END IF;
  IF m IN ('social','paid-social','paid_social','social-paid')
     OR s ~ '(facebook|instagram|linkedin|tiktok|twitter|youtube|snapchat|pinterest)'
     OR r ~ '(facebook|instagram|linkedin|tiktok|twitter|t\.co|youtube|snapchat|pinterest)' THEN RETURN 'SOCIAL'; END IF;
  IF m IN ('email','newsletter','mail') OR s = 'email' THEN RETURN 'EMAIL'; END IF;
  IF s <> '' OR m <> '' THEN RETURN 'CAMPAGNE'; END IF;
  IF r ~ '(google|bing|yahoo|duckduckgo|qwant|ecosia)' THEN RETURN 'SEO'; END IF;
  IF r <> '' THEN RETURN 'REFERRAL'; END IF;
  RETURN 'DIRECT';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_cleanup_missions_test()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ids uuid[];
  r record;
BEGIN
  SELECT array_agg(m.id) INTO v_ids
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE e.est_compte_test
    AND m.statut = 'OUVERTE'
    AND m.cree_le < now() - interval '2 hours';

  IF v_ids IS NULL THEN RETURN 0; END IF;

  FOR r IN
    SELECT c.conrelid::regclass::text AS t, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE c.confrelid = 'public.missions'::regclass AND c.contype = 'f'
  LOOP
    EXECUTE format('DELETE FROM %s WHERE %I = ANY($1)', r.t, r.col) USING v_ids;
  END LOOP;

  DELETE FROM missions WHERE id = ANY(v_ids);
  RETURN array_length(v_ids, 1);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_compteur_soignants_disponibles(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(DISTINCT s.id) INTO v_count
    FROM soignants s
    WHERE s.supprime_le IS NULL
      AND s.derniere_activite_le > NOW() - INTERVAL '7 days'
      AND fn_documents_ok_pour_mission(s.id, 'TOUS')
      AND s.profession IN (
          SELECT DISTINCT profession_requise FROM missions
          WHERE etablissement_id = p_etablissement_id AND statut = 'OUVERTE'
      )
      AND NOT fn_est_exclu(s.id, p_etablissement_id);
    RETURN jsonb_build_object('disponibles', v_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_confirmer_paiement_soignant(p_paiement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_uid UUID := auth.uid();
    v_paiement RECORD;
BEGIN
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifié');
    END IF;

    SELECT * INTO v_paiement FROM paiements_soignant WHERE id = p_paiement_id;
    IF v_paiement IS NULL THEN
        RETURN jsonb_build_object('error', 'Paiement introuvable');
    END IF;

    -- Seul le soignant destinataire peut confirmer
    IF v_paiement.soignant_id != v_uid THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    -- Ne pas reconfirmer si déjà confirmé
    IF v_paiement.confirme_par_soignant = TRUE THEN
        RETURN jsonb_build_object('error', 'Paiement déjà confirmé');
    END IF;

    -- Ne pas confirmer un paiement annulé ou contesté
    IF v_paiement.statut NOT IN ('DECLARE', 'EN_ATTENTE') THEN
        RETURN jsonb_build_object('error', 'Ce paiement ne peut plus être confirmé (statut: ' || v_paiement.statut || ')');
    END IF;

    UPDATE paiements_soignant
    SET
        statut = 'CONFIRME',
        confirme_par_soignant = TRUE,
        confirme_par_soignant_le = NOW(),
        modifie_le = NOW()
    WHERE id = p_paiement_id;

    RETURN jsonb_build_object('success', true, 'confirme_le', NOW());
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_confirmer_remboursement_avoir(p_avoir_id uuid, p_reference_virement text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_avoir RECORD;
  v_montant NUMERIC;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis.');
  END IF;
  IF length(trim(COALESCE(p_reference_virement, ''))) < 4 THEN
    RETURN jsonb_build_object('error', 'Référence virement requise (min 4 caractères).');
  END IF;

  SELECT * INTO v_avoir FROM public.factures_honoraires WHERE id = p_avoir_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Avoir introuvable.');
  END IF;
  IF v_avoir.type_document <> 'AVOIR' THEN
    RETURN jsonb_build_object('error', 'Ce document n''est pas un avoir.');
  END IF;
  IF v_avoir.mode_remboursement <> 'VIREMENT_MANUEL' THEN
    RETURN jsonb_build_object('error', 'Mode de remboursement incompatible (attendu : VIREMENT_MANUEL).');
  END IF;
  IF v_avoir.date_remboursement IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Remboursement déjà confirmé.');
  END IF;

  UPDATE public.factures_honoraires
     SET statut = 'REMBOURSE',
         date_remboursement = NOW(),
         reference_remboursement = trim(p_reference_virement)
   WHERE id = p_avoir_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'AVOIR_REMBOURSEMENT_CONFIRME',
    'facture_honoraire', p_avoir_id, NULL,
    jsonb_build_object(
      'numero_avoir', v_avoir.numero_facture,
      'montant_ht', v_avoir.montant_ht,
      'reference_virement', trim(p_reference_virement),
      'mode_remboursement', 'VIREMENT_MANUEL'
    ),
    NULL, NULL
  );

  -- Notifier le soignant (in-app + push + email), comme le chemin SWAN auto
  v_montant := COALESCE(v_avoir.montant_ttc, v_avoir.montant_ht, 0);
  IF v_avoir.soignant_id IS NOT NULL THEN
    PERFORM public.fn_litige_push_notification(
      v_avoir.soignant_id,
      'SOIGNANT',
      'REMBOURSEMENT_CONFIRME',
      'Remboursement effectué',
      'Le remboursement de ' || to_char(v_montant, 'FM999G999D00') || ' € (avoir ' ||
        COALESCE(v_avoir.numero_facture, '') || ') a été effectué par virement. Référence : ' ||
        trim(p_reference_virement) || '.',
      v_avoir.litige_id,
      jsonb_build_object(
        'montant', v_montant,
        'numero_avoir', v_avoir.numero_facture,
        'reference_virement', trim(p_reference_virement)
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'avoir_id', p_avoir_id,
    'statut', 'REMBOURSE',
    'date_remboursement', NOW()
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_compteur_heures_soignant(p_soignant_id uuid)
 RETURNS TABLE(heures_jolene integer, heures_externes_validees integer, heures_externes_en_attente integer, heures_totales integer, eligible_free_transition boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_heures_jolene INTEGER := 0;
  v_heures_ext_val INTEGER := 0;
  v_heures_ext_att INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;
  IF auth.uid() != p_soignant_id AND NOT est_admin() THEN
    RAISE EXCEPTION 'Accès non autorisé';
  END IF;

  SELECT COALESCE(SUM(
    COALESCE(
      (SELECT SUM(pr.heures_reelles)
         FROM public.presences pr
        WHERE pr.mission_id = m.id
          AND pr.heures_reelles IS NOT NULL),
      m.duree_heures_effective,
      m.duree_heures
    )
  )::INTEGER, 0)
  INTO v_heures_jolene
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id AND m.statut = 'TERMINEE';

  SELECT COALESCE(SUM(heures_declarees)::INTEGER, 0)
  INTO v_heures_ext_val
  FROM public.heures_externes_soignants
  WHERE soignant_id = p_soignant_id AND statut_validation = 'VALIDE';

  SELECT COALESCE(SUM(heures_declarees)::INTEGER, 0)
  INTO v_heures_ext_att
  FROM public.heures_externes_soignants
  WHERE soignant_id = p_soignant_id AND statut_validation = 'EN_ATTENTE';

  RETURN QUERY SELECT v_heures_jolene, v_heures_ext_val, v_heures_ext_att,
    v_heures_jolene + v_heures_ext_val, v_heures_jolene >= 3200;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_confirmer_accord_partie(p_litige_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_litige RECORD;
  v_partie TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable'); END IF;

  IF v_litige.statut NOT IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige déjà résolu');
  END IF;

  IF v_etab_id IS NOT NULL AND v_litige.etablissement_id = v_etab_id THEN
    UPDATE litiges SET accord_etablissement = true, accord_etablissement_le = COALESCE(accord_etablissement_le, NOW())
    WHERE id = p_litige_id;
    v_partie := 'ETAB';
  ELSIF v_litige.soignant_id = v_uid THEN
    UPDATE litiges SET accord_soignant = true, accord_soignant_le = COALESCE(accord_soignant_le, NOW())
    WHERE id = p_litige_id;
    v_partie := 'SOIGNANT';
  ELSIF est_admin() THEN
    UPDATE litiges SET
      accord_soignant = true, accord_soignant_le = COALESCE(accord_soignant_le, NOW()),
      accord_etablissement = true, accord_etablissement_le = COALESCE(accord_etablissement_le, NOW())
    WHERE id = p_litige_id;
    v_partie := 'ADMIN';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas partie au litige');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := CASE WHEN v_etab_id IS NOT NULL THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'MEDIATION_ACCORD_PARTIES',
    p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('partie', v_partie)
  );

  IF (SELECT statut FROM litiges WHERE id = p_litige_id) = 'RESOLU_ACCORD_PARTIES' THEN
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES
      (v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
       '✅ Litige résolu par accord mutuel',
       'Vous et l''établissement avez confirmé un accord. Aucune pénalité scoring.',
       '/soignant/litiges'),
      (v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
       '✅ Litige résolu par accord mutuel',
       'Vous et le soignant avez confirmé un accord. Aucune pénalité scoring.',
       '/etablissement/litiges');
  END IF;

  RETURN jsonb_build_object('success', true, 'partie', v_partie);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_confirmer_email_etab(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_expire timestamptz;
  v_rattachement jsonb;
BEGIN
  IF p_token IS NULL OR length(p_token) < 32 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token invalide');
  END IF;

  SELECT id, email_contact_token_expire_le
    INTO v_etab_id, v_expire
  FROM etablissements
  WHERE email_contact_token = p_token;

  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token inconnu ou déjà utilisé');
  END IF;

  IF v_expire < now() THEN
    UPDATE etablissements SET email_contact_token = NULL, email_contact_token_expire_le = NULL
    WHERE id = v_etab_id;
    RETURN jsonb_build_object('success', false, 'error', 'Token expiré. Veuillez renvoyer un e-mail de confirmation.');
  END IF;

  UPDATE etablissements SET
    email_contact_verifie = true,
    email_contact_verifie_le = now(),
    email_contact_token = NULL,
    email_contact_token_expire_le = NULL
  WHERE id = v_etab_id;

  BEGIN
    SELECT fn_evaluer_rattachement_etablissement(v_etab_id) INTO v_rattachement;
  EXCEPTION WHEN OTHERS THEN
    v_rattachement := NULL;
  END;

  RETURN jsonb_build_object('success', true, 'etablissement_id', v_etab_id, 'rattachement', v_rattachement);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_confirmer_presence_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id AND soignant_assigne_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus active.');
  END IF;
  UPDATE missions SET presence_confirmee_le = NOW(), modifie_le = NOW() WHERE id = p_mission_id;
  -- L'établissement est rassuré en temps réel
  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.etablissement_id, 'SYSTEM', 'Présence confirmée ✓',
    'Le soignant a confirmé sa présence pour "' || fn_html_escape(v_m.intitule) || '" du ' ||
    TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') || '.',
    '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');
  RETURN jsonb_build_object('success', TRUE);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_confirmer_honoraires_retrocession(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD; v_mandat boolean; v_facture boolean := false;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id AND soignant_assigne_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.montant_honoraires_bruts IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun relevé à confirmer.');
  END IF;
  IF v_m.honoraires_confirmes_le IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Relevé déjà confirmé.');
  END IF;

  UPDATE missions SET honoraires_confirmes_le = NOW(), modifie_le = NOW() WHERE id = p_mission_id;

  SELECT COALESCE(mandat_facturation_signe, FALSE) INTO v_mandat FROM soignants WHERE id = auth.uid();
  IF v_mandat AND NOT EXISTS (SELECT 1 FROM factures_honoraires WHERE mission_id = p_mission_id) THEN
    PERFORM fn_generer_facture_honoraires_mission(p_mission_id);
    v_facture := true;
  END IF;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.etablissement_id, 'SYSTEM', 'Relevé confirmé par le remplaçant ✓',
    'Le remplaçant a confirmé le relevé de "' || fn_html_escape(v_m.intitule) || '" — rétrocession de ' ||
    v_m.net_a_payer || ' € à régler par virement (à déclarer sur la mission).',
    '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');

  RETURN jsonb_build_object('success', TRUE, 'facture_generee', v_facture);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_consentir_gps(p_accepte boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    UPDATE soignants SET
        consentement_gps = p_accepte,
        consentement_gps_le = NOW(),
        modifie_le = NOW()
    WHERE id = auth.uid();

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'SOIGNANT', 'DONNEES_PERSO_MODIFICATION', 'soignant', auth.uid(),
        jsonb_build_object('consentement_gps', p_accepte));

    RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_contester_presence(p_presence_id uuid, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_presence RECORD;
  v_ip inet;
  v_user_agent text;
  v_headers jsonb;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  IF p_motif IS NULL OR length(trim(p_motif)) < 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Le motif est obligatoire (3 caractères min.)');
  END IF;

  SELECT p.* INTO v_presence
  FROM presences p
  JOIN missions m ON m.id = p.mission_id
  WHERE p.id = p_presence_id
    AND m.etablissement_id = v_etab_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Présence introuvable');
  END IF;

  UPDATE presences
  SET motif_litige = trim(p_motif),
      modifie_le = now()
  WHERE id = p_presence_id;

  -- Audit RGPD (contestation d'un pointage = donnée CDD critique)
  BEGIN
    v_headers := current_setting('request.headers', true)::jsonb;
    v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
    v_user_agent := NULLIF(v_headers->>'user-agent', '');
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL; v_user_agent := NULL;
  END;

  PERFORM fn_ecrire_audit(
    auth.uid(), 'ADMIN_ETABLISSEMENT', 'PRESENCE_CONTESTATION',
    'presence', p_presence_id, NULL,
    jsonb_build_object(
      'mission_id', v_presence.mission_id,
      'soignant_id', v_presence.soignant_id,
      'motif', LEFT(trim(p_motif), 500)
    ),
    v_ip, v_user_agent
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_contester_paiement_soignant(p_paiement_id uuid, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_paiement RECORD;
    v_litige_id UUID;
BEGIN
    SELECT * INTO v_paiement FROM paiements_soignant WHERE id = p_paiement_id;
    IF v_paiement IS NULL THEN RETURN '{"error":"Paiement introuvable"}'::JSONB; END IF;
    IF v_paiement.soignant_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;

    -- Marquer le paiement contesté
    UPDATE paiements_soignant SET
        conteste = TRUE,
        motif_contestation = p_motif,
        statut = 'CONTESTE',
        modifie_le = NOW()
    WHERE id = p_paiement_id;

    -- Créer automatiquement un litige
    INSERT INTO litiges (
        mission_id, soignant_id, etablissement_id, initie_par, motif,
        statut, paiement_soignant_id
    ) VALUES (
        v_paiement.mission_id,
        v_paiement.soignant_id,
        v_paiement.etablissement_id,
        'SOIGNANT',
        'Paiement contesté — ' || p_motif,
        'OUVERT',
        p_paiement_id
    ) RETURNING id INTO v_litige_id;

    -- Notifier l'établissement
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (
        v_paiement.etablissement_id,
        'CONTESTATION_PAIEMENT',
        'Paiement contesté ⚠️',
        'Le soignant conteste un paiement. Motif : ' || p_motif,
        '/etablissement/facturation',
        'ETABLISSEMENT'
    );

    -- Notifier l'admin
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    SELECT id, 'SYSTEM', 'Paiement contesté ⚠️',
        'Un soignant conteste un paiement. Motif : ' || p_motif,
        '/admin/facturation', 'ADMIN'
    FROM auth.users WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
    LIMIT 1;

    RETURN jsonb_build_object('success', true, 'litige_id', v_litige_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_confirmer_virement_admin(p_facture_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_facture RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN json_build_object('error', 'Réservé aux administrateurs');
  END IF;

  SELECT id, statut INTO v_facture FROM factures WHERE id = p_facture_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Facture introuvable');
  END IF;

  IF v_facture.statut != 'VIREMENT_DECLARE' THEN
    RETURN json_build_object('error', 'Cette facture n''est pas en attente de vérification de virement');
  END IF;

  UPDATE factures
     SET statut = 'PAYEE',
         date_paiement = now(),
         virement_confirme_le = now(),
         virement_confirme_par = auth.uid(),
         modifie_le = now()
   WHERE id = p_facture_id;

  RETURN json_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_consulter_rib_soignant(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_partage RECORD;
    v_doc RECORD;
BEGIN
    SELECT * INTO v_partage FROM partages_rib 
    WHERE mission_id = p_mission_id 
    AND (etablissement_id = mon_etablissement_id() OR est_admin())
    AND actif = TRUE;

    IF v_partage IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé. Le partage de RIB n''est pas actif pour cette mission.');
    END IF;

    IF v_partage.document_rib_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Le soignant n''a pas encore uploadé son RIB.', 'rib_manquant', true);
    END IF;

    SELECT id, nom_fichier, s3_cle, s3_bucket INTO v_doc 
    FROM documents_soignants WHERE id = v_partage.document_rib_id;

    -- Logger l'accès (audit RGPD)
    UPDATE partages_rib SET consulte_le = NOW(), consulte_par = auth.uid() WHERE id = v_partage.id;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN_ETABLISSEMENT', 'RIB_CONSULTE', 'document', v_doc.id,
        jsonb_build_object('mission_id', p_mission_id, 'soignant_id', v_partage.soignant_id));

    RETURN jsonb_build_object(
        'success', true,
        'document_id', v_doc.id,
        'nom_fichier', v_doc.nom_fichier,
        's3_cle', v_doc.s3_cle,
        's3_bucket', v_doc.s3_bucket
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_consulter_mon_iban()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_result RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT iban_last4, iban_titulaire, iban_virement IS NOT NULL AS iban_renseigne
  INTO v_result
  FROM soignants WHERE id = v_uid;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('iban_renseigne', false);
  END IF;

  RETURN jsonb_build_object(
    'iban_renseigne', COALESCE(v_result.iban_renseigne, false),
    'iban_last4', v_result.iban_last4,
    'iban_titulaire', v_result.iban_titulaire
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_contacter_support()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_support uuid;
  v_conv uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;
  SELECT id INTO v_support
  FROM auth.users
  WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ORDER BY (email = 'admin@jolene.app') DESC, created_at ASC
  LIMIT 1;
  IF v_support IS NULL THEN
    RAISE EXCEPTION 'Support indisponible pour le moment.';
  END IF;
  IF v_support = v_me THEN
    RAISE EXCEPTION 'Action non applicable pour ce compte.';
  END IF;
  SELECT id INTO v_conv
  FROM conversations
  WHERE (participant_1_id = v_me AND participant_2_id = v_support)
     OR (participant_1_id = v_support AND participant_2_id = v_me)
  LIMIT 1;
  IF v_conv IS NULL THEN
    INSERT INTO conversations (participant_1_id, participant_2_id, mission_id)
    VALUES (v_me, v_support, NULL)
    RETURNING id INTO v_conv;
  END IF;
  RETURN v_conv;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_conflit_planning_soignant(p_soignant_id uuid, p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_conflit RECORD;
  v_adjacent RECORD;
BEGIN
  SELECT debut_le, fin_le INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission.debut_le IS NULL THEN
    RETURN jsonb_build_object('conflit', false);
  END IF;

  SELECT m.intitule, m.debut_le, m.fin_le INTO v_conflit
  FROM missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS')
    AND m.debut_le < v_mission.fin_le
    AND m.fin_le > v_mission.debut_le
  LIMIT 1;

  IF v_conflit.intitule IS NOT NULL THEN
    RETURN jsonb_build_object(
      'conflit', true,
      'mission_conflit', v_conflit.intitule,
      'message', 'Tu es déjà confirmé(e) sur « ' || v_conflit.intitule || ' » du '
        || to_char(v_conflit.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24hMI') || ' au '
        || to_char(v_conflit.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM HH24hMI')
        || ' — ce créneau chevauche cette mission.'
    );
  END IF;

  SELECT m.intitule INTO v_adjacent
  FROM missions m
  WHERE m.soignant_assigne_id = p_soignant_id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS')
    AND (
      (m.fin_le <= v_mission.debut_le AND v_mission.debut_le - m.fin_le < interval '60 minutes')
      OR (v_mission.fin_le <= m.debut_le AND m.debut_le - v_mission.fin_le < interval '60 minutes')
    )
  LIMIT 1;

  IF v_adjacent.intitule IS NOT NULL THEN
    RETURN jsonb_build_object(
      'conflit', false,
      'warning', 'Attention : moins d''1 h de battement avec « ' || v_adjacent.intitule || ' ».'
    );
  END IF;

  RETURN jsonb_build_object('conflit', false);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_mission(p_intitule text, p_description text DEFAULT NULL::text, p_profession_requise type_profession DEFAULT NULL::type_profession, p_service text DEFAULT NULL::text, p_debut_le timestamp with time zone DEFAULT NULL::timestamp with time zone, p_fin_le timestamp with time zone DEFAULT NULL::timestamp with time zone, p_taux_horaire_base numeric DEFAULT NULL::numeric, p_est_urgente boolean DEFAULT false, p_niveau_urgence integer DEFAULT 0, p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'::text, p_specialite_medicale_requise text DEFAULT NULL::text, p_accepte_non_specialises boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID;
    v_blocage JSONB;
    v_mission_id UUID;
    v_mode TEXT;
BEGIN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN '{"error":"Acces refuse"}'::JSONB;
    END IF;

    v_blocage := fn_blocage_publication_etab(v_etab_id);
    IF v_blocage IS NOT NULL THEN
        RETURN v_blocage;
    END IF;

    IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_debut_le IS NULL OR p_fin_le IS NULL OR p_taux_horaire_base IS NULL THEN
        RETURN '{"error":"Champs obligatoires manquants."}'::JSONB;
    END IF;
    IF p_fin_le <= p_debut_le THEN
        RETURN '{"error":"La fin doit etre apres le debut."}'::JSONB;
    END IF;
    IF p_debut_le < NOW() AND NOT est_admin() THEN
        RETURN '{"error":"La mission ne peut pas commencer dans le passe."}'::JSONB;
    END IF;

    v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
    IF v_mode NOT IN ('PREMIER_ARRIVE', 'CANDIDATURE') THEN
        v_mode := 'PREMIER_ARRIVE';
    END IF;

    PERFORM set_config('jolene.creer_mission_context', 'true', true);

    INSERT INTO missions (
        etablissement_id, intitule, description,
        profession_requise, service, debut_le, fin_le,
        taux_horaire_base, est_urgente, niveau_urgence, mode_attribution,
        specialite_medicale_requise, accepte_non_specialises
    ) VALUES (
        v_etab_id, p_intitule, p_description,
        p_profession_requise, p_service, p_debut_le, p_fin_le,
        p_taux_horaire_base, p_est_urgente,
        CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END,
        v_mode,
        p_specialite_medicale_requise, p_accepte_non_specialises
    ) RETURNING id INTO v_mission_id;

    RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_bulletin_paie(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_mission RECORD;
  v_soignant RECORD;
  v_cot RECORD;
  v_bulletin_id uuid;
  v_numero text;
  v_existing uuid;
  v_type_exercice text;
BEGIN
  SELECT m.id, m.soignant_assigne_id, m.etablissement_id, m.statut, m.debut_le, m.fin_le, m.duree_heures, m.taux_horaire_base
  INTO v_mission
  FROM missions m WHERE m.id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;
  IF v_mission.soignant_assigne_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun soignant assigné');
  END IF;
  IF v_mission.statut <> 'TERMINEE' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission non terminée');
  END IF;

  -- Vérifier idempotence : déjà émis pour cette mission ?
  SELECT id INTO v_existing FROM bulletins_paie WHERE mission_id = p_mission_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'bulletin_id', v_existing, 'already_existed', true);
  END IF;

  -- Vérifier que le soignant est SALARIE ou MIXTE (pas LIBERAL pur)
  SELECT id, type_exercice INTO v_soignant
  FROM soignants WHERE id = v_mission.soignant_assigne_id;
  v_type_exercice := COALESCE(v_soignant.type_exercice, 'SALARIE');
  IF v_type_exercice = 'LIBERAL' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Bulletin de paie non applicable : le soignant est LIBERAL (la rémunération passe par facture honoraires)');
  END IF;

  -- S'assurer que les cotisations sont calculées
  SELECT * INTO v_cot FROM cotisations_sociales WHERE mission_id = p_mission_id;
  IF v_cot IS NULL THEN
    PERFORM public.fn_calculer_cotisations(p_mission_id);
    SELECT * INTO v_cot FROM cotisations_sociales WHERE mission_id = p_mission_id;
    IF v_cot IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Calcul cotisations échoué');
    END IF;
  END IF;

  -- Si le calcul a renvoyé type CDD mais soignant marqué MIXTE/SALARIE :
  -- on continue (CDD est le type de contrat applicable côté Jolene).
  IF v_cot.type_contrat = 'REMPLACEMENT_LIBERAL' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Mission classée libéral : pas de bulletin (facture honoraires uniquement)');
  END IF;

  v_numero := public.fn_next_bulletin_paie_number(v_mission.soignant_assigne_id);

  INSERT INTO bulletins_paie (
    numero_bulletin, soignant_id, mission_id, etablissement_id,
    periode_debut, periode_fin,
    salaire_brut, total_cotisations_salariales, total_cotisations_patronales,
    net_avant_impot, ifm, icp,
    statut, date_emission
  ) VALUES (
    v_numero, v_mission.soignant_assigne_id, p_mission_id, v_mission.etablissement_id,
    v_mission.debut_le::date, v_mission.fin_le::date,
    v_cot.salaire_brut, v_cot.total_cotisations_salariales, v_cot.total_cotisations_patronales,
    v_cot.net_avant_impot, COALESCE(v_cot.ifm, 0), COALESCE(v_cot.icp, 0),
    'EMIS', CURRENT_DATE
  )
  RETURNING id INTO v_bulletin_id;

  -- Audit
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_mission.soignant_assigne_id,
    p_type_acteur := 'SOIGNANT',
    p_action := 'BULLETIN_PAIE_EMIS',
    p_type_ressource := 'bulletin_paie',
    p_id_ressource := v_bulletin_id,
    p_details := jsonb_build_object(
      'numero_bulletin', v_numero,
      'mission_id', p_mission_id,
      'salaire_brut', v_cot.salaire_brut,
      'net_avant_impot', v_cot.net_avant_impot
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'bulletin_id', v_bulletin_id,
    'numero_bulletin', v_numero,
    'salaire_brut', v_cot.salaire_brut,
    'net_avant_impot', v_cot.net_avant_impot
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_filtre_sauvegarde(p_nom text, p_audience filtre_audience, p_filtres jsonb, p_alerte_active boolean DEFAULT false, p_frequence_alerte filtre_frequence_alerte DEFAULT 'QUOTIDIENNE'::filtre_frequence_alerte)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  IF length(p_nom) = 0 OR length(p_nom) > 100 THEN
    RETURN jsonb_build_object('error','Nom invalide (1-100 caractères)');
  END IF;

  -- Limite : 20 filtres max par utilisateur
  SELECT count(*) INTO v_count FROM filtres_sauvegardes WHERE utilisateur_id = v_uid;
  IF v_count >= 20 THEN
    RETURN jsonb_build_object('error', 'Limite de 20 recherches sauvegardées atteinte. Supprimez-en une avant d''en créer une nouvelle.');
  END IF;

  INSERT INTO filtres_sauvegardes (utilisateur_id, nom, audience, filtres, alerte_active, frequence_alerte)
  VALUES (v_uid, p_nom, p_audience, COALESCE(p_filtres, '{}'::jsonb), p_alerte_active, p_frequence_alerte)
  RETURNING id INTO v_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_CREE', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := v_id,
    p_details := jsonb_build_object('nom', p_nom, 'audience', p_audience::text, 'alerte_active', p_alerte_active, 'frequence', p_frequence_alerte::text)
  );

  IF p_alerte_active THEN
    PERFORM fn_ecrire_audit_safe(
      p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
      p_action := 'ALERTE_ACTIVEE', p_type_ressource := 'filtre_sauvegarde',
      p_id_ressource := v_id,
      p_details := jsonb_build_object('frequence', p_frequence_alerte::text)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Un filtre avec ce nom existe déjà');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_notation_mission(p_mission_id uuid, p_sens text, p_critere_1 integer, p_critere_2 integer, p_critere_3 integer, p_critere_4 integer, p_commentaire text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_mission RECORD;
  v_sens public.sens_notation;
  v_notateur_id UUID;
  v_note_id UUID;
  v_id UUID;
  v_tardive BOOLEAN := false;
  v_litige_actif_count INT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  BEGIN v_sens := UPPER(TRIM(p_sens))::public.sens_notation;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Sens invalide');
  END;

  IF p_critere_1 NOT BETWEEN 1 AND 5 OR p_critere_2 NOT BETWEEN 1 AND 5
     OR p_critere_3 NOT BETWEEN 1 AND 5 OR p_critere_4 NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Critères doivent être entre 1 et 5');
  END IF;

  IF p_commentaire IS NOT NULL AND LENGTH(p_commentaire) > 2000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Commentaire max 2000 caractères');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut, fin_le INTO v_mission
  FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  -- 7b-C : TERMINEE, ou EN_COURS avec départ pointé (check-out fait, le cron
  -- de transition n'est simplement pas encore passé).
  IF v_mission.statut <> 'TERMINEE'
     AND NOT (v_mission.statut = 'EN_COURS' AND EXISTS (
       SELECT 1 FROM presences pr
       WHERE pr.mission_id = p_mission_id AND pr.pointage_depart_le IS NOT NULL
     ))
     AND NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seules les missions TERMINEE peuvent être notées');
  END IF;

  -- Itération 1 fix B.8 : bloquer notation pendant litige actif (médiation/arbitrage)
  IF NOT est_admin() THEN
    SELECT COUNT(*) INTO v_litige_actif_count FROM litiges
    WHERE mission_id = p_mission_id
      AND statut IN ('MEDIATION_EN_COURS', 'REVUE_ADMIN');
    IF v_litige_actif_count > 0 THEN
      RETURN jsonb_build_object('success', false,
        'error', 'Notation impossible pendant un litige en médiation ou en revue admin. Vous pourrez noter après résolution.');
    END IF;
  END IF;

  IF v_sens = 'ETAB_VERS_SOIGNANT' THEN
    IF NOT est_admin() AND v_mission.etablissement_id <> v_etab_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas l''établissement de cette mission');
    END IF;
    IF v_mission.soignant_assigne_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'Mission sans soignant assigné');
    END IF;
    v_notateur_id := COALESCE(v_etab_id, v_mission.etablissement_id);
    v_note_id := v_mission.soignant_assigne_id;
  ELSE
    IF NOT est_admin() AND v_mission.soignant_assigne_id <> v_uid THEN
      RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas le soignant de cette mission');
    END IF;
    v_notateur_id := v_uid;
    v_note_id := v_mission.etablissement_id;
  END IF;

  IF v_mission.fin_le < NOW() - INTERVAL '30 days' THEN
    v_tardive := true;
  END IF;

  INSERT INTO notations_missions (
    mission_id, notateur_id, note_id, sens,
    critere_1, critere_2, critere_3, critere_4, commentaire
  ) VALUES (
    p_mission_id, v_notateur_id, v_note_id, v_sens,
    p_critere_1, p_critere_2, p_critere_3, p_critere_4, NULLIF(TRIM(p_commentaire), '')
  )
  ON CONFLICT (mission_id, sens) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission déjà notée pour ce sens');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_notateur_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'NOTATION_DONNEE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text, 'note_id', v_note_id, 'tardive', v_tardive)
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_note_id,
    p_type_acteur := CASE WHEN v_sens = 'ETAB_VERS_SOIGNANT' THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'NOTATION_RECUE',
    p_type_ressource := 'mission',
    p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('notation_id', v_id, 'sens', v_sens::text)
  );

  RETURN jsonb_build_object('success', true, 'id', v_id, 'tardive', v_tardive);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_api_key(p_nom text, p_permissions text[], p_etablissement_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_is_admin boolean;
  v_etab_id uuid;
  v_cle_api text;
  v_cle_secret text;
  v_id uuid;
  v_actor_type text;
BEGIN
  IF v_actor IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  v_is_admin := est_admin();

  -- Détermination du scope
  IF v_is_admin THEN
    v_etab_id := p_etablissement_id; -- NULL = clé admin globale
    v_actor_type := 'ADMIN_PLATEFORME';
  ELSE
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    -- Étab ne peut créer de clé que pour lui-même
    IF p_etablissement_id IS NOT NULL AND p_etablissement_id <> v_etab_id THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    v_actor_type := 'ADMIN_ETABLISSEMENT';
  END IF;

  IF p_nom IS NULL OR length(trim(p_nom)) = 0 THEN
    RETURN jsonb_build_object('error', 'Nom requis');
  END IF;

  IF p_permissions IS NULL OR array_length(p_permissions, 1) IS NULL THEN
    RETURN jsonb_build_object('error', 'Au moins une permission requise');
  END IF;

  -- Génération côté serveur (cryptographique, qualifié extensions)
  v_cle_api := 'sd_live_' || replace(extensions.gen_random_uuid()::text, '-', '');
  v_cle_secret := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.api_keys (nom, cle_api, cle_secret, cle_secret_hash, permissions, etablissement_id, actif)
  VALUES (
    trim(p_nom),
    v_cle_api,
    v_cle_secret, -- legacy (sera nullé en cleanup futur)
    public._sha256_hex(v_cle_secret),
    p_permissions,
    v_etab_id,
    true
  )
  RETURNING id INTO v_id;

  -- Audit
  PERFORM fn_ecrire_audit_safe(
    v_actor, v_actor_type,
    'API_KEY_CREEE', 'api_key', v_id,
    NULL,
    jsonb_build_object('nom', trim(p_nom), 'permissions', p_permissions, 'etablissement_id', v_etab_id),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'id', v_id,
    'cle_api', v_cle_api,
    'cle_secret', v_cle_secret -- retourné UNE SEULE FOIS
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_contrat_storage_path(p_contrat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_cm RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT storage_path, hash_document, contenu_html_rendu_le,
         soignant_id, etablissement_id
  INTO v_cm
  FROM public.contrats_mission WHERE id = p_contrat_id;

  IF v_cm IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin()
          OR v_cm.soignant_id = v_uid
          OR v_cm.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'storage_path', v_cm.storage_path,
    'hash_document', v_cm.hash_document,
    'rendu_le', v_cm.contenu_html_rendu_le
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_conversation_si_absente(p_mission_id uuid, p_soignant_id uuid, p_etablissement_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_etab_id uuid;
  v_conv_id uuid;
BEGIN
  SELECT user_id INTO v_user_etab_id
  FROM membres_etablissement
  WHERE etablissement_id = p_etablissement_id
    AND role = 'PROPRIETAIRE'
    AND actif = true
  ORDER BY accepte_le ASC
  LIMIT 1;

  IF v_user_etab_id IS NULL THEN
    INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'conversations', NULL,
            jsonb_build_object(
              'evenement', 'MESSAGERIE_CREATION_CONVERSATION_ECHEC',
              'raison', 'proprietaire_etab_introuvable',
              'mission_id', p_mission_id,
              'soignant_id', p_soignant_id,
              'etablissement_id', p_etablissement_id
            ));
    RETURN NULL;
  END IF;

  SELECT id INTO v_conv_id
  FROM conversations
  WHERE mission_id = p_mission_id
    AND (
      (participant_1_id = p_soignant_id AND participant_2_id = v_user_etab_id)
      OR (participant_1_id = v_user_etab_id AND participant_2_id = p_soignant_id)
    )
  LIMIT 1;

  IF v_conv_id IS NOT NULL THEN
    RETURN v_conv_id;
  END IF;

  INSERT INTO conversations(mission_id, participant_1_id, participant_2_id, cree_le, dernier_message_le)
  VALUES (p_mission_id, p_soignant_id, v_user_etab_id, NOW(), NOW())
  RETURNING id INTO v_conv_id;

  INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (p_soignant_id, 'SYSTEME', 'SYSTEM', 'conversations', v_conv_id,
          jsonb_build_object(
            'evenement', 'MESSAGERIE_CONVERSATION_OUVERTE',
            'origine', 'TRIGGER_ACCEPTATION_CANDIDATURE',
            'mission_id', p_mission_id,
            'soignant_id', p_soignant_id,
            'etablissement_id', p_etablissement_id,
            'user_etab_id', v_user_etab_id
          ));

  RETURN v_conv_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_mission_multi_jours(p_intitule text, p_description text DEFAULT NULL::text, p_profession_requise type_profession DEFAULT NULL::type_profession, p_service text DEFAULT NULL::text, p_taux_horaire_base numeric DEFAULT NULL::numeric, p_est_urgente boolean DEFAULT false, p_niveau_urgence integer DEFAULT 0, p_mode_attribution text DEFAULT 'PREMIER_ARRIVE'::text, p_specialite_medicale_requise text DEFAULT NULL::text, p_accepte_non_specialises boolean DEFAULT true, p_creneaux jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid;
  v_blocage jsonb;
  v_mission_id uuid;
  v_mode text;
  v_nb int;
  v_min timestamptz;
  v_max timestamptz;
  v_c jsonb;
  v_ordre int := 0;
  v_cd timestamptz;
  v_cf timestamptz;
BEGIN
  v_etab_id := mon_etablissement_id();
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN '{"error":"Acces refuse"}'::jsonb;
  END IF;

  v_blocage := fn_blocage_publication_etab(v_etab_id);
  IF v_blocage IS NOT NULL THEN RETURN v_blocage; END IF;

  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN '{"error":"Champs obligatoires manquants."}'::jsonb;
  END IF;

  v_nb := COALESCE(jsonb_array_length(p_creneaux), 0);
  IF v_nb = 0 THEN RETURN '{"error":"Aucun jour fourni."}'::jsonb; END IF;
  IF v_nb > 366 THEN RETURN '{"error":"Maximum 366 jours par mission."}'::jsonb; END IF;

  -- Validation de chaque jour (fin > début) + enveloppe globale
  FOR v_c IN SELECT * FROM jsonb_array_elements(p_creneaux) LOOP
    v_cd := (v_c->>'debut')::timestamptz;
    v_cf := (v_c->>'fin')::timestamptz;
    IF v_cd IS NULL OR v_cf IS NULL OR v_cf <= v_cd THEN
      RETURN '{"error":"Chaque jour doit avoir une fin après le début."}'::jsonb;
    END IF;
  END LOOP;

  SELECT MIN((c->>'debut')::timestamptz), MAX((c->>'fin')::timestamptz)
  INTO v_min, v_max
  FROM jsonb_array_elements(p_creneaux) c;

  IF v_min < NOW() AND NOT est_admin() THEN
    RETURN '{"error":"La mission ne peut pas commencer dans le passe."}'::jsonb;
  END IF;

  v_mode := COALESCE(p_mode_attribution, 'PREMIER_ARRIVE');
  IF v_mode NOT IN ('PREMIER_ARRIVE','CANDIDATURE') THEN v_mode := 'PREMIER_ARRIVE'; END IF;

  PERFORM set_config('jolene.creer_mission_context','true', true);

  -- (a) UNE mission, span = enveloppe (1er jour → dernier jour)
  INSERT INTO missions (
    etablissement_id, intitule, description, profession_requise, service,
    debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence, mode_attribution,
    specialite_medicale_requise, accepte_non_specialises
  ) VALUES (
    v_etab_id, p_intitule, p_description, p_profession_requise, p_service,
    v_min, v_max, p_taux_horaire_base, p_est_urgente,
    CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END, v_mode,
    p_specialite_medicale_requise, p_accepte_non_specialises
  ) RETURNING id INTO v_mission_id;

  -- (b) N créneaux PREVISIONNEL (sync suspendue → un seul re-sync ensuite, perf)
  PERFORM set_config('jolene.sync_in_progress','true', true);
  v_ordre := 0;
  FOR v_c IN SELECT * FROM jsonb_array_elements(p_creneaux) LOOP
    v_ordre := v_ordre + 1;
    INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre, type_creneau)
    VALUES (v_mission_id, (v_c->>'debut')::timestamptz, (v_c->>'fin')::timestamptz, false, v_ordre, 'PREVISIONNEL');
  END LOOP;
  PERFORM set_config('jolene.sync_in_progress','false', true);

  -- (c) Re-sync unique : enveloppe + nb_creneaux ; le trigger financier recalcule
  --     duree_heures depuis les créneaux (somme des jours).
  UPDATE missions SET debut_le = v_min, fin_le = v_max, nb_creneaux = v_nb
  WHERE id = v_mission_id;

  RETURN jsonb_build_object('success', true, 'mission_id', v_mission_id, 'nb_creneaux', v_nb);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_notification(p_destinataire_id uuid, p_type_destinataire text, p_type text, p_titre text, p_corps text, p_lien text DEFAULT NULL::text, p_type_ressource text DEFAULT NULL::text, p_id_ressource uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_id uuid;
BEGIN
    -- Sécurité : appelant authentifié OU contexte cron/service/admin (auth.uid() IS NULL).
    -- anon n'a PAS le GRANT EXECUTE → ce garde ne bloque que des appelants de confiance.
    -- Avant ce fix, le strict « auth.uid() IS NULL → refus » cassait tous les crons
    -- (relance-candidatures-en-attente notamment) qui s'exécutent sans session.
    IF auth.uid() IS NULL AND NOT fn_est_contexte_cron_ou_admin() THEN
      RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
    END IF;

    INSERT INTO public.notifications (
        destinataire_id, type_destinataire, type,
        titre, corps, lien, type_ressource, id_ressource
    ) VALUES (
        p_destinataire_id, p_type_destinataire, p_type,
        p_titre, p_corps, p_lien, p_type_ressource, p_id_ressource
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_serie(p_intitule text, p_description text DEFAULT NULL::text, p_profession_requise type_profession DEFAULT NULL::type_profession, p_service text DEFAULT NULL::text, p_taux_horaire_base numeric DEFAULT NULL::numeric, p_est_urgente boolean DEFAULT false, p_niveau_urgence integer DEFAULT 0, p_missions jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etablissement_id uuid;
  v_blocage jsonb;
  v_count integer;
  v_mission jsonb;
  v_created_ids uuid[] := '{}';
  v_mission_id uuid;
BEGIN
  v_etablissement_id := mon_etablissement_id();
  IF v_etablissement_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement non trouvé.');
  END IF;

  v_blocage := fn_blocage_publication_etab(v_etablissement_id);
  IF v_blocage IS NOT NULL THEN
    RETURN (v_blocage - 'error') || jsonb_build_object('success', false, 'error', v_blocage->>'error');
  END IF;

  IF p_intitule IS NULL OR p_profession_requise IS NULL OR p_taux_horaire_base IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Champs obligatoires manquants.');
  END IF;

  v_count := jsonb_array_length(p_missions);
  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucun créneau fourni.');
  END IF;
  IF v_count > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Maximum 30 créneaux par série.');
  END IF;

  FOR v_mission IN SELECT * FROM jsonb_array_elements(p_missions)
  LOOP
    INSERT INTO missions (
      etablissement_id, intitule, description, profession_requise, service,
      debut_le, fin_le, taux_horaire_base, est_urgente, niveau_urgence
    ) VALUES (
      v_etablissement_id,
      p_intitule,
      p_description,
      p_profession_requise,
      p_service,
      (v_mission->>'debut')::timestamptz,
      (v_mission->>'fin')::timestamptz,
      p_taux_horaire_base,
      p_est_urgente,
      CASE WHEN p_est_urgente THEN p_niveau_urgence ELSE 0 END
    )
    RETURNING id INTO v_mission_id;
    v_created_ids := v_created_ids || v_mission_id;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count, 'mission_ids', to_jsonb(v_created_ids));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_dashboard_soignant_complet()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_now TIMESTAMPTZ := NOW();
  v_lundi DATE;
  v_dimanche DATE;
  v_debut_mois DATE;
  v_fin_mois DATE;
  v_six_mois_ago DATE;
  v_profession type_profession;
  v_specialite text;
  v_result JSONB;
BEGIN
  v_lundi := date_trunc('week', v_now)::DATE;
  v_dimanche := v_lundi + 7;
  v_debut_mois := date_trunc('month', v_now)::DATE;
  v_fin_mois := (date_trunc('month', v_now) + INTERVAL '1 month' - INTERVAL '1 second')::DATE;
  v_six_mois_ago := date_trunc('month', v_now - INTERVAL '5 months')::DATE;

  SELECT profession, specialite_medicale INTO v_profession, v_specialite FROM soignants WHERE id = v_uid;

  SELECT jsonb_build_object(
    'profil', (
      SELECT row_to_json(s)::jsonb FROM (
        SELECT prenom, nom, telephone, date_naissance, profession, type_contrat,
          numero_rpps, numero_adeli, rpps_verifie, adresse_lat, adresse_lng,
          tous_documents_valides, identite_verifiee, score_fiabilite,
          total_missions_terminees, heures_cumulees, eligible_conversion_3200h,
          type_exercice, mandat_facturation_signe
        FROM soignants WHERE id = v_uid
      ) s
    ),
    'missions_ouvertes', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb) FROM (
        SELECT m.id, m.intitule, m.service, m.debut_le, m.fin_le, m.taux_horaire_base,
          m.est_urgente, m.etablissement_id, m.profession_requise,
          m.accepte_non_specialises, m.specialite_medicale_requise,
          e.nom AS etab_nom
        FROM missions m
        LEFT JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.statut = 'OUVERTE'
          AND (
            v_profession IS NULL
            OR fn_soignant_compatible_mission(
                 v_profession, v_specialite,
                 m.profession_requise, m.specialite_medicale_requise,
                 m.accepte_non_specialises
               )
          )
        ORDER BY m.debut_le LIMIT 3
      ) m
    ),
    'mes_missions', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb) FROM (
        SELECT m.id, m.intitule, m.debut_le, m.fin_le, m.statut, m.etablissement_id,
          e.nom AS etab_nom
        FROM missions m
        LEFT JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.soignant_assigne_id = v_uid AND m.statut IN ('ASSIGNEE', 'EN_COURS')
        ORDER BY m.debut_le LIMIT 3
      ) m
    ),
    'documents', (
      SELECT COALESCE(jsonb_agg(row_to_json(d)::jsonb), '[]'::jsonb) FROM (
        SELECT id, type_document, valide_jusqua, statut_verification
        FROM documents_soignants WHERE soignant_id = v_uid AND supprime_le IS NULL
      ) d
    ),
    'heures_semaine', (
      SELECT COALESCE(SUM(duree_heures), 0) FROM missions
      WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
        AND debut_le >= v_lundi AND debut_le < v_dimanche
    ),
    'gains_mois', (
      SELECT jsonb_build_object(
        'net_total', COALESCE(SUM(COALESCE(net_a_payer, net_estime, total_brut)), 0),
        'brut_total', COALESCE(SUM(total_brut), 0),
        'nb_missions', COUNT(*)
      ) FROM missions
      WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE'
        AND debut_le >= v_debut_mois AND debut_le <= v_fin_mois
    ),
    'gains_6mois', (
      SELECT COALESCE(jsonb_agg(row_to_json(g)::jsonb ORDER BY g.mois), '[]'::jsonb) FROM (
        SELECT TO_CHAR(debut_le, 'YYYY-MM') AS mois,
          ROUND(COALESCE(SUM(net_a_payer), 0)::NUMERIC, 2) AS net
        FROM missions
        WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE' AND debut_le >= v_six_mois_ago
        GROUP BY TO_CHAR(debut_le, 'YYYY-MM')
      ) g
    ),
    'missions_semaine_cal', (
      SELECT COALESCE(jsonb_agg(row_to_json(m)::jsonb), '[]'::jsonb) FROM (
        SELECT debut_le, statut FROM missions
        WHERE soignant_assigne_id = v_uid AND statut IN ('ASSIGNEE', 'EN_COURS')
          AND debut_le >= v_lundi AND debut_le < v_dimanche
      ) m
    ),
    'propositions', (
      SELECT COALESCE(jsonb_agg(row_to_json(p)::jsonb), '[]'::jsonb) FROM (
        SELECT c.id, c.mission_id, c.cree_le,
          m.intitule, m.debut_le, m.fin_le, m.taux_horaire_base, m.etablissement_id, m.est_urgente,
          e.nom AS etab_nom
        FROM candidatures c
        JOIN missions m ON m.id = c.mission_id
        LEFT JOIN etablissements e ON e.id = m.etablissement_id
        WHERE c.soignant_id = v_uid AND c.statut = 'PROPOSEE'
        ORDER BY c.cree_le DESC LIMIT 5
      ) p
    ),
    'heures_totales_terminees', (
      SELECT COALESCE(SUM(duree_heures), 0) FROM missions
      WHERE soignant_assigne_id = v_uid AND statut = 'TERMINEE'
    ),
    'missions_oubliees_count', (
      SELECT COUNT(*) FROM missions m
      WHERE m.soignant_assigne_id = v_uid AND m.statut = 'EN_COURS'
        AND m.fin_le < (v_now - INTERVAL '30 minutes')
        AND NOT EXISTS (SELECT 1 FROM presences p WHERE p.mission_id = m.id AND p.pointage_arrivee_le IS NOT NULL)
    ),
    'notifs_non_lues', (
      SELECT COUNT(*) FROM notifications WHERE destinataire_id = v_uid AND lue = FALSE
    )
  ) INTO v_result;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_cumul_annuel_paie(p_soignant_id uuid, p_annee integer DEFAULT NULL::integer, p_jusqu_au date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH params AS (
    SELECT
      COALESCE(p_annee, EXTRACT(YEAR FROM COALESCE(p_jusqu_au, CURRENT_DATE))::int) AS annee,
      COALESCE(p_jusqu_au, CURRENT_DATE) AS jusqu_au
  )
  SELECT jsonb_build_object(
    'annee', (SELECT annee FROM params),
    'jusqu_au', (SELECT jusqu_au FROM params),
    'nombre_bulletins', COALESCE(COUNT(bp.id), 0),
    'cumul_brut', COALESCE(SUM(bp.salaire_brut), 0),
    'cumul_cotisations_salariales', COALESCE(SUM(bp.total_cotisations_salariales), 0),
    'cumul_cotisations_patronales', COALESCE(SUM(bp.total_cotisations_patronales), 0),
    'cumul_net_avant_impot', COALESCE(SUM(bp.net_avant_impot), 0),
    'cumul_ifm', COALESCE(SUM(bp.ifm), 0),
    'cumul_icp', COALESCE(SUM(bp.icp), 0)
  )
  FROM bulletins_paie bp, params
  WHERE bp.soignant_id = p_soignant_id
    AND EXTRACT(YEAR FROM bp.periode_debut) = params.annee
    AND bp.periode_debut <= params.jusqu_au
    AND bp.statut <> 'ANNULE'
    AND (
      bp.soignant_id = auth.uid()
      OR public.est_admin()
    );
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_cumul_factures_mission(p_mission_id uuid, p_jusqu_au date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_cumul_ht numeric;
  v_cumul_ttc numeric;
  v_nb_factures integer;
BEGIN
  SELECT
    COALESCE(SUM(montant_ht), 0),
    COALESCE(SUM(montant_ttc), 0),
    COUNT(*)
  INTO v_cumul_ht, v_cumul_ttc, v_nb_factures
  FROM factures_honoraires
  WHERE mission_id = p_mission_id
    AND statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION','EN_GENERATION')
    AND type_document = 'FACTURE'
    AND (p_jusqu_au IS NULL OR periode_fin <= p_jusqu_au);

  RETURN jsonb_build_object(
    'mission_id', p_mission_id,
    'jusqu_au', p_jusqu_au,
    'cumul_ht', v_cumul_ht,
    'cumul_ttc', v_cumul_ttc,
    'nb_factures', v_nb_factures
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_dans_fenetre_retractation(p_candidature_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_acceptee_a timestamptz;
BEGIN
  SELECT acceptee_a INTO v_acceptee_a FROM public.candidatures WHERE id = p_candidature_id;
  IF v_acceptee_a IS NULL THEN RETURN false; END IF;
  RETURN NOW() - v_acceptee_a < INTERVAL '30 minutes';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_creer_reclamation_score(p_evenement_id uuid, p_evenement_type text, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_event RECORD;
  v_proprio_id uuid;
  v_reclamation_id uuid;
  v_existante RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_evenement_type NOT IN ('SOIGNANT', 'ETAB') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TYPE_INVALIDE',
                                'error', 'evenement_type doit être SOIGNANT ou ETAB');
  END IF;

  IF p_motif_categorie NOT IN ('URGENCE_MEDICALE','DEUIL','FORCE_MAJEURE',
                                'ERREUR_JOLENE','CONTEXTE_PARTICULIER','AUTRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif catégorie invalide');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 20 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 20 caractères)');
  END IF;

  -- Charger l'événement + check propriété + contestable
  IF p_evenement_type = 'SOIGNANT' THEN
    SELECT id, soignant_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_soignant WHERE id = p_evenement_id;
    v_proprio_id := v_event.soignant_id;
  ELSE
    SELECT id, etablissement_id AS proprio_id, contestable, decision_admin, reclamation_id
    INTO v_event FROM public.evenements_score_etab WHERE id = p_evenement_id;
    v_proprio_id := v_event.proprio_id;
  END IF;

  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EVENT_INTROUVABLE',
                                'error', 'Événement de score introuvable');
  END IF;

  -- Auth : seul le propriétaire peut réclamer
  IF p_evenement_type = 'SOIGNANT' AND v_proprio_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;
  IF p_evenement_type = 'ETAB' AND v_proprio_id != mon_etablissement_id() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas concerné par cet événement');
  END IF;

  IF NOT v_event.contestable THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_CONTESTABLE',
                                'error', 'Cet événement n''est pas contestable');
  END IF;

  IF v_event.decision_admin IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_TRAITE',
                                'error', 'Cet événement a déjà été traité par un admin');
  END IF;

  IF v_event.reclamation_id IS NOT NULL THEN
    SELECT id, statut INTO v_existante FROM public.reclamations_score WHERE id = v_event.reclamation_id;
    IF v_existante.statut = 'PENDING' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'RECLAMATION_EN_COURS',
                                  'error', 'Une réclamation est déjà ouverte pour cet événement',
                                  'reclamation_id', v_existante.id);
    END IF;
  END IF;

  -- Créer la réclamation
  INSERT INTO public.reclamations_score (
    evenement_type, evenement_soignant_id, evenement_etab_id,
    contesteur_id, motif_categorie, texte_libre, justificatif_storage_path
  ) VALUES (
    p_evenement_type,
    CASE WHEN p_evenement_type = 'SOIGNANT' THEN p_evenement_id ELSE NULL END,
    CASE WHEN p_evenement_type = 'ETAB' THEN p_evenement_id ELSE NULL END,
    v_uid, p_motif_categorie, trim(p_texte_libre), p_justificatif_storage_path
  ) RETURNING id INTO v_reclamation_id;

  -- Lier l'event à la réclamation
  IF p_evenement_type = 'SOIGNANT' THEN
    UPDATE public.evenements_score_soignant SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  ELSE
    UPDATE public.evenements_score_etab SET reclamation_id = v_reclamation_id WHERE id = p_evenement_id;
  END IF;

  -- Notification admin via externalisation
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('EMAIL_NOTIF', jsonb_build_object(
    'destinataire_role', 'ADMIN',
    'type', 'RECLAMATION_SCORE_NOUVELLE',
    'data', jsonb_build_object(
      'reclamation_id', v_reclamation_id,
      'evenement_type', p_evenement_type,
      'motif_categorie', p_motif_categorie,
      'contesteur_id', v_uid
    )
  ), 'AUTRE', v_reclamation_id);

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'reclamation_score', v_reclamation_id,
    jsonb_build_object('evenement', 'RECLAMATION_SCORE_CREEE',
                        'event_score_id', p_evenement_id,
                        'event_type', p_evenement_type,
                        'motif_categorie', p_motif_categorie,
                        'justificatif', p_justificatif_storage_path IS NOT NULL)
  );

  RETURN jsonb_build_object('success', true, 'reclamation_id', v_reclamation_id, 'statut', 'PENDING');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_declarer_arret_maladie(p_mission_id uuid, p_message text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD; v_nb int := 0;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id AND soignant_assigne_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus active.');
  END IF;
  IF v_m.est_arret_maladie THEN
    RETURN jsonb_build_object('error', 'Arrêt maladie déjà déclaré sur cette mission.');
  END IF;

  UPDATE missions SET est_arret_maladie = TRUE, arret_maladie_declare_le = NOW(), modifie_le = NOW()
   WHERE id = p_mission_id;

  -- Étab = employeur (CDDU) : notification + checklist des obligations CPAM
  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.etablissement_id, 'SYSTEM', 'Arrêt maladie déclaré 🏥 — vos 3 démarches employeur',
    'Le soignant assigné à "' || fn_html_escape(v_m.intitule) || '" déclare un arrêt maladie' ||
    CASE WHEN p_message IS NOT NULL THEN ' : « ' || fn_html_escape(p_message) || ' »' ELSE '.' END ||
    ' En tant qu''employeur (CDDU) : 1) réceptionnez le volet 3 de l''arrêt sous 48h ; ' ||
    '2) transmettez l''attestation de salaire à la CPAM sous 5 jours (net-entreprises.fr) pour déclencher ses IJSS ; ' ||
    '3) si le CDDU se termine pendant l''arrêt, signalez la fin de contrat.' ||
    CASE WHEN v_m.garantie_remplacement THEN ' Garantie remplacement : le pool d''urgence est alerté automatiquement.' ELSE ' Vous pouvez alerter le pool d''urgence depuis la mission.' END,
    '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (auth.uid(), 'SYSTEM', 'Arrêt maladie enregistré',
    'Votre arrêt est déclaré sans pénalité de score. Envoyez votre certificat médical sous 48h via Mes documents — sans justificatif, l''absence pourra être requalifiée. Pensez aussi à envoyer les volets 1-2 à votre CPAM sous 48h.',
    '/soignant/mes-documents', 'SOIGNANT');

  IF v_m.garantie_remplacement AND v_m.fin_le > NOW() + INTERVAL '1 hour' THEN
    UPDATE missions SET statut = 'OUVERTE', soignant_assigne_id = NULL,
        mode_attribution = 'PREMIER_ARRIVE', est_urgente = TRUE, niveau_urgence = 3,
        presence_confirmee_le = NULL,
        debut_le = GREATEST(debut_le, NOW() + INTERVAL '15 minutes'),
        modifie_le = NOW()
     WHERE id = p_mission_id;
    v_nb := fn_diffuser_pool_urgence(p_mission_id);
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'pool_alerte', v_nb);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_declarer_virement(p_facture_id uuid, p_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_facture RECORD;
BEGIN
    SELECT id, statut, etablissement_id INTO v_facture FROM factures WHERE id = p_facture_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Facture introuvable'); END IF;
    IF v_facture.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Non autorisé');
    END IF;
    IF v_facture.statut NOT IN ('EMISE', 'EN_RETARD') THEN
        RETURN jsonb_build_object('error', 'Statut incorrect : ' || v_facture.statut);
    END IF;
    IF p_reference IS NULL OR LENGTH(TRIM(p_reference)) < 3 THEN
        RETURN jsonb_build_object('error', 'Référence de virement requise.');
    END IF;
    UPDATE factures SET virement_reference = TRIM(p_reference), mode_paiement = 'VIREMENT',
        statut = 'VIREMENT_DECLARE', modifie_le = NOW() WHERE id = p_facture_id;
    RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_declarer_fin_retroactive(p_mission_id uuid, p_heure_fin timestamp with time zone, p_raison text DEFAULT 'Oubli de scan'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_creneau_id uuid;
  v_creneau_debut timestamptz;
  v_arrondi timestamptz;
  v_scan_numero smallint;
  v_new_code text;
  v_new_hmac text;
  v_caller_is_soignant boolean;
  v_caller_is_etab_admin boolean;
BEGIN
  SELECT id, soignant_assigne_id, etablissement_id, nb_scans, statut
  INTO v_mission
  FROM missions
  WHERE id = p_mission_id AND statut IN ('ASSIGNEE', 'EN_COURS')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable ou dans un statut incompatible.', p_mission_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_caller_is_soignant := (auth.uid() = v_mission.soignant_assigne_id);
  v_caller_is_etab_admin := est_admin_etablissement()
    AND mon_etablissement_id() = v_mission.etablissement_id;

  IF NOT (v_caller_is_soignant OR v_caller_is_etab_admin OR est_admin()) THEN
    RAISE EXCEPTION 'Vous n''êtes pas autorisé(e) à déclarer une fin rétroactive sur cette mission.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT id, debut INTO v_creneau_id, v_creneau_debut
  FROM mission_creneaux
  WHERE mission_id = v_mission.id AND type_creneau = 'EFFECTIF' AND fin IS NULL
  ORDER BY debut DESC LIMIT 1;

  IF v_creneau_id IS NULL THEN
    RAISE EXCEPTION 'Aucun créneau effectif ouvert à fermer pour cette mission.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF p_heure_fin <= v_creneau_debut THEN
    RAISE EXCEPTION 'L''heure de fin (%) doit être postérieure au début du créneau (%).',
      p_heure_fin, v_creneau_debut USING ERRCODE = 'check_violation';
  END IF;

  v_arrondi := fn_arrondir_quart_heure(p_heure_fin);
  IF v_arrondi <= v_creneau_debut THEN
    v_arrondi := v_creneau_debut + INTERVAL '15 minutes';
  END IF;

  UPDATE mission_creneaux SET fin = v_arrondi WHERE id = v_creneau_id;

  v_scan_numero := COALESCE(v_mission.nb_scans, 0) + 1;
  INSERT INTO scans_pointage (
    mission_id, soignant_id, code_saisi, numero_scan, type_scan,
    scanne_le, horodatage_arrondi, creneau_effectif_id,
    est_en_avance, validation_etab_requise
  ) VALUES (
    v_mission.id, v_mission.soignant_assigne_id, 'RETROACTIF', v_scan_numero, 'FERMETURE',
    now(), v_arrondi, v_creneau_id,
    false, true
  );

  v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  WHILE EXISTS (
    SELECT 1 FROM missions
    WHERE code_pointage_actif = v_new_code AND id != v_mission.id
      AND statut IN ('ASSIGNEE', 'EN_COURS')
  ) LOOP
    v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
  END LOOP;

  v_new_hmac := CASE
    WHEN current_setting('app.settings.hmac_secret', true) IS NOT NULL THEN
      encode(extensions.hmac(v_mission.id::text || ':' || v_new_code,
        current_setting('app.settings.hmac_secret', true), 'sha256'), 'hex')
    ELSE NULL
  END;

  UPDATE missions SET
    code_pointage_actif = v_new_code,
    code_pointage_hmac = v_new_hmac,
    prochain_type_scan = 'OUVERTURE',
    nb_scans = v_scan_numero
  WHERE id = v_mission.id;

  INSERT INTO journaux_audit
    (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (
    auth.uid(),
    CASE WHEN v_caller_is_soignant THEN 'SOIGNANT'
         WHEN v_caller_is_etab_admin THEN 'ADMIN_ETABLISSEMENT'
         ELSE 'ADMIN_PLATEFORME' END,
    'POINTAGE', 'mission', v_mission.id,
    jsonb_build_object(
      'sous_action', 'FIN_RETROACTIVE',
      'raison', p_raison,
      'creneau_effectif_id', v_creneau_id,
      'debut_creneau', v_creneau_debut,
      'heure_fin_declaree', p_heure_fin,
      'horodatage_arrondi', v_arrondi,
      'validation_etab_requise', true
    )
  );

  RETURN jsonb_build_object(
    'creneau_effectif_id', v_creneau_id,
    'debut_creneau', v_creneau_debut,
    'fin_declaree', v_arrondi,
    'validation_etab_requise', true,
    'nouveau_code', v_new_code,
    'nouveau_hmac', v_new_hmac,
    'prochain_type_scan', 'OUVERTURE',
    'numero_scan', v_scan_numero
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_declarer_paiement_soignant(p_mission_id uuid, p_montant numeric, p_methode text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_date_paiement date DEFAULT CURRENT_DATE, p_attestation_sur_l_honneur boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_soignant RECORD;
  v_etab RECORD;
  v_etab_id UUID := mon_etablissement_id();
  v_methode TEXT;
  v_echeance DATE;
  v_ref TEXT;
  v_stripe_actif BOOLEAN;
  v_paiement_id UUID;
  v_ecart_pct NUMERIC;
BEGIN
  IF NOT p_attestation_sur_l_honneur THEN
    RETURN jsonb_build_object('error', 'ATTESTATION_REQUISE',
      'message', 'L''attestation sur l''honneur est obligatoire pour déclarer un paiement soignant.');
  END IF;

  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_mission.etablissement_id != v_etab_id AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  IF v_mission.statut != 'TERMINEE' THEN
    RETURN jsonb_build_object('error', 'La mission doit être terminée');
  END IF;

  IF EXISTS (SELECT 1 FROM paiements_soignant WHERE mission_id = p_mission_id AND statut IN ('DECLARE', 'CONFIRME')) THEN
    RETURN jsonb_build_object('error', 'Paiement déjà déclaré pour cette mission');
  END IF;

  IF v_mission.type_contrat_applique IS NULL THEN
    RETURN jsonb_build_object('error', 'CONTRAT_NON_FIGE',
      'message', 'Le type de contrat de cette mission n''est pas encore figé (assignation incomplète ou MIXTE sans choix). Impossible de déclarer un paiement tant que type_contrat_applique = NULL.');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_mission.soignant_assigne_id;
  SELECT * INTO v_etab FROM etablissements WHERE id = v_etab_id;

  SELECT EXISTS(
    SELECT 1 FROM stripe_connect_onboarding
    WHERE soignant_id = v_soignant.id AND charges_enabled = TRUE AND payouts_enabled = TRUE
  ) INTO v_stripe_actif;

  IF p_methode IS NOT NULL THEN
    IF p_methode NOT IN ('VIREMENT', 'CHEQUE', 'BULLETIN_PAIE', 'NOTE_HONORAIRES') THEN
      RETURN jsonb_build_object('error', 'METHODE_INVALIDE',
        'message', 'Méthode de paiement non autorisée. Valeurs acceptées : VIREMENT, CHEQUE, BULLETIN_PAIE, NOTE_HONORAIRES.');
    END IF;
    v_methode := p_methode;
  ELSIF v_mission.type_paiement_soignant = 'NOTE_HONORAIRES' THEN
    IF v_stripe_actif THEN
      RETURN jsonb_build_object('error', 'use_stripe_connect',
        'message', 'Ce soignant a un compte Stripe Connect actif. Utilisez le paiement Stripe.',
        'use_stripe_connect', TRUE);
    END IF;
    v_methode := 'NOTE_HONORAIRES';
  ELSE
    v_methode := 'VIREMENT';
  END IF;

  IF v_mission.type_contrat_applique = 'SALARIE' AND v_methode = 'NOTE_HONORAIRES' THEN
    RETURN jsonb_build_object('error', 'CONTRAT_SALARIE_METHODE_INCOMPATIBLE',
      'message', 'Les missions en contrat salarié (CDD) ne peuvent pas être payées par note d''honoraires. Utilisez VIREMENT ou BULLETIN_PAIE.');
  END IF;

  IF v_mission.type_contrat_applique = 'LIBERAL' AND v_methode = 'BULLETIN_PAIE' THEN
    RETURN jsonb_build_object('error', 'CONTRAT_LIBERAL_METHODE_INCOMPATIBLE',
      'message', 'Les missions en contrat libéral ne génèrent pas de bulletin de paie. Utilisez VIREMENT ou NOTE_HONORAIRES.');
  END IF;

  IF v_methode IN ('VIREMENT', 'CHEQUE', 'NOTE_HONORAIRES') THEN
    v_ref := TRIM(COALESCE(p_reference, ''));
    IF LENGTH(v_ref) < 5 THEN
      RETURN jsonb_build_object('error', 'La référence doit contenir au moins 5 caractères.');
    END IF;
    IF v_ref !~ '[0-9]' THEN
      RETURN jsonb_build_object('error', 'La référence doit contenir au moins un chiffre.');
    END IF;
  ELSE
    v_ref := TRIM(COALESCE(p_reference, ''));
  END IF;

  IF p_montant <= 0 THEN
    RETURN jsonb_build_object('error', 'Le montant doit être supérieur à 0.');
  END IF;

  IF p_date_paiement > CURRENT_DATE THEN
    RETURN jsonb_build_object('error', 'La date de paiement ne peut pas être dans le futur.');
  END IF;

  v_echeance := p_date_paiement + COALESCE(v_etab.delai_paiement_jours, 30);

  INSERT INTO paiements_soignant (
    mission_id, soignant_id, etablissement_id, montant_net, methode, reference_virement,
    date_paiement, confirme_par_etablissement, confirme_par_etablissement_le, statut, echeance_le
  ) VALUES (
    p_mission_id, v_mission.soignant_assigne_id, v_etab_id,
    p_montant, v_methode, v_ref, p_date_paiement, TRUE, NOW(), 'DECLARE', v_echeance
  ) RETURNING id INTO v_paiement_id;

  IF v_mission.net_a_payer IS NOT NULL AND v_mission.net_a_payer > 0 THEN
    v_ecart_pct := ABS(p_montant - v_mission.net_a_payer) / v_mission.net_a_payer * 100;
    IF v_ecart_pct > 10 THEN
      PERFORM fn_ecrire_audit_safe(
        auth.uid(),
        'ETABLISSEMENT',
        'PAIEMENT',
        'paiements_soignant',
        v_paiement_id,
        NULL,
        jsonb_build_object(
          'sous_action', 'PAIEMENT_MONTANT_ECART',
          'mission_id', p_mission_id,
          'mission_intitule', v_mission.intitule,
          'montant_declare', p_montant,
          'montant_attendu_net_a_payer', v_mission.net_a_payer,
          'ecart_pct', ROUND(v_ecart_pct, 2),
          'methode', v_methode,
          'type_contrat_applique', v_mission.type_contrat_applique
        ),
        NULL,
        NULL
      );
    END IF;
  END IF;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    v_mission.soignant_assigne_id, 'SYSTEM', 'Paiement déclaré',
    'Paiement de ' || p_montant || ' € déclaré pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (réf. ' || v_ref || ').',
    '/soignant/mes-gains', 'SOIGNANT'
  );

  PERFORM public.fn_ecrire_audit_safe(
    auth.uid(),
    'ETABLISSEMENT',
    'PAIEMENT_SOIGNANT_DECLARE_ETAB',
    'paiements_soignant',
    v_paiement_id,
    NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'mission_intitule', v_mission.intitule,
      'soignant_id', v_mission.soignant_assigne_id,
      'etablissement_id', v_etab_id,
      'montant_net', p_montant,
      'methode', v_methode,
      'reference_virement', v_ref,
      'date_paiement', p_date_paiement,
      'echeance_le', v_echeance,
      'type_contrat_applique', v_mission.type_contrat_applique,
      'attestation_sur_l_honneur', TRUE,
      'attestation_timestamp', NOW()
    ),
    NULL,
    NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'paiement_id', v_paiement_id,
    'methode', v_methode,
    'echeance', v_echeance,
    'soignant_id', v_mission.soignant_assigne_id,
    'mission_intitule', v_mission.intitule
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_demander_confirmation_email_etab(p_etablissement_id uuid, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token text;
  v_expire timestamptz;
  v_etab RECORD;
BEGIN
  IF NOT est_admin() THEN
    IF mon_etablissement_id() IS NULL OR mon_etablissement_id() <> p_etablissement_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;
  END IF;

  IF p_email IS NULL OR p_email !~ '^[^@]+@[^@]+\.[^@]+$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Adresse e-mail invalide');
  END IF;

  SELECT id, nom INTO v_etab FROM etablissements WHERE id = p_etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expire := now() + interval '24 hours';

  UPDATE etablissements SET
    email_contact = p_email,
    email_contact_token = v_token,
    email_contact_token_expire_le = v_expire,
    email_contact_verifie = false,
    email_contact_verifie_le = NULL
  WHERE id = p_etablissement_id;

  INSERT INTO email_queue (id, type, destinataire_email, data, statut, cree_le)
  VALUES (
    gen_random_uuid(),
    'CONFIRMATION_EMAIL_PRO_ETAB',
    p_email,
    jsonb_build_object(
      'etablissement_id', p_etablissement_id,
      'etablissement_nom', v_etab.nom,
      'token', v_token,
      'expire_le', v_expire
    ),
    'EN_ATTENTE',
    now()
  );

  RETURN jsonb_build_object('success', true, 'email', p_email, 'expire_le', v_expire);
END;
$function$


---FIN-FONCTION---

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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_definir_retrocession_mission(p_mission_id uuid, p_pct numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut != 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'Modifiable uniquement sur une mission ouverte.');
  END IF;
  IF p_pct IS NULL OR p_pct <= 0 OR p_pct > 100 THEN
    RETURN jsonb_build_object('error', 'Pourcentage de rétrocession invalide (1-100).');
  END IF;
  UPDATE missions SET mode_remuneration = 'RETROCESSION', retrocession_pct = p_pct,
    type_contrat_recherche = 'LIBERAL', modifie_le = NOW()
   WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'retrocession_pct', p_pct);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_declarer_honoraires_retrocession(p_mission_id uuid, p_montant_honoraires numeric, p_justificatif_cle text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_m RECORD;
  v_retrocede numeric;
  v_taux_com numeric;
  v_com_ht numeric;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.mode_remuneration != 'RETROCESSION' THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est pas en rétrocession.');
  END IF;
  IF v_m.statut != 'TERMINEE' THEN
    RETURN jsonb_build_object('error', 'Déclaration possible une fois la mission terminée.');
  END IF;
  IF v_m.montant_honoraires_bruts IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Honoraires déjà déclarés. Contactez le support pour rectifier.');
  END IF;
  IF p_montant_honoraires IS NULL OR p_montant_honoraires <= 0 OR p_montant_honoraires > 100000 THEN
    RETURN jsonb_build_object('error', 'Montant d''honoraires invalide.');
  END IF;
  IF p_justificatif_cle IS NULL OR length(trim(p_justificatif_cle)) < 5 THEN
    RETURN jsonb_build_object('error', 'Justificatif obligatoire : téléversez le relevé d''actes ou bordereau de la période.');
  END IF;

  v_retrocede := ROUND(p_montant_honoraires * COALESCE(v_m.retrocession_pct, 50) / 100.0, 2);
  v_taux_com := COALESCE(v_m.taux_commission_fige, v_m.taux_commission, 15);
  v_com_ht := ROUND(v_retrocede * v_taux_com / 100.0, 2);

  UPDATE missions SET
    montant_honoraires_bruts = p_montant_honoraires,
    justificatif_honoraires_cle = trim(p_justificatif_cle),
    total_brut = v_retrocede,
    net_a_payer = v_retrocede,
    montant_commission_ht = v_com_ht,
    montant_commission_tva = ROUND(v_com_ht * 0.20, 2),
    montant_commission_ttc = ROUND(v_com_ht * 1.20, 2),
    modifie_le = NOW()
  WHERE id = p_mission_id;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (v_m.soignant_assigne_id, 'SYSTEM', 'Relevé d''honoraires à confirmer 💶',
    'Le cabinet déclare ' || p_montant_honoraires || ' € d''honoraires (justificatif joint) pour "' || fn_html_escape(v_m.intitule) ||
    '" — votre rétrocession (' || COALESCE(v_m.retrocession_pct, 50) || '%) : ' || v_retrocede ||
    ' €. CONFIRMEZ le relevé sur la mission (ou contestez sous 48h via un litige). Sans action de votre part, le montant sera validé automatiquement sous 48h.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT');

  RETURN jsonb_build_object('success', TRUE, 'montant_retrocede', v_retrocede,
    'commission_ttc', ROUND(v_com_ht * 1.20, 2), 'en_attente_confirmation', TRUE);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_demander_a_retravailler(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_s RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT prenom, nom, profession INTO v_s FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

  -- Légitimité : au moins une mission TERMINEE ensemble (on redemande à
  -- travailler quelque part où on a déjà travaillé).
  IF NOT EXISTS (
    SELECT 1 FROM missions m
    WHERE m.etablissement_id = p_etablissement_id
      AND m.soignant_assigne_id = v_uid AND m.statut = 'TERMINEE'
  ) THEN
    RETURN jsonb_build_object('error', 'Disponible après une première mission terminée avec cet établissement.');
  END IF;

  IF fn_est_exclu(v_uid, p_etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Demande impossible auprès de cet établissement.');
  END IF;

  -- Dédup 7 jours : une seule sollicitation par étab par semaine.
  IF EXISTS (
    SELECT 1 FROM notifications n
    WHERE n.destinataire_id = p_etablissement_id AND n.type = 'SYSTEM'
      AND n.lien = '/etablissement/soignants/' || v_uid
      AND n.titre LIKE '%veut retravailler%'
      AND n.cree_le > NOW() - INTERVAL '7 days'
  ) THEN
    RETURN jsonb_build_object('error', 'Demande déjà envoyée cette semaine — l''établissement a été prévenu.');
  END IF;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (p_etablissement_id, 'SYSTEM',
    v_s.prenom || ' ' || v_s.nom || ' veut retravailler avec vous ⭐',
    'Vous avez déjà travaillé ensemble. Reproposez-lui une mission en 2 clics depuis son profil.',
    '/etablissement/soignants/' || v_uid, 'ETABLISSEMENT');

  RETURN jsonb_build_object('success', TRUE);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_detecter_teleportation(p_soignant_id uuid, p_lat numeric, p_lng numeric, p_horodatage timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_precedent RECORD;
    v_distance_km NUMERIC;
    v_duree_heures NUMERIC;
    v_vitesse_kmh NUMERIC;
    v_vitesse_max CONSTANT NUMERIC := 200.0;
    v_resultat JSONB := '{"suspect": false}'::JSONB;
BEGIN
    SELECT
        COALESCE(p.pointage_depart_le, p.pointage_arrivee_le) AS dernier_horodatage,
        COALESCE(p.depart_lat, p.arrivee_lat) AS derniere_lat,
        COALESCE(p.depart_lng, p.arrivee_lng) AS derniere_lng,
        p.mission_id
    INTO v_precedent
    FROM presences p
    WHERE p.soignant_id = p_soignant_id
      AND COALESCE(p.pointage_depart_le, p.pointage_arrivee_le) IS NOT NULL
      AND COALESCE(p.pointage_depart_le, p.pointage_arrivee_le) < p_horodatage
    ORDER BY COALESCE(p.pointage_depart_le, p.pointage_arrivee_le) DESC
    LIMIT 1;

    IF v_precedent IS NULL OR v_precedent.derniere_lat IS NULL THEN
        RETURN v_resultat;
    END IF;

    -- Distance Haversine (km)
    v_distance_km := 6371 * acos(
        LEAST(1.0,
            cos(radians(v_precedent.derniere_lat)) * cos(radians(p_lat))
            * cos(radians(p_lng) - radians(v_precedent.derniere_lng))
            + sin(radians(v_precedent.derniere_lat)) * sin(radians(p_lat))
        )
    );

    v_duree_heures := EXTRACT(EPOCH FROM (p_horodatage - v_precedent.dernier_horodatage)) / 3600.0;
    IF v_duree_heures < 0.001 THEN v_duree_heures := 0.001; END IF;

    v_vitesse_kmh := v_distance_km / v_duree_heures;

    IF v_vitesse_kmh > v_vitesse_max AND v_distance_km > 5.0 THEN
        v_resultat := jsonb_build_object(
            'suspect', TRUE,
            'type_alerte', 'TELEPORTATION',
            'distance_km', ROUND(v_distance_km, 2),
            'duree_heures', ROUND(v_duree_heures, 4),
            'vitesse_implicite_kmh', ROUND(v_vitesse_kmh, 1),
            'vitesse_max_autorisee_kmh', v_vitesse_max,
            'position_precedente', jsonb_build_object(
                'lat', v_precedent.derniere_lat,
                'lng', v_precedent.derniere_lng,
                'horodatage', v_precedent.dernier_horodatage,
                'mission_id', v_precedent.mission_id
            ),
            'position_actuelle', jsonb_build_object(
                'lat', p_lat, 'lng', p_lng, 'horodatage', p_horodatage
            )
        );
    END IF;

    RETURN v_resultat;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_deposer_chorus(p_facture_id uuid, p_chorus_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_facture RECORD;
BEGIN
    SELECT * INTO v_facture FROM factures WHERE id = p_facture_id;
    IF v_facture IS NULL THEN RETURN '{"error":"Facture introuvable"}'::JSONB; END IF;
    IF v_facture.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
        RETURN '{"error":"Accès refusé"}'::JSONB;
    END IF;

    UPDATE factures SET
        chorus_pro_statut = 'DEPOSEE',
        chorus_pro_deposee_le = NOW(),
        chorus_pro_id = p_chorus_id
    WHERE id = p_facture_id;

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_detail_facture(p_facture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_facture RECORD;
    v_missions JSONB;
BEGIN
    IF v_etab_id IS NULL AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT * INTO v_facture FROM factures WHERE id = p_facture_id;
    IF v_facture IS NULL THEN RETURN jsonb_build_object('error', 'Facture introuvable'); END IF;
    IF v_facture.etablissement_id != v_etab_id AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    -- PRIORITÉ 1 : missions liées par facture_id
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', m.id,
            'intitule', m.intitule,
            'service', m.service,
            'debut_le', m.debut_le,
            'fin_le', m.fin_le,
            'duree_heures', m.duree_heures,
            'taux_horaire_base', m.taux_horaire_base,
            'total_brut', m.total_brut,
            'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
            'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
            'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
            'taux_ifm', COALESCE(m.taux_ifm, 0),
            'montant_ifm', COALESCE(m.montant_ifm, 0),
            'taux_icp', COALESCE(m.taux_icp, 0),
            'montant_icp', COALESCE(m.montant_icp, 0),
            'taux_commission', m.taux_commission,
            'montant_commission_ht', m.montant_commission_ht,
            'montant_commission_tva', m.montant_commission_tva,
            'montant_commission_ttc', m.montant_commission_ttc,
            'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
            'profession', m.profession_requise::TEXT,
            'presences', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', p.id,
                    'pointage_arrivee_le', p.pointage_arrivee_le,
                    'pointage_depart_le', p.pointage_depart_le,
                    'methode_pointage_arrivee', p.methode_pointage_arrivee,
                    'methode_pointage_depart', p.methode_pointage_depart,
                    'heures_reelles', p.heures_reelles,
                    'duree_brute_min', p.duree_brute_min,
                    'duree_nette_min', p.duree_nette_min,
                    'duree_pause_min', p.duree_pause_min,
                    'retard_min', p.retard_min,
                    'depart_anticipe_min', p.depart_anticipe_min,
                    'perimetre_gps_valide', p.perimetre_gps_valide,
                    'alerte_teleportation', p.alerte_teleportation,
                    'valide_par_etablissement', p.valide_par_etablissement
                ) ORDER BY p.pointage_arrivee_le)
                FROM presences p
                WHERE p.mission_id = m.id
            ), '[]'::JSONB)
        ) ORDER BY m.debut_le
    ), '[]'::JSONB)
    INTO v_missions
    FROM missions m
    LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
    WHERE m.facture_id = p_facture_id;

    -- PRIORITÉ 2 : si aucune mission liée par FK, chercher par période
    IF v_missions = '[]'::JSONB AND v_facture.periode_debut IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'intitule', m.intitule,
                'service', m.service,
                'debut_le', m.debut_le,
                'fin_le', m.fin_le,
                'duree_heures', m.duree_heures,
                'taux_horaire_base', m.taux_horaire_base,
                'total_brut', m.total_brut,
                'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
                'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
                'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
                'taux_ifm', COALESCE(m.taux_ifm, 0),
                'montant_ifm', COALESCE(m.montant_ifm, 0),
                'taux_icp', COALESCE(m.taux_icp, 0),
                'montant_icp', COALESCE(m.montant_icp, 0),
                'taux_commission', m.taux_commission,
                'montant_commission_ht', m.montant_commission_ht,
                'montant_commission_tva', m.montant_commission_tva,
                'montant_commission_ttc', m.montant_commission_ttc,
                'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
                'profession', m.profession_requise::TEXT,
                'presences', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', p.id,
                        'pointage_arrivee_le', p.pointage_arrivee_le,
                        'pointage_depart_le', p.pointage_depart_le,
                        'methode_pointage_arrivee', p.methode_pointage_arrivee,
                        'methode_pointage_depart', p.methode_pointage_depart,
                        'heures_reelles', p.heures_reelles,
                        'duree_brute_min', p.duree_brute_min,
                        'duree_nette_min', p.duree_nette_min,
                        'duree_pause_min', p.duree_pause_min,
                        'retard_min', p.retard_min,
                        'depart_anticipe_min', p.depart_anticipe_min,
                        'perimetre_gps_valide', p.perimetre_gps_valide,
                        'alerte_teleportation', p.alerte_teleportation,
                        'valide_par_etablissement', p.valide_par_etablissement
                    ) ORDER BY p.pointage_arrivee_le)
                    FROM presences p
                    WHERE p.mission_id = m.id
                ), '[]'::JSONB)
            ) ORDER BY m.debut_le
        ), '[]'::JSONB)
        INTO v_missions
        FROM missions m
        LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
        WHERE m.etablissement_id = v_facture.etablissement_id
        AND m.statut = 'TERMINEE' AND m.commission_facturee = TRUE
        AND m.debut_le >= v_facture.periode_debut::TIMESTAMP
        AND m.debut_le < (v_facture.periode_fin + 1)::TIMESTAMP;
    END IF;

    -- PRIORITÉ 3 : mission unique si facture a mission_id
    IF v_missions = '[]'::JSONB AND v_facture.mission_id IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'intitule', m.intitule,
                'service', m.service,
                'debut_le', m.debut_le,
                'fin_le', m.fin_le,
                'duree_heures', m.duree_heures,
                'taux_horaire_base', m.taux_horaire_base,
                'total_brut', m.total_brut,
                'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0),
                'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
                'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0),
                'taux_ifm', COALESCE(m.taux_ifm, 0),
                'montant_ifm', COALESCE(m.montant_ifm, 0),
                'taux_icp', COALESCE(m.taux_icp, 0),
                'montant_icp', COALESCE(m.montant_icp, 0),
                'taux_commission', m.taux_commission,
                'montant_commission_ht', m.montant_commission_ht,
                'montant_commission_tva', m.montant_commission_tva,
                'montant_commission_ttc', m.montant_commission_ttc,
                'soignant_nom', COALESCE(s.prenom || ' ' || s.nom, ''),
                'profession', m.profession_requise::TEXT,
                'presences', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id', p.id,
                        'pointage_arrivee_le', p.pointage_arrivee_le,
                        'pointage_depart_le', p.pointage_depart_le,
                        'methode_pointage_arrivee', p.methode_pointage_arrivee,
                        'methode_pointage_depart', p.methode_pointage_depart,
                        'heures_reelles', p.heures_reelles,
                        'duree_brute_min', p.duree_brute_min,
                        'duree_nette_min', p.duree_nette_min,
                        'duree_pause_min', p.duree_pause_min,
                        'retard_min', p.retard_min,
                        'depart_anticipe_min', p.depart_anticipe_min,
                        'perimetre_gps_valide', p.perimetre_gps_valide,
                        'alerte_teleportation', p.alerte_teleportation,
                        'valide_par_etablissement', p.valide_par_etablissement
                    ) ORDER BY p.pointage_arrivee_le)
                    FROM presences p
                    WHERE p.mission_id = m.id
                ), '[]'::JSONB)
            )
        ), '[]'::JSONB)
        INTO v_missions
        FROM missions m
        LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
        WHERE m.id = v_facture.mission_id;
    END IF;

    RETURN jsonb_build_object(
        'facture', jsonb_build_object(
            'id', v_facture.id, 'numero_facture', v_facture.numero_facture,
            'statut', v_facture.statut, 'montant_ht', v_facture.montant_ht,
            'taux_tva', v_facture.taux_tva, 'montant_tva', v_facture.montant_tva,
            'montant_ttc', v_facture.montant_ttc, 'nombre_missions', v_facture.nombre_missions,
            'mode_paiement', v_facture.mode_paiement,
            'periode_debut', v_facture.periode_debut, 'periode_fin', v_facture.periode_fin,
            'date_emission', v_facture.date_emission, 'date_echeance', v_facture.date_echeance,
            'date_paiement', v_facture.date_paiement
        ),
        'missions', v_missions
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_diagnostic_coherence_financiere()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_missions_incoherent jsonb;
  v_factures_ecart jsonb;
  v_transfers_orphelins jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  -- 1. Missions où total_brut diverge de taux × heures + majorations
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'intitule', intitule, 'total_brut', total_brut,
        'attendu', taux_horaire_base * duree_heures
          + COALESCE(montant_majoration_nuit,0)
          + COALESCE(montant_majoration_dimanche,0)
          + COALESCE(montant_majoration_ferie,0),
        'ecart', total_brut - (
          taux_horaire_base * duree_heures
          + COALESCE(montant_majoration_nuit,0)
          + COALESCE(montant_majoration_dimanche,0)
          + COALESCE(montant_majoration_ferie,0)
        )
      ))
      FROM missions m2
      WHERE total_brut IS NOT NULL AND taux_horaire_base IS NOT NULL AND duree_heures IS NOT NULL
        AND abs(total_brut - (
          taux_horaire_base * duree_heures
          + COALESCE(montant_majoration_nuit,0)
          + COALESCE(montant_majoration_dimanche,0)
          + COALESCE(montant_majoration_ferie,0)
        )) > 0.5
      LIMIT 10
    )
  ) INTO v_missions_incoherent
  FROM missions m
  WHERE total_brut IS NOT NULL AND taux_horaire_base IS NOT NULL AND duree_heures IS NOT NULL
    AND abs(total_brut - (
      taux_horaire_base * duree_heures
      + COALESCE(montant_majoration_nuit,0)
      + COALESCE(montant_majoration_dimanche,0)
      + COALESCE(montant_majoration_ferie,0)
    )) > 0.5;

  -- 2. Factures où montant_ht diverge de mission.net_a_payer (>1% ou >1€)
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', (
      SELECT jsonb_agg(jsonb_build_object(
        'facture_id', fh.id, 'numero_facture', fh.numero_facture,
        'mission_id', m.id, 'montant_ht', fh.montant_ht,
        'mission_net', m.net_a_payer,
        'ecart', fh.montant_ht - COALESCE(m.net_a_payer, 0)
      ))
      FROM factures_honoraires fh
      JOIN missions m ON m.id = fh.mission_id
      WHERE COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
        AND fh.statut NOT IN ('BROUILLON','REMPLACEE','ANNULEE')
        AND m.net_a_payer IS NOT NULL AND m.net_a_payer > 0
        AND abs(fh.montant_ht - m.net_a_payer) > GREATEST(m.net_a_payer * 0.01, 1.00)
      LIMIT 10
    )
  ) INTO v_factures_ecart
  FROM factures_honoraires fh
  JOIN missions m ON m.id = fh.mission_id
  WHERE COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
    AND fh.statut NOT IN ('BROUILLON','REMPLACEE','ANNULEE')
    AND m.net_a_payer IS NOT NULL AND m.net_a_payer > 0
    AND abs(fh.montant_ht - m.net_a_payer) > GREATEST(m.net_a_payer * 0.01, 1.00);

  -- 3. Transfers Stripe orphelins (mission qui n'a plus de facture)
  SELECT jsonb_build_object(
    'count', count(*),
    'echantillon', (
      SELECT jsonb_agg(jsonb_build_object(
        'transfer_id', st.id, 'mission_id', st.mission_id,
        'montant_total', st.montant_total
      ))
      FROM stripe_transfers st2
      WHERE st2.mission_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM factures_honoraires fh
          WHERE fh.mission_id = st2.mission_id
            AND COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
            AND fh.statut NOT IN ('BROUILLON','ANNULEE')
        )
      LIMIT 10
    )
  ) INTO v_transfers_orphelins
  FROM stripe_transfers st
  WHERE st.mission_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM factures_honoraires fh
      WHERE fh.mission_id = st.mission_id
        AND COALESCE(fh.type_document, 'FACTURE') = 'FACTURE'
        AND fh.statut NOT IN ('BROUILLON','ANNULEE')
    );

  RETURN jsonb_build_object(
    'success', true,
    'genere_le', now(),
    'missions_incoherentes', v_missions_incoherent,
    'factures_ecart_mission', v_factures_ecart,
    'stripe_transfers_orphelins', v_transfers_orphelins
  );
END;
$function$


---FIN-FONCTION---

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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_digest_hebdo_cibles(p_limit integer DEFAULT 500)
 RETURNS TABLE(id uuid, prenom text, email text, profession text, nb_missions bigint, taux_max numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT s.id, s.prenom::text, s.email::text, s.profession::text,
    (SELECT count(*) FROM missions m WHERE m.statut='OUVERTE' AND m.profession_requise = s.profession),
    (SELECT max(m.taux_horaire_base) FROM missions m WHERE m.statut='OUVERTE' AND m.profession_requise = s.profession)
  FROM soignants s
  WHERE s.email IS NOT NULL
    AND EXISTS (SELECT 1 FROM missions m WHERE m.statut='OUVERTE' AND m.profession_requise = s.profession)
  LIMIT greatest(p_limit, 1);
$function$


---FIN-FONCTION---

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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_diffuser_pool_urgence(p_mission_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD; v_nb int := 0;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng, e.adresse_ville AS etab_ville
    INTO v_m FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
   WHERE m.id = p_mission_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  SELECT s.id, 'POOL_URGENCE',
    '🚨 Mission urgente à pourvoir — premier arrivé, premier servi',
    fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
    TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') || ' à ' ||
    COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h.',
    '/soignant/missions/' || v_m.id, 'SOIGNANT'
  FROM soignants s
  WHERE s.profession = v_m.profession_requise
    AND s.supprime_le IS NULL
    AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
    AND COALESCE(s.tous_documents_valides, false)
    AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
    AND (v_m.soignant_assigne_id IS NULL OR s.id != v_m.soignant_assigne_id)
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.destinataire_id = s.id AND n.type = 'POOL_URGENCE'
        AND n.lien = '/soignant/missions/' || v_m.id
        AND n.cree_le > NOW() - INTERVAL '12 hours')
    AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
         OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
            <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
  LIMIT 50;
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb;
END;
$function$
