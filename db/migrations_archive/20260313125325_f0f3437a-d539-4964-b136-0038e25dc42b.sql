-- Fix 1: Drop the base table soignant SELECT policy (sensitive columns exposed)
DROP POLICY IF EXISTS pol_etab_select_soignant ON public.etablissements;

-- Fix 2: Recreate the view as security invoker (already done) and add RLS
-- The view already has security_invoker = true, but we need RLS on it.
-- PostgreSQL views don't support RLS directly, but security_invoker views
-- inherit the RLS of the underlying table. Since we dropped pol_etab_select_soignant,
-- soignants can no longer access the base table, so we need a different approach.
-- 
-- Solution: Make the view security_definer (owner = postgres who bypasses RLS)
-- but add its OWN row filter in the WHERE clause to restrict access.
DROP VIEW IF EXISTS public.v_etablissements_soignant;

-- Create a security definer function that returns safe establishment data
-- only for establishments linked to the calling soignant via missions
CREATE OR REPLACE FUNCTION public.fn_mes_etablissements_soignant()
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
    e.id,
    e.nom,
    e.adresse_rue,
    e.adresse_code_postal,
    e.adresse_ville,
    e.adresse_departement,
    e.adresse_lat,
    e.adresse_lng,
    e.type,
    e.finess,
    e.taux_majoration_nuit_pourcent,
    e.taux_majoration_dimanche_pourcent,
    e.taux_majoration_ferie_pourcent
  FROM etablissements e
  INNER JOIN missions m ON m.etablissement_id = e.id
  WHERE m.soignant_assigne_id = auth.uid()
$$;

-- Fix 3: Restrict soignant INSERT on soignants table
DROP POLICY IF EXISTS pol_soig_insert ON public.soignants;
CREATE POLICY pol_soig_insert ON public.soignants
FOR INSERT TO authenticated
WITH CHECK (
  id = auth.uid()
  AND rpps_verifie IS NOT TRUE
  AND diplome_verifie IS NOT TRUE
  AND identite_verifiee IS NOT TRUE
  AND tous_documents_valides IS NOT TRUE
  AND score_fiabilite IS NULL
  AND total_missions_terminees IS NULL
  AND heures_cumulees IS NULL
  AND heures_plateforme IS NULL
  AND eligible_conversion_3200h IS NOT TRUE
  AND statut_verification_aria IS NULL
);