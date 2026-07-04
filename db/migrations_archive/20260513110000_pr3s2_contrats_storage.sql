-- PR 3 Sprint 2 — Storage + hash pour génération contrat figé
--
-- Ajoute les colonnes nécessaires pour stocker l'HTML/PDF rendu final du
-- contrat avec son hash SHA-256 (preuve d'intégrité). Le rendu se fait
-- via l'edge function generate-contrat-mission-pdf.
--
-- Bucket Supabase Storage `contrats-signes` créé en parallèle (RLS :
-- accès lecture pour les parties + admin via policy storage.objects).
--
-- Approche MVP : stocke HTML rendu + hash. PDF binaire généré côté
-- frontend via jspdf au moment du téléchargement (le hash signé via
-- OTP couvre le HTML, et l'HTML => PDF est déterministe). PR Sprint 3+
-- pourra remplacer par Puppeteer headless si besoin de PDF natif côté
-- serveur.

-- 1. Colonnes contrats_mission
ALTER TABLE public.contrats_mission
  ADD COLUMN IF NOT EXISTS storage_path text,
  ADD COLUMN IF NOT EXISTS hash_document text,
  ADD COLUMN IF NOT EXISTS template_slug text,
  ADD COLUMN IF NOT EXISTS contenu_html_rendu_le timestamptz;

COMMENT ON COLUMN public.contrats_mission.storage_path IS
  'Chemin dans le bucket contrats-signes (ex: contrat_id/timestamp.html).';
COMMENT ON COLUMN public.contrats_mission.hash_document IS
  'SHA-256 hex du contenu HTML rendu et stocké. Lié à la signature OTP.';
COMMENT ON COLUMN public.contrats_mission.template_slug IS
  'Slug du template utilisé pour le rendu (ex: cdd, liberal-medecin-cabinet).';
COMMENT ON COLUMN public.contrats_mission.contenu_html_rendu_le IS
  'Date du dernier rendu HTML figé via generate-contrat-mission-pdf.';

CREATE INDEX IF NOT EXISTS idx_contrats_mission_storage_path
  ON public.contrats_mission(storage_path)
  WHERE storage_path IS NOT NULL;

-- 2. Création du bucket Storage (idempotent)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'contrats-signes', 'contrats-signes', false, 5242880,
  ARRAY['text/html', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['text/html', 'application/pdf'];

-- 3. RLS storage.objects : lecture pour les parties au contrat + admins
DROP POLICY IF EXISTS pol_contrats_signes_select ON storage.objects;
CREATE POLICY pol_contrats_signes_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'contrats-signes' AND (
      est_admin() OR EXISTS (
        SELECT 1 FROM public.contrats_mission cm
        WHERE cm.storage_path = storage.objects.name
          AND (cm.soignant_id = auth.uid()
               OR cm.etablissement_id = mon_etablissement_id())
      )
    )
  );

-- INSERT/UPDATE/DELETE bloqués (service_role bypass RLS pour writes via edge function)
DROP POLICY IF EXISTS pol_contrats_signes_insert_deny ON storage.objects;
CREATE POLICY pol_contrats_signes_insert_deny ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id != 'contrats-signes');

-- 4. RPC publique pour récupérer une URL signée vers le contrat
--    (le frontend appelle ça, l'edge function génère l'URL signée
--    avec service_role)
CREATE OR REPLACE FUNCTION public.fn_contrat_storage_path(p_contrat_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_cm RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT storage_path, hash_document, contenu_html_rendu_le,
         soignant_id, etablissement_id
  INTO v_cm
  FROM public.contrats_mission WHERE id = p_contrat_id;

  IF v_cm IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF NOT (est_admin()
          OR v_cm.soignant_id = v_uid
          OR v_cm.etablissement_id = mon_etablissement_id()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'storage_path', v_cm.storage_path,
    'hash_document', v_cm.hash_document,
    'rendu_le', v_cm.contenu_html_rendu_le
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_contrat_storage_path(uuid) TO authenticated;

-- 5. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'table', NULL,
  jsonb_build_object(
    'evenement', 'PR3_SPRINT2_CONTRATS_STORAGE_INSTALLED',
    'pr', 'PR 3 Sprint 2',
    'bucket', 'contrats-signes',
    'colonnes_ajoutees', ARRAY['storage_path', 'hash_document',
      'template_slug', 'contenu_html_rendu_le'],
    'edge_function', 'generate-contrat-mission-pdf (à déployer)'
  )
);
