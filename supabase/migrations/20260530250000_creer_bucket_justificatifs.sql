-- Bucket manquant : le front uploade des justificatifs (réclamations score +
-- annulations de candidature) vers 'justificatifs' qui n'existait pas → upload
-- échouait « Bucket not found ». Création + policies.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'justificatifs', 'justificatifs', false, 5242880,
  ARRAY['application/pdf', 'image/jpeg', 'image/png']
) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "justificatifs_insert_auth" ON storage.objects;
CREATE POLICY "justificatifs_insert_auth"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'justificatifs');

DROP POLICY IF EXISTS "justificatifs_select_auth" ON storage.objects;
CREATE POLICY "justificatifs_select_auth"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'justificatifs');

NOTIFY pgrst, 'reload schema';
