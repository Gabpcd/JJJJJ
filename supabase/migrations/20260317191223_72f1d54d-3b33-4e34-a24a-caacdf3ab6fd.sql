-- Allow soignants to update their own PROPOSEE candidatures (accept/refuse)
CREATE POLICY "pol_cand_update_soignant"
ON public.candidatures
FOR UPDATE
TO authenticated
USING (
  soignant_id = auth.uid()
  AND statut = 'PROPOSEE'
)
WITH CHECK (
  soignant_id = auth.uid()
  AND statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE')
);

-- Allow admins to update any candidature
CREATE POLICY "pol_cand_update_admin"
ON public.candidatures
FOR UPDATE
TO authenticated
USING (est_admin())
WITH CHECK (est_admin());