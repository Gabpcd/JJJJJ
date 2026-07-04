-- Validation manuelle d'un utilisateur par l'admin : quand un soignant ne peut
-- pas téléverser ses documents lui-même (envoi en privé à Jolene), l'admin les
-- téléverse pour lui et les valide. Storage : la policy INSERT n'autorisait que
-- son propre dossier — ajout du cas ADMIN_PLATEFORME.

DROP POLICY IF EXISTS pol_storage_jolene_insert ON storage.objects;
CREATE POLICY pol_storage_jolene_insert ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'jolene-documents'
  AND (
    (storage.foldername(name))[1] = (auth.uid())::text
    OR (auth.jwt() ->> 'role') = 'ADMIN_PLATEFORME'
  )
);

-- Insère un document au nom d'un soignant + validation immédiate optionnelle
-- (réutilise fn_admin_moderer_document pour le statut, l'audit et le recalcul
-- de tous_documents_valides).
CREATE OR REPLACE FUNCTION public.fn_admin_ajouter_document_soignant(
  p_soignant_id uuid,
  p_type_document text,
  p_cle text,
  p_nom_fichier text,
  p_type_mime text DEFAULT NULL,
  p_taille_octets bigint DEFAULT NULL,
  p_valider boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_doc_id uuid;
  v_resultat jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = p_soignant_id) THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  INSERT INTO documents_soignants (
    soignant_id, type_document, libelle, s3_bucket, s3_cle,
    nom_fichier, type_mime, taille_octets, statut_verification
  ) VALUES (
    p_soignant_id,
    p_type_document::type_document,
    'Ajouté par l''équipe Jolene (' || p_type_document || ')',
    'jolene-documents', p_cle,
    p_nom_fichier, p_type_mime, p_taille_octets, 'EN_ATTENTE'
  ) RETURNING id INTO v_doc_id;

  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (auth.uid(), 'ADMIN', 'MODERATION_DOCUMENT', 'document', v_doc_id,
    jsonb_build_object('action', 'AJOUT_ADMIN', 'type_document', p_type_document, 'soignant_id', p_soignant_id));

  IF p_valider THEN
    v_resultat := fn_admin_moderer_document(v_doc_id, 'VALIDER');
    IF v_resultat ? 'error' THEN RETURN v_resultat; END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'document_id', v_doc_id, 'valide', p_valider);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_admin_ajouter_document_soignant(uuid, text, text, text, text, bigint, boolean) TO authenticated;
