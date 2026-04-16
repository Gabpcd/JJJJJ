-- ============================================================
-- Sub-PR 1 / CP3 Fix — Targeted bypass for sync_in_progress
-- ============================================================
-- POST-MORTEM CP3: The original bypass did RETURN NEW immediately,
-- skipping ALL protections. This let financial recalculation triggers
-- persist unwanted changes. Fix: freeze financial fields to OLD
-- while allowing timing fields (debut_le, fin_le, duree_heures,
-- nb_creneaux) to pass through.
--
-- Also adds: trg_protect_creneaux_facture to block créneau
-- modifications on missions with emitted invoices.
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. dec_proteger_mission_soignant — targeted bypass
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_proteger_mission_soignant()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
        -- During sync: ALLOW timing fields, FREEZE everything else
        NEW.soignant_assigne_id := OLD.soignant_assigne_id;
        NEW.taux_horaire_base := OLD.taux_horaire_base;
        NEW.total_brut := OLD.total_brut;
        NEW.net_a_payer := OLD.net_a_payer;
        NEW.net_estime := OLD.net_estime;
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
        NEW.commission_facturee := OLD.commission_facturee;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.intitule := OLD.intitule;
        NEW.description := OLD.description;
        NEW.profession_requise := OLD.profession_requise;
        NEW.service := OLD.service;
        NEW.est_urgente := OLD.est_urgente;
        NEW.niveau_urgence := OLD.niveau_urgence;
        NEW.mode_attribution := OLD.mode_attribution;
        NEW.type_contrat_recherche := OLD.type_contrat_recherche;
        NEW.statut := OLD.statut;
        -- debut_le, fin_le, duree_heures, nb_creneaux: NOT frozen (sync writes these)
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
-- 2. fn_protect_mission_financials — targeted bypass
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_protect_mission_financials()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
        -- During sync: FREEZE all financial fields, allow timing
        NEW.taux_horaire_base := OLD.taux_horaire_base;
        NEW.total_brut := OLD.total_brut;
        NEW.net_a_payer := OLD.net_a_payer;
        NEW.net_estime := OLD.net_estime;
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
        NEW.commission_facturee := OLD.commission_facturee;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.profession_requise := OLD.profession_requise;
        -- debut_le, fin_le, duree_heures, nb_creneaux: NOT frozen
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
-- 3. dec_bloquer_modif_apres_acceptation — targeted bypass
--    (only skip timing check, keep taux_horaire check)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_bloquer_modif_apres_acceptation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF OLD.statut != 'OUVERTE' AND NOT est_admin() THEN
        IF OLD.taux_horaire_base IS DISTINCT FROM NEW.taux_horaire_base THEN
            RAISE EXCEPTION 'Le taux horaire ne peut plus être modifié après acceptation.';
        END IF;
        -- Skip timing check during sync (debut_le/fin_le legitimately change)
        IF current_setting('jolene.sync_in_progress', true) != 'true' THEN
            IF OLD.debut_le IS DISTINCT FROM NEW.debut_le OR OLD.fin_le IS DISTINCT FROM NEW.fin_le THEN
                RAISE EXCEPTION 'Les horaires ne peuvent plus être modifiés après acceptation.';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 4. New trigger: block créneau changes on facturée missions
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_protect_creneaux_si_facture()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_mission_id uuid;
  v_has_facture boolean;
  v_correction_mission uuid;
  v_correction_reason text;
BEGIN
  v_mission_id := COALESCE(NEW.mission_id, OLD.mission_id);

  SELECT EXISTS (
    SELECT 1 FROM factures_honoraires
    WHERE mission_id = v_mission_id
      AND statut NOT IN ('BROUILLON', 'ANNULEE')
  ) INTO v_has_facture;

  IF NOT v_has_facture THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  -- Facture exists → check for traced admin correction override
  v_correction_mission := NULLIF(current_setting('jolene.admin_correction_mission_id', true), '')::uuid;
  v_correction_reason := NULLIF(current_setting('jolene.admin_correction_reason', true), '');

  IF v_correction_mission = v_mission_id AND v_correction_reason IS NOT NULL THEN
    -- Admin correction with traced reason → allow and audit
    INSERT INTO invoice_audit_log (invoice_id, action, performed_by, payload_before)
    SELECT fh.id, 'CRENEAUX_MODIFIED_POST_FACTURE', auth.uid(),
      jsonb_build_object(
        'reason', v_correction_reason,
        'mission_id', v_mission_id,
        'operation', TG_OP,
        'creneau_id', COALESCE(NEW.id, OLD.id)
      )
    FROM factures_honoraires fh
    WHERE fh.mission_id = v_mission_id AND fh.statut NOT IN ('BROUILLON', 'ANNULEE')
    LIMIT 1;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  RAISE EXCEPTION 'Impossible de modifier les créneaux : une facture émise existe pour cette mission (mission_id=%). Pour corriger, un admin doit définir jolene.admin_correction_mission_id et jolene.admin_correction_reason.',
    v_mission_id USING ERRCODE = 'check_violation';
END;
$$;

CREATE TRIGGER trg_protect_creneaux_facture
  BEFORE INSERT OR UPDATE OR DELETE ON public.mission_creneaux
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_protect_creneaux_si_facture();
