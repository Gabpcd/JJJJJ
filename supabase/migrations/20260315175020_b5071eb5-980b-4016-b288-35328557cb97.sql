
DROP FUNCTION IF EXISTS public.fn_soignants_urgence(uuid);

CREATE OR REPLACE FUNCTION public.fn_soignants_urgence(p_mission_id uuid)
RETURNS TABLE(
  soignant_id uuid,
  prenom text,
  nom text,
  score_fiabilite integer,
  distance_km numeric,
  pool_urgence_rayon_km integer,
  telephone text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_mission record;
BEGIN
  SELECT m.*, e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
  INTO v_mission
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.id = p_mission_id;
  
  IF NOT FOUND THEN RETURN; END IF;
  
  RETURN QUERY
  SELECT 
    s.id,
    s.prenom,
    s.nom,
    s.score_fiabilite,
    CASE 
      WHEN s.adresse_lat IS NOT NULL AND v_mission.etab_lat IS NOT NULL THEN
        round((6371 * acos(
          cos(radians(v_mission.etab_lat)) * cos(radians(s.adresse_lat)) *
          cos(radians(s.adresse_lng) - radians(v_mission.etab_lng)) +
          sin(radians(v_mission.etab_lat)) * sin(radians(s.adresse_lat))
        ))::numeric, 1)
      ELSE NULL
    END AS distance_km,
    s.pool_urgence_rayon_km,
    s.telephone
  FROM soignants s
  WHERE s.pool_urgence_actif = true
    AND s.profession = v_mission.profession_requise
    AND s.id != COALESCE(v_mission.soignant_assigne_id, '00000000-0000-0000-0000-000000000000')
    AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
  ORDER BY s.score_fiabilite DESC
  LIMIT 20;
END;
$$;
