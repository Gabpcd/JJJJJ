-- Add UPDATE policy for storage upsert support (needed for contrat re-upload)
CREATE POLICY "pol_storage_jolene_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'jolene-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'jolene-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);