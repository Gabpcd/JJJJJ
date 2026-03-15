-- Allow admins and establishment owners to insert API keys
CREATE POLICY "pol_apikeys_insert" ON public.api_keys
FOR INSERT TO authenticated
WITH CHECK (est_admin() OR (etablissement_id = mon_etablissement_id()));

-- Allow admins to update API keys
CREATE POLICY "pol_apikeys_update" ON public.api_keys
FOR UPDATE TO authenticated
USING (est_admin() OR (etablissement_id = mon_etablissement_id()));

-- Allow admins to delete API keys
CREATE POLICY "pol_apikeys_delete" ON public.api_keys
FOR DELETE TO authenticated
USING (est_admin() OR (etablissement_id = mon_etablissement_id()));