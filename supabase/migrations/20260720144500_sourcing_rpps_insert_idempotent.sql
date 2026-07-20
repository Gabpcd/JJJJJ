-- L'extraction RPPS contient plusieurs millions de lieux d'exercice. Une
-- resynchronisation ne doit pas réécrire les lignes inchangées : la table
-- historique possède notamment trois index GIN de recherche, et leur mise à
-- jour inutile peut dépasser le statement_timeout de production.
--
-- Le vivier reste cumulatif : seules les nouvelles clés officielles sont
-- ajoutées. La fraîcheur globale de la source est tracée dans sourcing_imports.
CREATE OR REPLACE FUNCTION public.fn_sourcing_upsert_soignants(p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_count integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.prospects_soignants (
    cle, nom, prenom, profession, enseigne, telephone, email, adresse,
    code_postal, ville, departement, est_etudiant, numero_rpps,
    mode_exercice, finess_structure, siret_structure, source_code,
    source_url, source_maj_le, importe_le, dernier_controle_le
  )
  SELECT r.cle, r.nom, r.prenom, r.profession, r.enseigne, r.telephone,
         r.email, r.adresse, r.code_postal, r.ville, r.departement,
         COALESCE(r.est_etudiant, false), r.numero_rpps, r.mode_exercice,
         r.finess_structure, r.siret_structure, r.source_code, r.source_url,
         r.source_maj_le, now(), now()
  FROM jsonb_to_recordset(COALESCE(p_rows, '[]'::jsonb)) AS r(
    cle text, nom text, prenom text, profession text, enseigne text,
    telephone text, email text, adresse text, code_postal text, ville text,
    departement text, est_etudiant boolean, numero_rpps text, mode_exercice text,
    finess_structure text, siret_structure text, source_code text,
    source_url text, source_maj_le timestamptz
  )
  WHERE r.cle IS NOT NULL AND r.nom IS NOT NULL AND r.profession IS NOT NULL
  ON CONFLICT (cle) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_sourcing_upsert_soignants(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sourcing_upsert_soignants(jsonb)
  TO service_role;

COMMENT ON FUNCTION public.fn_sourcing_upsert_soignants(jsonb) IS
  'Ajoute idempotemment les nouvelles cles Annuaire Sante/RPPS sans reecrire les prospects deja indexes.';
