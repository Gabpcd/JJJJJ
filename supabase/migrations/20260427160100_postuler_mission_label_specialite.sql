-- fn_postuler_mission : remplacer le code spécialité brut (SM48) par le
-- libellé humain (Rhumatologie) dans le message d'erreur. Lookup via
-- specialites_medicales(code → label).

CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_rcp_valide BOOLEAN;
    v_choix_final TEXT;
    v_compatible BOOLEAN;
    v_specialite_label TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'CANDIDATURE' THEN RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    v_compatible := fn_soignant_compatible_mission(
      v_soignant.profession,
      v_soignant.specialite_medicale,
      v_mission.profession_requise,
      v_mission.specialite_medicale_requise,
      v_mission.accepte_non_specialises
    );

    IF NOT v_compatible THEN
      IF v_mission.profession_requise = 'MEDECIN'
         AND v_mission.specialite_medicale_requise IS NOT NULL
         AND v_soignant.profession = 'MEDECIN' THEN
        SELECT label INTO v_specialite_label
        FROM specialites_medicales
        WHERE code = v_mission.specialite_medicale_requise;
        RETURN jsonb_build_object('error',
          'Cette mission requiert la spécialité ' ||
          COALESCE(v_specialite_label, v_mission.specialite_medicale_requise) || '.');
      ELSIF v_mission.profession_requise IN ('IBODE', 'IADE')
            AND v_soignant.profession = 'IDE'
            AND COALESCE(v_mission.accepte_non_specialises, true) = false THEN
        RETURN jsonb_build_object('error',
          'Cette mission ' || v_mission.profession_requise::text || ' n''accepte pas les IDE non spécialisés.');
      ELSE
        RETURN jsonb_build_object('error',
          'Votre profession ne correspond pas à la mission requise (' || v_mission.profession_requise::text || ').');
      END IF;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN
        RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux salariés.'); END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux libéraux.'); END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL OR p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object(
                'error', 'Veuillez choisir votre mode de contrat.',
                'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDDU)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')
                ));
        END IF;
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM documents_soignants
        WHERE soignant_id = auth.uid()
        AND type_document = 'RCP_ASSURANCE'
        AND statut_verification = 'VERIFIE'
        AND supprime_le IS NULL
        AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
    ) INTO v_rcp_valide;
    IF NOT v_rcp_valide THEN
        RETURN jsonb_build_object('error', 'Assurance Responsabilité Civile Professionnelle (RCP) manquante ou expirée. Veuillez la téléverser dans vos documents.');
    END IF;

    IF EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 86400 < 7 THEN
        IF v_soignant.tous_documents_valides IS NOT TRUE THEN
            RETURN jsonb_build_object('error', 'Documents obligatoires non validés (mission < 7 jours).'); END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission'); END IF;

    IF v_mission.type_contrat_recherche = 'SALARIE' THEN
        v_choix_final := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
        v_choix_final := 'LIBERAL';
    ELSIF v_soignant.type_exercice = 'MIXTE' THEN
        v_choix_final := p_choix_contrat;
    ELSE
        v_choix_final := COALESCE(v_soignant.type_exercice, 'SALARIE');
    END IF;

    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, auth.uid(), fn_html_escape(p_message), 'EN_ATTENTE', v_choix_final);

    RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final);
END;
$function$;
