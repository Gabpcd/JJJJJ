-- Fix 1: fn_creer_litige — auto-resolve presence_id when NULL
CREATE OR REPLACE FUNCTION public.fn_creer_litige(p_mission_id uuid, p_presence_id uuid DEFAULT NULL::uuid, p_motif text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_mission RECORD;
    v_user_id UUID := auth.uid();
    v_qui TEXT;
    v_motif_safe TEXT;
    v_presence_id UUID;
BEGIN
    SELECT m.*, e.id AS etab_id FROM missions m 
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_mission_id INTO v_mission;
    
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    
    IF v_mission.soignant_assigne_id = v_user_id THEN
        v_qui := 'SOIGNANT';
    ELSIF mon_etablissement_id() = v_mission.etablissement_id THEN
        v_qui := 'ETABLISSEMENT';
    ELSIF est_admin() THEN
        v_qui := 'ADMIN';
    ELSE
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    IF EXISTS(SELECT 1 FROM litiges WHERE mission_id = p_mission_id AND statut IN ('OUVERT','EN_COURS','EN_DISCUSSION','EN_MEDIATION')) THEN
        RETURN jsonb_build_object('error', 'Un litige est déjà ouvert pour cette mission');
    END IF;
    
    v_motif_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_motif), ''), 'Contestation des heures ou conditions'), '<[^>]*>', '', 'g'), 2000);
    
    v_presence_id := p_presence_id;
    IF v_presence_id IS NULL THEN
        SELECT id INTO v_presence_id FROM presences 
        WHERE mission_id = p_mission_id 
        AND soignant_id = v_mission.soignant_assigne_id
        ORDER BY cree_le DESC LIMIT 1;
    END IF;
    
    IF v_presence_id IS NULL THEN
        INSERT INTO presences (mission_id, soignant_id, statut)
        VALUES (p_mission_id, v_mission.soignant_assigne_id, 'LITIGE')
        RETURNING id INTO v_presence_id;
    END IF;
    
    INSERT INTO litiges (mission_id, presence_id, soignant_id, etablissement_id, initie_par, motif, statut)
    VALUES (p_mission_id, v_presence_id, v_mission.soignant_assigne_id, v_mission.etablissement_id, v_qui, v_motif_safe, 'OUVERT');
    
    IF v_mission.statut = 'TERMINEE' THEN
        UPDATE missions SET statut = 'LITIGE' WHERE id = p_mission_id;
    END IF;
    
    RETURN jsonb_build_object('success', TRUE, 'message', 'Litige ouvert avec succès');
END;
$$;

-- Fix 2: fn_repondre_litige — use EN_DISCUSSION status and proper response format
CREATE OR REPLACE FUNCTION public.fn_repondre_litige(p_litige_id uuid, p_reponse text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
    
    IF v_litige.statut NOT IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE') THEN
        RETURN jsonb_build_object('error', 'Ce litige n''est plus ouvert');
    END IF;
    
    v_reponse_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_reponse), ''), ''), '<[^>]*>', '', 'g'), 2000);
    IF LENGTH(v_reponse_safe) < 10 THEN
        RETURN jsonb_build_object('error', 'La réponse doit contenir au moins 10 caractères');
    END IF;
    
    v_qui := CASE 
        WHEN v_litige.soignant_id = v_user_id THEN 'Soignant'
        WHEN est_admin() THEN 'Admin'
        ELSE 'Établissement'
    END;
    
    UPDATE litiges SET 
        reponse = COALESCE(reponse, '') || E'\n---\n[' || TO_CHAR(NOW(), 'DD/MM/YYYY HH24:MI') || '] ' || v_qui || ': ' || v_reponse_safe,
        statut = 'EN_DISCUSSION'
    WHERE id = p_litige_id;
    
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (v_user_id, UPPER(v_qui), 'REPONSE_LITIGE', 'LITIGES', p_litige_id,
        jsonb_build_object('mission_id', v_litige.mission_id));
    
    RETURN jsonb_build_object('success', TRUE);
END;
$$;

