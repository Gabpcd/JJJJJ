-- Step 1: Create the new bucket (copy settings from old one)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
SELECT 'jolene-documents', 'jolene-documents', public, file_size_limit, allowed_mime_types
FROM storage.buckets WHERE id = 'soin-direct-documents'
ON CONFLICT (id) DO NOTHING;

-- Step 2: Move all objects to new bucket
UPDATE storage.objects SET bucket_id = 'jolene-documents' WHERE bucket_id = 'soin-direct-documents';

-- Step 3: Update public schema references
UPDATE public.documents_soignants SET s3_bucket = 'jolene-documents' WHERE s3_bucket = 'soin-direct-documents';