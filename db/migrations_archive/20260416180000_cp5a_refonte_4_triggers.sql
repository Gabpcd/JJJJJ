-- ============================================================
-- CP5a Step 4 — Refonte 4 triggers span → créneaux
-- ============================================================
-- 4a: fn_trg_auto_heures_majorees (créneaux + _fige + TZ)
-- 4b: dec_refuser_chevauchement_soignant (NO CHANGE — D1 span)
-- 4c: dec_verifier_plafond_48h (créneaux non-pause)
-- 4d: dec_verifier_repos_11h (créneaux non-pause)
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 4a. fn_trg_auto_heures_majorees — refonte créneaux + _fige
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
BEGIN
  IF NEW.debut_le IS NULL OR NEW.fin_le IS NULL THEN
    RETURN NEW;
  END IF;

  -- Night hours from _fige (COALESCE etab, default)
  SELECT
    COALESCE(NEW.heure_debut_nuit_fige, e.heure_debut_nuit, '21:00'::time),
    COALESCE(NEW.heure_fin_nuit_fige, e.heure_fin_nuit, '06:00'::time)
  INTO v_h_debut_nuit, v_h_fin_nuit
  FROM etablissements e WHERE e.id = NEW.etablissement_id;

  IF NOT FOUND THEN
    v_h_debut_nuit := '21:00'::time;
    v_h_fin_nuit := '06:00'::time;
  END IF;

  FOR v_creneau IN
    SELECT debut, fin FROM mission_creneaux
    WHERE mission_id = NEW.id AND NOT est_pause
  LOOP
    v_cursor := v_creneau.debut;
    WHILE v_cursor < v_creneau.fin LOOP
      v_local_time := (v_cursor AT TIME ZONE 'Europe/Paris')::time;
      v_dow := EXTRACT(DOW FROM (v_cursor AT TIME ZONE 'Europe/Paris'));
      v_date := (v_cursor AT TIME ZONE 'Europe/Paris')::date;

      -- Night: configurable hours (typically 21:00→06:00, spans midnight)
      IF v_h_debut_nuit > v_h_fin_nuit THEN
        IF v_local_time >= v_h_debut_nuit OR v_local_time < v_h_fin_nuit THEN
          v_nuit := v_nuit + 0.5;
        END IF;
      ELSE
        IF v_local_time >= v_h_debut_nuit AND v_local_time < v_h_fin_nuit THEN
          v_nuit := v_nuit + 0.5;
        END IF;
      END IF;

      IF v_dow = 0 THEN
        v_dim := v_dim + 0.5;
      END IF;

      IF EXISTS (SELECT 1 FROM jours_feries_fr WHERE date_ferie = v_date) THEN
        v_fer := v_fer + 0.5;
      END IF;

      v_cursor := v_cursor + v_step;
    END LOOP;
  END LOOP;

  NEW.heures_nuit := v_nuit;
  NEW.heures_dimanche := v_dim;
  NEW.heures_ferie := v_fer;

  RETURN NEW;
END;
$$;

-- Fix fn_calculer_heures_majorees volatility (IMMUTABLE → STABLE, reads jours_feries_fr)
ALTER FUNCTION public.fn_calculer_heures_majorees(timestamptz, timestamptz) SET search_path TO 'public';
DO $$ BEGIN
  EXECUTE 'ALTER FUNCTION public.fn_calculer_heures_majorees(timestamptz, timestamptz) VOLATILE';
EXCEPTION WHEN others THEN NULL;
END $$;

-- ──────────────────────────────────────────────────────────────
-- 4b. dec_refuser_chevauchement_soignant — NO CHANGE
-- ──────────────────────────────────────────────────────────────
-- D1: Le span [debut_le, fin_le] bloque tout chevauchement.
-- Pas de finesse créneau-par-créneau. Si mission A = 7h–19h
-- (avec pause 12h–14h), mission B à 13h est REFUSÉE même si
-- le soignant est en pause. Décision produit validée.
-- Code inchangé.

-- ──────────────────────────────────────────────────────────────
-- 4c. dec_verifier_plafond_48h — refonte créneaux non-pause
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
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = NEW.soignant_assigne_id;
  IF v_soignant.type_exercice = 'LIBERAL' THEN RETURN NEW; END IF;

  v_semaine_debut := date_trunc('week', NEW.debut_le)::date;

  -- Heures effectives de cette mission (créneaux non-pause)
  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (mc.fin - mc.debut)) / 3600.0), 0)
  INTO v_heures_mission
  FROM mission_creneaux mc
  WHERE mc.mission_id = NEW.id AND NOT mc.est_pause;

  -- Fallback si pas encore de créneaux (INSERT avant création créneaux)
  IF v_heures_mission = 0 THEN
    v_heures_mission := COALESCE(NEW.duree_heures, EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0, 0);
  END IF;

  -- Heures effectives des autres missions cette semaine (créneaux non-pause)
  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (mc.fin - mc.debut)) / 3600.0), 0)
  INTO v_heures_jolene
  FROM mission_creneaux mc
  JOIN missions m ON m.id = mc.mission_id
  WHERE m.soignant_assigne_id = NEW.soignant_assigne_id
    AND m.id != NEW.id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND mc.debut >= v_semaine_debut::timestamptz
    AND mc.debut < (v_semaine_debut + 7)::timestamptz
    AND NOT mc.est_pause;

  -- Heures déclarées ailleurs
  SELECT COALESCE(heures_salarie, 0) INTO v_heures_externes
  FROM attestations_heures_externes
  WHERE soignant_id = NEW.soignant_assigne_id
    AND semaine_du = v_semaine_debut;

  IF NOT FOUND THEN v_heures_externes := 0; END IF;

  v_heures_total := v_heures_jolene + v_heures_externes + v_heures_mission;

  IF v_heures_total > 48 THEN
    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'VIOLATION_BLOQUEE',
      jsonb_build_object(
        'heures_jolene', ROUND(v_heures_jolene + v_heures_mission, 2),
        'heures_externes', ROUND(v_heures_externes, 2),
        'total', ROUND(v_heures_total, 2),
        'plafond', 48,
        'article', 'L3121-20'
      ));
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
-- 4d. dec_verifier_repos_11h — refonte créneaux non-pause
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_verifier_repos_11h()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_fin_prev_work timestamptz;
  v_debut_this_work timestamptz;
  v_fin_this_work timestamptz;
  v_debut_next_work timestamptz;
  v_ecart numeric;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  -- Actual start/end of work for THIS mission (non-pause créneaux)
  SELECT MIN(mc.debut), MAX(mc.fin)
  INTO v_debut_this_work, v_fin_this_work
  FROM mission_creneaux mc
  WHERE mc.mission_id = NEW.id AND NOT mc.est_pause;

  -- Fallback if no créneaux yet
  IF v_debut_this_work IS NULL THEN
    v_debut_this_work := NEW.debut_le;
    v_fin_this_work := NEW.fin_le;
  END IF;

  -- Previous mission: latest end of actual work (non-pause créneau)
  SELECT MAX(mc.fin) INTO v_fin_prev_work
  FROM missions m
  JOIN mission_creneaux mc ON mc.mission_id = m.id AND NOT mc.est_pause
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

  -- Next mission: earliest start of actual work (non-pause créneau)
  SELECT MIN(mc.debut) INTO v_debut_next_work
  FROM missions m
  JOIN mission_creneaux mc ON mc.mission_id = m.id AND NOT mc.est_pause
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
