-- Fix : admin_securite et admin_2fa_codes avaient la RLS active SANS policy.
-- Le client service_role créé avec createClient(url, serviceKey) dans l'edge
-- function admin-2fa ne bypass PAS la RLS automatiquement → les SELECT
-- retournaient vide → le code 2FA partait à l'email de connexion
-- (admin@jolene.app) au lieu de l'email perso paramétré (admin_securite).
-- Policy "FOR ALL USING (true)" = toute opération autorisée (ces tables ne
-- sont jamais lues côté client, uniquement par l'edge function en service_role).

DROP POLICY IF EXISTS service_role_all_admin_securite ON public.admin_securite;
CREATE POLICY service_role_all_admin_securite ON public.admin_securite
  FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS service_role_all_admin_2fa_codes ON public.admin_2fa_codes;
CREATE POLICY service_role_all_admin_2fa_codes ON public.admin_2fa_codes
  FOR ALL USING (true) WITH CHECK (true);
