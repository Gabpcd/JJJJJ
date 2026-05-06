-- ============================================================
-- Correction garantie d'heures : COALESCE → GREATEST(prev, eff)
-- ============================================================
-- Décision produit : le soignant facture au minimum ses heures
-- prévisionnelles (garantie plancher contractuelle). Si l'effectif
-- pointé dépasse le prévisionnel (avec accord étab), l'effectif
-- l'emporte.
--
-- Remplace la logique COALESCE(EFFECTIF fermé, PREVISIONNEL, 0) par
-- GREATEST(PREVISIONNEL, EFFECTIF fermé) dans 3 fonctions :
--   1. fn_calculer_financier_mission   (trigger BEFORE missions)
--   2. fn_trg_auto_heures_majorees     (trigger BEFORE missions)
--   3. fn_verifier_pre_facturation     (RPC appelée par edge generate-invoice)
--
-- Cf. /docs/correction-garantie-heures.md pour l'audit pré-implémentation.
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. fn_calculer_financier_mission — durée GREATEST
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_calculer_financier_mission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
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
BEGIN
  -- GREATEST : on prend la plus grande des deux sommes
  -- (prévisionnel plancher contractuel vs effectif pointé).
  -- COALESCE(..., 0) neutralise la propagation NULL de GREATEST.
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

  NEW.montant_ifm := ROUND(v_total_brut * COALESCE(NEW.taux_ifm, 0.10), 2);
  NEW.montant_icp := ROUND(v_total_brut * COALESCE(NEW.taux_icp, 0.10), 2);
  NEW.net_a_payer := ROUND(v_total_brut + NEW.montant_ifm + NEW.montant_icp, 2);
  NEW.net_estime := ROUND(NEW.net_a_payer * 0.78, 2);

  -- Commission Jolene sur même base GREATEST (décision D1) :
  -- étab paie le plancher, Jolene commissionne sur le plancher.
  v_commission_taux := COALESCE(NEW.taux_commission, COALESCE(v_etab.taux_commission_negocie, 15));
  NEW.taux_commission := v_commission_taux;
  v_commission_ht := ROUND(v_total_brut * v_commission_taux / 100.0, 2);
  v_commission_tva := ROUND(v_commission_ht * 0.20, 2);
  v_commission_ttc := ROUND(v_commission_ht + v_commission_tva, 2);
  NEW.montant_commission_ht := v_commission_ht;
  NEW.montant_commission_tva := v_commission_tva;
  NEW.montant_commission_ttc := v_commission_ttc;

  RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 2. fn_trg_auto_heures_majorees — source = set de créneaux gagnant
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trg_auto_heures_majorees()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_creneau RECORD;
  v_nuit numeric := 0;
  v_dim numeric := 0;
  v_fer numeric := 0;
  v_h_debut_nuit time;
  v_h_fin_nuit time;
  v_cursor timestamptz;
  v_step interval := '30 minutes';
  v_local_time time;
  v_dow int;
  v_date date;
  v_type_source text;
  v_sum_prev numeric;
  v_sum_eff numeric;
