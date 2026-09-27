BEGIN;

-- Le schéma staging hérite des fonctions de production ; leur transport doit
-- suivre le Vault du projet au lieu de conserver une destination constante.
CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_signature(
  p_contrat_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
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

  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_rate_check := public.fn_check_rate_limit_ip_signature(v_ip);
  IF NOT (v_rate_check->>'allowed')::boolean THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'TROP_DE_SMS_IP',
      'error', 'Trop de demandes de signature depuis votre IP. Réessayez dans 1h.',
      'envois_courant', v_rate_check->>'envois_courant', 'max', v_rate_check->>'max'
    );
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
  ELSIF v_contrat.etablissement_id = v_uid
     OR public.mon_etablissement_id() = v_contrat.etablissement_id THEN
    v_role := 'etablissement';
    SELECT telephone_contact INTO v_telephone
      FROM public.etablissements WHERE id = v_contrat.etablissement_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE', 'error', 'Non autorisé à signer ce contrat');
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
$function$;

REVOKE ALL ON FUNCTION public.fn_envoyer_otp_signature(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_signature(uuid) TO authenticated, service_role;

-- Même surface authentifiée ; seule la destination dépend du projet courant.
UPDATE private.security_definer_inventory i
   SET definition_md5 = pg_catalog.md5(p.prosrc),
       justification = 'RPC authentifiée : règles OTP conservées ; routage SMS via le Vault du projet, sans repli production.',
       recense_le = now()
  FROM pg_catalog.pg_proc p
 WHERE p.oid = 'public.fn_envoyer_otp_signature(uuid)'::regprocedure
   AND i.signature = 'fn_envoyer_otp_signature(uuid)';

COMMIT;
