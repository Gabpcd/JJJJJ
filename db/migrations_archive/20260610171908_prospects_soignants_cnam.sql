-- Sourcing soignants : base nationale des libéraux conventionnés (Annuaire Santé
-- CNAM ps-infospratiques.csv, ~183 Mo) avec téléphone de cabinet. Codes profession
-- dérivés empiriquement (mode sample de l'edge import-annuaire-cnam) :
-- 18/19=DENTISTE, 39=IDE, 43=KINE, 45=MEDECIN (généralistes), 57=ORTHOPHONISTE,
-- 61=PEDICURE_PODOLOGUE, 62=PHARMACIEN, 71=SAGE_FEMME.
-- NOTE : déjà appliquée prod via MCP (version 20260610171908).
CREATE TABLE IF NOT EXISTS public.prospects_soignants (
  cle text PRIMARY KEY,
  nom text NOT NULL,
  prenom text,
  profession text NOT NULL,
  enseigne text,
  telephone text,
  email text,
  adresse text,
  code_postal text,
  ville text,
  departement text,
  favori boolean NOT NULL DEFAULT false,
  maj_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_prof_dep ON public.prospects_soignants (profession, departement);
ALTER TABLE public.prospects_soignants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_prospects_soignants ON public.prospects_soignants;
CREATE POLICY admin_all_prospects_soignants ON public.prospects_soignants
  FOR ALL USING (public.est_admin()) WITH CHECK (public.est_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.prospects_soignants TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects_soignants(
  p_profession text DEFAULT NULL, p_departement text DEFAULT NULL,
  p_q text DEFAULT NULL, p_favoris boolean DEFAULT false, p_page int DEFAULT 1)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE v_total bigint; v_res jsonb; v_page int := GREATEST(p_page, 1);
BEGIN
  IF NOT public.est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  SELECT count(*) INTO v_total FROM prospects_soignants p
   WHERE (p_profession IS NULL OR p.profession = p_profession)
     AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
     AND (NOT p_favoris OR p.favori)
     AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%');
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_res FROM (
    SELECT p.* FROM prospects_soignants p
     WHERE (p_profession IS NULL OR p.profession = p_profession)
       AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
       AND (NOT p_favoris OR p.favori)
       AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%')
     ORDER BY p.favori DESC, p.departement, p.ville, p.nom
     LIMIT 30 OFFSET (v_page - 1) * 30
  ) t;
  RETURN jsonb_build_object('total', v_total, 'page', v_page,
    'total_pages', CEIL(v_total / 30.0), 'resultats', v_res);
END;
$body$;
GRANT EXECUTE ON FUNCTION public.fn_admin_chercher_prospects_soignants(text, text, text, boolean, int) TO authenticated;