BEGIN
  IF NEW.debut_le IS NULL OR NEW.fin_le IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT
    COALESCE(NEW.heure_debut_nuit_fige, e.heure_debut_nuit, '21:00'::time),
    COALESCE(NEW.heure_fin_nuit_fige, e.heure_fin_nuit, '06:00'::time)
  INTO v_h_debut_nuit, v_h_fin_nuit
  FROM etablissements e WHERE e.id = NEW.etablissement_id;

  IF NOT FOUND THEN
    v_h_debut_nuit := '21:00'::time;
    v_h_fin_nuit := '06:00'::time;
  END IF;

  -- Source = set de créneaux qui porte la durée gagnante GREATEST.
  -- Si EFF > PREV : EFFECTIF ; sinon PREVISIONNEL (inclut égalité et PREV > EFF).
  SELECT
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause), 0),
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause), 0)
  INTO v_sum_prev, v_sum_eff
  FROM mission_creneaux WHERE mission_id = NEW.id;

  IF v_sum_eff > v_sum_prev THEN
    v_type_source := 'EFFECTIF';
  ELSE
    v_type_source := 'PREVISIONNEL';
  END IF;

  FOR v_creneau IN
    SELECT debut, fin FROM mission_creneaux
    WHERE mission_id = NEW.id
      AND type_creneau = v_type_source
      AND NOT est_pause
      AND (v_type_source = 'PREVISIONNEL' OR fin IS NOT NULL)
  LOOP
    v_cursor := v_creneau.debut;
    WHILE v_cursor < v_creneau.fin LOOP
      v_local_time := (v_cursor AT TIME ZONE 'Europe/Paris')::time;
      v_dow := EXTRACT(DOW FROM (v_cursor AT TIME ZONE 'Europe/Paris'));
      v_date := (v_cursor AT TIME ZONE 'Europe/Paris')::date;

      IF v_h_debut_nuit > v_h_fin_nuit THEN
        IF v_local_time >= v_h_debut_nuit OR v_local_time < v_h_fin_nuit THEN
          v_nuit := v_nuit + 0.5;
        END IF;
      ELSE
        IF v_local_time >= v_h_debut_nuit AND v_local_time < v_h_fin_nuit THEN
          v_nuit := v_nuit + 0.5;
        END IF;
      END IF;

      IF v_dow = 0 THEN v_dim := v_dim + 0.5; END IF;
      IF EXISTS (SELECT 1 FROM jours_feries_fr WHERE date_ferie = v_date) THEN v_fer := v_fer + 0.5; END IF;

      v_cursor := v_cursor + v_step;
    END LOOP;
  END LOOP;

  NEW.heures_nuit := v_nuit;
  NEW.heures_dimanche := v_dim;
  NEW.heures_ferie := v_fer;

  RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 3. fn_verifier_pre_facturation — blocage asymétrique + WARNING PREV=0
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_verifier_pre_facturation(
  p_mission_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission RECORD;
  v_nb_effectif_ouvert integer;
  v_nb_effectif_ferme integer;
  v_duree_previsionnelle numeric;
  v_duree_effective numeric;
  v_ecart_heures numeric;
  v_ecart_pourcent numeric;
  v_source text;
BEGIN
  SELECT id, duree_heures, duree_heures_effective, statut
  INTO v_mission
  FROM missions WHERE id = p_mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mission % introuvable.', p_mission_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Check 1 : créneaux EFFECTIF ouverts → BLOQUANT (inchangé)
  SELECT
    COUNT(*) FILTER (WHERE fin IS NULL),
    COUNT(*) FILTER (WHERE fin IS NOT NULL)
  INTO v_nb_effectif_ouvert, v_nb_effectif_ferme
  FROM mission_creneaux
  WHERE mission_id = p_mission_id AND type_creneau = 'EFFECTIF';

  IF v_nb_effectif_ouvert > 0 THEN
    RAISE EXCEPTION 'Facturation bloquée : % créneau(x) effectif(s) ouvert(s) (fin IS NULL). Utilisez fn_declarer_fin_retroactive pour compléter le pointage.',
      v_nb_effectif_ouvert USING ERRCODE = 'check_violation';
  END IF;

  -- Durées PREV/EFF recalculées depuis les créneaux (ignore mission.duree_*)
  SELECT
    COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
             FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause)::numeric, 2), 0),
    COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
             FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)::numeric, 2), 0)
  INTO v_duree_previsionnelle, v_duree_effective
  FROM mission_creneaux WHERE mission_id = p_mission_id;

  v_ecart_heures := ROUND(ABS(v_duree_previsionnelle - v_duree_effective), 2);
  IF v_duree_previsionnelle > 0 THEN
    v_ecart_pourcent := ROUND(v_ecart_heures / v_duree_previsionnelle * 100, 2);
  ELSE
    v_ecart_pourcent := 0;
  END IF;

  -- Check 2 : EFF > PREV × 1.10 → BLOQUANT (dépassement > 10%)
  -- (Décision D2 : EFF < PREV = garantie plancher, pas de blocage)
  IF v_duree_previsionnelle > 0 AND v_duree_effective > v_duree_previsionnelle * 1.10 THEN
    RAISE EXCEPTION 'Facturation bloquée : effectif %h dépasse prévisionnel %h de plus de 10 pct (écart % pct). Validation étab/admin requise.',
      v_duree_effective, v_duree_previsionnelle, v_ecart_pourcent
      USING ERRCODE = 'check_violation';
  END IF;

  -- Check 3 : WARNING si PREV = 0 et EFF > 0 (cas exotique D3)
  IF v_duree_previsionnelle = 0 AND v_duree_effective > 0 THEN
    RAISE WARNING 'fn_verifier_pre_facturation mission=% : PREV=0 EFF=%h — mission sans prévisionnel saisi, facturation effectif.',
      p_mission_id, v_duree_effective;
  END IF;

  -- Source de facturation = celle qui porte la durée GREATEST
  v_source := CASE WHEN v_duree_effective > v_duree_previsionnelle THEN 'EFFECTIF' ELSE 'PREVISIONNEL' END;

  RETURN jsonb_build_object(
    'ok', true,
    'source_facturation', v_source,
    'duree_previsionnelle', v_duree_previsionnelle,
    'duree_effective', v_duree_effective,
    'duree_facturee', GREATEST(v_duree_previsionnelle, v_duree_effective),
    'ecart_heures', v_ecart_heures,
    'ecart_pourcent', v_ecart_pourcent,
    'nb_creneaux_effectif_fermes', v_nb_effectif_ferme
  );
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- GRANTs (preserve existing)
-- ──────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.fn_verifier_pre_facturation(uuid)
  TO authenticated, service_role;
