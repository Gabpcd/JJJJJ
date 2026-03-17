CREATE OR REPLACE FUNCTION public.fn_creer_notification(
  p_destinataire_id uuid,
  p_type_destinataire text,
  p_type text,
  p_titre text,
  p_corps text,
  p_lien text DEFAULT NULL,
  p_type_ressource text DEFAULT NULL,
  p_id_ressource uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_id uuid;
BEGIN
    INSERT INTO public.notifications (
        destinataire_id, type_destinataire, type,
        titre, corps, lien, type_ressource, id_ressource
    ) VALUES (
        p_destinataire_id, p_type_destinataire, p_type,
        p_titre, p_corps, p_lien, p_type_ressource, p_id_ressource
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_notifier_nouveau_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
BEGIN
  SELECT id, intitule, soignant_assigne_id, etablissement_id
  INTO v_mission
  FROM public.missions
  WHERE id = NEW.mission_id;

  IF v_mission IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.type_auteur = 'ADMIN' THEN
    IF v_mission.soignant_assigne_id IS NOT NULL THEN
      PERFORM public.fn_creer_notification(
        v_mission.soignant_assigne_id,
        'SOIGNANT',
        'NOUVEAU_MESSAGE',
        'Nouveau message',
        'L''admin vous a envoyé un message sur "' || v_mission.intitule || '"',
        '/soignant/missions/' || v_mission.id::text,
        'mission',
        v_mission.id
      );
    END IF;

    IF v_mission.etablissement_id IS NOT NULL THEN
      PERFORM public.fn_creer_notification(
        v_mission.etablissement_id,
        'ETABLISSEMENT',
        'NOUVEAU_MESSAGE',
        'Nouveau message',
        'L''admin vous a envoyé un message sur "' || v_mission.intitule || '"',
        '/etablissement/missions/' || v_mission.id::text,
        'mission',
        v_mission.id
      );
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.type_auteur = 'SOIGNANT' THEN
    IF v_mission.etablissement_id IS NOT NULL THEN
      PERFORM public.fn_creer_notification(
        v_mission.etablissement_id,
        'ETABLISSEMENT',
        'NOUVEAU_MESSAGE',
        'Nouveau message',
        'Le soignant vous a envoyé un message sur "' || v_mission.intitule || '"',
        '/etablissement/missions/' || v_mission.id::text,
        'mission',
        v_mission.id
      );
    END IF;
  ELSE
    IF v_mission.soignant_assigne_id IS NOT NULL THEN
      PERFORM public.fn_creer_notification(
        v_mission.soignant_assigne_id,
        'SOIGNANT',
        'NOUVEAU_MESSAGE',
        'Nouveau message',
        'L''établissement vous a envoyé un message sur "' || v_mission.intitule || '"',
        '/soignant/missions/' || v_mission.id::text,
        'mission',
        v_mission.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;