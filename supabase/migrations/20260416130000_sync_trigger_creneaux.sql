-- ============================================================
-- Sub-PR 1 / Checkpoint 2
-- Trigger sync: mission_creneaux → missions
-- Maintains: debut_le, fin_le, duree_heures, nb_creneaux
-- Also: fix dec_bloquer_modif_apres_acceptation to allow sync
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 0. Convert duree_heures from GENERATED to regular column
-- ──────────────────────────────────────────────────────────────
-- duree_heures was GENERATED ALWAYS AS (EXTRACT(epoch FROM (fin_le - debut_le)) / 3600.0).
-- This prevents direct UPDATE. We need to SET it from the sync trigger (sum of non-pause créneaux).
-- DROP EXPRESSION preserves existing computed values but makes it a regular stored column.
ALTER TABLE public.missions ALTER COLUMN duree_heures DROP EXPRESSION IF EXISTS;

-- ──────────────────────────────────────────────────────────────
-- 1. Fix dec_bloquer_modif_apres_acceptation: skip during sync
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_bloquer_modif_apres_acceptation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- Allow sync trigger to update debut_le/fin_le without blocking
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF OLD.statut != 'OUVERTE' AND NOT est_admin() THEN
        IF OLD.taux_horaire_base IS DISTINCT FROM NEW.taux_horaire_base THEN
            RAISE EXCEPTION 'Le taux horaire ne peut plus être modifié après acceptation.';
        END IF;
        IF OLD.debut_le IS DISTINCT FROM NEW.debut_le OR OLD.fin_le IS DISTINCT FROM NEW.fin_le THEN
            RAISE EXCEPTION 'Les horaires ne peuvent plus être modifiés après acceptation.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 1b. Fix dec_proteger_mission_soignant: skip during sync
-- ──────────────────────────────────────────────────────────────
-- Without this, the protection trigger reverts debut_le/fin_le/duree_heures
-- to OLD values when the sync UPDATE fires in a non-admin context.
CREATE OR REPLACE FUNCTION public.dec_proteger_mission_soignant()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF NOT est_admin() AND NOT est_admin_etablissement() THEN
        NEW.soignant_assigne_id := OLD.soignant_assigne_id;
        NEW.taux_horaire_base := OLD.taux_horaire_base;
        NEW.total_brut := OLD.total_brut;
        NEW.net_a_payer := OLD.net_a_payer;
        NEW.montant_ifm := OLD.montant_ifm;
        NEW.montant_icp := OLD.montant_icp;
        NEW.montant_majoration_nuit := OLD.montant_majoration_nuit;
        NEW.montant_majoration_dimanche := OLD.montant_majoration_dimanche;
        NEW.montant_majoration_ferie := OLD.montant_majoration_ferie;
        NEW.taux_commission := OLD.taux_commission;
        NEW.montant_commission_ht := OLD.montant_commission_ht;
        NEW.montant_commission_tva := OLD.montant_commission_tva;
        NEW.montant_commission_ttc := OLD.montant_commission_ttc;
        NEW.duree_heures := OLD.duree_heures;
        NEW.heures_nuit := OLD.heures_nuit;
        NEW.heures_dimanche := OLD.heures_dimanche;
        NEW.heures_ferie := OLD.heures_ferie;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.intitule := OLD.intitule;
        NEW.description := OLD.description;
        NEW.profession_requise := OLD.profession_requise;
        NEW.service := OLD.service;
        NEW.debut_le := OLD.debut_le;
        NEW.fin_le := OLD.fin_le;
        NEW.est_urgente := OLD.est_urgente;
        NEW.niveau_urgence := OLD.niveau_urgence;
        NEW.commission_facturee := OLD.commission_facturee;
        NEW.net_estime := OLD.net_estime;
        NEW.mode_attribution := OLD.mode_attribution;
        NEW.type_contrat_recherche := OLD.type_contrat_recherche;
    END IF;
    RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 1c. Fix fn_protect_mission_financials: skip during sync
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_protect_mission_financials()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
        RETURN NEW;
    END IF;

    IF OLD.soignant_assigne_id = auth.uid()
       AND NOT public.est_admin()
       AND NOT public.est_admin_etablissement() THEN
        NEW.taux_horaire_base := OLD.taux_horaire_base;
        NEW.total_brut := OLD.total_brut;
        NEW.net_a_payer := OLD.net_a_payer;
        NEW.montant_ifm := OLD.montant_ifm;
        NEW.montant_icp := OLD.montant_icp;
        NEW.taux_ifm := OLD.taux_ifm;
        NEW.taux_icp := OLD.taux_icp;
        NEW.montant_majoration_nuit := OLD.montant_majoration_nuit;
        NEW.montant_majoration_dimanche := OLD.montant_majoration_dimanche;
        NEW.montant_majoration_ferie := OLD.montant_majoration_ferie;
        NEW.heures_nuit := OLD.heures_nuit;
        NEW.heures_dimanche := OLD.heures_dimanche;
        NEW.heures_ferie := OLD.heures_ferie;
        NEW.taux_commission := OLD.taux_commission;
        NEW.montant_commission_ht := OLD.montant_commission_ht;
        NEW.montant_commission_tva := OLD.montant_commission_tva;
        NEW.montant_commission_ttc := OLD.montant_commission_ttc;
        NEW.taux_rist_plafonne := OLD.taux_rist_plafonne;
        NEW.rist_plafond_applique := OLD.rist_plafond_applique;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.profession_requise := OLD.profession_requise;
        NEW.duree_heures := OLD.duree_heures;
        NEW.debut_le := OLD.debut_le;
        NEW.fin_le := OLD.fin_le;
    END IF;
    RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 2. Sync trigger function
