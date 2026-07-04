-- SWIPE — 3 garanties manquantes, alignées sur le flux « Postuler » classique
-- (fn_postuler_mission) pour que candidater depuis le swipe soit aussi explicite :
--
--  1. FILTRE DUR TYPE D'EXERCICE sur le deck (fn_obtenir_missions_swipe) :
--     un soignant SALARIÉ ne voit JAMAIS de mission réservée aux libéraux et
--     vice-versa. Un MIXTE voit les deux. Même logique que la recherche
--     (fn_missions_publiques_recherche) et que fn_postuler_mission.
--
--  2. PLANCHER TARIF HORAIRE (préférence de profil persistante
--     soignants.taux_horaire_minimum) : le deck masque les missions sous le
--     tarif minimum choisi par le soignant. NULL = pas de plancher.
--
--  3. CHOIX DE CONTRAT EXPLICITE depuis le swipe (fn_enregistrer_swipe) :
--     quand la mission accepte les deux (type_contrat_recherche='TOUS') ET que
--     le soignant est MIXTE, on EXIGE un choix salarié/libéral (param
--     p_choix_contrat) — sauf préférence déjà mémorisée. Sans choix, le swipe
--     N'EST PAS enregistré (pas de candidature, pas de quota super-like consommé)
--     et on renvoie {choix_requis:true, options:[...]} pour que le front ouvre
--     ChoixContratDialog, exactement comme fn_postuler_mission. Le choix LIBERAL
--     exige une RCP valide (sinon erreur explicite).
--
-- NB CREATE OR REPLACE → l'event-trigger fn_auto_revoke_anon_execute révoque
-- l'EXECUTE : on re-GRANT explicitement en fin de migration (ces RPC sont
-- réservés aux soignants authentifiés, donc PAS de grant anon ici).

