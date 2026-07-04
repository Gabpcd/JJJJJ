-- Fix the security definer view warning by making it security invoker
CREATE OR REPLACE VIEW public.v_etablissements_soignant
WITH (security_barrier = true, security_invoker = true)
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