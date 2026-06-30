-- Swipe : FILTRE DUR PROFESSION manquant.
--
-- fn_obtenir_missions_swipe (version Codex) renvoyait TOUTES les missions OUVERTE,
-- sans filtrer par profession. Conséquence : une IDE voyait des missions de médecin,
-- pharmacien… dans son deck de swipe. Si elle swipait à droite, AUCUNE candidature
-- n'était créée (fn_enregistrer_swipe vérifie déjà fn_soignant_compatible_mission) →
-- pas de faille (impossible de postuler hors profession) mais UX cassée : on swipe
-- dans le vide. On applique le MÊME filtre de compatibilité au deck pour ne montrer
-- que les missions réellement exerçables. L'algorithme de matching (distance, tarif,
-- score établissement, urgence, fiabilité) continue de gérer l'ORDRE via score_global.
-- Déjà appliqué en prod via MCP.

CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
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
       AND fn_soignant_compatible_mission(
             v_sg.profession, v_sg.specialite_medicale,
             m.profession_requise, m.specialite_medicale_requise, m.accepte_non_specialises)
       AND m.id NOT IN (SELECT s.mission_id FROM public.swipes s WHERE s.soignant_id = v_soignant_id)
     ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
     LIMIT p_limit
  ) t;
  RETURN jsonb_build_object('missions', v_missions);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_missions_swipe(integer) TO authenticated, service_role;
