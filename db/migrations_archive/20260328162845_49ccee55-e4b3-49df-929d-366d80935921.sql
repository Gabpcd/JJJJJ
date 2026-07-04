
-- Fix evaluation trigger: use mon_etablissement_id() for establishment comparison
CREATE OR REPLACE FUNCTION public.dec_verifier_evaluation_counterparty()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mission RECORD;
    v_expected_evalue UUID;
    v_etab_id UUID;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = NEW.mission_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mission introuvable';
    END IF;

    v_etab_id := mon_etablissement_id();

    IF v_mission.soignant_assigne_id = NEW.evaluateur_id THEN
        -- Soignant évalue → doit évaluer l'établissement
        v_expected_evalue := v_mission.etablissement_id;
    ELSIF v_mission.etablissement_id = v_etab_id THEN
        -- Établissement évalue → doit évaluer le soignant
        v_expected_evalue := v_mission.soignant_assigne_id;
    ELSIF est_admin() THEN
        -- Admin peut évaluer
        NEW.visible := FALSE;
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Vous n''avez pas participé à cette mission.';
    END IF;

    IF NEW.evalue_id != v_expected_evalue THEN
        RAISE EXCEPTION 'L''évaluation doit concerner l''autre partie de la mission.';
    END IF;

    -- Forcer visible = FALSE (modération admin)
    NEW.visible := FALSE;

    RETURN NEW;
END;
$$;
