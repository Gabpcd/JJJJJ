-- Sales / Sourcing — RPC pour lister les établissements DÉJÀ inscrits sur Jolene
-- (avec leurs coordonnées) côté admin, pour les contacter depuis l'onglet Sales.

CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements(p_recherche text DEFAULT NULL)
RETURNS TABLE (
  id uuid,
  nom text,
  type text,
  ville text,
  code_postal text,
  telephone text,
  email text,
  statut_verification text,
  peut_publier boolean,
  cree_le timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  RETURN QUERY
  SELECT e.id, e.nom, e.type, e.adresse_ville, e.adresse_code_postal,
         e.telephone_contact, e.email_contact, e.statut_verification,
         e.peut_publier_missions, e.cree_le
  FROM public.etablissements e
  WHERE e.supprime_le IS NULL
    AND (p_recherche IS NULL OR p_recherche = ''
         OR e.nom ILIKE '%' || p_recherche || '%'
         OR e.adresse_ville ILIKE '%' || p_recherche || '%')
  ORDER BY e.cree_le DESC
  LIMIT 500;
END;
$body$;
