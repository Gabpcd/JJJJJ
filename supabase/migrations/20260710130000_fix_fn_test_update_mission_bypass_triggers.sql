-- Recapture hotfix prod (10/07/2026, v2) : fn_test_update_mission était un
-- NO-OP silencieux — dec_proteger_mission_soignant (BEFORE UPDATE missions)
-- re-force debut_le/fin_le/soignant_assigne_id/statut depuis OLD pour tout
-- caller non admin (service_role compris). Les specs E2E qui backdatent une
-- mission (presences-autovalidation, empêchement impérieux) croyaient déplacer
-- la mission : l'UPDATE entier était annulé et l'INSERT presences échouait
-- ensuite en « Pointage trop tôt ».
--
-- v1 (SET LOCAL session_replication_role) rejetée : supautils vérifie le rôle
-- de SESSION (authenticator via PostgREST), pas le owner SECURITY DEFINER →
-- 42501 en CI. v2 : flag étroit `app.test_bypass_protections`, posé UNIQUEMENT
-- par fn_test_update_mission (réservé service_role), respecté par
-- dec_proteger_mission_soignant (early return), remis à '' aussitôt après.
-- Un client PostgREST ne peut pas poser ce GUC (seuls les en-têtes request.*
-- sont mappés). Validé sur branche recette : backdating + assignation
-- appliqués, protection intacte hors helper, INSERT presences backdatée
-- accepté (triggers presences actifs).

-- Base = définition LIVE ; ajout marqué TEST BYPASS.
CREATE OR REPLACE FUNCTION public.dec_proteger_mission_soignant()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
    -- TEST BYPASS (10/07/2026) : posé uniquement par fn_test_update_mission
    -- (réservé service_role, seed E2E). Sans lui, le helper était un no-op
    -- silencieux : ce trigger re-forçait debut_le/soignant_assigne_id depuis OLD.
    IF current_setting('app.test_bypass_protections', true) = 'true' THEN
        RETURN NEW;
    END IF;

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

CREATE OR REPLACE FUNCTION public.fn_test_update_mission(p_mission_id uuid, p_data jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $_$
DECLARE
  v_set text;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'fn_test_update_mission réservé au service_role (seed E2E uniquement)';
  END IF;
  PERFORM set_config('app.internal_operation', 'true', true);
  PERFORM set_config('jolene.creer_mission_context', 'true', true);
  PERFORM set_config('app.test_bypass_protections', 'true', true);
  v_set := (SELECT string_agg(format('%I = r.%I', key, key), ',') FROM jsonb_object_keys(p_data) AS key);
  EXECUTE format(
    'UPDATE public.missions m SET %s FROM jsonb_populate_record(NULL::public.missions, $1) r WHERE m.id = $2',
    v_set
  ) USING p_data, p_mission_id;
  PERFORM set_config('app.test_bypass_protections', '', true);
END;
$_$;
