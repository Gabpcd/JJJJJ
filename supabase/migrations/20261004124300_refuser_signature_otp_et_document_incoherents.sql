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

  IF public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE', 'error', 'Non autorisé à signer ce contrat');
  END IF;

  SELECT cm.signature_soignant, cm.signature_etablissement, cm.statut, cm.soignant_id, cm.etablissement_id,
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
  IF (CASE v_sig.signataire_role
      WHEN 'soignant' THEN v_contrat.soignant_id = v_uid
      WHEN 'etablissement' THEN
        public.fn_role_etablissement_courant(v_contrat.etablissement_id) IS NOT NULL
        AND public.fn_a_permission_etablissement('contrats', v_contrat.etablissement_id) IS TRUE
      ELSE false END) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE', 'error', 'Non autorisé à signer ce contrat');
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
  'Signature OTP : compte et partie habilites, code strict, preuve HTML coherente et historiques conserves.',now()
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

-- Definition emission catalogue PROD/STAGING concordante au 2026-10-04 13:14 UTC.
DO $sender_preflight$
DECLARE routine pg_catalog.pg_proc;
BEGIN
  SELECT p.* INTO routine FROM pg_catalog.pg_proc p
  WHERE p.oid='public.fn_envoyer_otp_signature(uuid)'::regprocedure;
  IF routine.oid IS NULL OR md5(routine.prosrc) <> '8b36efa62f1b2247dd6a82223da12a8f'
     OR routine.proowner <> 'postgres'::regrole OR routine.prosecdef IS NOT TRUE
     OR routine.proconfig IS DISTINCT FROM ARRAY['search_path=public, extensions']::text[]
     OR routine.proacl::text IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='SIGNATURE_OTP_SENDER_SOURCE_INATTENDUE';
  END IF;
