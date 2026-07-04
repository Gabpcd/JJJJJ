-- Fix 1: Drop soignant direct UPDATE on presences (they use RPCs: fn_pointer_depart etc.)
DROP POLICY IF EXISTS pol_pres_update_soignant ON public.presences;

-- Fix 2: Replace eval SELECT to enforce visible flag
DROP POLICY IF EXISTS pol_eval_select ON public.evaluations;
CREATE POLICY pol_eval_select ON public.evaluations
FOR SELECT TO authenticated
USING (
  est_admin()
  OR evaluateur_id = auth.uid()
  OR (evalue_id = auth.uid() AND visible = true)
);

-- Fix 3: Replace broad soignant SELECT on etablissements with restricted view
-- Drop the old broad policy
DROP POLICY IF EXISTS pol_etab_select_soignant ON public.etablissements;

-- Create a restricted view for soignants (safe columns only, no stripe/commission/chorus)
CREATE OR REPLACE VIEW public.v_etablissements_soignant
WITH (security_barrier = true)
AS
SELECT
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
FROM public.etablissements e;

GRANT SELECT ON public.v_etablissements_soignant TO authenticated;

-- Re-create soignant policy on etablissements for FK joins (row-level only)
-- React code is updated to never select sensitive columns
CREATE POLICY pol_etab_select_soignant ON public.etablissements
FOR SELECT TO authenticated
USING (
  est_soignant() AND id IN (
    SELECT missions.etablissement_id FROM missions
    WHERE missions.soignant_assigne_id = auth.uid()
  )
);