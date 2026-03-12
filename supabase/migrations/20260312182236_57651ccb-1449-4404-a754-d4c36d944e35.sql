-- 1. Fix etablissements: replace overly permissive soignant SELECT policy
DROP POLICY IF EXISTS pol_etab_select ON public.etablissements;

-- Admins and own etablissement: full access
CREATE POLICY pol_etab_select_admin ON public.etablissements
  FOR SELECT TO authenticated
  USING (est_admin() OR (id = mon_etablissement_id()));

-- Soignants: only establishments where they have an assigned mission
CREATE POLICY pol_etab_select_soignant ON public.etablissements
  FOR SELECT TO authenticated
  USING (
    est_soignant() AND id IN (
      SELECT etablissement_id FROM missions
      WHERE soignant_assigne_id = auth.uid()
    )
  );

-- 2. Fix emails_envoyes: revoke INSERT for authenticated (only service_role can insert)
DROP POLICY IF EXISTS pol_email_insert ON public.emails_envoyes;