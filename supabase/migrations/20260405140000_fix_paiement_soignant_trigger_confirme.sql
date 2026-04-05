-- Fix: allow soignant to set statut to CONFIRME (not just CONTESTE)
CREATE OR REPLACE FUNCTION fn_protect_paiement_soignant()
RETURNS TRIGGER AS $$
BEGIN
    -- Service role (Edge Functions) peut tout modifier
    IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN
        RETURN NEW;
    END IF;
    -- Admin peut tout modifier
    IF est_admin() THEN RETURN NEW; END IF;

    -- Soignant: ne peut modifier que confirme_par_soignant, conteste, motif_contestation, et statut vers CONFIRME/CONTESTE
    IF auth.uid() = OLD.soignant_id THEN
        IF NEW.montant_net IS DISTINCT FROM OLD.montant_net THEN RAISE EXCEPTION 'Modification du montant non autorisée'; END IF;
        IF NEW.statut IS DISTINCT FROM OLD.statut AND NEW.statut NOT IN ('CONFIRME', 'CONTESTE') THEN RAISE EXCEPTION 'Modification du statut non autorisée'; END IF;
        IF NEW.methode IS DISTINCT FROM OLD.methode THEN RAISE EXCEPTION 'Modification de la méthode non autorisée'; END IF;
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification de la mission non autorisée'; END IF;
        IF NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
        RETURN NEW;
    END IF;

    -- Établissement: peut confirmer mais pas modifier les montants
    IF mon_etablissement_id() = OLD.etablissement_id THEN
        IF NEW.montant_net IS DISTINCT FROM OLD.montant_net THEN RAISE EXCEPTION 'Modification du montant non autorisée'; END IF;
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification de la mission non autorisée'; END IF;
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Accès refusé';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
