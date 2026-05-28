-- Chantier 2 — Allègement documents quand RPPS/ADELI vérifié
--
-- Si rpps_verifie=true ou adeli_verifie=true, le diplôme et l'attestation
-- RPPS/ADELI sont redondants (le RPPS/ADELI atteste du diplôme).
--
-- 1. Modifie fn_recalculer_tous_documents_valides pour exclure DIPLOME et
--    RPPS_ADELI de la vérification quand l'identité est confirmée
-- 2. Professions SANS RPPS/ADELI (AS, AES, PREPARATEUR_PHARMA) : diplôme
--    reste obligatoire (pas de numéro à vérifier)

CREATE OR REPLACE FUNCTION public.fn_recalculer_tous_documents_valides()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
    v_soignant_id UUID;
    v_rpps_verifie BOOLEAN;
    v_adeli_verifie BOOLEAN;
    v_identite_verifiee BOOLEAN;
BEGIN
    v_soignant_id := COALESCE(NEW.soignant_id, OLD.soignant_id);
    IF v_soignant_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

    SELECT COALESCE(rpps_verifie, false), COALESCE(adeli_verifie, false)
    INTO v_rpps_verifie, v_adeli_verifie
    FROM soignants WHERE id = v_soignant_id;

    v_identite_verifiee := v_rpps_verifie OR v_adeli_verifie;

    UPDATE soignants SET tous_documents_valides = NOT EXISTS(
        SELECT 1 FROM documents_requis_par_profession drp
        WHERE drp.profession = (SELECT profession FROM soignants WHERE id = v_soignant_id)
        AND drp.est_critique = true
        AND NOT (
            v_identite_verifiee AND drp.type_document IN ('DIPLOME', 'RPPS_ADELI')
        )
        AND NOT EXISTS (
            SELECT 1 FROM documents_soignants ds
            WHERE ds.soignant_id = v_soignant_id
            AND ds.type_document = drp.type_document
            AND ds.statut_verification = 'VERIFIE'
            AND ds.supprime_le IS NULL
            AND (drp.a_expiration = false OR ds.valide_jusqua IS NULL OR ds.valide_jusqua > NOW())
        )
    ) WHERE id = v_soignant_id;

    RETURN COALESCE(NEW, OLD);
END;
$body$;

NOTIFY pgrst, 'reload schema';
