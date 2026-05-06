-- ============================================================
-- E16 — Micro-passe 1E : fn_proposer_mission_soignant param choix
-- ============================================================
-- Extension backend : l'étab qui propose une mission à un soignant
-- MIXTE sur mission TOUS devait pouvoir spécifier le choix contrat.
-- Avant : INSERT candidatures sans type_contrat_choisi → proposition
-- orpheline rejetée par fn_repondre_proposition côté soignant (1D).
-- Après : p_choix_contrat strict pour MIXTE×TOUS + persistance.
-- ============================================================

DROP FUNCTION IF EXISTS public.fn_proposer_mission_soignant(uuid, uuid);

CREATE OR REPLACE FUNCTION public.fn_proposer_mission_soignant(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_choix_persiste TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;

    IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
        RETURN '{"error":"Acces refuse"}'::JSONB;
    END IF;

    IF v_mission.statut != 'OUVERTE' THEN
        RETURN '{"error":"La mission n est plus ouverte"}'::JSONB;
    END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = p_soignant_id;
    IF v_soignant IS NULL THEN RETURN '{"error":"Soignant introuvable"}'::JSONB; END IF;

    IF v_soignant.profession != v_mission.profession_requise THEN
        RETURN jsonb_build_object('error', 'Ce soignant est ' || v_soignant.profession::TEXT || ', la mission requiert un(e) ' || v_mission.profession_requise::TEXT);
    END IF;

    IF v_mission.type_contrat_recherche IS NOT NULL AND v_mission.type_contrat_recherche != 'TOUS' THEN
        IF (v_mission.type_contrat_recherche = 'SALARIE' AND v_soignant.type_exercice = 'LIBERAL')
           OR (v_mission.type_contrat_recherche = 'LIBERAL' AND v_soignant.type_exercice = 'SALARIE') THEN
            RETURN jsonb_build_object('error', 'Type d exercice incompatible avec cette mission');
        END IF;
    END IF;

    IF v_soignant.tous_documents_valides IS NOT TRUE THEN
        RETURN jsonb_build_object('error', 'Ce soignant n a pas tous ses documents valides.');
    END IF;

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = p_soignant_id AND statut IN ('EN_ATTENTE','PROPOSEE','ACCEPTEE')) THEN
        RETURN '{"error":"Deja propose a ce soignant"}'::JSONB;
    END IF;

    IF fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
        RETURN '{"error":"Ce soignant est dans votre liste d exclusions."}'::JSONB;
    END IF;

    -- Validation format p_choix_contrat si fourni
    IF p_choix_contrat IS NOT NULL AND p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
        RETURN jsonb_build_object('error', 'p_choix_contrat invalide (attendu SALARIE ou LIBERAL).');
    END IF;

    -- E16 : determination du choix a persister
    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL THEN
            RETURN jsonb_build_object(
                'error', 'E16_CHOIX_CONTRAT_REQUIS',
                'message', 'Ce soignant est MIXTE et la mission accepte les deux contrats. Specifiez p_choix_contrat SALARIE ou LIBERAL.',
                'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarie (CDDU)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Liberal (note d honoraires)')
                )
            );
        END IF;
        v_choix_persiste := p_choix_contrat;
    ELSIF v_mission.type_contrat_recherche = 'SALARIE' THEN
        v_choix_persiste := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
        v_choix_persiste := 'LIBERAL';
    ELSIF v_soignant.type_exercice IN ('SALARIE', 'LIBERAL') THEN
        v_choix_persiste := v_soignant.type_exercice;
    ELSE
        v_choix_persiste := NULL;
    END IF;

    INSERT INTO candidatures (mission_id, soignant_id, statut, proposee_par, type_contrat_choisi)
    VALUES (p_mission_id, p_soignant_id, 'PROPOSEE', auth.uid(), v_choix_persiste);

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Mission proposee',
        'On vous propose la mission "' || fn_html_escape(v_mission.intitule) || '"',
        '/soignant/missions/' || p_mission_id, 'SOIGNANT');

    RETURN jsonb_build_object('success', TRUE, 'choix_persiste', v_choix_persiste);
END;
$function$;

COMMENT ON FUNCTION public.fn_proposer_mission_soignant(uuid, uuid, text) IS
  'E16 ajoute p_choix_contrat strict pour MIXTE TOUS persiste type_contrat_choisi dans candidatures evite propositions orphelines';
