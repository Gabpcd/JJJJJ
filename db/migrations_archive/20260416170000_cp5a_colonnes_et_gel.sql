-- ============================================================
-- CP5a Step 1 — Colonnes snapshot + trigger de gel + backfill
-- ============================================================
-- Audit: /docs/cp5a-refonte-triggers-et-taux.md
-- Sections: 1.1-1.5 (DDL), 2.4 (trigger), 2.5 (audit)
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. ALTER TABLE etablissements — bornes nuit configurables
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS heure_debut_nuit time DEFAULT '21:00',
  ADD COLUMN IF NOT EXISTS heure_fin_nuit time DEFAULT '06:00';

ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_heure_debut_nuit CHECK (heure_debut_nuit BETWEEN '19:00' AND '23:59'),
  ADD CONSTRAINT chk_heure_fin_nuit CHECK (heure_fin_nuit BETWEEN '04:00' AND '08:00');

-- Planchers légaux sur taux existants (CCN FHP n°2264 art. 82.1/82.2)
ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_taux_maj_nuit_min CHECK (taux_majoration_nuit_pourcent >= 25),
  ADD CONSTRAINT chk_taux_maj_dim_min CHECK (taux_majoration_dimanche_pourcent >= 25),
  ADD CONSTRAINT chk_taux_maj_fer_min CHECK (taux_majoration_ferie_pourcent >= 50);

-- ──────────────────────────────────────────────────────────────
-- 2. ALTER TABLE missions — colonnes snapshot _fige
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS taux_horaire_base_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_nuit_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_dimanche_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_ferie_fige numeric,
  ADD COLUMN IF NOT EXISTS heure_debut_nuit_fige time,
  ADD COLUMN IF NOT EXISTS heure_fin_nuit_fige time,
  ADD COLUMN IF NOT EXISTS taux_commission_fige numeric,
  ADD COLUMN IF NOT EXISTS fige_le timestamptz;

-- ──────────────────────────────────────────────────────────────
-- 3. Trigger de gel — fn_geler_mission_a_assignation
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_geler_mission_a_assignation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_etab RECORD;
  v_champ_modifie text;