-- ──────────────────────────────────────────────────────────────
-- 2-PHASE SYNC: Phase 1 (sync guard ON) updates timing envelope (financials frozen).
-- Phase 2 (sync guard OFF) updates duree_heures → triggers fn_calculer_financier freely.
CREATE OR REPLACE FUNCTION public.fn_sync_mission_creneaux()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission_id uuid;
  v_old_mission_id uuid;
  v_debut timestamptz;
  v_fin timestamptz;
  v_duree numeric;
  v_nb integer;
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
  FROM mission_creneaux WHERE mission_id = v_mission_id;

  -- Phase 1: sync guard ON → timing envelope + nb (financials frozen by protectors)
  PERFORM set_config('jolene.sync_in_progress', 'true', true);
  IF v_nb > 0 THEN
    UPDATE missions SET debut_le = v_debut, fin_le = v_fin, nb_creneaux = v_nb
    WHERE id = v_mission_id;
  ELSE
    UPDATE missions SET nb_creneaux = 0 WHERE id = v_mission_id;
  END IF;
  PERFORM set_config('jolene.sync_in_progress', 'false', true);

  -- Phase 2: sync guard OFF → SET duree_heures → triggers fn_calculer_financier freely
  IF v_nb > 0 THEN
    UPDATE missions SET duree_heures = ROUND(v_duree::numeric, 2) WHERE id = v_mission_id;
  ELSE
    UPDATE missions SET duree_heures = NULL WHERE id = v_mission_id;
  END IF;

  IF v_old_mission_id IS NOT NULL THEN
    SELECT MIN(debut), MAX(fin),
      COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0),
      COUNT(*)
    INTO v_debut, v_fin, v_duree, v_nb
    FROM mission_creneaux WHERE mission_id = v_old_mission_id;

    PERFORM set_config('jolene.sync_in_progress', 'true', true);
    IF v_nb > 0 THEN
      UPDATE missions SET debut_le = v_debut, fin_le = v_fin, nb_creneaux = v_nb
      WHERE id = v_old_mission_id;
    ELSE
      UPDATE missions SET nb_creneaux = 0 WHERE id = v_old_mission_id;
    END IF;
    PERFORM set_config('jolene.sync_in_progress', 'false', true);

    IF v_nb > 0 THEN
      UPDATE missions SET duree_heures = ROUND(v_duree::numeric, 2) WHERE id = v_old_mission_id;
    ELSE
      UPDATE missions SET duree_heures = NULL WHERE id = v_old_mission_id;
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 3. Create the trigger
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_sync_creneaux ON public.mission_creneaux;
CREATE TRIGGER trg_sync_creneaux
  AFTER INSERT OR UPDATE OR DELETE ON public.mission_creneaux
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_sync_mission_creneaux();
