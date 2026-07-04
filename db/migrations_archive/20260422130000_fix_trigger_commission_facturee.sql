-- ============================================================
-- Fix bug commission_facturee non persisté après webhook Stripe
-- ============================================================
-- Trigger `dec_proteger_mission_soignant` BEFORE UPDATE sur missions
-- protège 37 champs contre modification par users non-admin. Sa branche
-- 2 (NOT est_admin AND NOT est_admin_etab) capture également le contexte
-- service_role (webhook Stripe) car auth.uid() = NULL → est_admin() = FALSE
-- → est_admin_etablissement() = FALSE. Conséquence : le webhook
-- stripe-webhook/index.ts ligne 221 fait bien
--   UPDATE missions SET commission_facturee=true, ...
-- mais le trigger revert commission_facturee à OLD.commission_facturee
-- (FALSE). Résultat :
--   1. La mission apparaît à tort dans fn_obligations_financieres
--      missions_non_facturees → "Commissions à venir"
--   2. Le cron mensuel fn_auto_facturation_mensuelle génère une
--      facture commission à tort → DOUBLE FACTURATION (commission
--      déjà capturée à la source par Stripe Connect via application_fee)
--   3. Affichage fiche mission erroné "Facturée en fin de mois"
--
-- Fix ciblé Option A1 : retirer UNIQUEMENT `commission_facturee` de la
-- branche 2. Les 36 autres champs restent protégés (identité, contrat,
-- financiers calculés par autres triggers).
--
-- Branche 1 (sync_in_progress) inchangée (syncs mission_creneaux ne
-- touchent pas commission_facturee de toute façon).
-- ============================================================

CREATE OR REPLACE FUNCTION public.dec_proteger_mission_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        -- FIX BUG-WEBHOOK-COMMISSION-FACTUREE (22/04/2026) — RETIRÉ :
        -- NEW.commission_facturee := OLD.commission_facturee;
        -- Motif : bloquait le webhook Stripe Connect + cron facturation
        -- mensuelle qui ont besoin de set TRUE. Risque anti-tamper nul
        -- car RLS empêche les users d'UPDATE directement ce champ via
        -- PostgREST (seuls service_role backend + RPCs SECURITY DEFINER
        -- le manipulent légitimement).
        NEW.net_estime := OLD.net_estime;
        NEW.mode_attribution := OLD.mode_attribution;
        NEW.type_contrat_recherche := OLD.type_contrat_recherche;
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
$function$;
