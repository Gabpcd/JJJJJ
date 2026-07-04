-- ============================================================
-- Sub-PR 1 / Checkpoint 4
-- Refonte fn_calculer_financier_mission: use mission_creneaux
-- as source of truth for duree_heures instead of debut_le/fin_le
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. Relax chk_duree_positive: allow 0 (all-pauses case)
--    + add upper bound 168h (1 full week)
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.missions DROP CONSTRAINT IF EXISTS chk_duree_positive;
ALTER TABLE public.missions ADD CONSTRAINT chk_duree_positive
  CHECK (duree_heures IS NULL OR (duree_heures >= 0 AND duree_heures <= 168));

-- ──────────────────────────────────────────────────────────────
-- 2. Refonte fn_calculer_financier_mission
--    ONLY change: step 1 (v_duree calculation)
--    Rest of function (RIST, majorations, IFM, ICP, commission)
--    is identical.
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_calculer_financier_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_duree numeric;
  v_taux_effectif numeric;
  v_brut_base numeric;
  v_total_majorations numeric;
  v_total_brut numeric;
  v_ifm numeric;
  v_icp numeric;
  v_net numeric;
  v_net_estime numeric;
  v_etab record;
  v_commission_taux numeric;
  v_commission_ht numeric;
  v_commission_tva numeric;
  v_commission_ttc numeric;
  v_has_creneaux boolean;
BEGIN
  -- ── Step 1 (CHANGED): Calculate duration from mission_creneaux ──
  -- Source de vérité: somme des créneaux non-pause
  SELECT
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0),
    COUNT(*) > 0
  INTO v_duree, v_has_creneaux
  FROM mission_creneaux
  WHERE mission_id = NEW.id AND NOT est_pause;

  -- Fallback: missions without any créneau (3 ANNULEE >24h, or pre-migration)
  IF NOT v_has_creneaux AND NOT EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id) THEN
    v_duree := COALESCE(NEW.duree_heures,
      EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0);
  END IF;

  NEW.duree_heures := v_duree;

  -- ── Steps 2+ (UNCHANGED): RIST, majorations, IFM, ICP, commission ──

  -- Get establishment data for surcharge rates
  SELECT taux_majoration_nuit_pourcent, taux_majoration_dimanche_pourcent,
         taux_majoration_ferie_pourcent, taux_commission_negocie,
         rist_plafond_actif, rist_taux_base_horaire
  INTO v_etab
  FROM etablissements WHERE id = NEW.etablissement_id;

  -- RIST cap
  v_taux_effectif := NEW.taux_horaire_base;
  IF COALESCE(v_etab.rist_plafond_actif, true) AND NEW.taux_horaire_base > COALESCE(v_etab.rist_taux_base_horaire, 25) THEN
    NEW.rist_plafond_applique := true;
    NEW.taux_rist_plafonne := COALESCE(v_etab.rist_taux_base_horaire, 25);
    v_taux_effectif := NEW.taux_rist_plafonne;
  ELSE
    NEW.rist_plafond_applique := false;
    NEW.taux_rist_plafonne := NULL;
  END IF;

  -- Base gross
  v_brut_base := v_taux_effectif * v_duree;

  -- Surcharges
  NEW.montant_majoration_nuit := ROUND(COALESCE(NEW.heures_nuit, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_nuit_pourcent, 25) / 100.0, 2);
  NEW.montant_majoration_dimanche := ROUND(COALESCE(NEW.heures_dimanche, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_dimanche_pourcent, 50) / 100.0, 2);
  NEW.montant_majoration_ferie := ROUND(COALESCE(NEW.heures_ferie, 0) * v_taux_effectif * COALESCE(v_etab.taux_majoration_ferie_pourcent, 100) / 100.0, 2);

  v_total_majorations := COALESCE(NEW.montant_majoration_nuit, 0) + COALESCE(NEW.montant_majoration_dimanche, 0) + COALESCE(NEW.montant_majoration_ferie, 0);

  -- Total brut = base + majorations
  v_total_brut := ROUND(v_brut_base + v_total_majorations, 2);
  NEW.total_brut := v_total_brut;

  -- IFM and ICP (10% each on total_brut)
  NEW.montant_ifm := ROUND(v_total_brut * COALESCE(NEW.taux_ifm, 0.10), 2);
  NEW.montant_icp := ROUND(v_total_brut * COALESCE(NEW.taux_icp, 0.10), 2);

  -- Net a payer (brut + IFM + ICP)
  v_net := ROUND(v_total_brut + NEW.montant_ifm + NEW.montant_icp, 2);
  NEW.net_a_payer := v_net;

  -- Net estime (after approx 22% social contributions)
  NEW.net_estime := ROUND(v_net * 0.78, 2);

  -- Commission
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
