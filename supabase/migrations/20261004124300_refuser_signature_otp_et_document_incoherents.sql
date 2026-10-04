-- Source : catalogue production lu le 2026-10-04, corps identique au snapshot main53.
-- Aucun UPDATE de document, de Storage ou de signature deja acquise.
DO $signature_preflight$
DECLARE routine pg_catalog.pg_proc;
BEGIN
  SELECT p.* INTO routine FROM pg_catalog.pg_proc p
  WHERE p.oid='public.fn_signer_contrat_otp(uuid,text,text,text)'::regprocedure;
  IF routine.oid IS NULL OR md5(routine.prosrc) <> '4a8b58cf68ee1a293d581d3bfd77d8fe'
     OR routine.proowner <> 'postgres'::regrole OR routine.prosecdef IS NOT TRUE
     OR routine.proconfig IS DISTINCT FROM ARRAY['search_path=public, extensions']::text[]
     OR routine.proacl::text IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='SIGNATURE_OTP_SOURCE_INATTENDUE';
  END IF;
END;
$signature_preflight$;

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_otp(p_contrat_id uuid, p_otp_code text, p_hash_document text DEFAULT NULL::text, p_signature_image text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_sig record;
  v_contrat record;
  v_expected_hash text;
  v_document_hash text;
  v_role text;
  v_ip inet;
  v_ua text;
  v_contrat_complet boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  SELECT cm.signature_soignant, cm.signature_etablissement, cm.statut,
         cm.contenu_html, cm.hash_document, cm.storage_path, cm.contenu_html_rendu_le
    INTO v_contrat
    FROM public.contrats_mission cm
   WHERE cm.id = p_contrat_id
   FOR UPDATE;
  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE', 'error', 'Contrat introuvable');
  END IF;
  IF v_contrat.statut IN ('ANNULE', 'EXPIRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INACTIF', 'error', 'Ce contrat ne peut plus être signé.');
  END IF;

  SELECT * INTO v_sig
    FROM public.signatures_contrats
   WHERE contrat_id = p_contrat_id AND signataire_user_id = v_uid
   ORDER BY cree_le DESC LIMIT 1
   FOR UPDATE;
  IF v_sig IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_NON_DEMANDE', 'error', 'Aucune demande OTP en cours. Cliquez d''abord sur "Recevoir un code SMS".');
  END IF;
  IF v_sig.statut_signature = 'signe' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_SIGNE', 'error', 'Vous avez déjà signé ce contrat.', 'signe_a', v_sig.signe_a);
  END IF;
  IF v_sig.otp_tentatives >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_TENTATIVES', 'error', 'Trop de tentatives. Renvoyez un nouveau code SMS.');
  END IF;
  IF v_sig.otp_envoye_a IS NULL OR v_sig.otp_envoye_a < now() - interval '10 minutes' THEN
    UPDATE public.signatures_contrats SET statut_signature = 'expire', modifie_le = now() WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_EXPIRE', 'error', 'Code expiré. Renvoyez un nouveau code SMS.');
  END IF;

  -- Une entree NULL ne doit jamais franchir la comparaison ternaire SQL.
  v_expected_hash := CASE WHEN (length(p_otp_code) = 6 AND p_otp_code ~ '^[0-9]{6}$') IS TRUE THEN
    encode(extensions.digest(p_otp_code || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex') END;
  IF v_expected_hash IS NULL OR v_expected_hash IS DISTINCT FROM v_sig.otp_code_hash THEN
    UPDATE public.signatures_contrats SET otp_tentatives = COALESCE(otp_tentatives, 0) + 1, modifie_le = now() WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_INCORRECT', 'error', 'Code incorrect.', 'tentatives_restantes', 5 - (COALESCE(v_sig.otp_tentatives, 0) + 1));
  END IF;

  -- Memes octets UTF-8 que le HTML original fige par l'Edge, sans rendu,
  -- normalisation ni reecriture du document ou d'une signature historique.
  v_document_hash := encode(extensions.digest(convert_to(v_contrat.contenu_html, 'UTF8'), 'sha256'), 'hex');
  IF (
    v_contrat.contenu_html IS NOT NULL AND btrim(v_contrat.contenu_html) <> ''
    AND v_contrat.contenu_html !~ '\{\{[[:space:]]*[^}]+[[:space:]]*\}\}'
    AND v_contrat.hash_document ~ '^[0-9a-f]{64}$'
    AND v_contrat.hash_document = v_document_hash
    AND p_hash_document = v_document_hash
    AND NULLIF(btrim(v_contrat.storage_path), '') IS NOT NULL
    AND v_contrat.contenu_html_rendu_le IS NOT NULL
  ) IS NOT TRUE OR EXISTS (
    SELECT 1 FROM public.signatures_contrats sc
    WHERE sc.contrat_id = p_contrat_id AND sc.statut_signature = 'signe'
      AND sc.hash_document IS DISTINCT FROM v_document_hash
  ) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'HASH_DOCUMENT_CHANGE',
      'error', 'Le document a change ou sa preuve est indisponible. Rechargez la page avant de signer.');
  END IF;

  v_role := v_sig.signataire_role;
  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_ua := current_setting('request.headers', true)::jsonb->>'user-agent';

  UPDATE public.signatures_contrats
     SET statut_signature = 'signe', otp_valide_a = now(), signe_a = now(),
         ip_signature = v_ip, user_agent = v_ua, hash_document = v_document_hash,
         signature_image_base64 = p_signature_image, modifie_le = now(),
         audit_trail = COALESCE(audit_trail, '{}'::jsonb)
           || jsonb_build_object('signe_le', now()::text, 'tentatives', v_sig.otp_tentatives + 1)
   WHERE id = v_sig.id;

  IF v_role = 'soignant' THEN
    UPDATE public.contrats_mission
       SET signature_soignant = true, signature_soignant_le = now(),
           signature_ip_soignant = COALESCE(v_ip, signature_ip_soignant),
           signature_navigateur_soignant = COALESCE(v_ua, signature_navigateur_soignant),
           signature_image_soignant = COALESCE(p_signature_image, signature_image_soignant),
           mode_signature = 'JOLENE_OTP',
           statut = CASE WHEN signature_etablissement IS TRUE THEN 'SIGNE_COMPLET' ELSE 'SIGNE_SOIGNANT' END,
           modifie_le = now()
     WHERE id = p_contrat_id;
  ELSIF v_role = 'etablissement' THEN
    UPDATE public.contrats_mission
       SET signature_etablissement = true, signature_etablissement_le = now(),
           signature_ip_etablissement = COALESCE(v_ip, signature_ip_etablissement),
           signature_navigateur_etablissement = COALESCE(v_ua, signature_navigateur_etablissement),
           signature_image_etablissement = COALESCE(p_signature_image, signature_image_etablissement),
           mode_signature = 'JOLENE_OTP',
           statut = CASE WHEN signature_soignant IS TRUE THEN 'SIGNE_COMPLET' ELSE 'SIGNE_ETABLISSEMENT' END,
           modifie_le = now()
     WHERE id = p_contrat_id;
  ELSE
    RAISE EXCEPTION 'Rôle de signature invalide' USING ERRCODE = '23514';
  END IF;

  SELECT signature_soignant IS TRUE AND signature_etablissement IS TRUE
    INTO v_contrat_complet
    FROM public.contrats_mission WHERE id = p_contrat_id;

  RETURN jsonb_build_object('success', true, 'role', v_role, 'contrat_complet', v_contrat_complet);
END;
$function$
;
ALTER FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) TO authenticated,service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT 'fn_signer_contrat_otp(uuid,text,text,text)','RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),
  'Signature OTP : code nonNULL a six chiffres, comparaison stricte et preuve HTML canonique coherente, historiques conserves.',now()
FROM pg_catalog.pg_proc p WHERE p.oid='public.fn_signer_contrat_otp(uuid,text,text,text)'::regprocedure
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,
  justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;

-- Un OTP court ne doit pas pouvoir etre recherche hors ligne a partir d'un
-- condensat lisible. Conserver les colonnes de preuve, les policies et le
-- service_role ; aucun UPDATE des lignes historiques.
REVOKE SELECT ON TABLE public.signatures_contrats FROM PUBLIC, anon, authenticated;
REVOKE SELECT (otp_code_hash) ON TABLE public.signatures_contrats FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, contrat_id, signataire_user_id, signataire_role, signe_a, ip_signature,
  user_agent, hash_document, otp_valide_a, psc_session_active, rpps_verifie,
  traits_identite_verifies, statut_signature, cree_le
) ON TABLE public.signatures_contrats TO authenticated;
DO $signature_acl$
BEGIN
  IF has_column_privilege('authenticated','public.signatures_contrats','otp_code_hash','SELECT')
     OR has_column_privilege('anon','public.signatures_contrats','otp_code_hash','SELECT')
     OR NOT has_column_privilege('service_role','public.signatures_contrats','otp_code_hash','SELECT') THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='SIGNATURE_OTP_ACL_INATTENDUE';
  END IF;
END;
$signature_acl$;