-- ── 1+2 : deck swipe (exercice + plancher tarif) ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_soignant_id uuid := auth.uid(); v_sg soignants%ROWTYPE; v_missions jsonb;
BEGIN
  IF v_soignant_id IS NULL THEN RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required'); END IF;
  SELECT * INTO v_sg FROM soignants WHERE id = v_soignant_id;
  SELECT COALESCE(jsonb_agg(payload ORDER BY (payload->>'score')::int DESC), '[]'::jsonb) INTO v_missions
  FROM (
    SELECT jsonb_build_object(
      'mission_id', m.id, 'intitule', m.intitule, 'profession_requise', m.profession_requise,
      'etablissement_id', m.etablissement_id, 'etablissement_nom', e.nom, 'etablissement_ville', e.adresse_ville,
      'etablissement_score', e.score_qualite, 'taux_horaire_base', m.taux_horaire_base, 'duree_heures', m.duree_heures,
      'debut_le', m.debut_le, 'fin_le', m.fin_le, 'est_urgente', m.est_urgente, 'service', m.service,
      'type_contrat_applique', m.type_contrat_applique, 'total_brut', m.total_brut, 'net_a_payer', m.net_a_payer,
      'net_estime', m.net_estime, 'montant_ifm', COALESCE(m.montant_ifm, 0), 'montant_icp', COALESCE(m.montant_icp, 0),
      'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0), 'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
      'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0), 'score', COALESCE(ms.score_global, 0),
      'breakdown', COALESCE(ms.breakdown, '{}'::jsonb)
    ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_soignant_id
     WHERE m.statut = 'OUVERTE'
       -- FILTRE DUR PROFESSION : ne montrer QUE les missions réellement exerçables.
       AND fn_soignant_compatible_mission(
             v_sg.profession, v_sg.specialite_medicale,
             m.profession_requise, m.specialite_medicale_requise, m.accepte_non_specialises)
       -- FILTRE DUR TYPE D'EXERCICE : un salarié ne voit pas les missions libérales
       -- et inversement ; un MIXTE (ou type_exercice inconnu) voit les deux.
       AND (m.type_contrat_recherche = 'TOUS' OR v_sg.type_exercice IS NULL OR v_sg.type_exercice = 'MIXTE'
            OR (m.type_contrat_recherche = 'SALARIE' AND v_sg.type_exercice IN ('SALARIE', 'MIXTE'))
            OR (m.type_contrat_recherche = 'LIBERAL' AND v_sg.type_exercice IN ('LIBERAL', 'MIXTE')))
       -- PLANCHER TARIF HORAIRE (préférence de profil persistante) : masque les
       -- missions sous le tarif minimum. NULL des deux côtés = pas de filtre.
       AND (v_sg.taux_horaire_minimum IS NULL OR m.taux_horaire_base IS NULL
            OR m.taux_horaire_base >= v_sg.taux_horaire_minimum)
       AND m.id NOT IN (SELECT s.mission_id FROM public.swipes s WHERE s.soignant_id = v_soignant_id)
     ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
     LIMIT p_limit
  ) t;
  RETURN jsonb_build_object('missions', v_missions);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_missions_swipe(integer) TO authenticated, service_role;

-- ── 3 : enregistrement du swipe + choix de contrat explicite ───────────────
-- Nouvelle signature (ajout de p_choix_contrat). On DROP l'ancienne (uuid, text)
-- pour éviter une surcharge ambiguë côté PostgREST.
DROP FUNCTION IF EXISTS public.fn_enregistrer_swipe(uuid, text);

CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(
  p_mission_id uuid,
  p_direction text,
  p_choix_contrat text DEFAULT NULL
)
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
  v_choix_effectif text;
  v_rcp_valide boolean;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'SUPER_LIKE') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;

  v_direction := p_direction::swipe_direction;

  -- Pour un LIKE/SUPER_LIKE (= candidature), on détermine le contrat AVANT de
  -- consommer le quota super-like ou d'enregistrer le swipe, afin de pouvoir
  -- demander un choix explicite sans effet de bord (mission reste swipeable).
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
      -- Garde-fou type d'exercice (le deck filtre déjà, défense en profondeur).
      IF v_mission.type_contrat_recherche = 'SALARIE'
         AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Cette mission est réservée aux salariés.');
      END IF;
      IF v_mission.type_contrat_recherche = 'LIBERAL'
         AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('ok', false, 'error', 'Cette mission est réservée aux libéraux.');
      END IF;

      -- MIXTE + mission TOUS → choix explicite obligatoire (param ou préférence
      -- mémorisée). Sans choix → on renvoie choix_requis SANS rien enregistrer.
      IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Veuillez choisir votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD)'),
              jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
      END IF;

      -- Contrat final
      IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_contrat := 'SALARIE';
      ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_contrat := 'LIBERAL';
      ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_contrat := v_choix_effectif;
      ELSE v_choix_contrat := COALESCE(v_soignant.type_exercice, 'SALARIE');
      END IF;

      -- Candidature libérale → RCP valide obligatoire (sinon erreur, pas de swipe).
      IF v_choix_contrat = 'LIBERAL' THEN
        SELECT EXISTS(SELECT 1 FROM documents_soignants
          WHERE soignant_id = v_soignant_id AND type_document = 'RCP_ASSURANCE'
            AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
            AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_valide;
        IF NOT v_rcp_valide THEN
          RETURN jsonb_build_object('ok', false, 'error',
            'Assurance RCP manquante ou expirée — obligatoire pour candidater en libéral. Téléversez-la dans vos documents (ou choisissez salarié si la mission le permet).');
        END IF;
      END IF;
    END IF;
  END IF;

  -- Quota super-like (après validation du choix : un choix_requis ne consomme rien).
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

  -- LIKE/SUPER_LIKE → candidature EN_ATTENTE avec le contrat retenu plus haut.
  IF v_direction IN ('LIKE', 'SUPER_LIKE') AND v_choix_contrat IS NOT NULL THEN
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

  RETURN jsonb_build_object(
    'ok', true,
    'swipe_id', v_swipe_id,
    'direction', p_direction,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_choix_contrat,
    'quota_restant', CASE WHEN v_direction = 'SUPER_LIKE' THEN v_quota_max - v_quota_count ELSE NULL END
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_enregistrer_swipe(uuid, text, text) TO authenticated, service_role;
