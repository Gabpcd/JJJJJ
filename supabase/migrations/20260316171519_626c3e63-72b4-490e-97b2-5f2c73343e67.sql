
-- Public search RPC for landing page (accessible by anon)
CREATE OR REPLACE FUNCTION public.fn_missions_publiques_recherche(
  p_profession text DEFAULT NULL,
  p_ville text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  intitule text,
  profession_requise text,
  ville text,
  code_postal text,
  debut_le timestamptz,
  fin_le timestamptz,
  taux_horaire_base numeric,
  est_urgente boolean,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT
      m.id,
      m.intitule,
      m.profession_requise::text,
      e.adresse_ville AS ville,
      e.adresse_code_postal AS code_postal,
      m.debut_le,
      m.fin_le,
      m.taux_horaire_base,
      m.est_urgente
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND e.supprime_le IS NULL
      AND (p_profession IS NULL OR p_profession = '' OR m.profession_requise::text = p_profession)
      AND (p_ville IS NULL OR p_ville = '' OR e.adresse_ville ILIKE '%' || p_ville || '%' OR e.adresse_code_postal LIKE p_ville || '%')
    ORDER BY m.debut_le ASC
  ),
  counted AS (
    SELECT count(*) AS cnt FROM filtered
  )
  SELECT
    f.id,
    f.intitule,
    f.profession_requise,
    f.ville,
    f.code_postal,
    f.debut_le,
    f.fin_le,
    f.taux_horaire_base,
    f.est_urgente,
    c.cnt AS total_count
  FROM filtered f
  CROSS JOIN counted c
  LIMIT 5;
$$;

-- Grant execute to anon so unauthenticated visitors can search
GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_recherche(text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_recherche(text, text) TO authenticated;
