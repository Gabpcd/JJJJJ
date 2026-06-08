-- Fix : fn_annuler_candidature_soignant était TOTALEMENT cassée en production.
--
-- Bug (découvert par audit e2e impersonation, rollback) : la fonction met le statut
-- de la CANDIDATURE à 'ANNULEE_PAR_SOIGNANT'. Or :
--   1. 'ANNULEE_PAR_SOIGNANT' est un statut de MISSION (enum statut_mission), PAS un
--      statut de candidature : candidatures_statut_check n'autorise que 'ANNULEE'.
--   2. Le trigger fn_protect_candidature_statut n'autorise au soignant que
--      EN_ATTENTE -> ANNULEE (jamais -> ANNULEE_PAR_SOIGNANT, ni depuis ACCEPTEE).
-- => Tout appel échouait ("Vous ne pouvez pas modifier le statut..." ou violation
--    CHECK), pour les candidatures EN_ATTENTE comme ACCEPTEE. Aucun soignant ne
--    pouvait annuler sa candidature / se désister d'une mission acceptée.
--
-- Fix :
--   A. fn_annuler_candidature_soignant : statut candidature -> 'ANNULEE' (valeur
--      valide, cohérente avec le reste du code). La sémantique « par le soignant »
--      reste tracée dans motif_refus + journaux_audit. Pose une GUC de contexte
--      jolene.annulation_soignant_ctx pour autoriser la transition ACCEPTEE->ANNULEE.
--   B. fn_protect_candidature_statut : autorise ACCEPTEE -> ANNULEE pour le soignant
--      UNIQUEMENT quand la GUC est posée (donc uniquement via la fonction légitime,
--      qui applique la grille de pénalité / l'événement de score). Empêche le
--      contournement de pénalité par UPDATE brut.
--
-- Validé e2e : annulation EN_ATTENTE (libre, 0 pt) + annulation ACCEPTEE (pénalité,
-- mission ré-ouverte, contrat RUPTURE_SOIGNANT, événement de score) passent désormais.

-- A. Fonction d'annulation (statut 'ANNULEE' + GUC de contexte)
CREATE OR REPLACE FUNCTION public.fn_annuler_candidature_soignant(p_candidature_id uuid, p_motif_categorie text, p_texte_libre text, p_justificatif_storage_path text DEFAULT NULL::text)
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

  -- Contexte autorisant la transition ACCEPTEE->ANNULEE côté trigger (voir fix B).
  PERFORM set_config('jolene.annulation_soignant_ctx', 'true', true);

  -- Si candidature pas encore acceptée : annulation libre
  IF v_candidature.statut = 'EN_ATTENTE' THEN
    UPDATE public.candidatures SET
      statut = 'ANNULEE',
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
    statut = 'ANNULEE',
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
    IF v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')
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

-- B. Trigger : autorise ACCEPTEE -> ANNULEE côté soignant via la GUC de contexte
CREATE OR REPLACE FUNCTION public.fn_protect_candidature_statut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    -- Soignant
    IF auth.uid() = OLD.soignant_id THEN
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
        IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

        IF NEW.statut IS DISTINCT FROM OLD.statut THEN
            IF OLD.statut = 'EN_ATTENTE' AND NEW.statut = 'ANNULEE' THEN
                RETURN NEW;
            ELSIF OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut = 'ANNULEE' THEN
                RETURN NEW;
            ELSIF OLD.statut = 'ACCEPTEE' AND NEW.statut = 'ANNULEE'
                  AND COALESCE(current_setting('jolene.annulation_soignant_ctx', true), '') = 'true' THEN
                -- Désistement d'une mission acceptée : uniquement via
                -- fn_annuler_candidature_soignant (qui applique la pénalité/score).
                RETURN NEW;
            ELSE
                RAISE EXCEPTION 'Vous ne pouvez pas modifier le statut de votre candidature (% → %)', OLD.statut, NEW.statut;
            END IF;
        END IF;

        IF NEW.message IS DISTINCT FROM OLD.message AND OLD.statut != 'EN_ATTENTE' THEN
            RAISE EXCEPTION 'Vous ne pouvez plus modifier votre message';
        END IF;

        NEW.motif_refus := OLD.motif_refus;
        NEW.traite_le := OLD.traite_le;
        RETURN NEW;
    END IF;

    -- Établissement
    IF mon_etablissement_id() IS NOT NULL THEN
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
        IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

        IF NEW.statut IS DISTINCT FROM OLD.statut THEN
            IF NOT (
                (OLD.statut = 'EN_ATTENTE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
                OR (OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
                OR (OLD.statut = 'PROPOSEE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE'))
            ) THEN
                RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Accès refusé à cette candidature';
END;
$function$;

-- NOTE : la fonction soignant écrasait motif_refus/traite_le via NEW.motif_refus :=
-- OLD.motif_refus dans le trigger. Comme la branche soignant retourne NEW APRÈS avoir
-- réécrit motif_refus = OLD, les UPDATE de motif_refus par la fonction seraient annulés.
-- Or la transition de statut sort plus tôt via RETURN NEW (les 3 branches ANNULEE),
-- donc motif_refus posé par la fonction est conservé. Comportement inchangé.
