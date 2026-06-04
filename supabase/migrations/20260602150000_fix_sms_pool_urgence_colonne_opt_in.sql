-- BUG : le toggle "Recevoir les alertes par SMS" (fn_toggle_pool_urgence_sms) écrit
-- la colonne pool_urgence_sms_opt_in, mais le trigger d'envoi fn_trg_sms_mission_urgente
-- filtrait sur sms_actif (colonne différente, défaut false, jamais mise à jour par le
-- toggle) → activer le toggle ne déclenchait JAMAIS d'envoi SMS. Fix : aligner le
-- filtre sur pool_urgence_sms_opt_in (la colonne réellement pilotée par l'UI).
-- Testé (rollback) : toggle ON → 1 entrée SMS_MISSION_URGENTE ; toggle OFF → 0.
CREATE OR REPLACE FUNCTION public.fn_trg_sms_mission_urgente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant RECORD;
BEGIN
    -- Seulement pour les nouvelles missions OUVERTE marquées urgentes
    IF NEW.statut = 'OUVERTE' AND NEW.est_urgente = TRUE
       AND (TG_OP = 'INSERT' OR (OLD.statut IS DISTINCT FROM 'OUVERTE' OR OLD.est_urgente IS DISTINCT FROM TRUE)) THEN

        FOR v_soignant IN
            SELECT s.id, s.telephone, s.prenom
            FROM soignants s
            WHERE s.supprime_le IS NULL
            AND s.pool_urgence_sms_opt_in = TRUE
            AND s.telephone IS NOT NULL
            AND s.disponible_urgence = TRUE
            AND s.profession = NEW.profession_requise
            AND s.score_fiabilite >= 50
            ORDER BY s.score_fiabilite DESC
            LIMIT 20
        LOOP
            -- Insérer dans la queue SMS (traité par le cron email-cron)
            INSERT INTO email_queue (type, destinataire_id, destinataire_email, data)
            VALUES ('SMS_MISSION_URGENTE', v_soignant.id, v_soignant.telephone, jsonb_build_object(
                'prenom', v_soignant.prenom,
                'mission', NEW.intitule,
                'mission_id', NEW.id,
                'telephone', v_soignant.telephone
            ));
        END LOOP;
    END IF;
    RETURN NEW;
END;
$function$;
