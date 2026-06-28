-- Consolidation commission / finance — vérification en profondeur (27/06).
--
-- Contexte vérifié :
--  * La commission SALARIÉ live est CORRECTE : à la clôture, dec_calculer_commission
--    fixe commission = net_a_payer × taux (toujours 15 %). Rappel terminologie : la
--    colonne `net_a_payer` est mal nommée — c'est le montant TOTAL (brut + primes
--    IFM/ICP), supérieur à `total_brut`. La com 15 % est bien sur ce total. NON modifié.
--
-- Vrais bugs corrigés (tous latents : 0 libéral en base, salarié→0 sur édition rare) :
--
-- 1. LIBÉRAL — IFM + ICP appliqués à tort. fn_calculer_remuneration_mission décidait
--    des primes sur soignants.type_contrat (défaut 'CDD') sans regarder type_exercice.
--    Un libéral (qui ne perçoit PAS d'IFM/ICP) voyait net_a_payer gonflé de ~21 %
--    → note d'honoraires ET commission gonflées. Corrigé : primes uniquement si
--    exercice ≠ LIBERAL. Prouvé : libéral 10 h × 30 € → net 300 (= brut) au lieu de 363.
--    Salarié inchangé (net 363). Comme dec_calculer_finance_mission et la note
--    d'honoraires dérivent de cette fonction, le libéral est corrigé partout via ce
--    seul point.
--
-- 2. fn_calculer_financier_mission — la commission y était calculée sur `total_brut`
--    avec un `salarié→0`. Cette fonction s'exécute en dernier sur édition des colonnes
--    finance : éditer une mission SALARIÉ déjà terminée pouvait écraser sa commission
--    à 0. Aligné sur dec_calculer_commission : commission = net_a_payer × taux,
--    TOUJOURS (salarié et libéral), plus de salarié→0, plus de base divergente.
--    + même gate libéral (pas d'IFM/ICP). Prouvé : salarié com 45 (= net 300 × 15 %),
--    libéral com 37,50 (= brut 250 × 15 %).
--
-- 3. Index unique partiel sur factures(mission_id) — anti double-facturation de la
--    facture commission étab (le côté honoraires avait déjà uniq_fh_mission_semaine_active).

-- 1. Source rémunération : pas d'IFM/ICP en exercice libéral
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

    -- IFM + ICP : primes d'un CDD salarié uniquement. Un soignant en exercice LIBÉRAL
    -- ne perçoit pas ces indemnités (il facture des honoraires).
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
$function$;

-- 2. Trigger finance : commission = net_a_payer × taux (toujours) + gate libéral IFM/ICP
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

  v_taux_ifm := CASE WHEN v_est_liberal THEN 0 ELSE COALESCE(NEW.taux_ifm, 0.10) END;
  v_taux_icp := CASE WHEN v_est_liberal THEN 0 ELSE COALESCE(NEW.taux_icp, 0.10) END;
  NEW.taux_ifm := v_taux_ifm;
  NEW.taux_icp := v_taux_icp;
  NEW.montant_ifm := ROUND(v_total_brut * v_taux_ifm, 2);
  NEW.montant_icp := ROUND(v_total_brut * v_taux_icp, 2);
  NEW.net_a_payer := ROUND(v_total_brut + NEW.montant_ifm + NEW.montant_icp, 2);
  NEW.net_estime := ROUND(NEW.net_a_payer * 0.78, 2);

  -- Commission Jolene : TOUJOURS 15 % (ou taux négocié/figé) sur le montant total
  -- (net_a_payer), salarié ET libéral. Aligné sur dec_calculer_commission.
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
$function$;

-- 3. Anti double-facturation de la facture commission étab
CREATE UNIQUE INDEX IF NOT EXISTS uniq_factures_mission_active
ON public.factures (mission_id)
WHERE mission_id IS NOT NULL
  AND type_document = 'FACTURE'
  AND statut NOT IN ('ANNULEE','REMPLACEE','ERREUR_GENERATION');
