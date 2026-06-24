-- Règle métier EXPLICITE : le soignant est rémunéré (et l'établissement facturé) sur
-- un PLANCHER = les heures PRÉVISIONNELLES planifiées, et davantage si l'effectif
-- pointé les dépasse.
--
--   heures facturées = GREATEST(prévisionnel hors pause, effectif hors pause)
--
-- Autrement dit : si le soignant travaille MOINS que prévu, il touche quand même le
-- planifié (plancher garanti) ; s'il travaille PLUS, il touche le réel.
--
-- Avant : incohérence entre les bases —
--   - duree_heures / bulletin : COALESCE(effectif, prévisionnel) = effectif si pointé
--     (pas de plancher → soignant payé moins s'il partait tôt)
--   - fn_calculer_montant_periode (hebdo) + fn_verifier_pre_facturation : GREATEST
--     (plancher) — déjà correct
-- On aligne TOUT sur GREATEST (plancher prévisionnel), pauses toujours exclues (fix #679).

-- 1. fn_sync_mission_creneaux : duree_heures = GREATEST(effectif, prévisionnel) hors pause.
CREATE OR REPLACE FUNCTION public.fn_sync_mission_creneaux()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission_id uuid;
  v_old_mission_id uuid;
  v_debut timestamptz;
  v_fin timestamptz;
  v_duree numeric;
  v_nb integer;
  v_debut_eff timestamptz;
  v_fin_eff timestamptz;
  v_duree_eff numeric;
  v_duree_phase2 numeric;
BEGIN
  IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
    RETURN NULL;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_mission_id := OLD.mission_id;
    v_old_mission_id := NULL;
  ELSIF TG_OP = 'UPDATE' AND OLD.mission_id IS DISTINCT FROM NEW.mission_id THEN
    v_mission_id := NEW.mission_id;
    v_old_mission_id := OLD.mission_id;
  ELSE
    v_mission_id := NEW.mission_id;
    v_old_mission_id := NULL;
  END IF;

  SELECT MIN(debut), MAX(fin),
    COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0),
    COUNT(*)
  INTO v_debut, v_fin, v_duree, v_nb
  FROM mission_creneaux
  WHERE mission_id = v_mission_id AND type_creneau = 'PREVISIONNEL';

  SELECT MIN(debut), MAX(fin),
    COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
  INTO v_debut_eff, v_fin_eff, v_duree_eff
  FROM mission_creneaux
  WHERE mission_id = v_mission_id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;

  IF v_duree_eff = 0 AND v_debut_eff IS NULL THEN
    v_duree_eff := NULL;
  END IF;

  -- PLANCHER PRÉVISIONNEL : on facture le max(prévisionnel, effectif).
  v_duree_phase2 := GREATEST(COALESCE(v_duree_eff, 0), COALESCE(v_duree, 0));

  PERFORM set_config('jolene.sync_in_progress', 'true', true);
  IF v_nb > 0 THEN
    UPDATE missions SET debut_le = v_debut, fin_le = v_fin, nb_creneaux = v_nb
    WHERE id = v_mission_id;
  ELSE
    UPDATE missions SET nb_creneaux = 0 WHERE id = v_mission_id;
  END IF;
  PERFORM set_config('jolene.sync_in_progress', 'false', true);

  IF v_nb > 0 OR v_duree_eff IS NOT NULL THEN
    UPDATE missions SET
      duree_heures = ROUND(v_duree_phase2::numeric, 2),
      debut_effectif = v_debut_eff,
      fin_effective = v_fin_eff,
      duree_heures_effective = CASE WHEN v_duree_eff IS NOT NULL THEN ROUND(v_duree_eff::numeric, 2) ELSE NULL END
    WHERE id = v_mission_id;
  ELSE
    UPDATE missions SET
      duree_heures = NULL, debut_effectif = NULL, fin_effective = NULL, duree_heures_effective = NULL
    WHERE id = v_mission_id;
  END IF;

  IF v_old_mission_id IS NOT NULL THEN
    SELECT MIN(debut), MAX(fin),
      COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0),
      COUNT(*)
    INTO v_debut, v_fin, v_duree, v_nb
    FROM mission_creneaux
    WHERE mission_id = v_old_mission_id AND type_creneau = 'PREVISIONNEL';

    SELECT MIN(debut), MAX(fin),
      COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
    INTO v_debut_eff, v_fin_eff, v_duree_eff
    FROM mission_creneaux
    WHERE mission_id = v_old_mission_id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;

    IF v_duree_eff = 0 AND v_debut_eff IS NULL THEN
      v_duree_eff := NULL;
    END IF;
    v_duree_phase2 := GREATEST(COALESCE(v_duree_eff, 0), COALESCE(v_duree, 0));

    PERFORM set_config('jolene.sync_in_progress', 'true', true);
    IF v_nb > 0 THEN
      UPDATE missions SET debut_le = v_debut, fin_le = v_fin, nb_creneaux = v_nb
      WHERE id = v_old_mission_id;
    ELSE
      UPDATE missions SET nb_creneaux = 0 WHERE id = v_old_mission_id;
    END IF;
    PERFORM set_config('jolene.sync_in_progress', 'false', true);

    IF v_nb > 0 OR v_duree_eff IS NOT NULL THEN
      UPDATE missions SET
        duree_heures = ROUND(v_duree_phase2::numeric, 2),
        debut_effectif = v_debut_eff,
        fin_effective = v_fin_eff,
        duree_heures_effective = CASE WHEN v_duree_eff IS NOT NULL THEN ROUND(v_duree_eff::numeric, 2) ELSE NULL END
      WHERE id = v_old_mission_id;
    ELSE
      UPDATE missions SET
        duree_heures = NULL, debut_effectif = NULL, fin_effective = NULL, duree_heures_effective = NULL
      WHERE id = v_old_mission_id;
    END IF;
  END IF;

  RETURN NULL;
END;
$function$;

-- 2. dec_calculer_finance_mission : choisit le jeu de créneaux (EFFECTIF vs PREVISIONNEL)
--    qui a le PLUS d'heures hors pause (= plancher prévisionnel), puis calcule la
--    rémunération + majorations sur ce jeu. Fallback span si aucun créneau.
CREATE OR REPLACE FUNCTION public.dec_calculer_finance_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_taux_effectif NUMERIC;
    v_calcul JSONB;
    v_c RECORD;
    v_sum_prev NUMERIC := 0;
    v_sum_eff NUMERIC := 0;
    v_use_effectif BOOLEAN;
    v_h_nuit NUMERIC := 0; v_h_dim NUMERIC := 0; v_h_fer NUMERIC := 0;
    v_m_nuit NUMERIC := 0; v_m_dim NUMERIC := 0; v_m_fer NUMERIC := 0;
    v_brut NUMERIC := 0;
    v_ifm NUMERIC := 0; v_icp NUMERIC := 0; v_taux_ifm NUMERIC := 0; v_taux_icp NUMERIC := 0;
BEGIN
    v_taux_effectif := COALESCE(NEW.taux_rist_plafonne, NEW.taux_horaire_base);

    SELECT COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
      INTO v_sum_prev FROM mission_creneaux
      WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND fin IS NOT NULL;
    SELECT COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
      INTO v_sum_eff FROM mission_creneaux
      WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;

    -- PLANCHER : on n'utilise l'effectif QUE s'il dépasse le prévisionnel.
    v_use_effectif := v_sum_eff > v_sum_prev;

    IF v_sum_prev > 0 OR v_sum_eff > 0 THEN
        FOR v_c IN
            SELECT debut, fin FROM mission_creneaux
            WHERE mission_id = NEW.id AND NOT est_pause AND fin IS NOT NULL
              AND type_creneau = CASE WHEN v_use_effectif THEN 'EFFECTIF' ELSE 'PREVISIONNEL' END
            ORDER BY debut
        LOOP
            v_calcul := fn_calculer_remuneration_mission(
                v_c.debut, v_c.fin, v_taux_effectif, NEW.etablissement_id, NEW.soignant_assigne_id);
            v_h_nuit := v_h_nuit + (v_calcul->>'heures_nuit')::NUMERIC;
            v_h_dim  := v_h_dim  + (v_calcul->>'heures_dimanche')::NUMERIC;
            v_h_fer  := v_h_fer  + (v_calcul->>'heures_ferie')::NUMERIC;
            v_m_nuit := v_m_nuit + (v_calcul->>'montant_majoration_nuit')::NUMERIC;
            v_m_dim  := v_m_dim  + (v_calcul->>'montant_majoration_dimanche')::NUMERIC;
            v_m_fer  := v_m_fer  + (v_calcul->>'montant_majoration_ferie')::NUMERIC;
            v_brut   := v_brut   + (v_calcul->>'total_brut')::NUMERIC;
            v_taux_ifm := (v_calcul->>'taux_ifm')::NUMERIC;
            v_taux_icp := (v_calcul->>'taux_icp')::NUMERIC;
        END LOOP;

        v_ifm := ROUND(v_brut * v_taux_ifm, 2);
        v_icp := ROUND((v_brut + v_ifm) * v_taux_icp, 2);

        NEW.heures_nuit                := ROUND(v_h_nuit, 2);
        NEW.heures_dimanche            := ROUND(v_h_dim, 2);
        NEW.heures_ferie               := ROUND(v_h_fer, 2);
        NEW.montant_majoration_nuit    := ROUND(v_m_nuit, 2);
        NEW.montant_majoration_dimanche:= ROUND(v_m_dim, 2);
        NEW.montant_majoration_ferie   := ROUND(v_m_fer, 2);
        NEW.total_brut                 := ROUND(v_brut, 2);
        NEW.taux_ifm                   := v_taux_ifm;
        NEW.montant_ifm                := v_ifm;
        NEW.taux_icp                   := v_taux_icp;
        NEW.montant_icp                := v_icp;
        NEW.net_a_payer                := ROUND(v_brut + v_ifm + v_icp, 2);
    ELSE
        v_calcul := fn_calculer_remuneration_mission(
            NEW.debut_le, NEW.fin_le, v_taux_effectif, NEW.etablissement_id, NEW.soignant_assigne_id);
        NEW.heures_nuit                := (v_calcul->>'heures_nuit')::NUMERIC;
        NEW.heures_dimanche            := (v_calcul->>'heures_dimanche')::NUMERIC;
        NEW.heures_ferie               := (v_calcul->>'heures_ferie')::NUMERIC;
        NEW.montant_majoration_nuit    := (v_calcul->>'montant_majoration_nuit')::NUMERIC;
        NEW.montant_majoration_dimanche:= (v_calcul->>'montant_majoration_dimanche')::NUMERIC;
        NEW.montant_majoration_ferie   := (v_calcul->>'montant_majoration_ferie')::NUMERIC;
        NEW.total_brut                 := (v_calcul->>'total_brut')::NUMERIC;
        NEW.taux_ifm                   := (v_calcul->>'taux_ifm')::NUMERIC;
        NEW.montant_ifm                := (v_calcul->>'montant_ifm')::NUMERIC;
        NEW.taux_icp                   := (v_calcul->>'taux_icp')::NUMERIC;
        NEW.montant_icp                := (v_calcul->>'montant_icp')::NUMERIC;
        NEW.net_a_payer                := (v_calcul->>'net_a_payer')::NUMERIC;
    END IF;

    RETURN NEW;
END;
$function$;
