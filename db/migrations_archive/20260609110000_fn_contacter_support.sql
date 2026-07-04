-- « Contacter Jolene » via la messagerie in-app (au lieu d'un mailto).
--
-- fn_obtenir_conversation interdit les conversations sans mission partagée, donc un
-- établissement (ou un soignant) ne pouvait pas ouvrir de conversation avec le
-- support Jolene. Cette RPC dédiée ouvre (ou retrouve) une conversation avec le
-- compte support (un ADMIN_PLATEFORME, de préférence admin@jolene.app). Les admins
-- disposent déjà d'une messagerie (/admin/messagerie) → ils voient le message.

CREATE OR REPLACE FUNCTION public.fn_contacter_support()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_support uuid;
  v_conv uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  -- Compte support = un ADMIN_PLATEFORME (préférence admin@jolene.app, sinon le plus ancien).
  SELECT id INTO v_support
  FROM auth.users
  WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ORDER BY (email = 'admin@jolene.app') DESC, created_at ASC
  LIMIT 1;

  IF v_support IS NULL THEN
    RAISE EXCEPTION 'Support indisponible pour le moment.';
  END IF;
  IF v_support = v_me THEN
    RAISE EXCEPTION 'Action non applicable pour ce compte.';
  END IF;

  SELECT id INTO v_conv
  FROM conversations
  WHERE (participant_1_id = v_me AND participant_2_id = v_support)
     OR (participant_1_id = v_support AND participant_2_id = v_me)
  LIMIT 1;

  IF v_conv IS NULL THEN
    INSERT INTO conversations (participant_1_id, participant_2_id, mission_id)
    VALUES (v_me, v_support, NULL)
    RETURNING id INTO v_conv;
  END IF;

  RETURN v_conv;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_contacter_support() TO authenticated;
