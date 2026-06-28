-- Swipe LIKE / SUPER_LIKE → candidature automatique EN_ATTENTE.
--
-- AVANT : un swipe LIKE/SUPER_LIKE enregistrait uniquement un row dans `swipes`.
-- L'établissement ne voyait RIEN : pas de candidature, pas de notification (sauf
-- SUPER_LIKE via edge function notif-match). Le soignant pensait « postuler » en
-- swipant à droite, mais rien ne se passait côté établissement. Bug produit majeur.
--
-- APRÈS : un swipe LIKE ou SUPER_LIKE crée automatiquement une candidature
-- EN_ATTENTE (si la profession est compatible, pas exclu, pas de doublon) et
-- notifie l'établissement. Le SUPER_LIKE ajoute un message « Candidature
-- prioritaire (super-like) » et une notification distincte « ⭐ Candidature
-- prioritaire reçue ! ». Le DISLIKE reste inchangé (enregistrement uniquement).

CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(p_mission_id uuid, p_direction text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_direction swipe_direction;
  v_quota_count integer;
  v_swipe_id uuid;
  v_quota_max integer := (public.fn_param_num('quota_superlikes_jour', 5))::integer;
  v_mission RECORD;
  v_soignant RECORD;
  v_candidature_id uuid;
  v_choix_contrat text;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'SUPER_LIKE') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;

  v_direction := p_direction::swipe_direction;

  IF v_direction = 'SUPER_LIKE' THEN
    SELECT count INTO v_quota_count
      FROM public.super_swipes_quota
     WHERE soignant_id = v_soignant_id AND date = current_date;

    IF COALESCE(v_quota_count, 0) >= v_quota_max THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'quota_super_like_atteint',
        'quota_max', v_quota_max,
        'reset_le', (current_date + interval '1 day')::date
      );
    END IF;

    INSERT INTO public.super_swipes_quota (soignant_id, date, count)
      VALUES (v_soignant_id, current_date, 1)
      ON CONFLICT (soignant_id, date)
        DO UPDATE SET count = super_swipes_quota.count + 1
      RETURNING count INTO v_quota_count;
  END IF;

  INSERT INTO public.swipes (soignant_id, mission_id, direction)
    VALUES (v_soignant_id, p_mission_id, v_direction)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING
    RETURNING id INTO v_swipe_id;

  IF v_swipe_id IS NULL THEN
    IF v_direction = 'SUPER_LIKE' THEN
      UPDATE public.super_swipes_quota
         SET count = count - 1
       WHERE soignant_id = v_soignant_id AND date = current_date;
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  -- LIKE ou SUPER_LIKE → créer automatiquement une candidature EN_ATTENTE
  IF v_direction IN ('LIKE', 'SUPER_LIKE') THEN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    SELECT * INTO v_soignant FROM soignants WHERE id = v_soignant_id;

    IF v_mission.id IS NOT NULL AND v_soignant.id IS NOT NULL
       AND v_mission.statut = 'OUVERTE'
       AND fn_soignant_compatible_mission(
             v_soignant.profession, v_soignant.specialite_medicale,
             v_mission.profession_requise, v_mission.specialite_medicale_requise,
             v_mission.accepte_non_specialises)
       AND NOT fn_est_exclu(v_soignant_id, v_mission.etablissement_id)
       AND NOT EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = v_soignant_id)
    THEN
      IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_contrat := 'SALARIE';
      ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_contrat := 'LIBERAL';
      ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_contrat := COALESCE(v_soignant.preference_contrat_mixte, 'SALARIE');
      ELSE v_choix_contrat := COALESCE(v_soignant.type_exercice, 'SALARIE');
      END IF;

      INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
      VALUES (p_mission_id, v_soignant_id,
              CASE WHEN v_direction = 'SUPER_LIKE' THEN 'Candidature prioritaire (super-like)' ELSE NULL END,
              'EN_ATTENTE', v_choix_contrat)
      RETURNING id INTO v_candidature_id;

      INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
      VALUES (
        v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
        CASE WHEN v_direction = 'SUPER_LIKE'
          THEN '⭐ Candidature prioritaire reçue !'
          ELSE '📋 Nouvelle candidature reçue'
        END,
        COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' || v_mission.intitule || ' ».'
          || CASE WHEN v_direction = 'SUPER_LIKE' THEN ' Ce soignant a montré un fort intérêt (super-like).' ELSE '' END,
        '/etablissement/missions/' || p_mission_id
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'swipe_id', v_swipe_id,
    'direction', p_direction,
    'candidature_id', v_candidature_id,
    'quota_restant', CASE WHEN v_direction = 'SUPER_LIKE' THEN v_quota_max - v_quota_count ELSE NULL END
  );
END;
$function$;