-- Fix 3: fn_cloturer_litige_mutuel — accept all open statuses
CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_mutuel(p_litige_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_litige RECORD;
    v_user_id UUID := auth.uid();
BEGIN
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    
    IF v_litige.statut NOT IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE') THEN
        RETURN jsonb_build_object('error', 'Ce litige ne peut plus être clôturé');
    END IF;
    
    IF v_litige.soignant_id = v_user_id THEN
        UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
    ELSIF mon_etablissement_id() = v_litige.etablissement_id THEN
        UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
    ELSIF est_admin() THEN
        UPDATE litiges SET statut = 'RESOLU', resolu_par = v_user_id, resolu_le = NOW(),
            resolution = 'Clôturé par l''administrateur' WHERE id = p_litige_id;
        RETURN jsonb_build_object('success', TRUE, 'cloture', TRUE);
    ELSE
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF COALESCE(v_litige.accord_soignant, FALSE) AND COALESCE(v_litige.accord_etablissement, FALSE) THEN
        UPDATE litiges SET statut = 'RESOLU', resolu_le = NOW(),
            resolution = 'Clôturé par accord mutuel' WHERE id = p_litige_id;
        RETURN jsonb_build_object('success', TRUE, 'cloture', TRUE);
    END IF;
    
    RETURN jsonb_build_object('success', TRUE, 'cloture', FALSE, 
        'accord_soignant', v_litige.accord_soignant, 'accord_etablissement', v_litige.accord_etablissement);
END;
$$;

-- Fix 4: fn_demander_mediation_admin — use correct notification columns and remove direct auth.users insert
CREATE OR REPLACE FUNCTION public.fn_demander_mediation_admin(p_litige_id uuid, p_message text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_litige RECORD;
    v_user_id UUID := auth.uid();
    v_qui TEXT;
BEGIN
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    
    IF v_litige.soignant_id != v_user_id 
       AND v_litige.etablissement_id != mon_etablissement_id()
       AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    IF v_litige.statut NOT IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'CONTESTEE') THEN
        RETURN jsonb_build_object('error', 'Ce litige ne peut plus être escaladé');
    END IF;
    
    v_qui := CASE 
        WHEN v_litige.soignant_id = v_user_id THEN 'Soignant'
        ELSE 'Établissement'
    END;
    
    UPDATE litiges SET statut = 'EN_MEDIATION',
        reponse = COALESCE(reponse, '') || E'\n---\n[' || TO_CHAR(NOW(), 'DD/MM/YYYY HH24:MI') || '] ' || v_qui || ' (DEMANDE DE MÉDIATION): ' 
            || COALESCE(NULLIF(TRIM(p_message), ''), 'Demande d''intervention de l''administrateur')
    WHERE id = p_litige_id;
    
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (v_user_id, UPPER(v_qui), 'DEMANDE_MEDIATION', 'LITIGES', p_litige_id,
        jsonb_build_object('mission_id', v_litige.mission_id, 'message', p_message));
    
    RETURN jsonb_build_object('success', TRUE, 'message', 'L''administrateur a été notifié');
END;
$$;

-- Fix 5: fn_proposer_cloture_litige — accept all open statuses
CREATE OR REPLACE FUNCTION public.fn_proposer_cloture_litige(p_litige_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_litige RECORD;
    v_user_id UUID := auth.uid();
BEGIN
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    
    IF v_litige.statut NOT IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'CONTESTEE') THEN
        RETURN jsonb_build_object('error', 'Ce litige ne peut plus être clôturé');
    END IF;
    
    IF v_litige.soignant_id = v_user_id THEN
        UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
    ELSIF mon_etablissement_id() = v_litige.etablissement_id THEN
        UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
    ELSE
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF COALESCE(v_litige.accord_soignant, FALSE) AND COALESCE(v_litige.accord_etablissement, FALSE) THEN
        UPDATE litiges SET statut = 'RESOLU', resolu_le = NOW(),
            resolution = 'Clôturé par accord mutuel' WHERE id = p_litige_id;
        RETURN jsonb_build_object('statut', 'cloture_validee');
    END IF;
    
    RETURN jsonb_build_object('statut', 'en_attente', 
        'accord_soignant', v_litige.accord_soignant, 'accord_etablissement', v_litige.accord_etablissement);
END;
$$;