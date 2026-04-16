-- ============================================================
-- CP5b Step 2 — Sync trigger + overlap fix for type_creneau
-- ============================================================
-- Maintains 2 sets of denormalized columns on missions:
-- SET PREVISIONNEL: debut_le, fin_le, duree_heures, nb_creneaux
-- SET EFFECTIF: debut_effectif, fin_effective, duree_heures_effective
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_sync_mission_creneaux()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
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

  -- ── Aggregate PREVISIONNEL ──
  SELECT MIN(debut), MAX(fin),
    COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0),
    COUNT(*)
  INTO v_debut, v_fin, v_duree, v_nb
  FROM mission_creneaux
  WHERE mission_id = v_mission_id AND type_creneau = 'PREVISIONNEL';

  -- ── Aggregate EFFECTIF (closed only) ──
  SELECT MIN(debut), MAX(fin),
    COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
  INTO v_debut_eff, v_fin_eff, v_duree_eff
  FROM mission_creneaux
  WHERE mission_id = v_mission_id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;

  -- NULL if no closed EFFECTIF
  IF v_duree_eff = 0 AND v_debut_eff IS NULL THEN
    v_duree_eff := NULL;
  END IF;

  -- Phase 2 duree: EFFECTIF if exist, else PREVISIONNEL (drives fn_calculer_financier)
  v_duree_phase2 := COALESCE(v_duree_eff, v_duree);

  -- ── Phase 1: sync guard ON → PREVISIONNEL envelope ──
  PERFORM set_config('jolene.sync_in_progress', 'true', true);
  IF v_nb > 0 THEN
    UPDATE missions SET debut_le = v_debut, fin_le = v_fin, nb_creneaux = v_nb
    WHERE id = v_mission_id;
  ELSE
    UPDATE missions SET nb_creneaux = 0 WHERE id = v_mission_id;
  END IF;
  PERFORM set_config('jolene.sync_in_progress', 'false', true);

  -- ── Phase 2: sync guard OFF → duree + effective columns ──
  IF v_nb > 0 OR v_duree_eff IS NOT NULL THEN
    UPDATE missions SET
      duree_heures = ROUND(v_duree_phase2::numeric, 2),
      debut_effectif = v_debut_eff,
      fin_effective = v_fin_eff,
      duree_heures_effective = CASE WHEN v_duree_eff IS NOT NULL THEN ROUND(v_duree_eff::numeric, 2) ELSE NULL END
    WHERE id = v_mission_id;
  ELSE
    UPDATE missions SET
      duree_heures = NULL,
      debut_effectif = NULL,
      fin_effective = NULL,
      duree_heures_effective = NULL
    WHERE id = v_mission_id;
  END IF;

  -- ── Handle mission_id change (UPDATE moved créneau to different mission) ──
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
    v_duree_phase2 := COALESCE(v_duree_eff, v_duree);

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
        duree_heures = NULL,
        debut_effectif = NULL,
        fin_effective = NULL,
        duree_heures_effective = NULL
      WHERE id = v_old_mission_id;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- Fix overlap check: only within same type_creneau (PREVISIONNEL vs EFFECTIF can overlap)
CREATE OR REPLACE FUNCTION public.fn_no_overlap_creneaux()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM mission_creneaux
    WHERE mission_id = NEW.mission_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND type_creneau = NEW.type_creneau
      AND NEW.debut < fin AND NEW.fin > debut
  ) THEN
    RAISE EXCEPTION 'Chevauchement de créneaux dans la même mission (type=%)', NEW.type_creneau
      USING ERRCODE = 'exclusion_violation';
  END IF;
  RETURN NEW;
END;
$function$;
