-- Légal : la RCP (responsabilité civile professionnelle) n'est obligatoire que
-- pour l'exercice LIBÉRAL. Un salarié — et un MIXTE qui exerce une mission en
-- tant que salarié — n'en a pas besoin (couvert par la RCP de l'employeur).
--
-- 3 corrections :
--   1. fn_postuler_mission : la garde RCP était INCONDITIONNELLE → bloquait
--      TOUTE candidature (même salariée). Désormais la RCP n'est exigée que si
--      le contrat effectif de la candidature est LIBÉRAL.
--   2. fn_recalculer_tous_documents_valides : RCP comptée dans le flag global
--      uniquement pour un LIBÉRAL pur (type_exercice='LIBERAL'). Un MIXTE peut
--      donc avoir tous_documents_valides=TRUE sans RCP et postuler/pointer en
--      salarié ; sa RCP est vérifiée mission par mission pour le libéral.
--   3. fn_toggle_pool_urgence : RCP exigée uniquement d'un libéral pur.

-- =============================================================
-- 1. fn_postuler_mission : RCP conditionnée au contrat effectif
-- =============================================================
CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD; v_soignant RECORD; v_rcp_valide BOOLEAN; v_choix_final TEXT;
    v_compatible BOOLEAN; v_specialite_label TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'CANDIDATURE' THEN RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
      RETURN jsonb_build_object('error',
        'Votre compte est ' || v_soignant.statut_compte::text || '. Vous ne pouvez plus candidater. Pour faire un recours, écrivez à bonjour@jolene.app.');
    END IF;

    v_compatible := fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
      v_mission.profession_requise, v_mission.specialite_medicale_requise, v_mission.accepte_non_specialises);

    IF NOT v_compatible THEN
      IF v_mission.profession_requise = 'MEDECIN' AND v_mission.specialite_medicale_requise IS NOT NULL
         AND v_soignant.profession = 'MEDECIN' THEN
        SELECT label INTO v_specialite_label FROM specialites_medicales WHERE code = v_mission.specialite_medicale_requise;
        RETURN jsonb_build_object('error', 'Cette mission requiert la spécialité ' ||
          COALESCE(v_specialite_label, v_mission.specialite_medicale_requise) || '.');
      ELSIF v_mission.profession_requise IN ('IBODE', 'IADE') AND v_soignant.profession = 'IDE'
            AND COALESCE(v_mission.accepte_non_specialises, true) = false THEN
        RETURN jsonb_build_object('error', 'Cette mission ' || v_mission.profession_requise::text || ' n''accepte pas les IDE non spécialisés.');
      ELSE
        RETURN jsonb_build_object('error', 'Votre profession ne correspond pas à la mission requise (' || v_mission.profession_requise::text || ').');
      END IF;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux salariés.'); END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux libéraux.'); END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL OR p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Veuillez choisir votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDDU)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    END IF;

    -- Déterminer le contrat effectif de CETTE candidature (avant la garde RCP).
    IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_final := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_final := 'LIBERAL';
    ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_final := p_choix_contrat;
    ELSE v_choix_final := COALESCE(v_soignant.type_exercice, 'SALARIE'); END IF;

    -- RCP exigée UNIQUEMENT pour une candidature en LIBÉRAL.
    IF v_choix_final = 'LIBERAL' THEN
        SELECT EXISTS(SELECT 1 FROM documents_soignants WHERE soignant_id = auth.uid() AND type_document = 'RCP_ASSURANCE'
            AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
            AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_valide;
        IF NOT v_rcp_valide THEN
            RETURN jsonb_build_object('error', 'Assurance Responsabilité Civile Professionnelle (RCP) manquante ou expirée — obligatoire pour candidater en libéral. Téléversez-la dans vos documents (ou candidatez en salarié si la mission le permet).');
        END IF;
    END IF;

    IF EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 86400 < 7 THEN
        IF v_soignant.tous_documents_valides IS NOT TRUE THEN
            RETURN jsonb_build_object('error', 'Documents obligatoires non validés (mission < 7 jours).'); END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission'); END IF;

    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, auth.uid(), fn_html_escape(p_message), 'EN_ATTENTE', v_choix_final);

    RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final);
END;
$function$;

-- =============================================================
-- 2. fn_recalculer_tous_documents_valides : RCP baseline = libéral pur
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
    v_est_liberal_pur BOOLEAN;
    v_est_salarie BOOLEAN;
BEGIN
    v_soignant_id := COALESCE(NEW.soignant_id, OLD.soignant_id);
    IF v_soignant_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

    SELECT COALESCE(rpps_verifie, false),
           COALESCE(adeli_verifie, false),
           (type_exercice = 'LIBERAL'),                              -- libéral pur : RCP au baseline
           (type_exercice IS DISTINCT FROM 'LIBERAL')                -- SALARIE + MIXTE + null : peut travailler en salarié
      INTO v_rpps_verifie, v_adeli_verifie, v_est_liberal_pur, v_est_salarie
      FROM soignants WHERE id = v_soignant_id;

    v_identite_verifiee := v_rpps_verifie OR v_adeli_verifie;

    UPDATE soignants SET tous_documents_valides = NOT EXISTS(
        SELECT 1 FROM documents_requis_par_profession drp
        WHERE drp.profession = (SELECT profession FROM soignants WHERE id = v_soignant_id)
        AND drp.est_critique = true
        AND (
            drp.type_exercice_requis = 'TOUS'
            OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_est_liberal_pur)
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

-- =============================================================
-- 3. fn_toggle_pool_urgence : RCP exigée d'un libéral pur uniquement
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
BEGIN
    SELECT tous_documents_valides, supprime_le, type_exercice, statut_liberal
      INTO v_soignant FROM soignants WHERE id = auth.uid();

    IF p_actif THEN
        IF v_soignant.tous_documents_valides IS NOT TRUE THEN
            RETURN jsonb_build_object('error', 'Vos documents obligatoires ne sont pas tous validés. Complétez votre dossier pour rejoindre le pool urgence.');
        END IF;

        -- RCP exigée uniquement d'un LIBÉRAL pur. Un mixte peut rejoindre le pool
        -- pour des remplacements salariés sans RCP ; sa RCP est vérifiée à
        -- l'acceptation d'une mission libérale.
        IF v_soignant.type_exercice = 'LIBERAL' THEN
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
-- 4. Backfill tous_documents_valides (les MIXTE sans RCP redeviennent valides)
-- =============================================================
UPDATE soignants s SET tous_documents_valides = NOT EXISTS (
    SELECT 1 FROM documents_requis_par_profession drp
    WHERE drp.profession = s.profession
    AND drp.est_critique = true
    AND (
        drp.type_exercice_requis = 'TOUS'
        OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND s.type_exercice = 'LIBERAL')
        OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND s.type_exercice IS DISTINCT FROM 'LIBERAL')
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
