CREATE OR REPLACE FUNCTION public.dec_appliquer_plafond_rist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_plafond NUMERIC; v_etab RECORD; v_prof type_profession;
BEGIN
    IF NEW.soignant_assigne_id IS NULL THEN
        NEW.taux_rist_plafonne := NEW.taux_horaire_base;
        NEW.rist_plafond_applique := FALSE;
        RETURN NEW;
    END IF;

    -- Vérifier si l'établissement est du secteur public
    SELECT est_secteur_public INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;
    
    IF NOT COALESCE(v_etab.est_secteur_public, FALSE) THEN
        -- Secteur privé : pas de plafond Rist
        NEW.taux_rist_plafonne := NEW.taux_horaire_base;
        NEW.rist_plafond_applique := FALSE;
        RETURN NEW;
    END IF;

    -- Secteur public uniquement : vérifier le type de contrat de la MISSION
    IF NEW.type_contrat_recherche NOT IN ('SALARIE', 'TOUS') THEN
        -- Libéral : pas de plafond Rist
        NEW.taux_rist_plafonne := NEW.taux_horaire_base;
        NEW.rist_plafond_applique := FALSE;
        RETURN NEW;
    END IF;

    SELECT profession INTO v_prof FROM soignants WHERE id = NEW.soignant_assigne_id;
    
    SELECT rp.plafond_calcule INTO v_plafond
    FROM rist_plafonds rp
    WHERE rp.profession = v_prof
      AND rp.en_vigueur_depuis <= CURRENT_DATE
      AND (rp.en_vigueur_jusqua IS NULL OR rp.en_vigueur_jusqua >= CURRENT_DATE)
    ORDER BY rp.en_vigueur_depuis DESC LIMIT 1;
    
    IF v_plafond IS NOT NULL AND NEW.taux_horaire_base > v_plafond THEN
        NEW.taux_rist_plafonne := v_plafond;
        NEW.rist_plafond_applique := TRUE;
    ELSE
        NEW.taux_rist_plafonne := NEW.taux_horaire_base;
        NEW.rist_plafond_applique := FALSE;
    END IF;
    
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_antifraude_presence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_teleport JSONB;
    v_etab RECORD;
    v_dist NUMERIC;
