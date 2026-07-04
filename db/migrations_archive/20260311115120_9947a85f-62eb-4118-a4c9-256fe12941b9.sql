-- Add INSERT policy for missions (etablissements can create missions)
CREATE POLICY "pol_insert_mission" ON public.missions
FOR INSERT TO public
WITH CHECK (
  etablissement_id = auth.uid()
  OR (auth.jwt() ->> 'role' = 'ADMIN_PLATEFORME')
);

-- Add UPDATE policy for missions (etablissements can update their own missions)
CREATE POLICY "pol_update_mission" ON public.missions
FOR UPDATE TO public
USING (
  etablissement_id = auth.uid()
  OR (auth.jwt() ->> 'role' = 'ADMIN_PLATEFORME')
)
WITH CHECK (
  etablissement_id = auth.uid()
  OR (auth.jwt() ->> 'role' = 'ADMIN_PLATEFORME')
);

-- Add INSERT policy for journaux_audit (allow authenticated users to insert via RPC)
CREATE POLICY "pol_insert_audit" ON public.journaux_audit
FOR INSERT TO public
WITH CHECK (true);