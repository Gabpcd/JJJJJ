
-- Fix 1: Restreindre l'accès des établissements aux données soignants
-- Remplacer la policy SELECT permissive par une vue restreinte via RPC
-- Les établissements doivent passer par fn_soignant_pour_etablissement / fn_mes_soignants_etablissement
DROP POLICY IF EXISTS pol_soig_select ON public.soignants;
CREATE POLICY pol_soig_select ON public.soignants
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR est_admin()
  );

-- Fix 2: Restreindre templates_contrat aux admins plateforme
DROP POLICY IF EXISTS pol_templates_contrat_lecture ON public.templates_contrat;
CREATE POLICY pol_templates_contrat_lecture ON public.templates_contrat
  FOR SELECT TO authenticated
  USING (est_admin());
