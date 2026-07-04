-- Fix : la RCP ne doit être exigée QUE des libéraux/mixtes, pas des salariés.
--
-- Contexte légal : un soignant salarié est couvert par la RCP de l'établissement
-- employeur (responsabilité du commettant) ; la RCP individuelle n'est PAS
-- obligatoire pour lui (seulement recommandée pour la « faute détachable du
-- service »). Source de vérité projet : documents_requis_par_profession où
-- RCP_ASSURANCE = LIBERAL_ONLY pour toutes les professions.
--
-- Deux endroits ignoraient `type_exercice_requis` et exigeaient la RCP pour tous :
--   1. fn_recalculer_tous_documents_valides (flag global tous_documents_valides)
--   2. fn_toggle_pool_urgence (garde explicite RCP à l'activation du pool urgence)
-- → un salarié restait bloqué hors du pool urgence (bug remonté en prod).

-- =============================================================
-- 1. fn_recalculer_tous_documents_valides : filtrer par type_exercice
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_recalculer_tous_documents_valides()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant_id UUID;
    v_rpps_verifie BOOLEAN;
    v_adeli_verifie BOOLEAN;
    v_identite_verifiee BOOLEAN;
    v_est_liberal BOOLEAN;
    v_est_salarie BOOLEAN;
BEGIN
    v_soignant_id := COALESCE(NEW.soignant_id, OLD.soignant_id);
    IF v_soignant_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

    SELECT COALESCE(rpps_verifie, false),
           COALESCE(adeli_verifie, false),
           (type_exercice IN ('LIBERAL','MIXTE') OR statut_liberal = 'ACTIF'),
           (type_exercice IN ('SALARIE','MIXTE') OR type_exercice IS NULL)
      INTO v_rpps_verifie, v_adeli_verifie, v_est_liberal, v_est_salarie
      FROM soignants WHERE id = v_soignant_id;

    v_identite_verifiee := v_rpps_verifie OR v_adeli_verifie;

    UPDATE soignants SET tous_documents_valides = NOT EXISTS(
        SELECT 1 FROM documents_requis_par_profession drp
        WHERE drp.profession = (SELECT profession FROM soignants WHERE id = v_soignant_id)
        AND drp.est_critique = true
        -- Ne considérer que les documents requis pour le type d'exercice du soignant.
        AND (
            drp.type_exercice_requis = 'TOUS'
            OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_est_liberal)
            OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND v_est_salarie)
        )
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
$function$;

-- Trigger legacy redondant (comptage sans filtre type_exercice) : son résultat
-- est de toute façon écrasé par trg_recalculer_docs_valides (ordre alphabétique),
-- mais on le supprime pour éviter une valeur intermédiaire fausse + la confusion.
DROP TRIGGER IF EXISTS dec_maj_docs_valides ON public.documents_soignants;

-- =============================================================
-- 2. fn_toggle_pool_urgence : RCP exigée uniquement des libéraux/mixtes
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_toggle_pool_urgence(
    p_actif boolean,
    p_rayon_km integer DEFAULT 15,
    p_creneaux jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant RECORD;
    v_rcp_ok BOOLEAN;
    v_est_liberal BOOLEAN;
BEGIN
    SELECT tous_documents_valides, supprime_le, type_exercice, statut_liberal
      INTO v_soignant FROM soignants WHERE id = auth.uid();

    IF p_actif THEN
        -- Documents obligatoires (déjà filtrés par type_exercice via le flag).
        IF v_soignant.tous_documents_valides IS NOT TRUE THEN
            RETURN jsonb_build_object('error', 'Vos documents obligatoires ne sont pas tous validés. Complétez votre dossier pour rejoindre le pool urgence.');
        END IF;

        -- RCP obligatoire UNIQUEMENT pour les libéraux/mixtes. Les salariés sont
        -- couverts par la RCP de l'établissement employeur.
        v_est_liberal := (v_soignant.type_exercice IN ('LIBERAL','MIXTE') OR v_soignant.statut_liberal = 'ACTIF');
        IF v_est_liberal THEN
            SELECT EXISTS(
                SELECT 1 FROM documents_soignants
                WHERE soignant_id = auth.uid() AND type_document = 'RCP_ASSURANCE'
                AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
                AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
            ) INTO v_rcp_ok;
            IF NOT v_rcp_ok THEN
                RETURN jsonb_build_object('error', 'Votre assurance RCP est manquante ou expirée. Elle est obligatoire pour le pool urgence (exercice libéral).');
            END IF;
        END IF;
    END IF;

    UPDATE soignants SET
        disponible_urgence = p_actif,
        urgence_rayon_km = p_rayon_km,
        urgence_creneaux = p_creneaux,
        modifie_le = NOW()
    WHERE id = auth.uid();

    RETURN jsonb_build_object('success', true, 'disponible_urgence', p_actif);
END;
$function$;

-- =============================================================
-- 3. Backfill : recalculer tous_documents_valides pour tous les soignants
--    (les salariés faussement bloqués redeviennent éligibles immédiatement)
-- =============================================================
UPDATE soignants s SET tous_documents_valides = NOT EXISTS (
    SELECT 1 FROM documents_requis_par_profession drp
    WHERE drp.profession = s.profession
    AND drp.est_critique = true
    AND (
        drp.type_exercice_requis = 'TOUS'
        OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND (s.type_exercice IN ('LIBERAL','MIXTE') OR s.statut_liberal = 'ACTIF'))
        OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND (s.type_exercice IN ('SALARIE','MIXTE') OR s.type_exercice IS NULL))
    )
    AND NOT (
        (COALESCE(s.rpps_verifie, false) OR COALESCE(s.adeli_verifie, false))
        AND drp.type_document IN ('DIPLOME', 'RPPS_ADELI')
    )
    AND NOT EXISTS (
        SELECT 1 FROM documents_soignants ds
        WHERE ds.soignant_id = s.id
        AND ds.type_document = drp.type_document
        AND ds.statut_verification = 'VERIFIE'
        AND ds.supprime_le IS NULL
        AND (drp.a_expiration = false OR ds.valide_jusqua IS NULL OR ds.valide_jusqua > NOW())
    )
)
WHERE s.supprime_le IS NULL;

NOTIFY pgrst, 'reload schema';
