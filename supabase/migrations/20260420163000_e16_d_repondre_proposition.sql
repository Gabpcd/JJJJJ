-- ============================================================
-- E16 — Micro-passe 1D : fn_repondre_proposition transmet choix
-- ============================================================
-- Avant : PERFORM fn_accepter_mission(v_cand.mid) sans choix
--         → même bug E16 pour flow PROPOSEE.
-- Après : lit candidatures.type_contrat_choisi et le transmet
--         à fn_accepter_mission(mid, choix). RAISE orpheline
--         si MIXTE×TOUS sans choix persisté.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_repondre_proposition(
  p_candidature_id uuid,
  p_accepter boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_cand RECORD;
    v_mission RECORD;
    v_soignant RECORD;
    v_user_id UUID := auth.uid();
    v_result JSONB;
BEGIN
    SELECT c.*, m.statut AS mission_statut, m.id AS mid,
           m.type_contrat_recherche AS mission_type_contrat_recherche
    INTO v_cand
    FROM candidatures c
    JOIN missions m ON m.id = c.mission_id
    WHERE c.id = p_candidature_id;

    IF v_cand IS NULL THEN
        RETURN jsonb_build_object('error', 'Candidature introuvable');
    END IF;

    IF v_cand.soignant_id != v_user_id THEN
        RETURN jsonb_build_object('error', 'Acces refuse');
    END IF;

    IF v_cand.statut != 'PROPOSEE' THEN
        RETURN jsonb_build_object('error', 'Cette proposition n est plus en attente');
    END IF;

    IF p_accepter THEN
        -- E16 : lire le choix persisté sur la candidature
        SELECT * INTO v_soignant FROM soignants WHERE id = v_cand.soignant_id;

        IF v_soignant.type_exercice = 'MIXTE' AND v_cand.mission_type_contrat_recherche = 'TOUS' THEN
            IF v_cand.type_contrat_choisi IS NULL OR v_cand.type_contrat_choisi NOT IN ('SALARIE', 'LIBERAL') THEN
                RETURN jsonb_build_object(
                    'error', 'E16_CANDIDATURE_ORPHELINE',
                    'message', 'Cette proposition a ete creee avant correctif E16. Le soignant doit re-candidater avec son choix de contrat (salarie ou liberal).',
                    'candidature_id', p_candidature_id
                );
            END IF;
        END IF;

        UPDATE candidatures SET statut = 'ACCEPTEE', traite_le = NOW() WHERE id = p_candidature_id;

        -- E16 : transmettre le choix à fn_accepter_mission (au lieu d'appel sans param)
        v_result := fn_accepter_mission(v_cand.mid, v_cand.type_contrat_choisi);

        -- Si fn_accepter_mission a échoué, rollback manuel du statut
        IF v_result ? 'error' THEN
            UPDATE candidatures SET statut = 'PROPOSEE', traite_le = NULL WHERE id = p_candidature_id;
            RETURN v_result;
        END IF;

        RETURN jsonb_build_object(
            'success', TRUE,
            'message', 'Proposition acceptee',
            'choix_applique', v_cand.type_contrat_choisi,
            'contrat_id', v_result->>'contrat_id',
            'contrat_numero', v_result->>'contrat_numero'
        );
    ELSE
        UPDATE candidatures SET statut = 'REFUSEE', traite_le = NOW() WHERE id = p_candidature_id;
        RETURN jsonb_build_object('success', TRUE, 'message', 'Proposition refusee');
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.fn_repondre_proposition(uuid, boolean) IS
  'E16 transmet candidature.type_contrat_choisi a fn_accepter_mission. RAISE E16_CANDIDATURE_ORPHELINE si MIXTE TOUS sans choix.';
