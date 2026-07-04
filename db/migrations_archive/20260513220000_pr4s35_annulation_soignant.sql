-- PR 4 Sprint 3.5 — Annulation mission côté soignant + fenêtre rétractation
--
-- Implémente la logique d'annulation côté soignant avec impact score
-- selon la grille validée par Gabrielle :
--   - Fenêtre 30 min après acceptation : annulation libre (0 pts)
--   - > 24h avant mission : neutre (0 pts, notif étab)
--   - 12-24h avant : -5 pts (contestable)
--   - 1-12h avant : -10 pts (contestable)
--   - ASAP annulée après fenêtre : -25 pts (contestable)
--   - < 1h ou no-show : -30 pts + signalement admin (PAS suspension auto)
--
-- AUCUNE pénalité financière soignant. AUCUNE suspension auto.
-- Mission repasse OUVERTE pour nouvelles candidatures.
-- Si CDD signé : enqueue annulation DPAE (URSSAF dans 48h).
-- Si contrat signé : marquage RUPTURE_SOIGNANT.

-- ============================================================
-- 1. Helper : déterminer le bucket de pénalité
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_calculer_penalite_annulation_soignant(
  p_acceptee_a timestamptz,
  p_debut_mission timestamptz,
  p_est_asap boolean
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_delta_retract interval;
  v_delta_mission interval;
  v_points int := 0;
  v_motif text := 'aucun';
  v_libre boolean := false;
BEGIN
  v_delta_retract := NOW() - p_acceptee_a;
  v_delta_mission := p_debut_mission - NOW();

  -- Fenêtre rétractation 30 min : annulation libre
  IF v_delta_retract < INTERVAL '30 minutes' THEN
    RETURN jsonb_build_object('libre', true, 'points', 0, 'motif', 'fenetre_retractation_30min');
  END IF;

  -- ASAP annulée après fenêtre rétractation
  IF p_est_asap AND v_delta_mission < INTERVAL '2 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -25,
                                'motif', 'ASAP_ANNULEE_APRES_FENETRE');
  END IF;

  -- No-show ou annulation last-minute (< 1h)
  IF v_delta_mission < INTERVAL '1 hour' THEN
    RETURN jsonb_build_object('libre', false, 'points', -30,
                                'motif', 'NO_SHOW', 'signalement_admin', true);
  END IF;

  -- 1-12h avant
  IF v_delta_mission < INTERVAL '12 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -10,
                                'motif', 'ANNULATION_1_12H');
  END IF;

  -- 12-24h avant
  IF v_delta_mission < INTERVAL '24 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -5,
                                'motif', 'ANNULATION_12_24H');
  END IF;

  -- > 24h : neutre
  RETURN jsonb_build_object('libre', true, 'points', 0, 'motif', 'neutre_delai_long');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_penalite_annulation_soignant(timestamptz, timestamptz, boolean) TO authenticated;

