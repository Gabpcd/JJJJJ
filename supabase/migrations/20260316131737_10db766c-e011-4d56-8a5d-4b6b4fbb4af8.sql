
-- 1. Trigger on litiges INSERT to notify the other party automatically
CREATE OR REPLACE FUNCTION dec_notifier_creation_litige()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_etab_nom TEXT;
    v_soignant_nom TEXT;
    v_mission_intitule TEXT;
    v_dest_id UUID;
    v_dest_type TEXT;
BEGIN
    SELECT nom INTO v_etab_nom FROM etablissements WHERE id = NEW.etablissement_id;
    SELECT COALESCE(prenom || ' ', '') || nom INTO v_soignant_nom FROM soignants WHERE id = NEW.soignant_id;
    SELECT intitule INTO v_mission_intitule FROM missions WHERE id = NEW.mission_id;

    IF NEW.initie_par = 'SOIGNANT' THEN
        v_dest_id := NEW.etablissement_id;
        v_dest_type := 'ETABLISSEMENT';
        PERFORM fn_creer_notification(
            v_dest_id, v_dest_type, 'LITIGE_OUVERT',
            'Nouveau litige signalé',
            COALESCE(v_soignant_nom, 'Un soignant') || ' a ouvert un litige sur la mission "' || COALESCE(v_mission_intitule, 'Mission') || '". Veuillez consulter et répondre.',
            '/etablissement/presences',
            'litige', NEW.id
        );
    ELSE
        v_dest_id := NEW.soignant_id;
        v_dest_type := 'SOIGNANT';
        PERFORM fn_creer_notification(
            v_dest_id, v_dest_type, 'LITIGE_OUVERT',
            'Nouveau litige signalé',
            'L''établissement "' || COALESCE(v_etab_nom, 'Établissement') || '" a ouvert un litige sur la mission "' || COALESCE(v_mission_intitule, 'Mission') || '". Veuillez consulter et répondre.',
            '/soignant/presences',
            'litige', NEW.id
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifier_creation_litige ON litiges;
CREATE TRIGGER trg_notifier_creation_litige
    AFTER INSERT ON litiges
    FOR EACH ROW
    EXECUTE FUNCTION dec_notifier_creation_litige();

-- 2. Allow the OTHER party to respond (update reponse field only)
CREATE POLICY pol_litige_update_reponse ON litiges
    FOR UPDATE TO authenticated
    USING (
        (initie_par = 'ETABLISSEMENT' AND soignant_id = auth.uid() AND statut IN ('OUVERT', 'EN_DISCUSSION'))
        OR
        (initie_par = 'SOIGNANT' AND etablissement_id = mon_etablissement_id() AND statut IN ('OUVERT', 'EN_DISCUSSION'))
    )
    WITH CHECK (
        (initie_par = 'ETABLISSEMENT' AND soignant_id = auth.uid() AND statut IN ('OUVERT', 'EN_DISCUSSION'))
        OR
        (initie_par = 'SOIGNANT' AND etablissement_id = mon_etablissement_id() AND statut IN ('OUVERT', 'EN_DISCUSSION'))
    );

-- 3. Trigger to auto-set statut to EN_DISCUSSION when reponse is added
CREATE OR REPLACE FUNCTION dec_litige_reponse_auto_statut()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.reponse IS NULL AND NEW.reponse IS NOT NULL AND NEW.statut = 'OUVERT' THEN
        NEW.statut := 'EN_DISCUSSION';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_litige_reponse_auto_statut ON litiges;
CREATE TRIGGER trg_litige_reponse_auto_statut
    BEFORE UPDATE ON litiges
    FOR EACH ROW
    EXECUTE FUNCTION dec_litige_reponse_auto_statut();

-- 4. Trigger to notify when response is added
CREATE OR REPLACE FUNCTION dec_notifier_reponse_litige()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_etab_nom TEXT;
    v_soignant_nom TEXT;
    v_mission_intitule TEXT;
BEGIN
    IF OLD.reponse IS NOT NULL OR NEW.reponse IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT nom INTO v_etab_nom FROM etablissements WHERE id = NEW.etablissement_id;
    SELECT COALESCE(prenom || ' ', '') || nom INTO v_soignant_nom FROM soignants WHERE id = NEW.soignant_id;
    SELECT intitule INTO v_mission_intitule FROM missions WHERE id = NEW.mission_id;

    IF NEW.initie_par = 'SOIGNANT' THEN
        PERFORM fn_creer_notification(
            NEW.soignant_id, 'SOIGNANT', 'LITIGE_REPONSE',
            'Réponse à votre litige',
            'L''établissement "' || COALESCE(v_etab_nom, 'Établissement') || '" a répondu à votre litige sur "' || COALESCE(v_mission_intitule, 'Mission') || '".',
            '/soignant/presences',
            'litige', NEW.id
        );
    ELSE
        PERFORM fn_creer_notification(
            NEW.etablissement_id, 'ETABLISSEMENT', 'LITIGE_REPONSE',
            'Réponse à votre litige',
            COALESCE(v_soignant_nom, 'Le soignant') || ' a répondu à votre litige sur "' || COALESCE(v_mission_intitule, 'Mission') || '".',
            '/etablissement/presences',
            'litige', NEW.id
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifier_reponse_litige ON litiges;
CREATE TRIGGER trg_notifier_reponse_litige
    AFTER UPDATE ON litiges
    FOR EACH ROW
    EXECUTE FUNCTION dec_notifier_reponse_litige();
