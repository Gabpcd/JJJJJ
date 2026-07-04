-- Fix 1: dec_maj_note_moyenne uses invalid enum values ABSENCE_SOIGNANT, ABSENCE_NON_JUSTIFIEE
-- The valid enum value is just 'ABSENCE'
CREATE OR REPLACE FUNCTION dec_maj_note_moyenne()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_note_moy NUMERIC;
    v_nb_evals INT;
    v_missions_term INT;
    v_absences INT;
    v_anciennete_mois INT;
    v_score INT;
BEGIN
    SELECT ROUND(AVG(note)::NUMERIC, 2), COUNT(*)
    INTO v_note_moy, v_nb_evals
    FROM evaluations WHERE evalue_id = NEW.evalue_id AND visible = TRUE;

    SELECT 
        COUNT(*) FILTER (WHERE statut = 'TERMINEE'),
        COUNT(*) FILTER (WHERE statut = 'ABSENCE')
    INTO v_missions_term, v_absences
    FROM missions WHERE soignant_assigne_id = NEW.evalue_id;

    SELECT GREATEST(1, EXTRACT(MONTH FROM AGE(NOW(), cree_le))::INT)
    INTO v_anciennete_mois
    FROM soignants WHERE id = NEW.evalue_id;

    v_score := LEAST(100, GREATEST(0,
        ROUND(COALESCE(v_note_moy, 3) * 8)
        + CASE WHEN v_missions_term = 0 THEN 20
               ELSE ROUND(GREATEST(0, 1 - (v_absences::NUMERIC / GREATEST(v_missions_term, 1))) * 40)
          END
        + LEAST(20, v_anciennete_mois * 20 / 12)
    ));

    UPDATE soignants SET
        note_moyenne = v_note_moy,
        nb_evaluations = v_nb_evals,
        score_fiabilite = v_score,
        modifie_le = NOW()
    WHERE id = NEW.evalue_id;

    RETURN NEW;
END;
$$;

-- Fix 2: dec_machine_etats_mission must allow TERMINEE -> LITIGE for dispute workflow
CREATE OR REPLACE FUNCTION dec_machine_etats_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.statut IS DISTINCT FROM NEW.statut THEN
        IF NOT (
            (OLD.statut = 'OUVERTE' AND NEW.statut IN ('ASSIGNEE', 'ANNULEE_PAR_ETABLISSEMENT'))
            OR (OLD.statut = 'ASSIGNEE' AND NEW.statut IN ('EN_COURS', 'ANNULEE_PAR_SOIGNANT', 'ANNULEE_PAR_ETABLISSEMENT'))
            OR (OLD.statut = 'EN_COURS' AND NEW.statut IN ('TERMINEE', 'ABSENCE', 'LITIGE'))
            OR (OLD.statut = 'TERMINEE' AND NEW.statut = 'LITIGE')
            OR (OLD.statut = 'LITIGE' AND NEW.statut IN ('TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT'))
            OR est_admin()
        ) THEN
            RAISE EXCEPTION 'Transition de statut interdite : % -> %', OLD.statut, NEW.statut;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;