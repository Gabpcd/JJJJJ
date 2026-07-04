-- PR 9 Sprint 3 — Intégration rate-limit IP dans fn_envoyer_otp_signature
--
-- PR 7 S3 a créé fn_check_rate_limit_ip_signature mais n'a pas câblé son
-- appel dans fn_envoyer_otp_signature pour minimiser le diff.
-- Cette migration finalise l'intégration : le check IP est désormais
-- effectué AVANT toute génération d'OTP.
--
-- Comportement :
--   1. Si IP non capturable (NULL) : bypass (cron / appels internes)
--   2. Si IP capturée + < 5 envois / h : OK, incrémente compteur, continue
--   3. Si IP capturée + >= 5 envois / h : refus error_code=TROP_DE_SMS_IP

CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_signature(p_contrat_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_contrat RECORD;
  v_role text;
  v_otp text;
  v_otp_hash text;
  v_telephone text;
  v_sig_existante RECORD;
  v_sms_count int;
  v_sms_window_start timestamptz;
  v_ip inet;
  v_rate_check jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  -- Capturer IP source pour rate-limit (PR 7 + PR 9 Sprint 3)
  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_rate_check := public.fn_check_rate_limit_ip_signature(v_ip);
  IF NOT (v_rate_check->>'allowed')::boolean THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TROP_DE_SMS_IP',
      'error', 'Trop de demandes de signature depuis votre IP. Réessayez dans 1h.',
      'envois_courant', v_rate_check->>'envois_courant',
      'max', v_rate_check->>'max'
    );
  END IF;

  SELECT cm.id, cm.soignant_id, cm.etablissement_id, cm.contenu_html, cm.statut,
         cm.signature_soignant, cm.signature_etablissement
  INTO v_contrat
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE', 'error', 'Contrat introuvable');
  END IF;

  IF v_contrat.statut IN ('ANNULE', 'EXPIRE') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INACTIF',
      'error', 'Ce contrat n''est plus actif (statut : ' || v_contrat.statut || ').');
  END IF;

  IF v_contrat.statut = 'SIGNE_COMPLET' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_DEJA_COMPLET',
      'error', 'Ce contrat est déjà entièrement signé.');
  END IF;

  IF v_contrat.soignant_id = v_uid THEN
    v_role := 'soignant';
    SELECT telephone INTO v_telephone FROM public.soignants WHERE id = v_uid;
  ELSIF v_contrat.etablissement_id = v_uid OR mon_etablissement_id() = v_contrat.etablissement_id THEN
    v_role := 'etablissement';
    SELECT telephone_contact INTO v_telephone FROM public.etablissements WHERE id = v_contrat.etablissement_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE',
      'error', 'Non autorisé à signer ce contrat');
  END IF;

  IF v_role = 'etablissement' AND v_contrat.signature_soignant IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ETAB_AVANT_SOIGNANT',
      'error', 'Le soignant doit signer en premier. Vous serez notifié(e) par email dès qu''il aura signé.');
  END IF;

  IF v_telephone IS NULL OR v_telephone = '' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TELEPHONE_MANQUANT',
      'error', 'Numéro de téléphone manquant. Mettez à jour votre profil avant de signer.');
  END IF;

  SELECT sms_envoyes_count, sms_premier_envoi_a, statut_signature
  INTO v_sig_existante
  FROM public.signatures_contrats
  WHERE contrat_id = p_contrat_id AND signataire_role = v_role;

  IF FOUND THEN
    IF v_sig_existante.statut_signature = 'signe' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_SIGNE',
        'error', 'Vous avez déjà signé ce contrat.');
    END IF;

    IF v_sig_existante.sms_premier_envoi_a IS NULL
       OR v_sig_existante.sms_premier_envoi_a < NOW() - INTERVAL '24 hours' THEN
      v_sms_count := 1;
      v_sms_window_start := NOW();
    ELSE
      v_sms_count := COALESCE(v_sig_existante.sms_envoyes_count, 0) + 1;
      v_sms_window_start := v_sig_existante.sms_premier_envoi_a;
      IF v_sms_count > 3 THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_SMS',
          'error', 'Trop de SMS envoyés (3 max / 24h).',
          'sms_envoyes', v_sms_count - 1,
          'reset_le', (v_sig_existante.sms_premier_envoi_a + INTERVAL '24 hours')::text);
      END IF;
    END IF;
  ELSE
    v_sms_count := 1;
    v_sms_window_start := NOW();
  END IF;

  v_otp := lpad(floor(random() * 1000000)::text, 6, '0');
  v_otp_hash := encode(digest(v_otp || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');

  INSERT INTO public.signatures_contrats (
    contrat_id, signataire_user_id, signataire_role,
    otp_envoye_a, otp_code_hash, statut_signature, audit_trail,
    sms_envoyes_count, sms_premier_envoi_a
  ) VALUES (
    p_contrat_id, v_uid, v_role,
    NOW(), v_otp_hash, 'otp_envoye',
    jsonb_build_object('otp_envoye_le', NOW()::text, 'sms_count', v_sms_count,
      'ip', v_ip::text),
    v_sms_count, v_sms_window_start
  )
  ON CONFLICT (contrat_id, signataire_role) DO UPDATE SET
    otp_envoye_a = NOW(),
    otp_code_hash = EXCLUDED.otp_code_hash,
    otp_tentatives = 0,
    statut_signature = 'otp_envoye',
    sms_envoyes_count = v_sms_count,
    sms_premier_envoi_a = v_sms_window_start,
    modifie_le = NOW(),
    audit_trail = COALESCE(signatures_contrats.audit_trail, '{}'::jsonb)
      || jsonb_build_object('otp_renvoye_le', NOW()::text, 'sms_count', v_sms_count,
                            'ip', v_ip::text);

  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-sms',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
      ),
      body := jsonb_build_object(
        'telephone', v_telephone,
        'type', 'OTP_SIGNATURE',
        'contenu', 'Code de signature Jolene : ' || v_otp || ' (valide 10 min). Ne le partagez avec personne.',
        'destinataire_id', v_uid,
        'prefix_type', 'SIGNATURE'
      )
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'telephone_masked', regexp_replace(v_telephone, '\d(?=\d{2})', '*', 'g'),
    'expire_dans_minutes', 10,
    'sms_envoyes', v_sms_count,
    'sms_restants', GREATEST(0, 3 - v_sms_count)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_signature(uuid) TO authenticated;

-- Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT3_PR9_RATE_LIMIT_IP_INTEGRE',
    'pr', 'PR 9 Sprint 3',
    'fix', 'fn_envoyer_otp_signature appelle désormais fn_check_rate_limit_ip_signature en début. Anti-abus inter-comptes effectif.'
  )
);
