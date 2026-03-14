-- Remove permissive self-update policy; the trigger already blocks verification fields,
-- but belt-and-suspenders: replace with a SECURITY DEFINER RPC approach.
-- Drop the overly permissive policy entirely.
DROP POLICY IF EXISTS pol_doc_update_self ON public.documents_soignants;

-- Create a restricted self-update policy: soignants can only update file metadata columns
-- by ensuring verification fields remain unchanged (matching OLD values via subquery trick)
-- Since RLS can't compare OLD, we rely on the trigger. But we remove the blanket policy
-- and create one that blocks if verification fields are set to non-default values.
CREATE POLICY pol_doc_update_self ON public.documents_soignants
  FOR UPDATE TO authenticated
  USING (soignant_id = auth.uid())
  WITH CHECK (
    soignant_id = auth.uid()
    AND statut_verification IS NOT DISTINCT FROM 'EN_ATTENTE'::statut_verification
  );