-- ============================================================
-- 2. RPC principale : annulation candidature par soignant
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_annuler_candidature_soignant(
  p_candidature_id uuid,
  p_motif_categorie text,
  p_texte_libre text,
  p_justificatif_storage_path text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_candidature RECORD;
  v_mission RECORD;
  v_contrat RECORD;
  v_penalite jsonb;
  v_event_id uuid;
  v_points int;
  v_motif_event text;
  v_signalement boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  IF p_motif_categorie IS NULL OR p_motif_categorie NOT IN (
    'URGENCE_PERSONNELLE', 'URGENCE_MEDICALE', 'DEUIL',
    'PROBLEME_TRANSPORT', 'CHANGEMENT_AVIS', 'AUTRE'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MOTIF_INVALIDE',
                                'error', 'Motif requis (URGENCE_PERSONNELLE, URGENCE_MEDICALE, DEUIL, PROBLEME_TRANSPORT, CHANGEMENT_AVIS, AUTRE)');
  END IF;

  IF p_texte_libre IS NULL OR length(trim(p_texte_libre)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEXTE_REQUIS',
                                'error', 'Texte libre obligatoire (min 10 caractères)');
  END IF;

  SELECT * INTO v_candidature FROM public.candidatures WHERE id = p_candidature_id;
  IF v_candidature IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CANDIDATURE_INTROUVABLE', 'error', 'Candidature introuvable');
  END IF;

  IF v_candidature.soignant_id != v_uid THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
                                'error', 'Vous n''êtes pas le soignant de cette candidature');
  END IF;

  IF v_candidature.statut NOT IN ('ACCEPTEE', 'EN_ATTENTE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'STATUT_INVALIDE',
                                'error', 'Candidature pas dans un état annulable (statut : ' || v_candidature.statut || ')');
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_candidature.mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'MISSION_INTROUVABLE', 'error', 'Mission introuvable');
  END IF;

  -- Si candidature pas encore acceptée : annulation libre
  IF v_candidature.statut = 'EN_ATTENTE' THEN
    UPDATE public.candidatures SET
      statut = 'ANNULEE_SOIGNANT',
      traite_le = NOW(),
      motif_refus = p_texte_libre
    WHERE id = p_candidature_id;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      v_uid, 'SOIGNANT', 'SYSTEM', 'candidature', p_candidature_id,
      jsonb_build_object('evenement', 'CANDIDATURE_ANNULEE_PAR_SOIGNANT',
                          'motif_categorie', p_motif_categorie,
                          'texte_libre', p_texte_libre,
                          'libre', true,
                          'statut_initial', v_candidature.statut)
    );

    RETURN jsonb_build_object('success', true, 'libre', true, 'points', 0,
                                'message', 'Candidature retirée sans impact');
  END IF;

  -- Candidature ACCEPTEE : calculer pénalité selon grille
  v_penalite := public.fn_calculer_penalite_annulation_soignant(
    v_candidature.acceptee_a, v_mission.debut_le, v_mission.est_asap
  );

  v_points := (v_penalite->>'points')::int;
  v_motif_event := v_penalite->>'motif';
  v_signalement := COALESCE((v_penalite->>'signalement_admin')::boolean, false);

  -- Update candidature
  UPDATE public.candidatures SET
    statut = 'ANNULEE_SOIGNANT',
    traite_le = NOW(),
    motif_refus = p_motif_categorie || ' : ' || p_texte_libre
  WHERE id = p_candidature_id;

  -- Mission repasse OUVERTE pour nouvelles candidatures
  UPDATE public.missions SET
    statut = 'OUVERTE',
    soignant_assigne_id = NULL,
    modifie_le = NOW()
  WHERE id = v_candidature.mission_id AND statut IN ('ASSIGNEE', 'EN_COURS');

  -- Si contrat existe, marquer RUPTURE_SOIGNANT
  SELECT * INTO v_contrat FROM public.contrats_mission
  WHERE mission_id = v_candidature.mission_id LIMIT 1;
  IF FOUND THEN
    UPDATE public.contrats_mission SET
      statut = 'RUPTURE_SOIGNANT',
      modifie_le = NOW()
    WHERE id = v_contrat.id;

    -- Si CDD signé : enqueue annulation DPAE
    IF v_contrat.type_contrat IN ('CDD', 'CDDU', 'SALARIE')
       AND v_contrat.statut = 'SIGNE_COMPLET' THEN
      INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
      VALUES ('DPAE_ANNULATION',
              jsonb_build_object('contrat_id', v_contrat.id, 'mission_id', v_candidature.mission_id,
                                  'motif', 'ANNULATION_SOIGNANT', 'echeance_legale_h', 48),
              'ANNULATION_MISSION', p_candidature_id);
    END IF;
  END IF;

  -- Créer l'événement de score si pénalité applicable
  IF v_points < 0 THEN
    INSERT INTO public.evenements_score_soignant (
      soignant_id, type_evenement, points, motif, contestable,
      mission_id, candidature_id, justificatif_storage_path,
      details
    ) VALUES (
      v_uid, v_motif_event, v_points,
      p_motif_categorie || ' : ' || left(p_texte_libre, 200),
      true,  -- contestable=true (réclamation possible)
      v_candidature.mission_id, p_candidature_id, p_justificatif_storage_path,
      jsonb_build_object(
        'motif_categorie', p_motif_categorie,
        'texte_libre', p_texte_libre,
        'delta_mission_h', EXTRACT(EPOCH FROM (v_mission.debut_le - NOW())) / 3600,
        'delta_retract_min', EXTRACT(EPOCH FROM (NOW() - v_candidature.acceptee_a)) / 60,
        'est_asap', v_mission.est_asap,
        'signalement_admin', v_signalement
      )
    ) RETURNING id INTO v_event_id;

    -- Signalement admin si no-show (alerte, PAS suspension auto)
    IF v_signalement THEN
      INSERT INTO public.journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource, details
      ) VALUES (
        v_uid, 'SOIGNANT', 'SYSTEM', 'soignant', v_uid,
        jsonb_build_object('evenement', 'ALERTE_ADMIN_NO_SHOW',
                            'mission_id', v_candidature.mission_id,
                            'event_score_id', v_event_id,
                            'motif_categorie', p_motif_categorie,
                            'action_requise', 'REVISION_MANUELLE_ADMIN')
      );
    END IF;
  END IF;

  -- Notification étab (email + push) que la mission se libère
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES
    ('EMAIL_NOTIF', jsonb_build_object(
      'destinataire_id', v_mission.etablissement_id,
      'type', 'CANDIDATURE_ANNULEE_SOIGNANT',
      'data', jsonb_build_object(
        'mission_id', v_mission.id,
        'motif_categorie', p_motif_categorie,
        'libre', v_points = 0
      )
    ), 'ANNULATION_MISSION', p_candidature_id),
    ('PUSH_NOTIF', jsonb_build_object(
      'destinataire_id', v_mission.etablissement_id,
      'type_evenement', 'CANDIDATURE_ANNULEE_SOIGNANT',
      'titre', 'Le soignant a annulé',
      'corps', 'La mission est de nouveau disponible. Notifications envoyées aux soignants matching.'
    ), 'ANNULATION_MISSION', p_candidature_id);

  -- Audit
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'candidature', p_candidature_id,
    jsonb_build_object(
      'evenement', 'CANDIDATURE_ANNULEE_PAR_SOIGNANT',
      'motif_categorie', p_motif_categorie,
      'texte_libre', p_texte_libre,
      'points', v_points,
      'motif_score', v_motif_event,
      'event_score_id', v_event_id,
      'mission_id', v_mission.id,
      'signalement_admin', v_signalement
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'libre', v_points = 0,
    'points', v_points,
    'motif_score', v_motif_event,
    'event_score_id', v_event_id,
    'contestable', v_points < 0,
    'signalement_admin', v_signalement
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_annuler_candidature_soignant(uuid, text, text, text) TO authenticated;

-- ============================================================
-- 3. Trigger pour mettre à jour candidatures.acceptee_a
-- ============================================================
CREATE OR REPLACE FUNCTION public.dec_set_candidature_acceptee_a()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.statut = 'ACCEPTEE' AND OLD.statut IS DISTINCT FROM 'ACCEPTEE' THEN
    NEW.acceptee_a := COALESCE(NEW.acceptee_a, NOW());
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_set_candidature_acceptee_a ON public.candidatures;
CREATE TRIGGER trg_set_candidature_acceptee_a
  BEFORE UPDATE OF statut ON public.candidatures
  FOR EACH ROW EXECUTE FUNCTION public.dec_set_candidature_acceptee_a();

-- Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT35_PR4_ANNULATION_SOIGNANT_INSTALLED',
    'pr', 'PR 4 Sprint 3.5',
    'rpcs', ARRAY['fn_calculer_penalite_annulation_soignant',
                   'fn_annuler_candidature_soignant'],
    'triggers', ARRAY['trg_set_candidature_acceptee_a'],
    'note', 'AUCUNE suspension auto. Signalement admin uniquement pour no-show. Réclamation possible via fn_creer_reclamation_score (PR 7 S35).'
  )
);
