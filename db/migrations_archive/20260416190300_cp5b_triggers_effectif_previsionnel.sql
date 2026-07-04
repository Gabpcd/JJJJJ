-- ============================================================
-- CP5b Step 4 — Update 3 triggers with COALESCE EFFECTIF/PREVISIONNEL
-- ============================================================
-- 4a. fn_calculer_financier_mission
-- 4b. fn_trg_auto_heures_majorees
-- 4c. dec_verifier_plafond_48h + dec_verifier_repos_11h
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 4a. fn_calculer_financier_mission
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
  -- COALESCE: EFFECTIF closed non-pause, else PREVISIONNEL non-pause, else 0
  SELECT COALESCE(
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause),
    SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause),
    0
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

-- Extend trigger WHEN OF to include duree_heures
-- So auto_heures fires when sync Phase 2 updates duree_heures from EFFECTIF changes
DROP TRIGGER IF EXISTS trg_auto_heures_majorees ON public.missions;
CREATE TRIGGER trg_auto_heures_majorees
  BEFORE INSERT OR UPDATE OF debut_le, fin_le, duree_heures
  ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION fn_trg_auto_heures_majorees();

-- ──────────────────────────────────────────────────────────────
-- 4b. fn_trg_auto_heures_majorees — iterate EFFECTIF if exists, else PREVISIONNEL
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

  -- Choose source: EFFECTIF if closed créneaux exist, else PREVISIONNEL
  IF EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL) THEN
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
-- 4c. dec_verifier_plafond_48h — EFFECTIF/PREVISIONNEL per mission
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_verifier_plafond_48h()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_heures_mission numeric;
  v_heures_jolene numeric;
  v_heures_externes numeric;
  v_heures_total numeric;
  v_soignant RECORD;
  v_semaine_debut date;
  v_use_effectif boolean;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = NEW.soignant_assigne_id;
  IF v_soignant.type_exercice = 'LIBERAL' THEN RETURN NEW; END IF;

  v_semaine_debut := date_trunc('week', NEW.debut_le)::date;

  -- Current mission: EFFECTIF closed if exists, else PREVISIONNEL
  v_use_effectif := EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL);

  IF v_use_effectif THEN
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0) INTO v_heures_mission
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause;
  ELSE
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0) INTO v_heures_mission
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND NOT est_pause;
  END IF;

  IF v_heures_mission = 0 AND NOT EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id) THEN
    v_heures_mission := COALESCE(NEW.duree_heures, EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0, 0);
  END IF;

  -- Other missions this week: EFFECTIF per mission if closed créneaux exist
  SELECT COALESCE(SUM(
    CASE
      WHEN EXISTS (SELECT 1 FROM mission_creneaux mc2 WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL)
      THEN (SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (mc3.fin - mc3.debut)) / 3600.0), 0)
            FROM mission_creneaux mc3 WHERE mc3.mission_id = m.id AND mc3.type_creneau = 'EFFECTIF' AND mc3.fin IS NOT NULL AND NOT mc3.est_pause)
      ELSE (SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (mc4.fin - mc4.debut)) / 3600.0), 0)
            FROM mission_creneaux mc4 WHERE mc4.mission_id = m.id AND mc4.type_creneau = 'PREVISIONNEL' AND NOT mc4.est_pause)
    END
  ), 0) INTO v_heures_jolene
  FROM missions m
  WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
    AND m.id != NEW.id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND m.debut_le >= v_semaine_debut::timestamptz
    AND m.debut_le < (v_semaine_debut + 7)::timestamptz;

  SELECT COALESCE(heures_salarie, 0) INTO v_heures_externes
  FROM attestations_heures_externes
  WHERE soignant_id = NEW.soignant_assigne_id AND semaine_du = v_semaine_debut;
  IF NOT FOUND THEN v_heures_externes := 0; END IF;

  v_heures_total := v_heures_jolene + v_heures_externes + v_heures_mission;

  IF v_heures_total > 48 THEN
    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'VIOLATION_BLOQUEE',
      jsonb_build_object('heures_jolene', ROUND(v_heures_jolene + v_heures_mission, 2),
        'heures_externes', ROUND(v_heures_externes, 2), 'total', ROUND(v_heures_total, 2),
        'plafond', 48, 'article', 'L3121-20'));
    RAISE EXCEPTION '[CODE DU TRAVAIL] Plafond hebdomadaire dépassé : %h Jolene + %h ailleurs = %h total (max 48h, Art. L3121-20)',
      ROUND(v_heures_jolene + v_heures_mission, 1), ROUND(v_heures_externes, 1), ROUND(v_heures_total, 1);
  END IF;

  INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
  VALUES (NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'CONFORME',
    jsonb_build_object('total_heures', ROUND(v_heures_total, 2)));
  RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 4c bis. dec_verifier_repos_11h — EFFECTIF/PREVISIONNEL per mission
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_verifier_repos_11h()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_fin_prev_work timestamptz;
  v_debut_this_work timestamptz;
  v_fin_this_work timestamptz;
  v_debut_next_work timestamptz;
  v_ecart numeric;
  v_use_effectif boolean;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  -- Current mission: EFFECTIF closed if exists, else PREVISIONNEL
  v_use_effectif := EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL);

  IF v_use_effectif THEN
    SELECT MIN(debut), MAX(fin) INTO v_debut_this_work, v_fin_this_work
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause;
  ELSE
    SELECT MIN(debut), MAX(fin) INTO v_debut_this_work, v_fin_this_work
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND NOT est_pause;
  END IF;

  IF v_debut_this_work IS NULL THEN
    v_debut_this_work := NEW.debut_le;
    v_fin_this_work := NEW.fin_le;
  END IF;

  -- Previous mission: use EFFECTIF if exists else PREVISIONNEL
  SELECT MAX(
    CASE
      WHEN EXISTS (SELECT 1 FROM mission_creneaux mc2 WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL)
      THEN (SELECT MAX(mc3.fin) FROM mission_creneaux mc3 WHERE mc3.mission_id = m.id AND mc3.type_creneau = 'EFFECTIF' AND mc3.fin IS NOT NULL AND NOT mc3.est_pause)
      ELSE (SELECT MAX(mc4.fin) FROM mission_creneaux mc4 WHERE mc4.mission_id = m.id AND mc4.type_creneau = 'PREVISIONNEL' AND NOT mc4.est_pause)
    END
  ) INTO v_fin_prev_work
  FROM missions m
  WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
    AND m.id != NEW.id
    AND m.fin_le <= NEW.debut_le
    AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE');

  IF v_fin_prev_work IS NOT NULL THEN
    v_ecart := EXTRACT(EPOCH FROM (v_debut_this_work - v_fin_prev_work)) / 3600.0;
    IF v_ecart < 11.0 THEN
      INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
      VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'VIOLATION_BLOQUEE',
        jsonb_build_object('ecart_heures', ROUND(v_ecart, 2), 'minimum_requis', 11, 'sens', 'avant', 'article', 'L3131-1'));
      RAISE EXCEPTION '[CODE DU TRAVAIL] Repos insuffisant avant mission : % heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.', ROUND(v_ecart, 1);
    END IF;
  END IF;

  -- Next mission: use EFFECTIF if exists else PREVISIONNEL
  SELECT MIN(
    CASE
      WHEN EXISTS (SELECT 1 FROM mission_creneaux mc2 WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL)
      THEN (SELECT MIN(mc3.debut) FROM mission_creneaux mc3 WHERE mc3.mission_id = m.id AND mc3.type_creneau = 'EFFECTIF' AND mc3.fin IS NOT NULL AND NOT mc3.est_pause)
      ELSE (SELECT MIN(mc4.debut) FROM mission_creneaux mc4 WHERE mc4.mission_id = m.id AND mc4.type_creneau = 'PREVISIONNEL' AND NOT mc4.est_pause)
    END
  ) INTO v_debut_next_work
  FROM missions m
  WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
    AND m.id != NEW.id
    AND m.debut_le >= NEW.fin_le
    AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE');

  IF v_debut_next_work IS NOT NULL THEN
    v_ecart := EXTRACT(EPOCH FROM (v_debut_next_work - v_fin_this_work)) / 3600.0;
    IF v_ecart < 11.0 THEN
      INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
      VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'VIOLATION_BLOQUEE',
        jsonb_build_object('ecart_heures', ROUND(v_ecart, 2), 'minimum_requis', 11, 'sens', 'apres', 'article', 'L3131-1'));
      RAISE EXCEPTION '[CODE DU TRAVAIL] Repos insuffisant après mission : % heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.', ROUND(v_ecart, 1);
    END IF;
  END IF;

  INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat)
  VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'CONFORME');
  RETURN NEW;
END;
$$;
