-- La notification d'acceptation demande explicitement au soignant de signer.
-- Elle doit donc ouvrir le contrat, pas la conversation de la mission.

CREATE OR REPLACE FUNCTION public.fn_notifier_candidature_acceptee(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_titre text DEFAULT NULL,
  p_corps text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_conversation_id uuid;
  v_contrat_id uuid;
  v_notification_id uuid;
  v_lien text;
  v_titre text;
  v_corps text;
BEGIN
  SELECT mi.*
  INTO v_mission
  FROM public.missions mi
  WHERE mi.id = p_mission_id
    AND mi.soignant_assigne_id = p_soignant_id
    AND mi.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND EXISTS (
      SELECT 1
      FROM public.candidatures c
      WHERE c.mission_id = mi.id
        AND c.soignant_id = p_soignant_id
        AND c.statut = 'ACCEPTEE'
    )
  FOR SHARE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object(
      'error', 'Mission non attribuée à ce soignant'
    );
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'CANDIDATURE_ACCEPTEE:' || p_mission_id::text || ':' ||
      p_soignant_id::text,
      0
    )
  );

  v_conversation_id := public.fn_creer_conversation_si_absente(
    p_mission_id,
    p_soignant_id,
    v_mission.etablissement_id
  );

  SELECT cm.id
  INTO v_contrat_id
  FROM public.contrats_mission cm
  WHERE cm.mission_id = p_mission_id
    AND cm.soignant_id = p_soignant_id
    AND cm.etablissement_id = v_mission.etablissement_id
    AND cm.statut NOT IN ('ANNULE', 'EXPIRE')
  ORDER BY cm.cree_le DESC, cm.id DESC
  LIMIT 1;

  v_lien := CASE
    WHEN v_contrat_id IS NOT NULL
      THEN '/contrat/' || v_contrat_id::text
    ELSE '/soignant/missions/' || p_mission_id::text
  END;
  v_titre := COALESCE(
    NULLIF(pg_catalog.btrim(p_titre), ''),
    'Candidature acceptée'
  );
  v_corps := COALESCE(
    NULLIF(pg_catalog.btrim(p_corps), ''),
    'Votre candidature pour « ' || v_mission.intitule ||
      ' » a été acceptée. Signez votre contrat.'
  );

  SELECT n.id
  INTO v_notification_id
  FROM public.notifications n
  WHERE n.destinataire_id = p_soignant_id
    AND n.type_destinataire = 'SOIGNANT'
    AND n.type = 'CANDIDATURE_ACCEPTEE'
    AND n.type_ressource = 'mission'
    AND n.id_ressource = p_mission_id
  ORDER BY n.cree_le DESC, n.id
  LIMIT 1
  FOR UPDATE;

  IF v_notification_id IS NULL THEN
    INSERT INTO public.notifications (
      destinataire_id,
      type_destinataire,
      type,
      titre,
      corps,
      lien,
      type_ressource,
      id_ressource
    ) VALUES (
      p_soignant_id,
      'SOIGNANT',
      'CANDIDATURE_ACCEPTEE',
      v_titre,
      v_corps,
      v_lien,
      'mission',
      p_mission_id
    )
    RETURNING id INTO v_notification_id;
  ELSE
    UPDATE public.notifications
    SET titre = v_titre,
        corps = v_corps,
        lien = v_lien,
        type_ressource = 'mission',
        id_ressource = p_mission_id
    WHERE id = v_notification_id;
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'success', true,
    'notification_id', v_notification_id,
    'conversation_id', v_conversation_id,
    'contrat_id', v_contrat_id,
    'lien', v_lien
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_notifier_candidature_acceptee(
  uuid, uuid, text, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_notifier_candidature_acceptee(
  uuid, uuid, text, text
) TO service_role;

-- Répare les notifications encore non lues afin que l'utilisateur déjà averti
-- n'ait pas à deviner où se trouve le contrat.
UPDATE public.notifications n
SET lien = '/contrat/' || (
  SELECT contrat.id::text
  FROM public.contrats_mission contrat
  WHERE contrat.mission_id = n.id_ressource
    AND contrat.soignant_id = n.destinataire_id
    AND contrat.statut NOT IN ('ANNULE', 'EXPIRE')
  ORDER BY contrat.cree_le DESC, contrat.id DESC
  LIMIT 1
)
WHERE n.type = 'CANDIDATURE_ACCEPTEE'
  AND n.type_destinataire = 'SOIGNANT'
  AND n.type_ressource = 'mission'
  AND n.lue = false
  AND EXISTS (
    SELECT 1
    FROM public.contrats_mission contrat
    WHERE contrat.mission_id = n.id_ressource
      AND contrat.soignant_id = n.destinataire_id
      AND contrat.statut NOT IN ('ANNULE', 'EXPIRE')
  );
