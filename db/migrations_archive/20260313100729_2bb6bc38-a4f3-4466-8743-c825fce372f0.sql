-- Trigger: notifier quand un message est envoyé sur une mission
CREATE OR REPLACE FUNCTION public.dec_notifier_nouveau_message()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_mission RECORD;
  v_dest_id UUID;
  v_dest_type TEXT;
  v_auteur_label TEXT;
BEGIN
  -- Récupérer la mission
  SELECT id, intitule, soignant_assigne_id, etablissement_id
  INTO v_mission
  FROM missions WHERE id = NEW.mission_id;

  IF v_mission IS NULL THEN RETURN NEW; END IF;

  -- Déterminer le destinataire (l'autre partie)
  IF NEW.type_auteur = 'SOIGNANT' THEN
    v_dest_id := v_mission.etablissement_id;
    v_dest_type := 'ETABLISSEMENT';
    v_auteur_label := 'Le soignant';
  ELSE
    v_dest_id := v_mission.soignant_assigne_id;
    v_dest_type := 'SOIGNANT';
    v_auteur_label := 'L''établissement';
  END IF;

  IF v_dest_id IS NULL THEN RETURN NEW; END IF;

  -- Créer la notification in-app
  PERFORM fn_creer_notification(
    v_dest_id,
    v_dest_type,
    'NOUVEAU_MESSAGE',
    'Nouveau message',
    v_auteur_label || ' vous a envoyé un message sur "' || v_mission.intitule || '"',
    CASE WHEN v_dest_type = 'SOIGNANT'
      THEN '/soignant/missions/' || v_mission.id::TEXT
      ELSE '/etablissement/missions/' || v_mission.id::TEXT
    END,
    'mission',
    v_mission.id
  );

  RETURN NEW;
END;
$$;

-- Attacher le trigger
CREATE TRIGGER trg_notifier_nouveau_message
  AFTER INSERT ON messages_mission
  FOR EACH ROW
  EXECUTE FUNCTION dec_notifier_nouveau_message();