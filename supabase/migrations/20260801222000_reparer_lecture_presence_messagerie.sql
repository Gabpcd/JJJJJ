-- La policy RLS de presence_status appelait directement un helper private
-- dont EXECUTE est volontairement révoqué à authenticated. PostgreSQL ne
-- garantissant pas le court-circuit des OR, même la lecture de sa propre
-- présence pouvait alors échouer en 42501.
--
-- Les interlocuteurs exposés par la messagerie sont déjà normalisés dans la
-- conversation. La policy peut donc rester stricte sans appeler le helper
-- interne ni lui ouvrir un droit supplémentaire.

BEGIN;

DROP POLICY IF EXISTS pol_presence_status_select ON public.presence_status;
CREATE POLICY pol_presence_status_select
  ON public.presence_status
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE presence_status.user_id IN (
          c.participant_1_id,
          c.participant_2_id,
          c.soignant_id
        )
        AND c.archived_at IS NULL
        AND public.fn_conversation_accessible(c.id)
    )
  );

-- Un admin peut être simple observateur d'un fil métier, ou participant d'un
-- fil direct de support. Le premier cas ne modifie aucun accusé ; le second
-- marque uniquement les messages entrants, comme pour tout participant.
CREATE OR REPLACE FUNCTION public.fn_marquer_messages_lus(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_conv public.conversations%ROWTYPE;
  v_autre uuid;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'Non authentifié' USING ERRCODE = '28000';
  END IF;

  SELECT c.* INTO v_conv
  FROM public.conversations c
  WHERE c.id = p_conversation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  IF public.est_admin() THEN
    IF v_conv.soignant_id IS NULL
       AND v_conv.etablissement_id IS NULL
       AND v_uid IN (v_conv.participant_1_id, v_conv.participant_2_id) THEN
      UPDATE public.messages_chat
      SET lu = true
      WHERE conversation_id = p_conversation_id
        AND auteur_id <> v_uid
        AND lu IS FALSE;
    END IF;
    RETURN;
  END IF;

  IF v_conv.etablissement_id IS NOT NULL
     AND v_conv.soignant_id IS NOT NULL THEN
    IF private.fn_relation_conversation_partagee(
         v_uid,
         p_conversation_id
       ) THEN
      v_autre := CASE
        WHEN v_uid = v_conv.soignant_id THEN
          private.fn_interlocuteur_operationnel_id(
            v_conv.etablissement_id
          )
        ELSE v_conv.soignant_id
      END;
    ELSE
      RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
    END IF;
  ELSE
    IF v_uid = v_conv.participant_1_id THEN
      v_autre := v_conv.participant_2_id;
    ELSIF v_uid = v_conv.participant_2_id THEN
      v_autre := v_conv.participant_1_id;
    ELSE
      RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
    END IF;

    IF private.fn_relation_messagerie_autorisee(
         v_uid,
         v_autre,
         v_conv.mission_id
       ) IS NOT TRUE THEN
      RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF v_conv.soignant_id = v_uid THEN
    UPDATE public.messages_chat
    SET lu = true
    WHERE conversation_id = p_conversation_id
      AND auteur_id <> v_conv.soignant_id
      AND lu IS FALSE;
  ELSIF v_conv.soignant_id IS NOT NULL
        AND private.fn_membre_equipe_conversation(
          v_uid,
          p_conversation_id
        ) THEN
    UPDATE public.messages_chat
    SET lu = true
    WHERE conversation_id = p_conversation_id
      AND auteur_id = v_conv.soignant_id
      AND lu IS FALSE;
  ELSE
    UPDATE public.messages_chat
    SET lu = true
    WHERE conversation_id = p_conversation_id
      AND auteur_id <> v_uid
      AND lu IS FALSE;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_marquer_messages_lus(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_marquer_messages_lus(uuid)
  TO authenticated;

COMMIT;
