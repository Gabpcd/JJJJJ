-- AUDIT FONCTIONNEL — FIX BUG CRITIQUE #1
-- fn_calculer_financier_mission appliquait commission Jolene (15% par défaut) sur TOUTES
-- les missions, incluant SALARIE (type_paiement_soignant=BULLETIN_PAIE). Or les missions
-- SALARIE ne doivent JAMAIS générer de commission Jolene (l'établissement paie le soignant
-- directement via bulletin de paie, hors plateforme).
--
-- Impact constaté : 1 mission BULLETIN_PAIE en prod avec 30€ HT de commission appliquée.

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
  v_est_salarie boolean;
BEGIN
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

  -- AUDIT FIX : missions SALARIE → commission = 0 (l'étab paie le soignant en direct)
  v_est_salarie := COALESCE(NEW.type_paiement_soignant::text, '') = 'BULLETIN_PAIE'
                   OR COALESCE(NEW.type_contrat_applique::text, '') = 'SALARIE';

  IF v_est_salarie THEN
    v_commission_taux := 0;
  ELSE
    v_commission_taux := COALESCE(NEW.taux_commission, COALESCE(v_etab.taux_commission_negocie, 15));
  END IF;
  NEW.taux_commission := v_commission_taux;
  v_commission_ht := ROUND(v_total_brut * v_commission_taux / 100.0, 2);
  v_commission_tva := ROUND(v_commission_ht * 0.20, 2);
  v_commission_ttc := ROUND(v_commission_ht + v_commission_tva, 2);
  NEW.montant_commission_ht := v_commission_ht;
  NEW.montant_commission_tva := v_commission_tva;
  NEW.montant_commission_ttc := v_commission_ttc;

  RETURN NEW;
END;
$function$;

-- Réparer les missions SALARIE déjà créées avec commission > 0
UPDATE missions SET
  taux_commission = 0,
  montant_commission_ht = 0,
  montant_commission_tva = 0,
  montant_commission_ttc = 0
WHERE (type_paiement_soignant = 'BULLETIN_PAIE' OR type_contrat_applique = 'SALARIE')
  AND COALESCE(montant_commission_ht, 0) > 0;

NOTIFY pgrst, 'reload schema';
