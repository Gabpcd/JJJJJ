-- Batch function: given an array of etablissement_ids, return safe columns
-- for establishments the caller has legitimate access to
CREATE OR REPLACE FUNCTION public.fn_etablissements_safe(p_ids uuid[])
RETURNS TABLE(
  id uuid,
  nom text,
  adresse_rue text,
  adresse_code_postal varchar,
  adresse_ville text,
  adresse_departement varchar,
  adresse_lat numeric,
  adresse_lng numeric,
  type public.type_etablissement,
  finess varchar,
  taux_majoration_nuit_pourcent numeric,
  taux_majoration_dimanche_pourcent numeric,
  taux_majoration_ferie_pourcent numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    e.id, e.nom, e.adresse_rue, e.adresse_code_postal,
    e.adresse_ville, e.adresse_departement, e.adresse_lat, e.adresse_lng,
    e.type, e.finess,
    e.taux_majoration_nuit_pourcent, e.taux_majoration_dimanche_pourcent,
    e.taux_majoration_ferie_pourcent
  FROM etablissements e
  WHERE e.id = ANY(p_ids)
    AND (
      -- Soignant assigned to a mission at this establishment
      EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.soignant_assigne_id = auth.uid())
      -- Open missions visible to all soignants
      OR EXISTS (SELECT 1 FROM missions m WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE')
      -- Establishment admin
      OR e.id = mon_etablissement_id()
      -- Platform admin
      OR est_admin()
    )
$$;