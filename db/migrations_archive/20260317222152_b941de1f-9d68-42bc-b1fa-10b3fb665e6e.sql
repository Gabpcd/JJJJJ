-- Copy storage RLS policies for jolene-documents bucket
CREATE POLICY "pol_storage_jolene_insert" ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'jolene-documents'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "pol_storage_jolene_select" ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'jolene-documents'
  AND (
    (storage.foldername(name))[1] = auth.uid()::text
    OR (auth.jwt() ->> 'role') = 'ADMIN_PLATEFORME'
  )
);

CREATE POLICY "pol_storage_jolene_delete" ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'jolene-documents'
  AND (auth.jwt() ->> 'role') = 'ADMIN_PLATEFORME'
);

-- Update default value for s3_bucket column
ALTER TABLE public.documents_soignants
  ALTER COLUMN s3_bucket SET DEFAULT 'jolene-documents';