-- Une acceptation de candidature et sa notification forment une seule
-- opération métier. Le helper ci-dessous est aussi le point idempotent utilisé
-- par l'Edge Function historique : aucun retry ne peut créer un doublon.

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

  -- Sérialise aussi deux appels Edge simultanés, sans supprimer l'historique
  -- existant et sans dépendre d'un index partiel difficile à upsert.
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
  v_lien := CASE
    WHEN v_conversation_id IS NOT NULL
      THEN '/soignant/messagerie?conv=' || v_conversation_id::text
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

CREATE OR REPLACE FUNCTION public.fn_traiter_candidature(
  p_candidature_id uuid,
  p_decision text,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_candidature public.candidatures%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_mission_id uuid;
  v_result jsonb;
  v_notification jsonb;
BEGIN
  -- Ordre global de verrouillage : mission avant candidature. Deux candidats
  -- traités simultanément pour la même mission ne peuvent ainsi pas former le
  -- cycle candidature A -> mission -> candidature B.
  SELECT c.mission_id INTO v_mission_id
  FROM public.candidatures c
  WHERE c.id = p_candidature_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Candidature introuvable');
  END IF;

  SELECT mi.* INTO v_mission
  FROM public.missions mi
  WHERE mi.id = v_mission_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Mission introuvable');
  END IF;

  SELECT c.* INTO v_candidature
  FROM public.candidatures c
  WHERE c.id = p_candidature_id
    AND c.mission_id = v_mission_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Candidature introuvable');
  END IF;
  IF public.fn_a_permission_etablissement(
       'candidatures',
       v_mission.etablissement_id
     ) IS NOT TRUE THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_candidature.statut::text NOT IN (
    'EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB'
  ) THEN
    RETURN pg_catalog.jsonb_build_object(
      'error', 'Cette candidature a déjà été traitée.'
    );
  END IF;

  IF p_decision = 'REFUSEE' THEN
    UPDATE public.candidatures
    SET statut = 'REFUSEE', motif_refus = p_motif,
        traite_le = pg_catalog.now()
    WHERE id = p_candidature_id;

    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_candidature.soignant_id,
      'CANDIDATURE_REFUSEE',
      'Candidature non retenue',
      'Votre candidature pour « ' || v_mission.intitule ||
        ' » n''a pas été retenue.' ||
        CASE WHEN p_motif IS NOT NULL
          THEN ' Motif : ' || p_motif
          ELSE ''
        END,
      '/soignant/missions',
      'SOIGNANT'
    );
    RETURN pg_catalog.jsonb_build_object('success', true);
  ELSIF p_decision <> 'ACCEPTEE' THEN
    RETURN pg_catalog.jsonb_build_object('error', 'Décision invalide');
  END IF;

  v_result := public.fn_finaliser_attribution_mission(
    v_candidature.mission_id,
    v_candidature.soignant_id,
    v_candidature.type_contrat_choisi
  );
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
    IF v_result->>'documents_requis_pour' IS NOT NULL THEN
      INSERT INTO public.notifications (
        destinataire_id, type, titre, corps, lien, type_destinataire
      )
      SELECT
        v_candidature.soignant_id,
        'RAPPEL_DOCUMENTS',
        'Un établissement veut accepter votre candidature',
        'Complétez les documents requis pour la mission ' ||
          pg_catalog.lower(v_result->>'documents_requis_pour') ||
          ' afin de finaliser votre contrat.',
        '/soignant/mes-documents',
        'SOIGNANT'
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.notifications n
        WHERE n.destinataire_id = v_candidature.soignant_id
          AND n.type = 'RAPPEL_DOCUMENTS'
          AND n.cree_le > pg_catalog.now() - interval '6 hours'
      );
    END IF;
    RETURN v_result;
  END IF;

  UPDATE public.candidatures
  SET statut = 'ACCEPTEE', traite_le = pg_catalog.now()
  WHERE id = p_candidature_id;
  UPDATE public.candidatures
  SET statut = 'REFUSEE',
      motif_refus = 'Un autre candidat a été sélectionné',
      traite_le = pg_catalog.now()
  WHERE mission_id = v_candidature.mission_id
    AND id <> p_candidature_id
    AND statut::text IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB');

  v_notification := public.fn_notifier_candidature_acceptee(
    v_candidature.mission_id,
    v_candidature.soignant_id,
    'Candidature acceptée',
    'Votre candidature pour « ' || v_mission.intitule ||
      ' » a été acceptée. Signez votre contrat.'
  );
  IF COALESCE((v_notification->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Notification d''acceptation impossible : %',
      COALESCE(v_notification->>'error', 'erreur inconnue');
  END IF;

  IF v_result->>'choix_applique' = 'LIBERAL'
     AND NOT COALESCE((
       SELECT s.mandat_facturation_signe
       FROM public.soignants s
       WHERE s.id = v_candidature.soignant_id
     ), false) THEN
    INSERT INTO public.notifications (
      destinataire_id, type, titre, corps, lien, type_destinataire
    ) VALUES (
      v_candidature.soignant_id,
      'CONTRAT_A_SIGNER',
      '✍️ Signez votre mandat de facturation',
      'Votre mission « ' || v_mission.intitule ||
        ' » est confirmée en libéral. Signez le mandat avant son démarrage.',
      '/soignant/mandat-facturation',
      'SOIGNANT'
    );
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_traiter_candidature(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_traiter_candidature(uuid, text, text)
  TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
