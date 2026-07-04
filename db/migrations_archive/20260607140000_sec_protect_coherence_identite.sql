-- AUDIT sécurité (anti-fraude soignant) — fn_protect_soignant_verification protégeait
-- diplome_verifie/identite_verifiee/tous_documents_valides/rpps_* mais PAS
-- coherence_identite ni coherence_details. Un soignant pouvait donc se remettre
-- en 'COHERENT' alors qu'il était flaggé 'INCOHERENT' (identité ne correspond pas),
-- échappant ainsi à la modération admin (page Incohérences identité). Le gate mission
-- restait bloqué (tous_documents_valides protégé), mais on ferme le trou.
-- Ajout du reset NEW.coherence_* := OLD.coherence_* dans les 2 branches utilisateur.
-- Le recalcul légitime (fn_verifier_coherence_identite) tourne en service_role
-- (passthrough en tête de trigger) → non impacté.
CREATE OR REPLACE FUNCTION public.fn_protect_soignant_verification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
        RETURN NEW;
    END IF;
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    IF est_admin() THEN RETURN NEW; END IF;

    IF COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN
        RETURN NEW;
    END IF;

    IF COALESCE(current_setting('jolene.rpc_update', true), '') = 'true' THEN
        IF OLD.id = auth.uid() THEN
            NEW.diplome_verifie := OLD.diplome_verifie;
            NEW.identite_verifiee := OLD.identite_verifiee;
            NEW.tous_documents_valides := OLD.tous_documents_valides;
            NEW.rpps_verifie := OLD.rpps_verifie;
            NEW.rpps_verifie_le := OLD.rpps_verifie_le;
            NEW.rpps_nom_api := OLD.rpps_nom_api;
            NEW.rpps_prenom_api := OLD.rpps_prenom_api;
            NEW.rpps_profession_api := OLD.rpps_profession_api;
            NEW.statut_verification_aria := OLD.statut_verification_aria;
            NEW.coherence_identite := OLD.coherence_identite;
            NEW.coherence_details := OLD.coherence_details;
            IF OLD.profession IS NOT NULL THEN
                NEW.profession := OLD.profession;
            END IF;
            NEW.score_fiabilite := OLD.score_fiabilite;
            NEW.note_moyenne := OLD.note_moyenne;
            NEW.total_absences := OLD.total_absences;
            NEW.total_retards_pointage := OLD.total_retards_pointage;
            NEW.total_missions_annulees := OLD.total_missions_annulees;
            NEW.total_missions_terminees := OLD.total_missions_terminees;
            NEW.heures_cumulees := OLD.heures_cumulees;
            NEW.heures_plateforme := OLD.heures_plateforme;
            NEW.stripe_account_id := OLD.stripe_account_id;
            NEW.supprime_le := OLD.supprime_le;
            NEW.parraine_par := OLD.parraine_par;
            IF OLD.rpps_verifie = TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
            IF OLD.identite_verifiee = TRUE THEN NEW.nom := OLD.nom; NEW.prenom := OLD.prenom; END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.id = auth.uid() THEN
        NEW.diplome_verifie := OLD.diplome_verifie;
        NEW.identite_verifiee := OLD.identite_verifiee;
        NEW.tous_documents_valides := OLD.tous_documents_valides;
        NEW.rpps_verifie := OLD.rpps_verifie;
        NEW.rpps_verifie_le := OLD.rpps_verifie_le;
        NEW.rpps_nom_api := OLD.rpps_nom_api;
        NEW.rpps_prenom_api := OLD.rpps_prenom_api;
        NEW.rpps_profession_api := OLD.rpps_profession_api;
        NEW.statut_verification_aria := OLD.statut_verification_aria;
        NEW.coherence_identite := OLD.coherence_identite;
        NEW.coherence_details := OLD.coherence_details;
        IF OLD.rpps_verifie = TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
        IF OLD.identite_verifiee = TRUE THEN NEW.nom := OLD.nom; NEW.prenom := OLD.prenom; END IF;
        IF OLD.profession IS NOT NULL THEN
            NEW.profession := OLD.profession;
        END IF;
        NEW.type_exercice := OLD.type_exercice;
        NEW.statut_liberal := OLD.statut_liberal;
        NEW.score_fiabilite := OLD.score_fiabilite;
        NEW.note_moyenne := OLD.note_moyenne;
        NEW.total_absences := OLD.total_absences;
        NEW.total_retards_pointage := OLD.total_retards_pointage;
        NEW.total_missions_annulees := OLD.total_missions_annulees;
        NEW.total_missions_terminees := OLD.total_missions_terminees;
        NEW.heures_cumulees := OLD.heures_cumulees;
        NEW.heures_plateforme := OLD.heures_plateforme;
        NEW.eligible_conversion_3200h := OLD.eligible_conversion_3200h;
        NEW.validation_3200h_statut := OLD.validation_3200h_statut;
        NEW.stripe_account_id := OLD.stripe_account_id;
        NEW.supprime_le := OLD.supprime_le;
        NEW.parraine_par := OLD.parraine_par;
    END IF;

    RETURN NEW;
END;
$function$;
