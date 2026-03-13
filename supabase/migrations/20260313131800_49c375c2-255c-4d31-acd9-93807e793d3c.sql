-- Fix: Remove soignant from contrat INSERT policy — only admin and etablissement can create contracts
DROP POLICY IF EXISTS pol_contrat_insert ON public.contrats_mission;
CREATE POLICY pol_contrat_insert ON public.contrats_mission
FOR INSERT TO authenticated
WITH CHECK (
  est_admin()
  OR (
    est_admin_etablissement()
    AND etablissement_id = mon_etablissement_id()
  )
);