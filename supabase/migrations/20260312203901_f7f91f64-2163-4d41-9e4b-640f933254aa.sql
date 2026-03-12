-- Fix: restrict audit INSERT to authenticated users only (was TO public)
DROP POLICY IF EXISTS "pol_insert_audit" ON public.journaux_audit;
CREATE POLICY "pol_insert_audit" ON public.journaux_audit
FOR INSERT TO authenticated
WITH CHECK (acteur_id = auth.uid());