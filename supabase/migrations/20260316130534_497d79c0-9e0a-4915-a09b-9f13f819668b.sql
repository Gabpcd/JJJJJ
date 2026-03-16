CREATE OR REPLACE FUNCTION dec_notifier_resolution_litige()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_etab_nom TEXT;
    v_soignant_nom TEXT;
    v_mission_intitule TEXT;
    v_resolution_label TEXT;
BEGIN
    -- Ne déclencher que si le statut passe à résolu/fermé
    IF OLD.statut = NEW.statut THEN
        RETURN NEW;
    END IF;

    IF NEW.statut NOT IN ('RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN', 'FERME') THEN
        RETURN NEW;
    END IF;

    -- Récupérer les noms pour le message
    SELECT nom INTO v_etab_nom FROM etablissements WHERE id = NEW.etablissement_id;
    SELECT COALESCE(prenom || ' ', '') || nom INTO v_soignant_nom FROM soignants WHERE id = NEW.soignant_id;
    SELECT intitule INTO v_mission_intitule FROM missions WHERE id = NEW.mission_id;

    -- Label de résolution
    CASE NEW.statut
        WHEN 'RESOLU_SOIGNANT' THEN v_resolution_label := 'résolu en faveur du soignant';
        WHEN 'RESOLU_ETABLISSEMENT' THEN v_resolution_label := 'résolu en faveur de l''établissement';
        WHEN 'RESOLU_ADMIN' THEN v_resolution_label := 'résolu par l''administrateur';
        WHEN 'FERME' THEN v_resolution_label := 'fermé par l''administrateur';
    END CASE;

    -- Notifier le soignant
    PERFORM fn_creer_notification(
        NEW.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
        'Litige ' || v_resolution_label,
        'Le litige concernant la mission "' || COALESCE(v_mission_intitule, 'Mission') || '" a été ' || v_resolution_label || '.',
        '/soignant/presences',
        'litige', NEW.id
    );

    -- Notifier l'établissement
    PERFORM fn_creer_notification(
        NEW.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
        'Litige ' || v_resolution_label,
        'Le litige avec ' || COALESCE(v_soignant_nom, 'un soignant') || ' sur la mission "' || COALESCE(v_mission_intitule, 'Mission') || '" a été ' || v_resolution_label || '.',
        '/etablissement/presences',
        'litige', NEW.id
    );

    RETURN NEW;
END;
$$;

-- Créer le trigger AFTER UPDATE sur litiges
DROP TRIGGER IF EXISTS trg_notifier_resolution_litige ON litiges;
CREATE TRIGGER trg_notifier_resolution_litige
    AFTER UPDATE ON litiges
    FOR EACH ROW
    EXECUTE FUNCTION dec_notifier_resolution_litige();