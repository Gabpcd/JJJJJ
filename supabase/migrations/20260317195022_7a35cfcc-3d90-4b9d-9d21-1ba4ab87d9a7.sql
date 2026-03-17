CREATE OR REPLACE FUNCTION public.dec_notifier_nouveau_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_notification_type TEXT;
    v_titre TEXT;
    v_corps TEXT;
BEGIN
    SELECT id, etablissement_id, soignant_assigne_id
    INTO v_mission
    FROM public.missions
    WHERE id = NEW.mission_id;

    IF v_mission.id IS NULL THEN
        RETURN NEW;
    END IF;

    v_notification_type := CASE
        WHEN NEW.type_auteur = 'ADMIN' THEN 'MESSAGE_ADMIN'
        ELSE 'MESSAGE_RECU'
    END;

    v_titre := CASE
        WHEN NEW.type_auteur = 'ADMIN' THEN '🛡️ Message de l''équipe Jolene'
        WHEN NEW.type_auteur = 'SOIGNANT' THEN '💬 Nouveau message du soignant'
        ELSE '💬 Nouveau message de l''établissement'
    END;

    v_corps := LEFT(NEW.contenu, 100);

    IF NEW.type_auteur = 'ADMIN' THEN
        IF v_mission.soignant_assigne_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.soignant_assigne_id,
                'SOIGNANT',
                v_notification_type,
                v_titre,
                v_corps,
                '/soignant/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;

        IF v_mission.etablissement_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.etablissement_id,
                'ETABLISSEMENT',
                v_notification_type,
                v_titre,
                v_corps,
                '/etablissement/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;
    ELSIF NEW.type_auteur = 'SOIGNANT' THEN
        IF v_mission.etablissement_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.etablissement_id,
                'ETABLISSEMENT',
                v_notification_type,
                v_titre,
                v_corps,
                '/etablissement/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;
    ELSIF NEW.type_auteur = 'ETABLISSEMENT' THEN
        IF v_mission.soignant_assigne_id IS NOT NULL THEN
            PERFORM public.fn_creer_notification(
                v_mission.soignant_assigne_id,
                'SOIGNANT',
                v_notification_type,
                v_titre,
                v_corps,
                '/soignant/missions/' || v_mission.id,
                'mission',
                v_mission.id
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;