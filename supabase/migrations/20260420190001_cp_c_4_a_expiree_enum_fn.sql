-- ============================================================
-- CP-C-4 A — Refonte fn_auto_transitions_missions (suite enum)
-- ============================================================
-- - Section 4 : OUVERTE → EXPIREE au lieu de ANNULEE_PAR_ETAB
-- - Seuil 1h (vs 15 min) plus raisonnable pour missions passées
-- - Candidatures EN_ATTENTE/PROPOSEE → REFUSEE auto (motif 'expirée')
-- - Notification MISSION_NON_POURVUE conservée (titre adapté)
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_auto_transitions_missions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_assignee_to_en_cours INT := 0;
    v_assignee_to_terminee INT := 0;
    v_en_cours_to_terminee INT := 0;
    v_ouverte_to_expiree INT := 0;
    v_candidatures_refusees INT := 0;
    v_rows INT;
    v_mission RECORD;
BEGIN
    -- 1. ASSIGNEE → EN_COURS
    UPDATE missions
    SET statut = 'EN_COURS', modifie_le = now()
    WHERE statut = 'ASSIGNEE'
    AND debut_le <= now()
    AND fin_le > now();
    GET DIAGNOSTICS v_assignee_to_en_cours = ROW_COUNT;

    -- 2. ASSIGNEE → TERMINEE (cas extrême)
    UPDATE missions
    SET statut = 'TERMINEE', modifie_le = now()
    WHERE statut = 'ASSIGNEE'
    AND fin_le < now() - INTERVAL '15 minutes';
    GET DIAGNOSTICS v_assignee_to_terminee = ROW_COUNT;

    -- 3. EN_COURS → TERMINEE
    UPDATE missions
    SET statut = 'TERMINEE', modifie_le = now()
    WHERE statut = 'EN_COURS'
    AND fin_le < now() - INTERVAL '15 minutes';
    GET DIAGNOSTICS v_en_cours_to_terminee = ROW_COUNT;

    -- 4. OUVERTE → EXPIREE (non pourvue, seuil 1h post debut_le)
    FOR v_mission IN
        SELECT id, intitule, etablissement_id, debut_le
        FROM missions
        WHERE statut = 'OUVERTE'
        AND debut_le < now() - INTERVAL '1 hour'
    LOOP
        UPDATE missions
        SET statut = 'EXPIREE', modifie_le = now()
        WHERE id = v_mission.id;
        v_ouverte_to_expiree := v_ouverte_to_expiree + 1;

        -- Candidatures EN_ATTENTE/PROPOSEE → REFUSEE auto
        UPDATE candidatures
        SET statut = 'REFUSEE',
            motif_refus = 'Mission expiree (non pourvue)',
            traite_le = NOW()
        WHERE mission_id = v_mission.id
        AND statut IN ('EN_ATTENTE', 'PROPOSEE');
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        v_candidatures_refusees := v_candidatures_refusees + v_rows;

        -- Notification établissement
        INSERT INTO notifications (
            destinataire_id, type_destinataire, type, titre, corps, lien,
            type_ressource, id_ressource
        ) VALUES (
            v_mission.etablissement_id,
            'ETABLISSEMENT',
            'MISSION_NON_POURVUE',
            'Mission expiree (non pourvue)',
            'Votre mission "' || v_mission.intitule || '" n''a trouve aucun soignant et est passee en expiree. Vous pouvez la republier depuis votre espace.',
            '/etablissement/missions/' || v_mission.id,
            'mission',
            v_mission.id
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'assignee_to_en_cours', v_assignee_to_en_cours,
        'assignee_to_terminee', v_assignee_to_terminee,
        'en_cours_to_terminee', v_en_cours_to_terminee,
        'ouverte_to_expiree', v_ouverte_to_expiree,
        'candidatures_refusees', v_candidatures_refusees
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_auto_transitions_missions() IS
  'CP-C-4 A transitions auto missions. Section 4 utilise EXPIREE distinct ANNULEE explicite + candidatures auto REFUSEE.';