BEGIN
  -- ════════════════════════════════════════════════════
  -- BLOC 1 : GEL — transition OUVERTE → ASSIGNEE
  -- ════════════════════════════════════════════════════
  IF OLD.statut = 'OUVERTE' AND NEW.statut = 'ASSIGNEE' THEN
    SELECT
      COALESCE(e.taux_majoration_nuit_pourcent, 25)     AS taux_nuit,
      COALESCE(e.taux_majoration_dimanche_pourcent, 25)  AS taux_dim,
      COALESCE(e.taux_majoration_ferie_pourcent, 50)     AS taux_fer,
      COALESCE(e.heure_debut_nuit, '21:00'::time)        AS h_debut_nuit,
      COALESCE(e.heure_fin_nuit, '06:00'::time)          AS h_fin_nuit,
      COALESCE(e.taux_commission_negocie, 15)             AS taux_comm
    INTO v_etab
    FROM etablissements e
    WHERE e.id = NEW.etablissement_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Établissement % introuvable — impossible de geler la mission.',
        NEW.etablissement_id USING ERRCODE = 'foreign_key_violation';
    END IF;

    NEW.taux_horaire_base_fige        := NEW.taux_horaire_base;
    NEW.taux_majoration_nuit_fige     := v_etab.taux_nuit;
    NEW.taux_majoration_dimanche_fige := v_etab.taux_dim;
    NEW.taux_majoration_ferie_fige    := v_etab.taux_fer;
    NEW.heure_debut_nuit_fige         := v_etab.h_debut_nuit;
    NEW.heure_fin_nuit_fige           := v_etab.h_fin_nuit;
    NEW.taux_commission_fige          := COALESCE(NEW.taux_commission, v_etab.taux_comm);
    NEW.fige_le                       := now();

    RETURN NEW;
  END IF;

  -- ════════════════════════════════════════════════════
  -- BLOC 2 : DEGEL — transition vers OUVERTE
  -- ════════════════════════════════════════════════════
  IF NEW.statut = 'OUVERTE' AND OLD.statut != 'OUVERTE'
     AND OLD.fige_le IS NOT NULL THEN

    INSERT INTO journaux_audit
      (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      auth.uid(), 'SYSTEME', 'DEGEL_APPLIED', 'mission', OLD.id,
      jsonb_build_object(
        'old_snapshot', jsonb_build_object(
          'taux_horaire_base_fige', OLD.taux_horaire_base_fige,
          'taux_majoration_nuit_fige', OLD.taux_majoration_nuit_fige,
          'taux_majoration_dimanche_fige', OLD.taux_majoration_dimanche_fige,
          'taux_majoration_ferie_fige', OLD.taux_majoration_ferie_fige,
          'heure_debut_nuit_fige', OLD.heure_debut_nuit_fige,
          'heure_fin_nuit_fige', OLD.heure_fin_nuit_fige,
          'taux_commission_fige', OLD.taux_commission_fige,
          'fige_le', OLD.fige_le
        ),
        'old_statut', OLD.statut,
        'new_statut', 'OUVERTE'
      )
    );

    NEW.taux_horaire_base_fige        := NULL;
    NEW.taux_majoration_nuit_fige     := NULL;
    NEW.taux_majoration_dimanche_fige := NULL;
    NEW.taux_majoration_ferie_fige    := NULL;
    NEW.heure_debut_nuit_fige         := NULL;
    NEW.heure_fin_nuit_fige           := NULL;
    NEW.taux_commission_fige          := NULL;
    NEW.fige_le                       := NULL;

    RETURN NEW;
  END IF;

  -- ════════════════════════════════════════════════════
  -- BLOC 3 : PROTECTION — champs bloqués après gel
  -- ════════════════════════════════════════════════════
  IF OLD.fige_le IS NOT NULL THEN

    IF current_setting('jolene.admin_override_gel', true) = OLD.id::text
       AND COALESCE(current_setting('jolene.admin_override_reason', true), '') != '' THEN

      -- 3c. Audit override admin — log TOUS les champs modifiés
      DECLARE
        v_fields_modified jsonb := '{}'::jsonb;
        v_override_reason text := current_setting('jolene.admin_override_reason', true);
      BEGIN
        IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'taux_horaire_base', jsonb_build_object('old', OLD.taux_horaire_base, 'new', NEW.taux_horaire_base));
        END IF;
        IF NEW.intitule IS DISTINCT FROM OLD.intitule THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'intitule', jsonb_build_object('old', OLD.intitule, 'new', NEW.intitule));
        END IF;
        IF NEW.profession_requise IS DISTINCT FROM OLD.profession_requise THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'profession_requise', jsonb_build_object('old', OLD.profession_requise, 'new', NEW.profession_requise));
        END IF;
        IF NEW.taux_horaire_base_fige IS DISTINCT FROM OLD.taux_horaire_base_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'taux_horaire_base_fige', jsonb_build_object('old', OLD.taux_horaire_base_fige, 'new', NEW.taux_horaire_base_fige));
        END IF;
        IF NEW.taux_majoration_nuit_fige IS DISTINCT FROM OLD.taux_majoration_nuit_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'taux_majoration_nuit_fige', jsonb_build_object('old', OLD.taux_majoration_nuit_fige, 'new', NEW.taux_majoration_nuit_fige));
        END IF;
        IF NEW.taux_majoration_dimanche_fige IS DISTINCT FROM OLD.taux_majoration_dimanche_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'taux_majoration_dimanche_fige', jsonb_build_object('old', OLD.taux_majoration_dimanche_fige, 'new', NEW.taux_majoration_dimanche_fige));
        END IF;
        IF NEW.taux_majoration_ferie_fige IS DISTINCT FROM OLD.taux_majoration_ferie_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'taux_majoration_ferie_fige', jsonb_build_object('old', OLD.taux_majoration_ferie_fige, 'new', NEW.taux_majoration_ferie_fige));
        END IF;
        IF NEW.heure_debut_nuit_fige IS DISTINCT FROM OLD.heure_debut_nuit_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'heure_debut_nuit_fige', jsonb_build_object('old', OLD.heure_debut_nuit_fige, 'new', NEW.heure_debut_nuit_fige));
        END IF;
        IF NEW.heure_fin_nuit_fige IS DISTINCT FROM OLD.heure_fin_nuit_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'heure_fin_nuit_fige', jsonb_build_object('old', OLD.heure_fin_nuit_fige, 'new', NEW.heure_fin_nuit_fige));
        END IF;
        IF NEW.taux_commission_fige IS DISTINCT FROM OLD.taux_commission_fige THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'taux_commission_fige', jsonb_build_object('old', OLD.taux_commission_fige, 'new', NEW.taux_commission_fige));
        END IF;
        IF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN
          v_fields_modified := v_fields_modified || jsonb_build_object(
            'fige_le', jsonb_build_object('old', OLD.fige_le, 'new', NEW.fige_le));
        END IF;

        IF v_fields_modified != '{}'::jsonb THEN
          INSERT INTO journaux_audit
            (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
          VALUES (
            auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_CHAMP_POST_GEL', 'mission', OLD.id,
            jsonb_build_object(
              'reason', v_override_reason,
              'fields_modified', v_fields_modified
            )
          );
        END IF;
      END;

      RETURN NEW;

    ELSE

      -- 3b. Vérification — RAISE si champ bloqué modifié
      -- NOTE : seul le premier champ modifié est signalé.
      -- L'utilisateur corrige et réessaie. Acceptable V1.
      IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base THEN
        v_champ_modifie := 'taux_horaire_base';
      ELSIF NEW.intitule IS DISTINCT FROM OLD.intitule THEN
        v_champ_modifie := 'intitule';
      ELSIF NEW.profession_requise IS DISTINCT FROM OLD.profession_requise THEN
        v_champ_modifie := 'profession_requise';
      ELSIF NEW.taux_horaire_base_fige IS DISTINCT FROM OLD.taux_horaire_base_fige THEN
        v_champ_modifie := 'taux_horaire_base_fige';
      ELSIF NEW.taux_majoration_nuit_fige IS DISTINCT FROM OLD.taux_majoration_nuit_fige THEN
        v_champ_modifie := 'taux_majoration_nuit_fige';
      ELSIF NEW.taux_majoration_dimanche_fige IS DISTINCT FROM OLD.taux_majoration_dimanche_fige THEN
        v_champ_modifie := 'taux_majoration_dimanche_fige';
      ELSIF NEW.taux_majoration_ferie_fige IS DISTINCT FROM OLD.taux_majoration_ferie_fige THEN
        v_champ_modifie := 'taux_majoration_ferie_fige';
      ELSIF NEW.heure_debut_nuit_fige IS DISTINCT FROM OLD.heure_debut_nuit_fige THEN
        v_champ_modifie := 'heure_debut_nuit_fige';
      ELSIF NEW.heure_fin_nuit_fige IS DISTINCT FROM OLD.heure_fin_nuit_fige THEN
        v_champ_modifie := 'heure_fin_nuit_fige';
      ELSIF NEW.taux_commission_fige IS DISTINCT FROM OLD.taux_commission_fige THEN
        v_champ_modifie := 'taux_commission_fige';
      ELSIF NEW.fige_le IS DISTINCT FROM OLD.fige_le THEN
        v_champ_modifie := 'fige_le';
      END IF;

      IF v_champ_modifie IS NOT NULL THEN
        RAISE EXCEPTION 'Modification du champ "%" interdite après assignation (gel du %). Pour corriger une coquille, contactez le support Jolene pour un override admin tracé. Pour modifier le contenu substantiel, annuler la mission et en créer une nouvelle.',
          v_champ_modifie, OLD.fige_le
          USING ERRCODE = 'check_violation';
      END IF;

    END IF; -- fin bypass admin

  END IF; -- fin fige_le IS NOT NULL

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_zz_geler_mission
  BEFORE UPDATE ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_geler_mission_a_assignation();

-- ──────────────────────────────────────────────────────────────
-- 4. Mise à jour protecteurs — ajout _fige aux listes de freeze
-- ──────────────────────────────────────────────────────────────

-- 4a. dec_proteger_mission_soignant
CREATE OR REPLACE FUNCTION public.dec_proteger_mission_soignant()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
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
        -- CP5a: freeze _fige columns during sync
        NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
        NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
        NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
        NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
        NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
        NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
        NEW.taux_commission_fige := OLD.taux_commission_fige;
        NEW.fige_le := OLD.fige_le;
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
        -- CP5a: freeze _fige columns for non-admin
        NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
        NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
        NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
        NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
        NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
        NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
        NEW.taux_commission_fige := OLD.taux_commission_fige;
        NEW.fige_le := OLD.fige_le;
    END IF;
    RETURN NEW;
END;
$$;

-- 4b. fn_protect_mission_financials
CREATE OR REPLACE FUNCTION public.fn_protect_mission_financials()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
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
        -- CP5a: freeze _fige columns during sync
        NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
        NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
        NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
        NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
        NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
        NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
        NEW.taux_commission_fige := OLD.taux_commission_fige;
        NEW.fige_le := OLD.fige_le;
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
        -- CP5a: freeze _fige columns for assigned soignant
        NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
        NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
        NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
        NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
        NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
        NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
        NEW.taux_commission_fige := OLD.taux_commission_fige;
        NEW.fige_le := OLD.fige_le;
    END IF;
    RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 5. Backfill — missions non-OUVERTE
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.missions DISABLE TRIGGER USER;

UPDATE missions m SET
  taux_horaire_base_fige = m.taux_horaire_base,
  taux_majoration_nuit_fige = e.taux_majoration_nuit_pourcent,
  taux_majoration_dimanche_fige = e.taux_majoration_dimanche_pourcent,
  taux_majoration_ferie_fige = e.taux_majoration_ferie_pourcent,
  heure_debut_nuit_fige = COALESCE(e.heure_debut_nuit, '21:00'::time),
  heure_fin_nuit_fige = COALESCE(e.heure_fin_nuit, '06:00'::time),
  taux_commission_fige = COALESCE(m.taux_commission, e.taux_commission_negocie, 15),
  fige_le = NULL
FROM etablissements e
WHERE e.id = m.etablissement_id
  AND m.statut != 'OUVERTE';

ALTER TABLE public.missions ENABLE TRIGGER USER;

-- ──────────────────────────────────────────────────────────────
-- 6. Extend journaux_audit CHECK constraint for new actions
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action = ANY (ARRAY[
  'INSCRIPTION','CONNEXION','DECONNEXION','MODIFICATION_PROFIL','SUPPRESSION_COMPTE',
  'UPLOAD_DOCUMENT','TELECHARGEMENT_DOCUMENT','VERIFICATION_DOCUMENT','VERIFICATION_RPPS',
  'CREATION_MISSION','MODIFICATION_MISSION','ANNULATION_MISSION','CANDIDATURE','ASSIGNATION',
  'POINTAGE','SIGNATURE_CONTRAT','EVALUATION','PAIEMENT','FACTURATION',
  'DONNEES_PERSO_CONSULTATION','DONNEES_PERSO_EXPORT','DONNEES_PERSO_SUPPRESSION',
  'ADMIN_ACTION','SYSTEM','RIB_CONSULTE','RIB_PARTAGE','CONTRAT_SIGNE',
  'DOCUMENT_CONSULTATION','DOCUMENT_TELEVERSEMENT','DONNEES_PERSO_MODIFICATION',
  'EXPORT_RH_PAIE','FINANCE_FACTURE_PAYEE','MISSION_ASSIGNATION','MISSION_CREATION',
  'RGPD_EXPORT_DONNEES',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL'
]));

-- ──────────────────────────────────────────────────────────────
-- 7. Bugfix: dec_alerte_mission_liberee — 'CRITIQUE' → 3 (integer)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_alerte_mission_liberee()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
    IF OLD.statut = 'ASSIGNEE' AND NEW.statut = 'OUVERTE'
       AND NEW.debut_le < NOW() + INTERVAL '24 hours' THEN
        NEW.est_urgente := TRUE;
        NEW.niveau_urgence := 3;
    END IF;
    RETURN NEW;
END;
$function$;
