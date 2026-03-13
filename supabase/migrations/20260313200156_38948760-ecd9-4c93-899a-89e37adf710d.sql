DROP FUNCTION IF EXISTS public.fn_missions_publiques_etablissement(uuid);

CREATE OR REPLACE FUNCTION public.fn_missions_publiques_etablissement(p_etablissement_id uuid)
RETURNS TABLE(
  id uuid,
  intitule text,
  profession_requise public.type_profession,
  debut_le timestamptz,
  fin_le timestamptz,
  taux_horaire_base numeric,
  service text,
  nom_etablissement text,
  ville_etablissement text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 
    m.id,
    m.intitule,
    m.profession_requise,
    m.debut_le,
    m.fin_le,
    m.taux_horaire_base,
    m.service,
    e.nom,
    e.adresse_ville
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.etablissement_id = p_etablissement_id
    AND m.statut = 'OUVERTE'
    AND e.supprime_le IS NULL
  ORDER BY m.debut_le
  LIMIT 10;
$$;

GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_etablissement(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_etablissement(uuid) TO authenticated;