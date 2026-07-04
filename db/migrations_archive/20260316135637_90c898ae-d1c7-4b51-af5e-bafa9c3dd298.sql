
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
RETURNS TABLE(
  soignant_id uuid,
  prenom text,
  nom text,
  profession text,
  score_fiabilite integer,
  pool_urgence_rayon_km integer,
  distance_km numeric,
  missions_urgence_terminees bigint,
  en_mission_maintenant boolean,
  derniere_mission_chez_nous timestamp with time zone,
  bio text,
  avatar_url text,
  est_favori boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_etab record;
BEGIN
  SELECT e.adresse_lat, e.adresse_lng
  INTO v_etab
  FROM etablissements e
  WHERE e.id = p_etablissement_id;

  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT 
    s.id AS soignant_id,
    s.prenom,
    s.nom,
    s.profession::text,
    s.score_fiabilite,
    s.pool_urgence_rayon_km,
    CASE 
      WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
        round((6371 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(v_etab.adresse_lat)) * cos(radians(s.adresse_lat)) *
            cos(radians(s.adresse_lng) - radians(v_etab.adresse_lng)) +
            sin(radians(v_etab.adresse_lat)) * sin(radians(s.adresse_lat))
          ))
        ))::numeric, 1)
      ELSE NULL
    END AS distance_km,
    (SELECT count(*) FROM missions m WHERE m.soignant_assigne_id = s.id AND m.est_urgente = true AND m.statut = 'TERMINEE') AS missions_urgence_terminees,
    EXISTS(
      SELECT 1 FROM missions m 
      WHERE m.soignant_assigne_id = s.id 
      AND m.statut = 'EN_COURS' 
      AND now() BETWEEN m.debut_le AND m.fin_le
    ) AS en_mission_maintenant,
    (SELECT max(m2.fin_le) FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = p_etablissement_id AND m2.statut = 'TERMINEE') AS derniere_mission_chez_nous,
    s.bio,
    s.avatar_url,
    EXISTS(SELECT 1 FROM favoris f WHERE f.soignant_id = s.id AND f.etablissement_id = p_etablissement_id) AS est_favori
  FROM soignants s
  WHERE s.pool_urgence_actif = true
    AND NOT fn_est_exclu(s.id, p_etablissement_id)
  ORDER BY s.score_fiabilite DESC;
END;
$$;
