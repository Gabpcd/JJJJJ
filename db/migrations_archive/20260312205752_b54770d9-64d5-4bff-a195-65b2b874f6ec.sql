DROP FUNCTION IF EXISTS public.fn_etablissement_public(uuid);

CREATE OR REPLACE FUNCTION public.fn_etablissement_public(p_etablissement_id uuid)
RETURNS TABLE(
  id uuid,
  nom text,
  type public.type_etablissement,
  adresse_rue text,
  adresse_ville text,
  adresse_code_postal varchar,
  adresse_departement varchar,
  adresse_lat numeric,
  adresse_lng numeric,
  telephone_contact varchar,
  email_contact text,
  finess varchar
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    e.id, e.nom, e.type,
    e.adresse_rue, e.adresse_ville, e.adresse_code_postal,
    e.adresse_departement, e.adresse_lat, e.adresse_lng,
    e.telephone_contact, e.email_contact, e.finess
  FROM public.etablissements e
  WHERE e.id = p_etablissement_id
    AND e.supprime_le IS NULL;
$$;