BEGIN
    IF NEW.pointage_arrivee_le IS NOT NULL AND NEW.arrivee_lat IS NOT NULL THEN
        -- Détection téléportation
        v_teleport := fn_detecter_teleportation(
            NEW.soignant_id, NEW.arrivee_lat, NEW.arrivee_lng, NEW.pointage_arrivee_le
        );
        IF (v_teleport->>'suspect')::BOOLEAN THEN
            NEW.alerte_teleportation := TRUE;
            NEW.alertes_fraude := NEW.alertes_fraude || jsonb_build_array(v_teleport);

            INSERT INTO file_revue_manuelle (type_entite, id_entite, service_en_echec, motif_echec, donnees_originales, priorite)
            VALUES ('ALERTE_FRAUDE', NEW.id, 'GEOLOCALISATION', 'Téléportation détectée', v_teleport, 5);

            PERFORM fn_ecrire_audit(
                NEW.soignant_id, 'SYSTEME', 'PRESENCE_ALERTE_FRAUDE',
                'presence', NEW.id, NULL, v_teleport
            );
        END IF;

        -- Vérification périmètre GPS (géofence 500m)
        SELECT e.adresse_lat, e.adresse_lng INTO v_etab
        FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.id = NEW.mission_id;

        IF v_etab.adresse_lat IS NOT NULL THEN
            v_dist := 6371000 * acos(LEAST(1.0,
                cos(radians(v_etab.adresse_lat)) * cos(radians(NEW.arrivee_lat))
                * cos(radians(NEW.arrivee_lng) - radians(v_etab.adresse_lng))
                + sin(radians(v_etab.adresse_lat)) * sin(radians(NEW.arrivee_lat))
            ));
            NEW.distance_etablissement_m := ROUND(v_dist, 2);
            NEW.perimetre_gps_valide := (v_dist <= 500);

            IF NOT NEW.perimetre_gps_valide THEN
                NEW.alertes_fraude := NEW.alertes_fraude || jsonb_build_array(jsonb_build_object(
                    'type_alerte', 'HORS_PERIMETRE',
                    'distance_m', ROUND(v_dist, 2),
                    'distance_max_m', 500
                ));
            END IF;
        END IF;
    END IF;

    -- Retard de pointage (> 15 min)
    IF NEW.pointage_arrivee_le IS NOT NULL THEN
        DECLARE v_debut_mission TIMESTAMPTZ;
        BEGIN
            SELECT m.debut_le INTO v_debut_mission FROM missions m WHERE m.id = NEW.mission_id;
            IF NEW.pointage_arrivee_le > v_debut_mission + INTERVAL '15 minutes' THEN
                UPDATE soignants SET
                    total_retards_pointage = total_retards_pointage + 1, modifie_le = NOW()
                WHERE id = NEW.soignant_id;
            END IF;
        END;
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_annuler_contrat_si_mission_annulee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.statut IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT') THEN
        UPDATE contrats_mission SET statut = 'ANNULE', modifie_le = NOW()
        WHERE mission_id = NEW.id AND statut NOT IN ('SIGNE_COMPLET', 'ANNULE');
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_anti_double_assignation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.soignant_assigne_id IS NOT NULL AND NEW.statut = 'ASSIGNEE' THEN
        IF OLD.soignant_assigne_id IS NOT NULL AND OLD.statut = 'ASSIGNEE' THEN
            -- Déjà assigné, refuser le double
            IF OLD.soignant_assigne_id != NEW.soignant_assigne_id THEN
                RAISE EXCEPTION 'Cette mission est déjà assignée à un autre soignant.';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_alerte_mission_liberee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF OLD.statut = 'ASSIGNEE' AND NEW.statut = 'OUVERTE'
       AND NEW.debut_le < NOW() + INTERVAL '24 hours' THEN
        NEW.est_urgente := TRUE;
        NEW.niveau_urgence := 3;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_auto_calculer_cotisations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Quand une mission passe en TERMINEE, calculer automatiquement les cotisations
    IF NEW.statut = 'TERMINEE' AND (OLD.statut IS NULL OR OLD.statut != 'TERMINEE') AND NEW.soignant_assigne_id IS NOT NULL THEN
        PERFORM fn_calculer_cotisations(NEW.id);
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_alerte_pause_obligatoire()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_total_pauses NUMERIC;
BEGIN
    IF NEW.pointage_depart_le IS NOT NULL AND NEW.duree_brute_min IS NOT NULL THEN
        SELECT COALESCE(SUM(
            CASE WHEN fin_le IS NOT NULL THEN EXTRACT(EPOCH FROM (fin_le - debut_le)) / 60 ELSE 0 END
        ), 0) INTO v_total_pauses FROM pauses_presence WHERE presence_id = NEW.id;

        IF NEW.duree_brute_min > 360 AND v_total_pauses < 20 THEN
            NEW.alertes_fraude := COALESCE(NEW.alertes_fraude, '[]'::JSONB) || jsonb_build_array(jsonb_build_object(
                'type_alerte', 'PAUSE_MANQUANTE',
                'duree_shift_min', NEW.duree_brute_min,
                'duree_pause_min', v_total_pauses,
                'message', 'Shift > 6h sans 20 min de pause. Art. L3121-16.'
            ));
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public._sha256_hex(p_input text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT encode(extensions.digest(p_input, 'sha256'), 'hex');
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bloquer_modification_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    RAISE EXCEPTION 'Les journaux d''audit sont immuables (HDS).';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bloquer_changement_proprio_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF OLD.etablissement_id != NEW.etablissement_id THEN
        RAISE EXCEPTION 'INTERDIT : le propriétaire d''une facture ne peut pas être modifié.';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bloquer_modif_apres_acceptation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF OLD.statut != 'OUVERTE' AND NOT est_admin() THEN
        IF OLD.taux_horaire_base IS DISTINCT FROM NEW.taux_horaire_base THEN
            RAISE EXCEPTION 'Le taux horaire ne peut plus être modifié après acceptation.';
        END IF;
        IF current_setting('jolene.sync_in_progress', true) != 'true' THEN
            IF OLD.debut_le IS DISTINCT FROM NEW.debut_le OR OLD.fin_le IS DISTINCT FROM NEW.fin_le THEN
                RAISE EXCEPTION 'Les horaires ne peuvent plus être modifiés après acceptation.';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bloquer_desinscription_missions()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_nb_missions INTEGER;
BEGIN
    -- Soft delete (supprime_le mis à jour)
    IF NEW.supprime_le IS NOT NULL AND OLD.supprime_le IS NULL THEN
        SELECT COUNT(*) INTO v_nb_missions
        FROM missions
        WHERE soignant_assigne_id = OLD.id
          AND statut IN ('ASSIGNEE', 'EN_COURS')
          AND fin_le > NOW();

        IF v_nb_missions > 0 THEN
            RAISE EXCEPTION 'Vous avez % mission(s) prévue(s). Annulez-les avant de supprimer votre compte.', v_nb_missions;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bloquer_si_facture_impayee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_nb_impayees INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT COUNT(*) INTO v_nb_impayees
        FROM factures
        WHERE etablissement_id = NEW.etablissement_id
          AND statut = 'EMISE'
          AND cree_le + INTERVAL '30 days' < NOW();

        IF v_nb_impayees > 0 AND NOT est_admin() THEN
            RAISE EXCEPTION 'Vous avez % facture(s) impayée(s) depuis plus de 30 jours. Régularisez votre situation pour publier de nouvelles missions.', v_nb_impayees;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bloquer_paiement_manuel_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si quelqu'un essaie de passer une facture en PAYEE
    IF NEW.statut = 'PAYEE' AND OLD.statut != 'PAYEE' THEN
        -- Seul l'admin OU le service_role (webhook Stripe) peut faire ça
        IF NOT est_admin() AND auth.uid() IS NOT NULL THEN
            RAISE EXCEPTION 'Le paiement des factures passe exclusivement par Stripe ou virement bancaire.';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_auto_partager_rib()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_doc_rib UUID;
    v_mission RECORD;
BEGIN
    -- Seulement quand le contrat passe en SIGNE_COMPLET et c'est un CDD
    IF NEW.statut = 'SIGNE_COMPLET' AND (OLD.statut IS NULL OR OLD.statut != 'SIGNE_COMPLET') 
       AND NEW.type_contrat = 'CDD' THEN
        
        -- Trouver le document RIB du soignant
        SELECT id INTO v_doc_rib FROM documents_soignants 
        WHERE soignant_id = NEW.soignant_id AND type_document = 'RIB' 
        AND supprime_le IS NULL AND statut_verification = 'VERIFIE'
        ORDER BY televerse_le DESC LIMIT 1;

        -- Créer le partage même si pas de RIB (l'établissement verra "RIB non uploadé")
        INSERT INTO partages_rib (soignant_id, etablissement_id, mission_id, contrat_id, actif, document_rib_id)
        VALUES (NEW.soignant_id, NEW.etablissement_id, NEW.mission_id, NEW.id, TRUE, v_doc_rib)
        ON CONFLICT DO NOTHING;

        -- Notifier le soignant si pas de RIB uploadé
        IF v_doc_rib IS NULL THEN
            INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (NEW.soignant_id, 'SYSTEM',
                '📋 RIB requis pour le paiement',
                'Le contrat pour votre mission est signé. Veuillez uploader votre RIB dans "Mes documents" pour que l''établissement puisse vous payer.',
                '/soignant/documents', 'SOIGNANT');
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_auto_generer_qr_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_existing_qr int;
BEGIN
  -- Trigger sur INSERT presences ou UPDATE contrats SIGNE_COMPLET
  IF TG_TABLE_NAME = 'contrats_mission' THEN
    IF NEW.statut != 'SIGNE_COMPLET' OR (OLD.statut = 'SIGNE_COMPLET') THEN
      RETURN NEW;
    END IF;
    -- Mission n'a pas encore de QR UNIVERSEL actif ?
    SELECT COUNT(*) INTO v_existing_qr FROM public.qr_codes_mission
    WHERE mission_id = NEW.mission_id AND type = 'UNIVERSEL' AND actif = true;
    IF v_existing_qr = 0 THEN
      -- Génère via insertion directe (auth.uid NULL en trigger système)
      INSERT INTO public.qr_codes_mission (mission_id, token, type, expire_le, cree_par)
      SELECT
        NEW.mission_id,
        gen_random_uuid()::text || '_' || encode(extensions.gen_random_bytes(8), 'hex'),
        'UNIVERSEL',
        LEAST(COALESCE(m.fin_le, NOW() + INTERVAL '7 days') + INTERVAL '2 hours',
              NOW() + INTERVAL '7 days'),
        '00000000-0000-0000-0000-000000000000'::uuid
      FROM public.missions m WHERE m.id = NEW.mission_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_calculer_finance_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_taux_effectif NUMERIC; v_calcul JSONB; v_c RECORD;
    v_sum_prev NUMERIC := 0; v_sum_eff NUMERIC := 0; v_use_effectif BOOLEAN;
    v_h_nuit NUMERIC := 0; v_h_dim NUMERIC := 0; v_h_fer NUMERIC := 0;
    v_m_nuit NUMERIC := 0; v_m_dim NUMERIC := 0; v_m_fer NUMERIC := 0;
    v_brut NUMERIC := 0; v_ifm NUMERIC := 0; v_icp NUMERIC := 0; v_taux_ifm NUMERIC := 0; v_taux_icp NUMERIC := 0;
BEGIN
    v_taux_effectif := COALESCE(NEW.taux_rist_plafonne, NEW.taux_horaire_base);
    SELECT COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
      INTO v_sum_prev FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND fin IS NOT NULL;
    SELECT COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
      INTO v_sum_eff FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;
    v_use_effectif := v_sum_eff > v_sum_prev;

    IF v_sum_prev > 0 OR v_sum_eff > 0 THEN
        FOR v_c IN
            SELECT debut, fin FROM mission_creneaux
            WHERE mission_id = NEW.id AND NOT est_pause AND fin IS NOT NULL
              AND type_creneau = CASE WHEN v_use_effectif THEN 'EFFECTIF' ELSE 'PREVISIONNEL' END
            ORDER BY debut
        LOOP
            v_calcul := fn_calculer_remuneration_mission(v_c.debut, v_c.fin, v_taux_effectif, NEW.etablissement_id, NEW.soignant_assigne_id);
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
        NEW.heures_nuit := ROUND(v_h_nuit, 2); NEW.heures_dimanche := ROUND(v_h_dim, 2); NEW.heures_ferie := ROUND(v_h_fer, 2);
        NEW.montant_majoration_nuit := ROUND(v_m_nuit, 2); NEW.montant_majoration_dimanche := ROUND(v_m_dim, 2); NEW.montant_majoration_ferie := ROUND(v_m_fer, 2);
        NEW.total_brut := ROUND(v_brut, 2); NEW.taux_ifm := v_taux_ifm; NEW.montant_ifm := v_ifm; NEW.taux_icp := v_taux_icp; NEW.montant_icp := v_icp;
        NEW.net_a_payer := ROUND(v_brut + v_ifm + v_icp, 2);
    ELSE
        v_calcul := fn_calculer_remuneration_mission(NEW.debut_le, NEW.fin_le, v_taux_effectif, NEW.etablissement_id, NEW.soignant_assigne_id);
        NEW.heures_nuit := (v_calcul->>'heures_nuit')::NUMERIC; NEW.heures_dimanche := (v_calcul->>'heures_dimanche')::NUMERIC; NEW.heures_ferie := (v_calcul->>'heures_ferie')::NUMERIC;
        NEW.montant_majoration_nuit := (v_calcul->>'montant_majoration_nuit')::NUMERIC; NEW.montant_majoration_dimanche := (v_calcul->>'montant_majoration_dimanche')::NUMERIC; NEW.montant_majoration_ferie := (v_calcul->>'montant_majoration_ferie')::NUMERIC;
        NEW.total_brut := (v_calcul->>'total_brut')::NUMERIC; NEW.taux_ifm := (v_calcul->>'taux_ifm')::NUMERIC; NEW.montant_ifm := (v_calcul->>'montant_ifm')::NUMERIC; NEW.taux_icp := (v_calcul->>'taux_icp')::NUMERIC; NEW.montant_icp := (v_calcul->>'montant_icp')::NUMERIC;
        NEW.net_a_payer := (v_calcul->>'net_a_payer')::NUMERIC;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_calculer_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_taux NUMERIC;
BEGIN
    IF NEW.statut = 'TERMINEE' AND NEW.net_a_payer IS NOT NULL THEN
        v_taux := COALESCE(
            NEW.taux_commission_fige,
            (SELECT e.taux_commission_negocie FROM etablissements e WHERE e.id = NEW.etablissement_id),
            public.fn_param_num('commission_defaut_pct', 15)
        );

        NEW.taux_commission := v_taux;
        NEW.montant_commission_ht := ROUND(NEW.net_a_payer * (v_taux / 100.0), 2);
        NEW.montant_commission_tva := ROUND(NEW.montant_commission_ht * 0.20, 2);
        NEW.montant_commission_ttc := NEW.montant_commission_ht + NEW.montant_commission_tva;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bloquer_suppression_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    RAISE EXCEPTION 'Les journaux d''audit sont immuables (HDS).';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_calculer_net_estime()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.net_a_payer IS NOT NULL AND NEW.net_a_payer > 0 THEN
        NEW.net_estime := ROUND(NEW.net_a_payer * 0.78, 2);
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_bonus_urgence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.statut = 'TERMINEE' AND OLD.statut != 'TERMINEE' AND NEW.est_urgente = TRUE THEN
        UPDATE soignants SET
            score_fiabilite = LEAST(100, score_fiabilite + 10),
            total_missions_urgence = total_missions_urgence + 1,
            modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_check_coherence_apres_rpps()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.rpps_verifie = TRUE AND (OLD.rpps_verifie IS NULL OR OLD.rpps_verifie = FALSE) THEN
        PERFORM fn_verifier_coherence_identite(NEW.id);
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_check_coherence_apres_doc_identite()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.statut_verification = 'VERIFIE' AND NEW.type_document = 'CARTE_IDENTITE' 
       AND (OLD.statut_verification IS NULL OR OLD.statut_verification != 'VERIFIE') THEN
        PERFORM fn_verifier_coherence_identite(NEW.soignant_id);
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_calculer_duree_presence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_debut_mission TIMESTAMPTZ;
    v_fin_mission TIMESTAMPTZ;
    v_total_pauses NUMERIC;
BEGIN
    IF NEW.pointage_depart_le IS NOT NULL AND NEW.pointage_arrivee_le IS NOT NULL THEN
        -- Durée brute
        NEW.duree_brute_min := ROUND(EXTRACT(EPOCH FROM (NEW.pointage_depart_le - NEW.pointage_arrivee_le)) / 60, 2);
        
        -- Total pauses depuis la table pauses_presence
        SELECT COALESCE(SUM(
            CASE WHEN fin_le IS NOT NULL THEN EXTRACT(EPOCH FROM (fin_le - debut_le)) / 60
            ELSE 0 END
        ), 0) INTO v_total_pauses FROM pauses_presence WHERE presence_id = NEW.id;
        
        NEW.duree_pause_min := ROUND(v_total_pauses, 2);
        NEW.duree_nette_min := GREATEST(0, NEW.duree_brute_min - NEW.duree_pause_min);
        NEW.heures_reelles := ROUND(NEW.duree_nette_min / 60, 2);

        -- Retard / départ anticipé
        SELECT debut_le, fin_le INTO v_debut_mission, v_fin_mission FROM missions WHERE id = NEW.mission_id;
        
        IF v_debut_mission IS NOT NULL AND NEW.pointage_arrivee_le > v_debut_mission THEN
            NEW.retard_min := ROUND(EXTRACT(EPOCH FROM (NEW.pointage_arrivee_le - v_debut_mission)) / 60, 2);
        ELSE
            NEW.retard_min := 0;
        END IF;
        
        IF v_fin_mission IS NOT NULL AND NEW.pointage_depart_le < v_fin_mission THEN
            NEW.depart_anticipe_min := ROUND(EXTRACT(EPOCH FROM (v_fin_mission - NEW.pointage_depart_le)) / 60, 2);
        ELSE
            NEW.depart_anticipe_min := 0;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_definir_type_paiement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_type_exercice TEXT;
    v_choix TEXT;
BEGIN
    IF NEW.soignant_assigne_id IS NOT NULL THEN
        SELECT type_exercice INTO v_type_exercice FROM soignants WHERE id = NEW.soignant_assigne_id;
        v_choix := NEW.choix_contrat_soignant;

        IF v_type_exercice = 'LIBERAL' THEN
            NEW.type_paiement_soignant := 'NOTE_HONORAIRES';
            NEW.mode_paiement_soignant := 'STRIPE_CONNECT';
        ELSIF v_type_exercice = 'MIXTE' THEN
            IF NEW.type_contrat_recherche = 'TOUS' AND v_choix = 'LIBERAL' THEN
                NEW.type_paiement_soignant := 'NOTE_HONORAIRES';
                NEW.mode_paiement_soignant := 'STRIPE_CONNECT';
            ELSIF NEW.type_contrat_recherche = 'LIBERAL' THEN
                NEW.type_paiement_soignant := 'NOTE_HONORAIRES';
                NEW.mode_paiement_soignant := 'STRIPE_CONNECT';
            ELSE
                NEW.type_paiement_soignant := 'BULLETIN_PAIE';
                NEW.mode_paiement_soignant := 'DIRECT';
            END IF;
        ELSE
            NEW.type_paiement_soignant := 'BULLETIN_PAIE';
            NEW.mode_paiement_soignant := 'DIRECT';
        END IF;

        IF NEW.type_paiement_soignant = 'NOTE_HONORAIRES' 
           AND NEW.statut = 'TERMINEE' AND NEW.numero_note_honoraires IS NULL THEN
            NEW.numero_note_honoraires := fn_generer_numero_note_honoraires();
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_detecter_secteur_public_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
BEGIN
    SELECT type, est_secteur_public INTO v_etab
    FROM etablissements WHERE id = NEW.etablissement_id;

    IF v_etab.est_secteur_public = TRUE OR v_etab.type IN ('HOPITAL_PUBLIC', 'ESPIC') THEN
        NEW.est_secteur_public := TRUE;
        NEW.mode_paiement := 'CHORUS_PRO';
        NEW.chorus_pro_statut := 'A_DEPOSER';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_depart_apres_arrivee()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.pointage_depart_le IS NOT NULL AND NEW.pointage_arrivee_le IS NULL THEN
        RAISE EXCEPTION 'Impossible de pointer le départ sans avoir pointé l''arrivée.';
    END IF;
    IF NEW.pointage_depart_le IS NOT NULL AND NEW.pointage_depart_le < NEW.pointage_arrivee_le THEN
        RAISE EXCEPTION 'Le départ ne peut pas être avant l''arrivée.';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_contestation_48h()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$ DECLARE v_valide_le TIMESTAMPTZ; BEGIN IF NEW.presence_id IS NULL THEN RETURN NEW; END IF; SELECT valide_le INTO v_valide_le FROM presences WHERE id = NEW.presence_id; IF v_valide_le IS NULL THEN RETURN NEW; END IF; IF v_valide_le + INTERVAL '48 hours' < NOW() THEN RETURN NEW; END IF; RETURN NEW; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_detecter_secteur_public_etablissement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.type IN ('HOPITAL_PUBLIC', 'ESPIC') THEN
        NEW.est_secteur_public := TRUE;
    END IF;
    -- Aussi via la catégorie juridique INSEE si disponible
    IF NEW.siret_categorie_juridique IS NOT NULL AND LEFT(NEW.siret_categorie_juridique, 1) = '7' THEN
        NEW.est_secteur_public := TRUE;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_creer_conversation_assignation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_conv_id UUID;
    v_etab_user_id UUID;
BEGIN
    -- Seulement quand on passe en ASSIGNEE avec un soignant
    IF NEW.statut != 'ASSIGNEE' OR NEW.soignant_assigne_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF OLD.statut = 'ASSIGNEE' AND OLD.soignant_assigne_id = NEW.soignant_assigne_id THEN
        RETURN NEW; -- Pas de changement
    END IF;

    -- L'établissement_id est aussi l'user_id (même UUID)
    v_etab_user_id := NEW.etablissement_id;

    -- Vérifier si une conversation existe déjà pour cette mission
    SELECT id INTO v_conv_id FROM conversations
    WHERE mission_id = NEW.id
    AND (
        (participant_1_id = NEW.soignant_assigne_id AND participant_2_id = v_etab_user_id)
        OR (participant_1_id = v_etab_user_id AND participant_2_id = NEW.soignant_assigne_id)
    );

    -- Si pas de conversation, en créer une
    IF v_conv_id IS NULL THEN
        INSERT INTO conversations (participant_1_id, participant_2_id, mission_id)
        VALUES (NEW.soignant_assigne_id, v_etab_user_id, NEW.id)
        RETURNING id INTO v_conv_id;

        -- Message système de bienvenue
        INSERT INTO messages_chat (conversation_id, auteur_id, contenu, est_admin)
        VALUES (v_conv_id, v_etab_user_id, 
            '📋 Mission "' || COALESCE(NEW.intitule, 'Mission') || '" assignée. Vous pouvez échanger ici pour coordonner les détails.',
            TRUE);
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_creer_partage_rib_contrat()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_doc_rib_id UUID;
BEGIN
    -- Seulement quand le contrat passe en SIGNE_COMPLET
    IF NEW.statut != 'SIGNE_COMPLET' THEN RETURN NEW; END IF;
    IF OLD.statut = 'SIGNE_COMPLET' THEN RETURN NEW; END IF;
    
    SELECT * INTO v_mission FROM missions WHERE id = NEW.mission_id;
    IF v_mission IS NULL OR v_mission.type_paiement_soignant != 'BULLETIN_PAIE' THEN
        RETURN NEW;
    END IF;
    
    -- Trouver le RIB vérifié du soignant
    SELECT id INTO v_doc_rib_id FROM documents_soignants
    WHERE soignant_id = NEW.soignant_id AND type_document = 'RIB'
    AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
    LIMIT 1;
    
    -- Créer le partage
    INSERT INTO partages_rib (soignant_id, etablissement_id, mission_id, contrat_id, actif, document_rib_id, partage_le)
    VALUES (NEW.soignant_id, NEW.etablissement_id, NEW.mission_id, NEW.id, TRUE, v_doc_rib_id, NOW())
    ON CONFLICT DO NOTHING;
    
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_email_contrat_a_signer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lien text;
BEGIN
  -- Ne tirer l'email que pour les contrats en attente de signature
  IF NEW.statut NOT IN ('EN_ATTENTE_SIGNATURES', 'EN_ATTENTE_SIGNATURE') THEN
    RETURN NEW;
  END IF;

  v_lien := 'https://app.jolene.app/contrat/' || NEW.id::text;

  -- Email soignant (best-effort, via net.http_post)
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_A_SIGNER',
        'destinataire_id', NEW.soignant_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'type_contrat', NEW.type_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- net pas dispo ou erreur réseau : silencieux
  END;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_incrementer_heures_plateforme()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.statut = 'TERMINEE' AND (OLD.statut IS NULL OR OLD.statut != 'TERMINEE') THEN
        UPDATE soignants SET
            heures_plateforme = COALESCE(heures_plateforme, 0) + COALESCE(NEW.duree_heures, 0),
            modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_fenetre_pointage()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_debut TIMESTAMPTZ;
    v_fin TIMESTAMPTZ;
BEGIN
    SELECT debut_le, fin_le INTO v_debut, v_fin
    FROM missions WHERE id = NEW.mission_id;

    IF NEW.pointage_arrivee_le IS NOT NULL AND NEW.pointage_arrivee_le < v_debut - INTERVAL '30 minutes' THEN
        RAISE EXCEPTION 'Pointage trop tôt. La mission commence à %.', TO_CHAR(v_debut, 'HH24:MI');
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_idempotence_facture_payee()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si la facture est DÉJÀ payée, ne rien faire
    IF OLD.statut = 'PAYEE' AND NEW.statut = 'PAYEE' THEN
        RETURN OLD; -- Pas de modification
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_limiter_liste_attente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF (SELECT COUNT(*) FROM liste_attente_premium WHERE utilisateur_id = auth.uid()) >= 3 THEN
        RAISE EXCEPTION 'Maximum 3 inscriptions à la liste d''attente.';
    END IF;
    NEW.utilisateur_id := auth.uid();
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_generer_codes_pointage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Système ① (codes statiques arrivée/départ) — conservé tel quel.
    NEW.code_arrivee := LPAD(FLOOR(RANDOM() * 999999)::TEXT, 6, '0');
    NEW.code_depart := LPAD(FLOOR(RANDOM() * 999999)::TEXT, 6, '0');
    WHILE NEW.code_depart = NEW.code_arrivee LOOP
        NEW.code_depart := LPAD(FLOOR(RANDOM() * 999999)::TEXT, 6, '0');
    END LOOP;

    -- Système ② (rotatif) — code de départ. fn_scanner_code_pointage le régénère
    -- à chaque scan. On n'écrase pas une valeur déjà présente.
    IF NEW.code_pointage_actif IS NULL THEN
        NEW.code_pointage_actif := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_evaluer_dans_delai()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_terminee_le TIMESTAMPTZ;
BEGIN
    SELECT terminee_le INTO v_terminee_le FROM missions WHERE id = NEW.mission_id;
    IF v_terminee_le IS NOT NULL AND v_terminee_le + INTERVAL '30 days' < NOW() THEN
        RAISE EXCEPTION 'Le délai d''évaluation de 30 jours est dépassé.';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_email_contrat_signe_complet()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lien text;
BEGIN
  -- Ne tirer que sur transition vers SIGNE_COMPLET
  IF OLD.statut = 'SIGNE_COMPLET' OR NEW.statut != 'SIGNE_COMPLET' THEN
    RETURN NEW;
  END IF;

  v_lien := 'https://app.jolene.app/contrat/' || NEW.id::text;

  -- Email soignant
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.soignant_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Email étab
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'CONTRAT_SIGNE',
        'destinataire_id', NEW.etablissement_id,
        'data', jsonb_build_object(
          'numero_contrat', NEW.numero_contrat,
          'lien', v_lien
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', 'SYSTEME',
    'CONTRAT_SIGNE', 'contrat_mission', NEW.id,
    jsonb_build_object(
      'evenement', 'CONTRAT_SIGNE_COMPLET_AUTO',
      'numero_contrat', NEW.numero_contrat,
      'type_contrat', NEW.type_contrat,
      'mode_signature', NEW.mode_signature,
      'dpae_requise', (NEW.type_contrat IN ('CDD', 'CDD'))
    )
  );

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_email_invitation_equipe_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_nom text;
  v_invite_par_email text;
  v_invite_par_nom text;
BEGIN
  -- Ne tirer l'email que pour les invitations EN_ATTENTE fraîches
  IF NEW.statut != 'EN_ATTENTE' THEN
    RETURN NEW;
  END IF;

  -- Récupérer nom étab
  SELECT nom INTO v_etab_nom FROM public.etablissements WHERE id = NEW.etablissement_id;
  IF v_etab_nom IS NULL THEN
    RETURN NEW;
  END IF;

  -- Récupérer nom de l'invitant (PROPRIETAIRE qui crée l'invitation)
  SELECT u.email INTO v_invite_par_email FROM auth.users u WHERE u.id = NEW.invite_par;
  v_invite_par_nom := COALESCE(v_invite_par_email, 'Un administrateur');

  -- Envoi best-effort via net.http_post → send-email edge function
  -- Flow externe : destinataire_email (l'invité peut ne pas avoir de compte)
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'type', 'INVITATION_EQUIPE_ETAB',
        'destinataire_email', NEW.email_invite,
        'data', jsonb_build_object(
          'token', NEW.token,
          'nom_etablissement', v_etab_nom,
          'role', NEW.role_propose,
          'invite_par_nom', v_invite_par_nom,
          'expire_le', to_char(NEW.expire_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY à HH24:MI')
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- net.http_post indisponible ou erreur réseau : silencieux
    -- L'UI affiche déjà le lien d'invitation pour copier/coller manuel
    NULL;
  END;

  -- Audit (action générique SYSTEM, contexte dans details)
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    NEW.invite_par, 'SYSTEME', 'SYSTEM', 'invitation_etab', NEW.id,
    jsonb_build_object(
      'evenement', 'EMAIL_INVITATION_EQUIPE_ENVOYE',
      'destinataire_email', NEW.email_invite,
      'etablissement_id', NEW.etablissement_id,
      'role_propose', NEW.role_propose
    )
  );

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_mettre_a_jour_fiabilite()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_parrain_id UUID;
  v_nb_filleuls_valides INT;
  v_parrain_avait_badge BOOLEAN;
  v_filleul_prenom TEXT;
  v_heures_mission NUMERIC;
BEGIN
    IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;

    IF NEW.statut = 'TERMINEE' AND OLD.statut != 'TERMINEE' THEN
        v_heures_mission := COALESCE(
            (SELECT SUM(pr.heures_reelles) FROM public.presences pr
              WHERE pr.mission_id = NEW.id AND pr.heures_reelles IS NOT NULL),
            EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0
        );

        UPDATE soignants SET
            total_missions_terminees = total_missions_terminees + 1,
            heures_cumulees = heures_cumulees + v_heures_mission,
            eligible_conversion_3200h = (heures_cumulees + v_heures_mission) >= 3200,
            premiere_mission_le = COALESCE(premiere_mission_le, NOW()),
            derniere_activite_le = NOW(), modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;

        UPDATE suivi_conversion_3200h SET
            heures_actuelles = (SELECT heures_cumulees FROM soignants WHERE id = NEW.soignant_assigne_id),
            jalon_800h_atteint  = heures_actuelles >= 800,
            jalon_1600h_atteint = heures_actuelles >= 1600,
            jalon_2400h_atteint = heures_actuelles >= 2400,
            jalon_3200h_atteint = heures_actuelles >= 3200,
            modifie_le = NOW()
        WHERE soignant_id = NEW.soignant_assigne_id;

        SELECT parraine_par, prenom INTO v_parrain_id, v_filleul_prenom
        FROM soignants WHERE id = NEW.soignant_assigne_id;

        IF v_parrain_id IS NOT NULL THEN
          SELECT COUNT(*) INTO v_nb_filleuls_valides
          FROM soignants
          WHERE parraine_par = v_parrain_id
            AND premiere_mission_le IS NOT NULL
            AND supprime_le IS NULL;

          IF v_nb_filleuls_valides >= 3 THEN
            SELECT badge_ambassadeur INTO v_parrain_avait_badge
            FROM soignants WHERE id = v_parrain_id;

            IF NOT COALESCE(v_parrain_avait_badge, false) THEN
              UPDATE soignants SET badge_ambassadeur = true, modifie_le = NOW()
              WHERE id = v_parrain_id;

              INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
              VALUES (
                v_parrain_id, 'SOIGNANT', 'PARRAINAGE',
                '🛡️ Badge Ambassadeur débloqué !',
                'Bravo ! ' || COALESCE(v_filleul_prenom, 'Votre filleul')
                  || ' vient de terminer sa 1ère mission. Vous avez 3 filleuls validés et obtenez le badge Ambassadeur, visible sur votre profil.',
                '/soignant/parrainage'
              );
            END IF;
          END IF;
        END IF;
    END IF;

    IF NEW.statut = 'ABSENCE' AND OLD.statut != 'ABSENCE' THEN
        UPDATE soignants SET total_absences = total_absences + 1, modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;

    IF NEW.statut = 'ANNULEE_PAR_SOIGNANT' AND OLD.statut != 'ANNULEE_PAR_SOIGNANT' THEN
        UPDATE soignants SET total_missions_annulees = total_missions_annulees + 1, modifie_le = NOW()
        WHERE id = NEW.soignant_assigne_id;
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_machine_etats_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF OLD.statut IS DISTINCT FROM NEW.statut THEN
        IF NOT (
            (OLD.statut = 'OUVERTE' AND NEW.statut IN ('ASSIGNEE', 'ANNULEE_PAR_ETABLISSEMENT'))
            OR (OLD.statut = 'ASSIGNEE' AND NEW.statut IN ('EN_COURS', 'ANNULEE_PAR_SOIGNANT', 'ANNULEE_PAR_ETABLISSEMENT'))
            OR (OLD.statut = 'EN_COURS' AND NEW.statut IN ('TERMINEE', 'ABSENCE', 'LITIGE'))
            OR (OLD.statut = 'TERMINEE' AND NEW.statut = 'LITIGE')
            OR (OLD.statut = 'LITIGE' AND NEW.statut IN ('TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT'))
            OR est_admin()
        ) THEN
            RAISE EXCEPTION 'Transition de statut interdite : % -> %', OLD.statut, NEW.statut;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_litige_reponse_auto_statut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF OLD.reponse IS NULL AND NEW.reponse IS NOT NULL AND NEW.statut = 'OUVERT' THEN
        NEW.statut := 'EN_DISCUSSION';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_maj_compteurs_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant_id UUID;
BEGIN
    v_soignant_id := COALESCE(NEW.soignant_assigne_id, OLD.soignant_assigne_id);
    IF v_soignant_id IS NULL THEN RETURN NEW; END IF;

    PERFORM set_config('jolene.system_update', 'true', true);

    UPDATE soignants SET
        total_missions_terminees = (SELECT COUNT(*) FROM missions WHERE soignant_assigne_id = v_soignant_id AND statut = 'TERMINEE'),
        total_missions_annulees = (SELECT COUNT(*) FROM missions WHERE soignant_assigne_id = v_soignant_id AND statut IN ('ANNULEE_PAR_SOIGNANT')),
        total_absences = (SELECT COUNT(*) FROM missions WHERE soignant_assigne_id = v_soignant_id AND statut = 'ABSENCE'),
        heures_cumulees = COALESCE((SELECT SUM(duree_heures) FROM missions WHERE soignant_assigne_id = v_soignant_id AND statut = 'TERMINEE'), 0),
        modifie_le = NOW()
    WHERE id = v_soignant_id;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_maj_tous_documents_valides()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM fn_calculer_tous_documents_valides(COALESCE(NEW.soignant_id, OLD.soignant_id));
  RETURN COALESCE(NEW, OLD);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_maj_note_moyenne()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_note_moy NUMERIC;
    v_nb_evals INT;
    v_missions_term INT;
    v_absences INT;
    v_anciennete_mois INT;
    v_score INT;
BEGIN
    SELECT ROUND(AVG(note)::NUMERIC, 2), COUNT(*)
    INTO v_note_moy, v_nb_evals
    FROM evaluations WHERE evalue_id = NEW.evalue_id AND visible = TRUE;

    SELECT 
        COUNT(*) FILTER (WHERE statut = 'TERMINEE'),
        COUNT(*) FILTER (WHERE statut = 'ABSENCE')
    INTO v_missions_term, v_absences
    FROM missions WHERE soignant_assigne_id = NEW.evalue_id;

    SELECT GREATEST(1, EXTRACT(MONTH FROM AGE(NOW(), cree_le))::INT)
    INTO v_anciennete_mois
    FROM soignants WHERE id = NEW.evalue_id;

    v_score := LEAST(100, GREATEST(0,
        ROUND(COALESCE(v_note_moy, 3) * 8)
        + CASE WHEN v_missions_term = 0 THEN 20
               ELSE ROUND(GREATEST(0, 1 - (v_absences::NUMERIC / GREATEST(v_missions_term, 1))) * 40)
          END
        + LEAST(20, v_anciennete_mois * 20 / 12)
    ));

    -- Poser le flag pour que le trigger de protection autorise le changement
    PERFORM set_config('jolene.system_update', 'true', true);

    UPDATE soignants SET
        note_moyenne = v_note_moy,
        nb_evaluations = v_nb_evals,
        score_fiabilite = v_score,
        modifie_le = NOW()
    WHERE id = NEW.evalue_id;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_maj_note_moyenne_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Mettre à jour si c'est un établissement qui est évalué
    IF NEW.type_evaluateur = 'SOIGNANT' THEN
        UPDATE etablissements SET
            note_moyenne = (SELECT ROUND(AVG(note)::NUMERIC, 2) FROM evaluations WHERE evalue_id = NEW.evalue_id AND visible = TRUE AND type_evaluateur = 'SOIGNANT'),
            nb_evaluations = (SELECT COUNT(*) FROM evaluations WHERE evalue_id = NEW.evalue_id AND visible = TRUE AND type_evaluateur = 'SOIGNANT'),
            modifie_le = NOW()
        WHERE id = NEW.evalue_id;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_notif_signature_soignant_recue()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_lien text;
BEGIN
  IF NEW.signature_soignant IS NOT TRUE THEN RETURN NEW; END IF;
  IF OLD.signature_soignant = TRUE THEN RETURN NEW; END IF;
  IF NEW.signature_etablissement IS TRUE THEN RETURN NEW; END IF;
  IF NEW.statut IN ('SIGNE_COMPLET','ANNULE','EXPIRE','REFUSE') THEN RETURN NEW; END IF;
  v_lien := 'https://app.jolene.app/contrat/' || NEW.id::text;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
      body := jsonb_build_object(
        'type', 'CONTRAT_A_SIGNER', 'destinataire_id', NEW.etablissement_id,
        'data', jsonb_build_object('numero_contrat', NEW.numero_contrat, 'type_contrat', NEW.type_contrat,
                                    'lien', v_lien, 'signataire_precedent', 'soignant'))
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
      body := jsonb_build_object('destinataire_id', NEW.etablissement_id,
        'type_evenement', 'CONTRAT_A_SIGNER',
        'titre', 'Le soignant a signé — à votre tour',
        'corps', 'Le contrat ' || COALESCE(NEW.numero_contrat, '') || ' attend votre signature.',
        'data', jsonb_build_object('contrat_id', NEW.id, 'lien', v_lien))
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_notifier_changement_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_nom TEXT;
    v_soignant_nom TEXT;
BEGIN
    SELECT nom INTO v_etab_nom FROM etablissements WHERE id = NEW.etablissement_id;

    IF NEW.statut = 'ASSIGNEE' AND (OLD.statut IS NULL OR OLD.statut = 'OUVERTE') THEN
        SELECT COALESCE(prenom, '') || ' ' || COALESCE(nom, '') INTO v_soignant_nom 
        FROM soignants WHERE id = NEW.soignant_assigne_id;
        
        PERFORM fn_creer_notification(
            NEW.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_ACCEPTEE',
            'Mission acceptée',
            COALESCE(v_soignant_nom, 'Un soignant') || ' a accepté la mission "' || COALESCE(NEW.intitule, 'Mission') || '".',
            '/etablissement/missions/' || NEW.id::TEXT,
            'mission', NEW.id
        );
    END IF;

    IF NEW.statut IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT') 
       AND OLD.statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT') THEN
        IF NEW.soignant_assigne_id IS NOT NULL THEN
            PERFORM fn_creer_notification(
                NEW.soignant_assigne_id, 'SOIGNANT', 'MISSION_ANNULEE',
                'Mission annulée',
                'La mission "' || COALESCE(NEW.intitule, 'Mission') || '" chez ' || COALESCE(v_etab_nom, 'un établissement') || ' a été annulée.',
                '/soignant/missions', 'mission', NEW.id
            );
        END IF;
        PERFORM fn_creer_notification(
            NEW.etablissement_id, 'ETABLISSEMENT', 'MISSION_ANNULEE',
            'Mission annulée',
            'La mission "' || COALESCE(NEW.intitule, 'Mission') || '" a été annulée.',
            '/etablissement/missions/' || NEW.id::TEXT, 'mission', NEW.id
        );
    END IF;

    IF NEW.statut = 'TERMINEE' AND OLD.statut != 'TERMINEE' THEN
        IF NEW.soignant_assigne_id IS NOT NULL THEN
            PERFORM fn_creer_notification(
                NEW.soignant_assigne_id, 'SOIGNANT', 'MISSION_TERMINEE',
                'Mission terminée',
                'Votre mission "' || COALESCE(NEW.intitule, 'Mission') || '" chez ' || COALESCE(v_etab_nom, 'un établissement') || ' est terminée.',
                '/soignant/missions', 'mission', NEW.id
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_notifier_nouveau_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_notification_type TEXT;
    v_titre TEXT;
    v_corps TEXT;
BEGIN
    SELECT id, etablissement_id, soignant_assigne_id
    INTO v_mission
    FROM public.missions
    WHERE id = NEW.mission_id;

    IF v_mission.id IS NULL THEN
        RETURN NEW;
    END IF;

    v_notification_type := CASE
        WHEN NEW.type_auteur = 'ADMIN' THEN 'MESSAGE_ADMIN'
        ELSE 'MESSAGE_RECU'
    END;

    v_titre := CASE
        WHEN NEW.type_auteur = 'ADMIN' THEN '🛡️ Message de l''équipe Jolene'
        WHEN NEW.type_auteur = 'SOIGNANT' THEN '💬 Nouveau message du soignant'
        ELSE '💬 Nouveau message de l''établissement'
    END;

    v_corps := LEFT(NEW.contenu, 100);

    IF NEW.type_auteur = 'ADMIN' THEN
        IF v_mission.soignant_assigne_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.soignant_assigne_id,
                'SOIGNANT',
                v_notification_type,
                v_titre,
                v_corps,
                '/soignant/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;

        IF v_mission.etablissement_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.etablissement_id,
                'ETABLISSEMENT',
                v_notification_type,
                v_titre,
                v_corps,
                '/etablissement/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;
    ELSIF NEW.type_auteur = 'SOIGNANT' THEN
        IF v_mission.etablissement_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.etablissement_id,
                'ETABLISSEMENT',
                v_notification_type,
                v_titre,
                v_corps,
                '/etablissement/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;
    ELSIF NEW.type_auteur = 'ETABLISSEMENT' THEN
        IF v_mission.soignant_assigne_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.soignant_assigne_id,
                'SOIGNANT',
                v_notification_type,
                v_titre,
                v_corps,
                '/soignant/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_penalite_annulation_tardive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_heures_avant NUMERIC;
    v_penalite INTEGER;
BEGIN
    -- Annulation par le soignant
    IF NEW.statut = 'ANNULEE_PAR_SOIGNANT' AND OLD.statut = 'ASSIGNEE' THEN
        v_heures_avant := EXTRACT(EPOCH FROM (OLD.debut_le - NOW())) / 3600;

        IF v_heures_avant < 4 THEN
            v_penalite := 25;
        ELSIF v_heures_avant < 24 THEN
            v_penalite := 15;
        ELSE
            v_penalite := 8; -- pénalité standard déjà en place
        END IF;

        -- Appliquer la pénalité au score
        UPDATE soignants SET
            score_fiabilite = GREATEST(0, score_fiabilite - v_penalite),
            total_missions_annulees = total_missions_annulees + 1,
            modifie_le = NOW()
        WHERE id = OLD.soignant_assigne_id;

        -- Remettre la mission en OUVERTE pour qu'un autre soignant puisse la prendre
        NEW.soignant_assigne_id := NULL;
        NEW.statut := 'OUVERTE';
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_champs_commerciaux_etab()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN
        NEW.stripe_customer_id := OLD.stripe_customer_id;
        NEW.taux_commission_negocie := OLD.taux_commission_negocie;
        NEW.mode_facturation := OLD.mode_facturation;
        NEW.chorus_pro_identifiant := OLD.chorus_pro_identifiant;
        NEW.chorus_pro_actif := OLD.chorus_pro_actif;
        NEW.delai_paiement_jours := OLD.delai_paiement_jours;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_premiere_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.statut = 'ASSIGNEE' AND OLD.statut = 'OUVERTE' AND NEW.soignant_assigne_id IS NOT NULL THEN
        UPDATE soignants SET
            premiere_mission_le = COALESCE(premiere_mission_le, NOW())
        WHERE id = NEW.soignant_assigne_id
          AND premiere_mission_le IS NULL;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_notifier_resolution_litige()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant_nom TEXT;
    v_mission_intitule TEXT;
    v_resolution_label TEXT;
BEGIN
    IF OLD.statut = NEW.statut THEN RETURN NEW; END IF;
    IF NEW.statut NOT IN ('RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME') THEN RETURN NEW; END IF;

    SELECT COALESCE(prenom || ' ', '') || nom INTO v_soignant_nom FROM soignants WHERE id = NEW.soignant_id;
    SELECT intitule INTO v_mission_intitule FROM missions WHERE id = NEW.mission_id;

    CASE NEW.statut
        WHEN 'RESOLU_SOIGNANT' THEN v_resolution_label := 'résolu en faveur du soignant';
        WHEN 'RESOLU_ETABLISSEMENT' THEN v_resolution_label := 'résolu en faveur de l''établissement';
        WHEN 'RESOLU_ADMIN' THEN v_resolution_label := 'résolu par l''administrateur';
        WHEN 'FERME' THEN v_resolution_label := 'clôturé par accord mutuel';
    END CASE;

    -- Notifier le soignant
    PERFORM fn_creer_notification(
        NEW.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
        'Litige ' || v_resolution_label,
        'Le litige concernant la mission "' || COALESCE(v_mission_intitule, 'Mission') || '" a été ' || v_resolution_label || '.',
        '/soignant/litiges',
        'litige', NEW.id
    );

    -- Notifier l'établissement
    PERFORM fn_creer_notification(
        NEW.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
        'Litige ' || v_resolution_label,
        'Le litige avec ' || COALESCE(v_soignant_nom, 'un soignant') || ' sur la mission "' || COALESCE(v_mission_intitule, 'Mission') || '" a été ' || v_resolution_label || '.',
        '/etablissement/litiges',
        'litige', NEW.id
    );
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_notifier_creation_litige()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_nom TEXT;
    v_soignant_nom TEXT;
    v_mission_intitule TEXT;
BEGIN
    SELECT nom INTO v_etab_nom FROM etablissements WHERE id = NEW.etablissement_id;
    SELECT COALESCE(prenom || ' ', '') || nom INTO v_soignant_nom FROM soignants WHERE id = NEW.soignant_id;
    SELECT intitule INTO v_mission_intitule FROM missions WHERE id = NEW.mission_id;

    IF NEW.initie_par = 'SOIGNANT' THEN
        PERFORM fn_creer_notification(
            NEW.etablissement_id, 'ETABLISSEMENT', 'LITIGE_OUVERT',
            'Nouveau litige signalé',
            COALESCE(v_soignant_nom, 'Un soignant') || ' a ouvert un litige sur la mission "' || COALESCE(v_mission_intitule, 'Mission') || '".',
            '/etablissement/litiges',
            'litige', NEW.id
        );
    ELSE
        PERFORM fn_creer_notification(
            NEW.soignant_id, 'SOIGNANT', 'LITIGE_OUVERT',
            'Nouveau litige signalé',
            'L''établissement "' || COALESCE(v_etab_nom, 'Établissement') || '" a ouvert un litige sur la mission "' || COALESCE(v_mission_intitule, 'Mission') || '".',
            '/soignant/litiges',
            'litige', NEW.id
        );
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_notifier_reponse_litige()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_nom TEXT;
    v_soignant_nom TEXT;
    v_mission_intitule TEXT;
    v_repondant TEXT;
BEGIN
    -- Détecter un ajout de réponse (texte plus long = nouvelle réponse ajoutée)
    IF NEW.reponse IS NULL THEN RETURN NEW; END IF;
    IF OLD.reponse IS NOT NULL AND LENGTH(NEW.reponse) <= LENGTH(OLD.reponse) THEN RETURN NEW; END IF;

    SELECT nom INTO v_etab_nom FROM etablissements WHERE id = NEW.etablissement_id;
    SELECT COALESCE(prenom || ' ', '') || nom INTO v_soignant_nom FROM soignants WHERE id = NEW.soignant_id;
    SELECT intitule INTO v_mission_intitule FROM missions WHERE id = NEW.mission_id;

    -- Déterminer qui a répondu en regardant la dernière ligne
    IF NEW.reponse LIKE '%Établissement:%' AND (OLD.reponse IS NULL OR NOT OLD.reponse LIKE '%' || split_part(NEW.reponse, E'\n', -1)) THEN
        -- L'établissement a répondu → notifier le soignant
        PERFORM fn_creer_notification(
            NEW.soignant_id, 'SOIGNANT', 'LITIGE_REPONSE',
            'Réponse à votre litige',
            'L''établissement "' || COALESCE(v_etab_nom, 'Établissement') || '" a répondu à votre litige sur "' || COALESCE(v_mission_intitule, 'Mission') || '".',
            '/soignant/litiges',
            'litige', NEW.id
        );
    ELSIF NEW.reponse LIKE '%Soignant:%' THEN
        -- Le soignant a répondu → notifier l'établissement
        PERFORM fn_creer_notification(
            NEW.etablissement_id, 'ETABLISSEMENT', 'LITIGE_REPONSE',
            'Réponse à votre litige',
            COALESCE(v_soignant_nom, 'Le soignant') || ' a répondu à votre litige sur "' || COALESCE(v_mission_intitule, 'Mission') || '".',
            '/etablissement/litiges',
            'litige', NEW.id
        );
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_journaux_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    RAISE EXCEPTION '[SÉCURITÉ] Les journaux d''audit sont immuables. Toute modification ou suppression est interdite.';
    RETURN NULL;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_contenu_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Service role → passthrough
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
        RETURN NEW;
    END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;

    -- Seuls lue et lue_le peuvent être modifiés par le destinataire
    IF OLD.titre != NEW.titre
       OR OLD.corps != NEW.corps
       OR OLD.type != NEW.type
       OR OLD.destinataire_id != NEW.destinataire_id THEN
        IF NOT est_admin() THEN
            RAISE EXCEPTION 'INTERDIT : seuls les champs de lecture peuvent être modifiés.';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_donnees_financieres_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si c'est un soignant qui modifie (pas un admin)
    IF est_soignant() AND NOT est_admin() THEN
        -- Bloquer toute modification des colonnes financières
        IF OLD.taux_horaire_base IS DISTINCT FROM NEW.taux_horaire_base
           OR OLD.total_brut IS DISTINCT FROM NEW.total_brut
           OR OLD.net_a_payer IS DISTINCT FROM NEW.net_a_payer
           OR OLD.montant_ifm IS DISTINCT FROM NEW.montant_ifm
           OR OLD.montant_icp IS DISTINCT FROM NEW.montant_icp
           OR OLD.montant_majoration_nuit IS DISTINCT FROM NEW.montant_majoration_nuit
           OR OLD.montant_majoration_dimanche IS DISTINCT FROM NEW.montant_majoration_dimanche
           OR OLD.montant_majoration_ferie IS DISTINCT FROM NEW.montant_majoration_ferie
           OR OLD.taux_commission IS DISTINCT FROM NEW.taux_commission
           OR OLD.montant_commission_ht IS DISTINCT FROM NEW.montant_commission_ht
           OR OLD.duree_heures IS DISTINCT FROM NEW.duree_heures
           OR OLD.etablissement_id IS DISTINCT FROM NEW.etablissement_id
        THEN
            RAISE EXCEPTION 'INTERDIT : un soignant ne peut pas modifier les données financières.';
        END IF;

        -- Le soignant peut uniquement modifier : soignant_assigne_id (accepter) et statut
        -- Vérifier que le statut change vers un statut autorisé
        IF OLD.statut IS DISTINCT FROM NEW.statut THEN
            IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ANNULEE_PAR_SOIGNANT') THEN
                RAISE EXCEPTION 'INTERDIT : transition de statut non autorisée pour un soignant.';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_presence_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() AND NOT est_admin_etablissement() THEN
        -- Le soignant ne peut PAS modifier :
        NEW.valide_par_etablissement := OLD.valide_par_etablissement;
        NEW.valide_le := OLD.valide_le;
        NEW.alerte_teleportation := OLD.alerte_teleportation;
        NEW.alertes_fraude := OLD.alertes_fraude;
        NEW.perimetre_gps_valide := OLD.perimetre_gps_valide;
        NEW.distance_etablissement_m := OLD.distance_etablissement_m;
        NEW.motif_litige := OLD.motif_litige;
        NEW.heures_reelles := OLD.heures_reelles;
        NEW.duree_brute_min := OLD.duree_brute_min;
        NEW.duree_nette_min := OLD.duree_nette_min;
        NEW.retard_min := OLD.retard_min;
        NEW.depart_anticipe_min := OLD.depart_anticipe_min;
        NEW.mission_id := OLD.mission_id;
        NEW.soignant_id := OLD.soignant_id;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_signature_contrat()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF est_soignant() AND NOT est_admin() THEN
        -- Le soignant ne peut signer QUE sa propre partie
        NEW.signature_etablissement := OLD.signature_etablissement;
        NEW.signature_etablissement_le := OLD.signature_etablissement_le;
        NEW.signature_image_etablissement := OLD.signature_image_etablissement;
        NEW.signature_ip_etablissement := OLD.signature_ip_etablissement;
        NEW.signature_navigateur_etablissement := OLD.signature_navigateur_etablissement;
        -- Il ne peut pas modifier le contenu ni le numéro
        NEW.contenu_html := OLD.contenu_html;
        NEW.numero_contrat := OLD.numero_contrat;
        NEW.type_contrat := OLD.type_contrat;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.soignant_id := OLD.soignant_id;
        NEW.mission_id := OLD.mission_id;
    END IF;

    IF est_admin_etablissement() AND NOT est_admin() THEN
        -- L'admin étab ne peut signer QUE sa propre partie
        NEW.signature_soignant := OLD.signature_soignant;
        NEW.signature_soignant_le := OLD.signature_soignant_le;
        NEW.signature_image_soignant := OLD.signature_image_soignant;
        NEW.signature_ip_soignant := OLD.signature_ip_soignant;
        NEW.signature_navigateur_soignant := OLD.signature_navigateur_soignant;
        -- Il ne peut pas modifier le contenu ni le numéro
        NEW.contenu_html := OLD.contenu_html;
        NEW.numero_contrat := OLD.numero_contrat;
        NEW.type_contrat := OLD.type_contrat;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.soignant_id := OLD.soignant_id;
        NEW.mission_id := OLD.mission_id;
    END IF;

    -- Auto-update du statut
    IF NEW.signature_soignant = TRUE AND NEW.signature_etablissement = TRUE THEN
        NEW.statut := 'SIGNE_COMPLET';
    ELSIF NEW.signature_soignant = TRUE AND OLD.signature_soignant IS DISTINCT FROM TRUE THEN
        NEW.statut := 'SIGNE_SOIGNANT';
    ELSIF NEW.signature_etablissement = TRUE AND OLD.signature_etablissement IS DISTINCT FROM TRUE THEN
        NEW.statut := 'SIGNE_ETABLISSEMENT';
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_resolution_litige()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;

    IF NEW.statut IN ('FERME','RESOLU_ACCORD_PARTIES') AND NOT est_admin() THEN
        IF COALESCE(NEW.accord_soignant, FALSE) AND COALESCE(NEW.accord_etablissement, FALSE) THEN
            NEW.resolu_le := COALESCE(NEW.resolu_le, NOW());
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'Seul l''administrateur peut clôturer un litige sans accord mutuel.';
        END IF;
    END IF;

    IF NEW.statut IN ('RESOLU_ADMIN','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE','REVUE_ADMIN')
       AND NOT est_admin() THEN
        RAISE EXCEPTION 'Seul l''administrateur peut résoudre un litige (ou demander revue admin).';
    END IF;

    IF NOT est_admin() THEN
        NEW.resolu_par := OLD.resolu_par;
        IF NEW.statut NOT IN ('FERME','RESOLU_ACCORD_PARTIES') THEN
            NEW.resolution := OLD.resolution;
        END IF;
    END IF;

    IF NEW.statut IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME',
                      'RESOLU_ACCORD_PARTIES','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE')
       AND OLD.statut NOT IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME',
                              'RESOLU_ACCORD_PARTIES','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE') THEN
        NEW.resolu_le := COALESCE(NEW.resolu_le, NOW());
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_proteger_validation_documents()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Service role → passthrough
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    
    IF est_admin() THEN RETURN NEW; END IF;

    -- Un soignant ne peut pas se valider ses propres documents
    IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification THEN
        RAISE EXCEPTION 'Seul un administrateur peut modifier le statut de vérification';
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_sanitiser_contrat()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.contenu_html IS NOT NULL THEN
        NEW.contenu_html := fn_sanitiser_html(NEW.contenu_html);
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_refuser_mission_passee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.debut_le < NOW() - INTERVAL '1 hour' THEN
        RAISE EXCEPTION 'Impossible de publier une mission dans le passé.';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_refuser_chevauchement_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.soignant_assigne_id IS NOT NULL AND NEW.statut IN ('ASSIGNEE', 'EN_COURS') THEN
        IF EXISTS (
            SELECT 1 FROM missions
            WHERE soignant_assigne_id = NEW.soignant_assigne_id
              AND id != NEW.id
              AND statut IN ('ASSIGNEE', 'EN_COURS')
              AND debut_le < NEW.fin_le
              AND fin_le > NEW.debut_le
        ) THEN
            RAISE EXCEPTION 'Ce soignant a déjà une mission sur ce créneau.';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_refuser_auto_evaluation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_statut statut_mission;
BEGIN
    IF NEW.evaluateur_id = NEW.evalue_id THEN
        RAISE EXCEPTION 'Vous ne pouvez pas vous évaluer vous-même.';
    END IF;
    SELECT statut INTO v_statut FROM missions WHERE id = NEW.mission_id;
    IF v_statut != 'TERMINEE' THEN
        RAISE EXCEPTION 'L''évaluation n''est possible qu''après la fin de la mission.';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_rappel_evaluation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.statut = 'TERMINEE' AND (OLD.statut IS NULL OR OLD.statut != 'TERMINEE') THEN
        -- Notifier l'établissement de laisser une évaluation
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (NEW.etablissement_id, 'SYSTEM',
            '⭐ Évaluez le soignant',
            'La mission "' || NEW.intitule || '" est terminée. Laissez une évaluation pour aider la communauté.',
            '/etablissement/missions/' || NEW.id, 'ETABLISSEMENT');

        -- Notifier le soignant de laisser une évaluation
        IF NEW.soignant_assigne_id IS NOT NULL THEN
            INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (NEW.soignant_assigne_id, 'SYSTEM',
                '⭐ Évaluez l''établissement',
                'La mission "' || NEW.intitule || '" est terminée. Laissez une évaluation.',
                '/soignant/evaluations', 'SOIGNANT');
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_push_contrat_a_signer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN
  IF NEW.statut NOT IN ('EN_ATTENTE_SIGNATURES', 'EN_ATTENTE_SIGNATURE') THEN RETURN NEW; END IF;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
      body := jsonb_build_object(
        'destinataire_id', NEW.soignant_id, 'type_evenement', 'CONTRAT_A_SIGNER',
        'titre', 'Contrat à signer',
        'corps', 'Vous avez un nouveau contrat ' || COALESCE(NEW.numero_contrat, '') || ' à signer.',
        'data', jsonb_build_object('contrat_id', NEW.id, 'lien', 'https://app.jolene.app/contrat/' || NEW.id::text))
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_push_contrat_signe_complet()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN
  IF OLD.statut = 'SIGNE_COMPLET' OR NEW.statut != 'SIGNE_COMPLET' THEN RETURN NEW; END IF;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
      body := jsonb_build_object(
        'destinataire_id', NEW.soignant_id, 'type_evenement', 'CONTRAT_SIGNE',
        'titre', 'Contrat signé ✅',
        'corps', 'Mission confirmée : contrat ' || COALESCE(NEW.numero_contrat, '') || ' signé par les 2 parties.',
        'data', jsonb_build_object('contrat_id', NEW.id, 'lien', 'https://app.jolene.app/contrat/' || NEW.id::text))
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
      body := jsonb_build_object(
        'destinataire_id', NEW.etablissement_id, 'type_evenement', 'CONTRAT_SIGNE',
        'titre', 'Contrat signé ✅',
        'corps', 'Mission confirmée : contrat ' || COALESCE(NEW.numero_contrat, '') || '.',
        'data', jsonb_build_object('contrat_id', NEW.id, 'lien', 'https://app.jolene.app/contrat/' || NEW.id::text))
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_set_candidature_acceptee_a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.statut = 'ACCEPTEE' AND OLD.statut IS DISTINCT FROM 'ACCEPTEE' THEN
    NEW.acceptee_a := COALESCE(NEW.acceptee_a, NOW());
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_valider_paiement_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.statut = 'PAYEE' AND OLD.statut != 'PAYEE' THEN
        IF NOT est_admin() THEN
            IF NEW.etablissement_id != mon_etablissement_id() THEN
                RAISE EXCEPTION 'INTERDIT : vous ne pouvez payer que vos propres factures.';
            END IF;
        END IF;
    END IF;
    IF OLD.etablissement_id != NEW.etablissement_id THEN
        RAISE EXCEPTION 'INTERDIT : le propriétaire ne peut pas être modifié.';
    END IF;
    IF OLD.montant_ht IS DISTINCT FROM NEW.montant_ht AND NOT est_admin() THEN
        RAISE EXCEPTION 'INTERDIT : le montant ne peut pas être modifié.';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_age_minimum()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.date_naissance IS NOT NULL AND NEW.date_naissance > CURRENT_DATE - INTERVAL '18 years' THEN
        RAISE EXCEPTION 'Vous devez avoir au moins 18 ans pour vous inscrire.';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_valider_couleur_theme()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.couleur_theme IS NOT NULL AND NEW.couleur_theme !~ '^#[0-9a-fA-F]{6}$' THEN
        NEW.couleur_theme := '#17A2B8';
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_docs_avant_debut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_rcp_ok BOOLEAN;
BEGIN
    IF NEW.statut = 'EN_COURS' AND OLD.statut = 'ASSIGNEE' AND NEW.soignant_assigne_id IS NOT NULL THEN
        IF NOT fn_documents_ok_pour_mission(NEW.soignant_assigne_id, NEW.type_contrat_applique::text) THEN
            RAISE EXCEPTION 'Documents obligatoires non validés pour le régime de cette mission. Le soignant doit compléter son dossier avant le début.';
        END IF;
        IF NEW.type_contrat_applique = 'LIBERAL' THEN
            SELECT EXISTS(SELECT 1 FROM documents_soignants
                WHERE soignant_id = NEW.soignant_assigne_id AND type_document = 'RCP_ASSURANCE'
                AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
                AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_ok;
            IF NOT v_rcp_ok THEN
                RAISE EXCEPTION 'Assurance RCP manquante ou expirée. Le soignant ne peut pas commencer la mission en libéral.';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_sync_types_contrat_exercice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.type_exercice IS DISTINCT FROM OLD.type_exercice THEN
        CASE NEW.type_exercice
            WHEN 'MIXTE' THEN NEW.types_contrat_acceptes := 'CDD,LIBERAL';
            WHEN 'LIBERAL' THEN NEW.types_contrat_acceptes := 'LIBERAL';
            WHEN 'SALARIE' THEN NEW.types_contrat_acceptes := 'CDD';
            ELSE NULL;
        END CASE;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_valider_type_contrat_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.type_contrat_recherche = 'LIBERAL' THEN
        IF NOT fn_profession_peut_etre_liberal(NEW.profession_requise::TEXT) THEN
            RAISE EXCEPTION 'La profession % ne peut pas exercer en libéral. Seul le type "Salarié" est autorisé pour cette profession.', NEW.profession_requise;
        END IF;
    ELSIF NEW.type_contrat_recherche = 'TOUS' THEN
        -- Profession salariée uniquement : 'TOUS' se réduit de fait à 'SALARIE'
        IF NOT fn_profession_peut_etre_liberal(NEW.profession_requise::TEXT) THEN
            NEW.type_contrat_recherche := 'SALARIE';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_valider_type_exercice_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Si le soignant se déclare libéral ou mixte, vérifier que sa profession le permet
    IF NEW.type_exercice IN ('LIBERAL', 'MIXTE') THEN
        IF NOT fn_profession_peut_etre_liberal(NEW.profession::TEXT) THEN
            RAISE EXCEPTION 'La profession % ne peut pas exercer en libéral. Vous ne pouvez choisir que le statut "Salarié".', NEW.profession;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_valider_compatibilite_mission_liberal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_type_etab text;
BEGIN
  IF NEW.type_contrat_recherche IS DISTINCT FROM 'LIBERAL' THEN
    RETURN NEW;
  END IF;

  SELECT type::text INTO v_type_etab FROM public.etablissements
  WHERE id = NEW.etablissement_id;

  IF NEW.profession_requise IS NOT NULL AND v_type_etab IS NOT NULL THEN
    IF NOT public.peut_exercer_liberal(NEW.profession_requise::text, v_type_etab) THEN
      RAISE EXCEPTION
        '[CODE DU TRAVAIL] La profession % ne peut pas exercer en libéral en % '
        '(cas de salariat déguisé, art. L8221-1 Code travail + Conseil d''Etat 11/02/2025). '
        'Proposez la mission en CDD ou Vacation.',
        NEW.profession_requise, v_type_etab;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
