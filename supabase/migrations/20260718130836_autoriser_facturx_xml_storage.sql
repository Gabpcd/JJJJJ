-- generate-invoice dépose un PDF et son XML CII Factur-X dans le même bucket.
-- Le bucket production refusait application/xml, ce qui faisait basculer toute
-- facture en ERREUR_GENERATION après la création correcte du PDF.
UPDATE storage.buckets
SET allowed_mime_types = ARRAY(
  SELECT DISTINCT mime
  FROM unnest(
    COALESCE(allowed_mime_types, ARRAY[]::text[])
      || ARRAY['application/xml', 'text/xml']::text[]
  ) AS mime
  ORDER BY mime
)
WHERE id = 'jolene-documents';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM storage.buckets b
    WHERE b.id = 'jolene-documents'
      AND 'application/pdf' = ANY(b.allowed_mime_types)
      AND 'application/xml' = ANY(b.allowed_mime_types)
  ) THEN
    RAISE EXCEPTION 'Bucket jolene-documents absent ou MIME Factur-X incomplets';
  END IF;
END;
$$;
