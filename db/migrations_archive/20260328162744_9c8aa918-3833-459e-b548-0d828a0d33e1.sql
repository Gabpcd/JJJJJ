
-- Fix fn_repondre_litige: wrong column name ressource_id → id_ressource
CREATE OR REPLACE FUNCTION public.fn_repondre_litige(p_litige_id uuid, p_reponse text)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_litige RECORD;
    v_user_id UUID := auth.uid();
    v_reponse_safe TEXT;
    v_qui TEXT;
BEGIN
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    
    IF v_litige.soignant_id != v_user_id 
       AND v_litige.etablissement_id != mon_etablissement_id()
       AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    IF v_litige.statut NOT IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION') THEN
        RETURN jsonb_build_object('error', 'Ce litige n''est plus ouvert');
    END IF;
    
    v_reponse_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_reponse), ''), ''), '<[^>]*>', '', 'g'), 2000);
    IF LENGTH(v_reponse_safe) < 10 THEN
        RETURN jsonb_build_object('error', 'La réponse doit contenir au moins 10 caractères');
    END IF;
    
    v_qui := CASE 
        WHEN v_litige.soignant_id = v_user_id THEN 'SOIGNANT'
        WHEN est_admin() THEN 'ADMIN'
        ELSE 'ETABLISSEMENT'
    END;
    
    UPDATE litiges SET 
        reponse = COALESCE(reponse, '') || E'\n\n--- ' || v_qui || ' (' || TO_CHAR(NOW(), 'DD/MM/YYYY HH24:MI') || ') ---\n' || v_reponse_safe,
        statut = 'EN_COURS'
    WHERE id = p_litige_id;
    
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (v_user_id, v_qui, 'REPONSE_LITIGE', 'LITIGES', p_litige_id,
        jsonb_build_object('mission_id', v_litige.mission_id));
    
    RETURN jsonb_build_object('success', TRUE);
END;
$$;

-- Fix fn_ouvrir_litige_rate_limited: calls non-existent fn_ouvrir_litige, should call fn_creer_litige
CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(p_mission_id uuid, p_motif text)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_allowed BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifié');
    END IF;
    
    v_allowed := fn_verifier_rate_limit(v_user_id::TEXT, 'litige', 3, 86400);
    IF NOT v_allowed THEN
        RETURN jsonb_build_object('error', 'Limite de litiges atteinte pour aujourd''hui.');
    END IF;
    
    RETURN fn_creer_litige(p_mission_id, NULL, p_motif);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_repondre_litige FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited FROM anon;