END;
$sender_preflight$;
CREATE OR REPLACE FUNCTION "public"."fn_envoyer_otp_signature"("p_contrat_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $_$
DECLARE
  v_uid uuid := auth.uid();
  v_contrat record;
  v_role text;
  v_otp text;
  v_otp_hash text;
  v_telephone text;
  v_sig_existante record;
  v_sms_count integer;
  v_sms_window_start timestamptz;
  v_ip inet;
  v_rate_check jsonb;
  v_idempotency_key text;
  v_supabase_url text;
  v_service_role_key text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  IF public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE', 'error', 'Non autorisé à signer ce contrat');
  END IF;

  SELECT cm.id, cm.soignant_id, cm.etablissement_id, cm.contenu_html,
         cm.statut, cm.signature_soignant, cm.signature_etablissement
    INTO v_contrat
    FROM public.contrats_mission cm
   WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE', 'error', 'Contrat introuvable');
  END IF;
  IF v_contrat.statut IN ('ANNULE', 'EXPIRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INACTIF', 'error', 'Ce contrat n''est plus actif (statut : ' || v_contrat.statut || ').');
  END IF;
  IF v_contrat.statut = 'SIGNE_COMPLET' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_DEJA_COMPLET', 'error', 'Ce contrat est déjà entièrement signé.');
  END IF;

  IF v_contrat.soignant_id = v_uid THEN
    v_role := 'soignant';
    SELECT telephone INTO v_telephone FROM public.soignants WHERE id = v_uid;
  ELSIF public.fn_role_etablissement_courant(v_contrat.etablissement_id) IS NOT NULL
     AND public.fn_a_permission_etablissement('contrats', v_contrat.etablissement_id) IS TRUE THEN
    v_role := 'etablissement';
    SELECT telephone_contact INTO v_telephone
      FROM public.etablissements WHERE id = v_contrat.etablissement_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE', 'error', 'Non autorisé à signer ce contrat');
  END IF;

  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_rate_check := public.fn_check_rate_limit_ip_signature(v_ip);
  IF NOT (v_rate_check->>'allowed')::boolean THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'TROP_DE_SMS_IP',
      'error', 'Trop de demandes de signature depuis votre IP. Réessayez dans 1h.',
      'envois_courant', v_rate_check->>'envois_courant', 'max', v_rate_check->>'max'
    );
  END IF;

  IF v_telephone IS NULL OR v_telephone = '' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TELEPHONE_MANQUANT', 'error', 'Numéro de téléphone manquant. Mettez à jour votre profil avant de signer.');
  END IF;

  -- Le bootstrap staging aligne ces deux valeurs sur son propre projet.
  -- Aucune URL de production de secours : une configuration absente ou
  -- étrangère à un projet Supabase refuse l'envoi avant de créer l'OTP.
  SELECT rtrim(ds.decrypted_secret, '/') INTO v_supabase_url
    FROM vault.decrypted_secrets ds WHERE ds.name = 'supabase_url' LIMIT 1;
  SELECT ds.decrypted_secret INTO v_service_role_key
    FROM vault.decrypted_secrets ds WHERE ds.name = 'service_role_key' LIMIT 1;
  IF v_supabase_url IS NULL
     OR v_supabase_url !~ '^https://[a-z0-9]{20}\.supabase\.co$'
     OR v_service_role_key IS NULL OR btrim(v_service_role_key) = '' THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'CONFIGURATION_SMS_INDISPONIBLE',
      'error', 'Envoi du code indisponible. Réessayez plus tard.'
    );
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_contrat_id::text || ':' || v_role, 618337)
  );

  SELECT sms_envoyes_count, sms_premier_envoi_a, statut_signature
    INTO v_sig_existante
    FROM public.signatures_contrats
   WHERE contrat_id = p_contrat_id AND signataire_role = v_role;

  IF FOUND THEN
    IF v_sig_existante.statut_signature = 'signe' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_SIGNE', 'error', 'Vous avez déjà signé ce contrat.');
    END IF;
    IF v_sig_existante.sms_premier_envoi_a IS NULL
       OR v_sig_existante.sms_premier_envoi_a < now() - interval '24 hours' THEN
      v_sms_count := 1;
      v_sms_window_start := now();
    ELSE
      v_sms_count := COALESCE(v_sig_existante.sms_envoyes_count, 0) + 1;
      v_sms_window_start := v_sig_existante.sms_premier_envoi_a;
      IF v_sms_count > 3 THEN
        RETURN jsonb_build_object(
          'success', false, 'error_code', 'TROP_DE_SMS',
          'error', 'Trop de SMS envoyés (3 max / 24h).',
          'sms_envoyes', v_sms_count - 1,
          'reset_le', (v_sig_existante.sms_premier_envoi_a + interval '24 hours')::text
        );
      END IF;
    END IF;
  ELSE
    v_sms_count := 1;
    v_sms_window_start := now();
  END IF;

  v_otp := lpad(floor(random() * 1000000)::text, 6, '0');
  v_otp_hash := encode(digest(v_otp || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');

  INSERT INTO public.signatures_contrats (
    contrat_id, signataire_user_id, signataire_role, otp_envoye_a,
    otp_code_hash, statut_signature, audit_trail, sms_envoyes_count,
    sms_premier_envoi_a
  ) VALUES (
    p_contrat_id, v_uid, v_role, now(), v_otp_hash, 'otp_envoye',
    jsonb_build_object('otp_envoye_le', now()::text, 'sms_count', v_sms_count, 'ip', v_ip::text),
    v_sms_count, v_sms_window_start
  )
  ON CONFLICT (contrat_id, signataire_role) DO UPDATE SET
    signataire_user_id = EXCLUDED.signataire_user_id,
    otp_envoye_a = now(),
    otp_code_hash = EXCLUDED.otp_code_hash,
    otp_tentatives = 0,
    statut_signature = 'otp_envoye',
    sms_envoyes_count = v_sms_count,
    sms_premier_envoi_a = v_sms_window_start,
    modifie_le = now(),
    audit_trail = COALESCE(signatures_contrats.audit_trail, '{}'::jsonb)
      || jsonb_build_object('otp_renvoye_le', now()::text, 'sms_count', v_sms_count, 'ip', v_ip::text);

  v_idempotency_key := 'otp-signature.' || p_contrat_id::text || '.'
    || v_uid::text || '.' || v_role || '.'
    || extract(epoch FROM v_sms_window_start)::bigint::text || '.' || v_sms_count::text;

  BEGIN
    PERFORM net.http_post(
      url := v_supabase_url || '/functions/v1/send-sms',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key
      ),
      body := jsonb_build_object(
        'telephone', v_telephone,
        'type', 'OTP_SIGNATURE',
        'contenu', 'Code de signature Jolene : ' || v_otp || ' (valide 10 min). Ne le partagez avec personne.',
        'destinataire_id', v_uid,
        'prefix_type', 'SIGNATURE',
        'idempotency_key', v_idempotency_key,
        'data', jsonb_build_object('contrat_id', p_contrat_id)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'telephone_masked', regexp_replace(v_telephone, '\d(?=\d{2})', '*', 'g'),
    'expire_dans_minutes', 10,
    'sms_envoyes', v_sms_count,
    'sms_restants', greatest(0, 3 - v_sms_count)
  );
END;
$_$;


ALTER FUNCTION "public"."fn_envoyer_otp_signature"("p_contrat_id" "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION public.fn_envoyer_otp_signature(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_signature(uuid) TO authenticated,service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT 'fn_envoyer_otp_signature(uuid)','RPC_UTILISATEUR_AUTH_INTERNE',md5(p.prosrc),
 'Demande OTP : compte actif, partie soignante ou rattachement et permission contrats actuels.',now()
FROM pg_catalog.pg_proc p WHERE p.oid='public.fn_envoyer_otp_signature(uuid)'::regprocedure
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,
 justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
