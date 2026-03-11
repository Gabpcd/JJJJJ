-- RLS policies for soignant INSERT and UPDATE on presences
CREATE POLICY pol_insert_presence ON presences
    FOR INSERT WITH CHECK (soignant_id = auth.uid());

CREATE POLICY pol_update_presence ON presences
    FOR UPDATE USING (
      soignant_id = auth.uid()
      OR (auth.jwt() ->> 'role' IN ('ADMIN_PLATEFORME', 'ADMIN_ETABLISSEMENT'))
    );