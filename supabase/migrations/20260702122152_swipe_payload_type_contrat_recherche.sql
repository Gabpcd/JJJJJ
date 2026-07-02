-- 6c.2 (Lot 6c) — Carte swipe rééquilibrée : le type de contrat recherché
-- (salarié / libéral / les deux) s'affiche au centre de la carte. Ajout du
-- champ au payload de fn_obtenir_missions_swipe (type_contrat_applique est
-- NULL sur une mission OUVERTE — c'est type_contrat_recherche qui informe).
-- + nb_creneaux pour le pattern multi-jours (« 20 jours · 8 h/j »).
CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
      'etablissement_code_postal', e.adresse_code_postal, 'etablissement_logo_url', e.logo_url,
      'etablissement_score', e.score_qualite, 'taux_horaire_base', m.taux_horaire_base, 'duree_heures', m.duree_heures,
      'debut_le', m.debut_le, 'fin_le', m.fin_le, 'est_urgente', m.est_urgente, 'service', m.service,
      'type_contrat_applique', m.type_contrat_applique, 'type_contrat_recherche', m.type_contrat_recherche,
      'nb_creneaux', m.nb_creneaux, 'total_brut', m.total_brut, 'net_a_payer', m.net_a_payer,
      'net_estime', m.net_estime, 'montant_ifm', COALESCE(m.montant_ifm, 0), 'montant_icp', COALESCE(m.montant_icp, 0),
      'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0), 'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
      'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0), 'score', COALESCE(ms.score_global, 0),
      'breakdown', COALESCE(ms.breakdown, '{}'::jsonb),
      'distance_km', CASE
        WHEN v_sg.adresse_lat IS NOT NULL AND v_sg.adresse_lng IS NOT NULL
         AND e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
        THEN ROUND((fn_haversine_distance_m(v_sg.adresse_lat, v_sg.adresse_lng, e.adresse_lat, e.adresse_lng) / 1000.0)::numeric, 1)
        ELSE NULL END
    ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_soignant_id
     WHERE m.statut = 'OUVERTE'
       AND (m.intitule NOT LIKE '[%' OR v_sg.email LIKE 'playwright-%')
       AND fn_soignant_compatible_mission(
             v_sg.profession, v_sg.specialite_medicale,
             m.profession_requise, m.specialite_medicale_requise, m.accepte_non_specialises)
       AND (m.type_contrat_recherche = 'TOUS' OR v_sg.type_exercice IS NULL OR v_sg.type_exercice = 'MIXTE'
            OR (m.type_contrat_recherche = 'SALARIE' AND v_sg.type_exercice IN ('SALARIE', 'MIXTE'))
            OR (m.type_contrat_recherche = 'LIBERAL' AND v_sg.type_exercice IN ('LIBERAL', 'MIXTE')))
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
