-- Session E-2 : aperçu du marché AVANT l'effort documentaire (standard Uber
-- « Earn up to X €/week in your city »). Agrégat public léger appelé pendant
-- l'inscription (anon) et sur la page succès : nombre de missions ouvertes,
-- taux max/moyen, nombre d'établissements — optionnellement bornés à un rayon.
-- Aucune donnée personnelle retournée, agrégats uniquement.

CREATE OR REPLACE FUNCTION public.fn_apercu_marche_profession(
  p_profession text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_rayon_km integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_geo boolean := p_lat IS NOT NULL AND p_lng IS NOT NULL AND COALESCE(p_rayon_km, 0) > 0;
  v_nb_missions integer;
  v_taux_max numeric;
  v_taux_moyen numeric;
  v_nb_etabs integer;
BEGIN
  SELECT count(*)::integer, max(m.taux_horaire_base), round(avg(m.taux_horaire_base), 2)
  INTO v_nb_missions, v_taux_max, v_taux_moyen
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE'
    AND m.debut_le > now()
    AND e.supprime_le IS NULL
    AND (p_profession IS NULL OR btrim(p_profession) = '' OR m.profession_requise::text = btrim(p_profession))
    AND (
      NOT v_geo
      OR (e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
          AND public.fn_haversine_distance_m(e.adresse_lat, e.adresse_lng, p_lat::numeric, p_lng::numeric) <= p_rayon_km * 1000)
    );

  -- Preuve sociale de repli quand le marché est vide : établissements inscrits.
  SELECT count(*)::integer
  INTO v_nb_etabs
  FROM etablissements e
  WHERE e.supprime_le IS NULL
    AND (
      NOT v_geo
      OR (e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
          AND public.fn_haversine_distance_m(e.adresse_lat, e.adresse_lng, p_lat::numeric, p_lng::numeric) <= p_rayon_km * 1000)
    );

  RETURN jsonb_build_object(
    'nb_missions', COALESCE(v_nb_missions, 0),
    'taux_max', v_taux_max,
    'taux_moyen', v_taux_moyen,
    'nb_etablissements', COALESCE(v_nb_etabs, 0),
    'zone', CASE WHEN v_geo THEN 'rayon' ELSE 'national' END
  );
END;
$body$;

-- Appelée pendant l'inscription, AVANT toute session : anon nécessaire.
GRANT EXECUTE ON FUNCTION public.fn_apercu_marche_profession(text, double precision, double precision, integer) TO anon, authenticated;
