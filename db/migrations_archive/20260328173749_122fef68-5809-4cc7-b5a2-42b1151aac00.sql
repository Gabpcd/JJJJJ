
-- fn_ouvrir_litige_rate_limited: create a dispute with rate limiting
CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(
    p_mission_id UUID,
    p_motif TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_etab_id UUID := mon_etablissement_id();
    v_mission RECORD;
    v_presence_id UUID;
    v_is_soignant BOOLEAN;
    v_is_etab BOOLEAN;
    v_recent_count INTEGER;
    v_litige_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifie');
    END IF;

    IF length(trim(p_motif)) < 10 THEN
        RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caracteres');
    END IF;

    SELECT id, etablissement_id, soignant_assigne_id, statut
    INTO v_mission FROM missions WHERE id = p_mission_id;

    IF v_mission IS NULL THEN
        RETURN jsonb_build_object('error', 'Mission introuvable');
    END IF;

    v_is_soignant := (v_mission.soignant_assigne_id = v_user_id);
    v_is_etab := (v_etab_id IS NOT NULL AND v_mission.etablissement_id = v_etab_id);

    IF NOT v_is_soignant AND NOT v_is_etab AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Vous n etes pas autorise a ouvrir un litige sur cette mission');
    END IF;

    IF EXISTS (SELECT 1 FROM litiges WHERE mission_id = p_mission_id AND statut NOT IN ('RESOLU', 'FERME', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT')) THEN
        RETURN jsonb_build_object('error', 'Un litige est deja en cours pour cette mission');
    END IF;

    SELECT COUNT(*) INTO v_recent_count FROM litiges
    WHERE ((soignant_id = v_user_id) OR (etablissement_id = v_etab_id))
    AND cree_le > NOW() - INTERVAL '24 hours';

    IF v_recent_count >= 3 THEN
        RETURN jsonb_build_object('error', 'Vous avez atteint la limite de 3 litiges par 24h');
    END IF;

    SELECT id INTO v_presence_id FROM presences
    WHERE mission_id = p_mission_id
    AND soignant_id = v_mission.soignant_assigne_id
    LIMIT 1;

    IF v_presence_id IS NULL THEN
        INSERT INTO presences (mission_id, soignant_id, statut)
        VALUES (p_mission_id, v_mission.soignant_assigne_id, 'LITIGE')
        RETURNING id INTO v_presence_id;
    END IF;

    INSERT INTO litiges (mission_id, presence_id, soignant_id, etablissement_id, motif, initie_par, statut)
    VALUES (
        p_mission_id,
        v_presence_id,
        v_mission.soignant_assigne_id,
        v_mission.etablissement_id,
        trim(p_motif),
        CASE WHEN v_is_soignant THEN 'SOIGNANT' ELSE 'ETABLISSEMENT' END,
        'OUVERT'
    )
    RETURNING id INTO v_litige_id;

    RETURN jsonb_build_object('success', true, 'litige_id', v_litige_id);
END;
$$;

-- fn_repondre_litige: add a response to a dispute thread
CREATE OR REPLACE FUNCTION public.fn_repondre_litige(
    p_litige_id UUID,
    p_reponse TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_etab_id UUID := mon_etablissement_id();
    v_litige RECORD;
    v_auteur TEXT;
    v_new_entry TEXT;
    v_current TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifie');
    END IF;

    IF length(trim(p_reponse)) < 10 THEN
        RETURN jsonb_build_object('error', 'La reponse doit contenir au moins 10 caracteres');
    END IF;

    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN
        RETURN jsonb_build_object('error', 'Litige introuvable');
    END IF;

    IF v_litige.statut IN ('RESOLU', 'FERME', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT') THEN
        RETURN jsonb_build_object('error', 'Ce litige est deja cloture');
    END IF;

    IF v_litige.soignant_id = v_user_id THEN
        v_auteur := 'Soignant';
    ELSIF v_etab_id IS NOT NULL AND v_litige.etablissement_id = v_etab_id THEN
        v_auteur := 'Etablissement';
    ELSIF est_admin() THEN
        v_auteur := 'Admin';
    ELSE
        RETURN jsonb_build_object('error', 'Non autorise');
    END IF;

    v_new_entry := '[' || to_char(NOW(), 'DD/MM/YYYY HH24:MI') || '] ' || v_auteur || ': ' || trim(p_reponse);
    v_current := COALESCE(v_litige.reponse, '');

    IF v_current = '' THEN
        v_current := v_new_entry;
    ELSE
        v_current := v_current || E'\n---\n' || v_new_entry;
    END IF;

    UPDATE litiges SET
        reponse = v_current,
        statut = CASE WHEN v_litige.statut = 'OUVERT' THEN 'EN_DISCUSSION' ELSE v_litige.statut END
    WHERE id = p_litige_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- fn_cloturer_litige_mutuel: mutual closure
CREATE OR REPLACE FUNCTION public.fn_cloturer_litige_mutuel(
    p_litige_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_etab_id UUID := mon_etablissement_id();
    v_litige RECORD;
    v_is_soignant BOOLEAN;
    v_is_etab BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifie');
    END IF;

    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN
        RETURN jsonb_build_object('error', 'Litige introuvable');
    END IF;

    IF v_litige.statut IN ('RESOLU', 'FERME', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT') THEN
        RETURN jsonb_build_object('error', 'Ce litige est deja cloture');
    END IF;

    v_is_soignant := (v_litige.soignant_id = v_user_id);
    v_is_etab := (v_etab_id IS NOT NULL AND v_litige.etablissement_id = v_etab_id);

    IF NOT v_is_soignant AND NOT v_is_etab AND NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Non autorise');
    END IF;

    IF v_is_soignant THEN
        UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
    END IF;
    IF v_is_etab THEN
        UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
    END IF;
    IF est_admin() THEN
        UPDATE litiges SET accord_soignant = TRUE, accord_etablissement = TRUE, accord_soignant_le = NOW(), accord_etablissement_le = NOW() WHERE id = p_litige_id;
    END IF;

    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;

    IF v_litige.accord_soignant AND v_litige.accord_etablissement THEN
        UPDATE litiges SET statut = 'FERME', resolu_le = NOW(), resolution = 'Cloture d un commun accord' WHERE id = p_litige_id;
        RETURN jsonb_build_object('success', true, 'cloture', true);
    END IF;

    RETURN jsonb_build_object('success', true, 'cloture', false, 'accord_soignant', v_litige.accord_soignant, 'accord_etablissement', v_litige.accord_etablissement);
END;
$$;

-- fn_demander_mediation_admin: escalate to admin
CREATE OR REPLACE FUNCTION public.fn_demander_mediation_admin(
    p_litige_id UUID,
    p_message TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_etab_id UUID := mon_etablissement_id();
    v_litige RECORD;
    v_auteur TEXT;
    v_entry TEXT;
    v_current TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifie');
    END IF;

    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN
        RETURN jsonb_build_object('error', 'Litige introuvable');
    END IF;

    IF v_litige.statut IN ('RESOLU', 'FERME', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'EN_MEDIATION') THEN
        RETURN jsonb_build_object('error', 'Ce litige ne peut pas etre soumis a mediation');
    END IF;

    IF v_litige.soignant_id = v_user_id THEN
        v_auteur := 'Soignant';
    ELSIF v_etab_id IS NOT NULL AND v_litige.etablissement_id = v_etab_id THEN
        v_auteur := 'Etablissement';
    ELSE
        RETURN jsonb_build_object('error', 'Non autorise');
    END IF;

    v_entry := '[' || to_char(NOW(), 'DD/MM/YYYY HH24:MI') || '] ' || v_auteur || ': Demande de mediation admin' || COALESCE(' -- ' || trim(p_message), '');
    v_current := COALESCE(v_litige.reponse, '');
    IF v_current = '' THEN v_current := v_entry;
    ELSE v_current := v_current || E'\n---\n' || v_entry;
    END IF;

    UPDATE litiges SET statut = 'EN_MEDIATION', reponse = v_current WHERE id = p_litige_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- fn_mon_contrat_plateforme: get contract info for current establishment
CREATE OR REPLACE FUNCTION public.fn_mon_contrat_plateforme()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_etab RECORD;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT contrat_valide, contrat_url, contrat_uploade_le, nom, siret, taux_commission_negocie
    INTO v_etab FROM etablissements WHERE id = v_etab_id;

    IF v_etab IS NULL THEN RETURN NULL; END IF;

    RETURN jsonb_build_object(
        'contrat_valide', COALESCE(v_etab.contrat_valide, false),
        'contrat_url', v_etab.contrat_url,
        'contrat_uploade_le', v_etab.contrat_uploade_le,
        'nom', v_etab.nom,
        'siret', v_etab.siret,
        'taux_commission_negocie', COALESCE(v_etab.taux_commission_negocie, 15)
    );
END;
$$;

-- fn_uploader_contrat_plateforme: save contract URL and reset validation
CREATE OR REPLACE FUNCTION public.fn_uploader_contrat_plateforme(p_contrat_url TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non autorise');
    END IF;

    UPDATE etablissements SET
        contrat_url = p_contrat_url,
        contrat_uploade_le = NOW(),
        contrat_valide = FALSE
    WHERE id = v_etab_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_ouvrir_litige_rate_limited(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_repondre_litige(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cloturer_litige_mutuel(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_demander_mediation_admin(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mon_contrat_plateforme() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_uploader_contrat_plateforme(TEXT) TO authenticated;
