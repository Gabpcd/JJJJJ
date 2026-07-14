-- Les deux buckets sont déjà présents en production, mais leur création
-- historique n'était pas versionnée. Les déclarer rend le contrat front/back
-- reproductible et conserve une configuration privée et restrictive.

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'contrats-signes',
  'contrats-signes',
  false,
  5242880,
  ARRAY['text/html', 'application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'justificatifs',
  'justificatifs',
  false,
  10485760,
  ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Cette ancienne politique « deny » était en réalité permissive pour tous les
-- autres buckets, les politiques RLS PostgreSQL étant combinées avec OR.
-- Aucun INSERT client n'est nécessaire ici : la génération de contrat passe
-- exclusivement par l'Edge Function avec le service_role.
DROP POLICY IF EXISTS pol_contrats_signes_insert_deny ON storage.objects;

DROP POLICY IF EXISTS pol_contrats_signes_select ON storage.objects;
CREATE POLICY pol_contrats_signes_select
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'contrats-signes'
  AND (
    public.est_admin()
    OR EXISTS (
      SELECT 1
      FROM public.contrats_mission cm
      WHERE cm.storage_path = storage.objects.name
        AND (
          cm.soignant_id = (SELECT auth.uid())
          OR cm.etablissement_id = public.mon_etablissement_id()
        )
    )
  )
);
