-- Version candidate avant correction des verrous, uniquement témoin PG17 éphémère.
CREATE OR REPLACE FUNCTION public.fn_terminer_generation_honoraires(p_facture_id uuid,p_token uuid,p_documents jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $terminer$
DECLARE v_f public.factures_honoraires%ROWTYPE; v_b private.generations_factures_honoraires%ROWTYPE;
  v_resultat jsonb; v_prefixe text; v_pdf text; v_xml text; v_uuid_regex constant text:='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
BEGIN
  IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' THEN
    RAISE EXCEPTION 'Réservé au service de facturation' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_f FROM public.factures_honoraires WHERE id=p_facture_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'FACTURE_GENERATION_INTROUVABLE'; END IF;
  SELECT * INTO v_b FROM private.generations_factures_honoraires WHERE facture_id=p_facture_id FOR UPDATE;
  IF NOT FOUND OR p_token IS NULL OR v_b.token IS DISTINCT FROM p_token THEN
    RAISE EXCEPTION 'FACTURE_GENERATION_TOKEN_PERIME' USING ERRCODE='23514'; END IF;
  IF v_b.resultat IS NOT NULL THEN
    IF p_documents IS NOT NULL AND p_documents IS DISTINCT FROM v_b.documents THEN
      RAISE EXCEPTION 'FACTURE_GENERATION_REJEU_DIFFERENT' USING ERRCODE='23514'; END IF;
    RETURN v_b.resultat;
  END IF;
  -- Un succès acquis reste rejouable ; un renderer expiré ne peut plus écrire.
  IF v_b.expire_le<=clock_timestamp() THEN
    RAISE EXCEPTION 'FACTURE_GENERATION_BAIL_EXPIRE' USING ERRCODE='23514'; END IF;
  IF v_f.statut IS DISTINCT FROM 'EN_GENERATION' THEN RAISE EXCEPTION 'FACTURE_GENERATION_ETAT_INVALIDE' USING ERRCODE='23514'; END IF;
  IF p_documents IS NULL THEN
    UPDATE public.factures_honoraires SET statut='ERREUR_GENERATION' WHERE id=p_facture_id;
    UPDATE private.generations_factures_honoraires SET expire_le=clock_timestamp() WHERE facture_id=p_facture_id;
    RETURN jsonb_build_object('success',false,'statut','ERREUR_GENERATION','facture_id',p_facture_id);
  END IF;
  v_prefixe:=(CASE WHEN v_f.type_document='AVOIR' THEN 'avoirs/' ELSE 'invoices/' END)||v_f.soignant_id::text||'/'||v_f.numero_facture||'/';
  v_pdf:=p_documents->>'pdf_s3_key'; v_xml:=p_documents->>'facturx_xml_url';
  IF jsonb_typeof(p_documents) IS DISTINCT FROM 'object'
    OR (SELECT count(*) FROM jsonb_object_keys(p_documents))<>4
    OR v_pdf IS NULL OR v_xml IS NULL
    OR left(v_pdf,length(v_prefixe))<>v_prefixe OR left(v_xml,length(v_prefixe))<>v_prefixe
    OR substring(v_pdf from length(v_prefixe)+1) !~ ('^'||v_uuid_regex||'\.pdf$')
    OR substring(v_xml from length(v_prefixe)+1) !~ ('^'||v_uuid_regex||'\.xml$')
    OR COALESCE(p_documents->>'pdf_sha256','') !~ '^[a-f0-9]{64}$'
    OR COALESCE(p_documents->>'xml_sha256','') !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'FACTURE_GENERATION_DOCUMENTS_INVALIDES' USING ERRCODE='23514'; END IF;
  INSERT INTO public.factures_honoraires_documents(facture_honoraire_id,pdf_s3_key,facturx_xml_url,pdf_sha256,xml_sha256,motif_generation)
    VALUES(p_facture_id,v_pdf,v_xml,p_documents->>'pdf_sha256',p_documents->>'xml_sha256',
      CASE WHEN v_f.nature_correction='ORIGINALE' THEN 'EMISSION_INITIALE' ELSE 'EMISSION_DOCUMENT_CORRECTION' END);
  IF v_f.type_document='AVOIR' THEN
    UPDATE public.factures_honoraires cible
      SET chorus_avoir_reference_invoice=origine.numero_facture
      FROM public.factures_honoraires origine
      WHERE cible.id=p_facture_id AND origine.id=v_f.facture_precedente_id
        AND origine.mission_id=v_f.mission_id AND origine.soignant_id=v_f.soignant_id
        AND origine.etablissement_id=v_f.etablissement_id AND origine.type_document='FACTURE';
    IF NOT FOUND THEN RAISE EXCEPTION 'FACTURE_GENERATION_REFERENCE_INVALIDE' USING ERRCODE='23514'; END IF;
  END IF;
  v_resultat:=public.fn_emettre_document_facturation_honoraires(p_facture_id,v_pdf,v_xml);
  IF (v_resultat->>'success')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'FACTURE_GENERATION_EMISSION_REFUSEE'; END IF;
  UPDATE private.generations_factures_honoraires SET resultat=v_resultat,documents=p_documents WHERE facture_id=p_facture_id;
  RETURN v_resultat;
END;
$terminer$;
