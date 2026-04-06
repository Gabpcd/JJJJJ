-- 1. Store SEPA payment method ID on etablissements
ALTER TABLE etablissements ADD COLUMN IF NOT EXISTS stripe_sepa_payment_method_id TEXT;

-- 2. Cross-document name verification function
CREATE OR REPLACE FUNCTION fn_verifier_coherence_documents(p_soignant_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_soignant_id UUID := COALESCE(p_soignant_id, auth.uid());
    v_soignant RECORD;
    v_docs JSONB;
    v_noms_extraits TEXT[];
    v_coherent BOOLEAN := TRUE;
    v_problemes TEXT[] := '{}';
BEGIN
    SELECT prenom, nom INTO v_soignant FROM soignants WHERE id = v_soignant_id;
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;

    SELECT jsonb_agg(jsonb_build_object(
        'type', d.type_document,
        'nom_extrait', d.nom_extrait_ia,
        'prenom_extrait', d.prenom_extrait_ia,
        'coherence_nom', d.coherence_nom,
        'score_confiance', d.score_confiance_ia,
        'statut', d.statut_verification
    )) INTO v_docs
    FROM documents_soignants d
    WHERE d.soignant_id = v_soignant_id
      AND d.supprime_le IS NULL
      AND d.nom_extrait_ia IS NOT NULL;

    IF v_docs IS NULL OR jsonb_array_length(v_docs) = 0 THEN
        RETURN jsonb_build_object('coherent', TRUE, 'message', 'Pas assez de documents', 'documents', '[]'::JSONB);
    END IF;

    SELECT array_agg(DISTINCT UPPER(TRIM(elem->>'nom_extrait')))
    INTO v_noms_extraits
    FROM jsonb_array_elements(v_docs) elem
    WHERE elem->>'nom_extrait' IS NOT NULL AND TRIM(elem->>'nom_extrait') != '';

    IF array_length(v_noms_extraits, 1) > 1 THEN
        v_coherent := FALSE;
        v_problemes := v_problemes || ('Noms différents entre documents : ' || array_to_string(v_noms_extraits, ', '));
    END IF;

    IF v_noms_extraits IS NOT NULL AND array_length(v_noms_extraits, 1) > 0 THEN
        DECLARE
            v_profil_nom TEXT := UPPER(TRIM(v_soignant.nom));
            v_match BOOLEAN := FALSE;
        BEGIN
            FOR i IN 1..array_length(v_noms_extraits, 1) LOOP
                IF v_noms_extraits[i] LIKE '%' || v_profil_nom || '%' OR v_profil_nom LIKE '%' || v_noms_extraits[i] || '%' THEN
                    v_match := TRUE;
                END IF;
            END LOOP;
            IF NOT v_match THEN
                v_coherent := FALSE;
                v_problemes := v_problemes || ('Nom profil (' || v_soignant.nom || ') ≠ documents');
            END IF;
        END;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_docs) elem WHERE (elem->>'coherence_nom')::BOOLEAN = FALSE) THEN
        v_coherent := FALSE;
        v_problemes := v_problemes || 'Document(s) avec nom incohérent';
    END IF;

    RETURN jsonb_build_object(
        'coherent', v_coherent,
        'problemes', to_jsonb(v_problemes),
        'documents', v_docs,
        'profil_nom', v_soignant.nom,
        'profil_prenom', v_soignant.prenom
    );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_verifier_coherence_documents(UUID) TO authenticated;
