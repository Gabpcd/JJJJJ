-- Audit étab Fix #2 : signature contrat service stockage image
-- Ajouter colonne signature_s3_key + paramètre p_signature_s3_key à fn_signer_contrat_service
-- Le frontend uploadera la signature PNG dans le bucket jolene-documents
-- (path: etablissements/{id}/signatures/contrat-service-{timestamp}.png)
-- puis transmettra le path à la RPC qui le stocke en DB.

ALTER TABLE public.contrats_service_signatures
  ADD COLUMN IF NOT EXISTS signature_s3_key TEXT;

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_service(
  p_version TEXT,
  p_ip TEXT,
  p_user_agent TEXT,
  p_contenu_hash TEXT,
  p_signature_s3_key TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_existing uuid;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  SELECT id INTO v_existing FROM contrats_service_signatures
   WHERE etablissement_id = v_etab_id AND revoked_at IS NULL;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat déjà signé et actif');
  END IF;

  INSERT INTO contrats_service_signatures (etablissement_id, version, ip_address, user_agent, contenu_hash, signature_s3_key)
  VALUES (v_etab_id, p_version, p_ip, p_user_agent, p_contenu_hash, p_signature_s3_key);

  PERFORM set_config('app.internal_operation', 'true', true);
  UPDATE etablissements
  SET contrat_service_signe = true, contrat_service_signe_le = now()
  WHERE id = v_etab_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := 'ADMIN_ETABLISSEMENT',
    p_action := 'CONTRAT_SIGNE',
    p_type_ressource := 'etablissement',
    p_id_ressource := v_etab_id,
    p_details := jsonb_build_object(
      'type', 'contrat_service_jolene',
      'version', p_version,
      'has_signature_image', p_signature_s3_key IS NOT NULL
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_service(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
