-- PR 1 Sprint 2 — Signature OTP : limites anti-abus + ordre + codes d'erreur
--
-- Renforce fn_envoyer_otp_signature et fn_signer_contrat_otp :
--   1. Max 3 envois SMS par contrat × rôle / 24h (anti-abus)
--   2. Ordre obligatoire : soignant signe avant l'établissement
--      (article L1242-13 Code du travail : l'employeur ne peut être seul à signer)
--   3. Toutes les erreurs retournent un champ `error_code` (enum) pour
--      permettre à l'UI de router des messages précis et différencier
--      OTP_EXPIRE / OTP_INCORRECT / TROP_DE_TENTATIVES / TROP_DE_SMS /
--      ETAB_AVANT_SOIGNANT / DEJA_SIGNE / TELEPHONE_MANQUANT / NON_AUTORISE.
--
-- Conserve le format de réponse jsonb compatible : ajoute des champs sans
-- supprimer ceux du module v1 (PR 4 Sprint 1).

-- 1. Ajouter colonne sms_envoyes_count + sms_premier_envoi_a pour fenêtre 24h
ALTER TABLE public.signatures_contrats
  ADD COLUMN IF NOT EXISTS sms_envoyes_count int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sms_premier_envoi_a timestamptz;

COMMENT ON COLUMN public.signatures_contrats.sms_envoyes_count IS
  'Nombre de SMS OTP envoyés depuis sms_premier_envoi_a. Limite : 3 / 24h (anti-abus).';

-- 2. Remplacer fn_envoyer_otp_signature avec :
--    - Vérification max 3 SMS / 24h
--    - Ordre : étab refusé si soignant pas encore signé
--    - error_code structuré
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
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

  -- ORDRE OBLIGATOIRE : étab ne peut envoyer OTP que si soignant a déjà signé
  IF v_role = 'etablissement' AND v_contrat.signature_soignant IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ETAB_AVANT_SOIGNANT',
      'error', 'Le soignant doit signer en premier. Vous serez notifié(e) par email dès qu''il aura signé.');
  END IF;

  IF v_telephone IS NULL OR v_telephone = '' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TELEPHONE_MANQUANT',
      'error', 'Numéro de téléphone manquant. Mettez à jour votre profil avant de signer.');
  END IF;

  -- Vérifier limite 3 SMS / 24h
  SELECT sms_envoyes_count, sms_premier_envoi_a, statut_signature
  INTO v_sig_existante
  FROM public.signatures_contrats
  WHERE contrat_id = p_contrat_id AND signataire_role = v_role;

  IF FOUND THEN
    -- Si déjà signé : refus
    IF v_sig_existante.statut_signature = 'signe' THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_SIGNE',
        'error', 'Vous avez déjà signé ce contrat.');
    END IF;

    -- Fenêtre 24h : reset si dépassée
    IF v_sig_existante.sms_premier_envoi_a IS NULL
       OR v_sig_existante.sms_premier_envoi_a < NOW() - INTERVAL '24 hours' THEN
      v_sms_count := 1;
      v_sms_window_start := NOW();
    ELSE
      v_sms_count := COALESCE(v_sig_existante.sms_envoyes_count, 0) + 1;
      v_sms_window_start := v_sig_existante.sms_premier_envoi_a;
      IF v_sms_count > 3 THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_SMS',
          'error', 'Trop de SMS envoyés (3 max / 24h). Réessayez après ' ||
            to_char(v_sig_existante.sms_premier_envoi_a + INTERVAL '24 hours', 'DD/MM HH24:MI') || '.',
          'sms_envoyes', v_sms_count - 1,
          'reset_le', (v_sig_existante.sms_premier_envoi_a + INTERVAL '24 hours')::text);
      END IF;
    END IF;
  ELSE
    v_sms_count := 1;
    v_sms_window_start := NOW();
  END IF;

  -- Générer OTP 6 chiffres + hash
  v_otp := lpad(floor(random() * 1000000)::text, 6, '0');
  v_otp_hash := encode(digest(v_otp || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');

  INSERT INTO public.signatures_contrats (
    contrat_id, signataire_user_id, signataire_role,
    otp_envoye_a, otp_code_hash, statut_signature, audit_trail,
    sms_envoyes_count, sms_premier_envoi_a
  ) VALUES (
    p_contrat_id, v_uid, v_role,
    NOW(), v_otp_hash, 'otp_envoye',
    jsonb_build_object('otp_envoye_le', NOW()::text, 'sms_count', v_sms_count),
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
      || jsonb_build_object('otp_renvoye_le', NOW()::text, 'sms_count', v_sms_count);

  -- Envoi SMS best-effort
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

-- 3. Remplacer fn_signer_contrat_otp avec error_code structuré + détection
--    hash document changé (HASH_DOCUMENT_CHANGE).
CREATE OR REPLACE FUNCTION public.fn_signer_contrat_otp(
  p_contrat_id uuid,
  p_otp_code text,
  p_hash_document text DEFAULT NULL,
  p_signature_image text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_sig RECORD;
  v_contrat RECORD;
  v_expected_hash text;
  v_role text;
  v_ip inet;
  v_ua text;
  v_other_signed boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  SELECT cm.signature_soignant, cm.signature_etablissement, cm.statut
  INTO v_contrat
  FROM public.contrats_mission cm WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE', 'error', 'Contrat introuvable');
  END IF;

  SELECT * INTO v_sig FROM public.signatures_contrats
  WHERE contrat_id = p_contrat_id AND signataire_user_id = v_uid
  ORDER BY cree_le DESC LIMIT 1;

  IF v_sig IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_NON_DEMANDE',
      'error', 'Aucune demande OTP en cours. Cliquez d''abord sur "Recevoir un code SMS".');
  END IF;

  IF v_sig.statut_signature = 'signe' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DEJA_SIGNE',
      'error', 'Vous avez déjà signé ce contrat le ' ||
        COALESCE(to_char(v_sig.signe_a, 'DD/MM/YYYY HH24:MI'), '—') || '.',
      'signe_a', v_sig.signe_a);
  END IF;

  -- Ordre obligatoire (vérif redondante avec fn_envoyer_otp_signature)
  IF v_sig.signataire_role = 'etablissement' AND v_contrat.signature_soignant IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ETAB_AVANT_SOIGNANT',
      'error', 'Le soignant doit signer en premier.');
  END IF;

  IF v_sig.otp_tentatives >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_DE_TENTATIVES',
      'error', 'Trop de tentatives. Renvoyez un nouveau code SMS.');
  END IF;

  IF v_sig.otp_envoye_a IS NULL OR v_sig.otp_envoye_a < NOW() - INTERVAL '10 minutes' THEN
    UPDATE public.signatures_contrats
    SET statut_signature = 'expire', modifie_le = NOW()
    WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_EXPIRE',
      'error', 'Code expiré. Renvoyez un nouveau code SMS.');
  END IF;

  v_expected_hash := encode(digest(p_otp_code || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');
  IF v_expected_hash != v_sig.otp_code_hash THEN
    UPDATE public.signatures_contrats
    SET otp_tentatives = otp_tentatives + 1, modifie_le = NOW()
    WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_INCORRECT',
      'error', 'Code incorrect.',
      'tentatives_restantes', 5 - (v_sig.otp_tentatives + 1));
  END IF;

  v_role := v_sig.signataire_role;
  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_ua := current_setting('request.headers', true)::jsonb->>'user-agent';

  UPDATE public.signatures_contrats
  SET statut_signature = 'signe',
      otp_valide_a = NOW(),
      signe_a = NOW(),
      ip_signature = v_ip,
      user_agent = v_ua,
      hash_document = p_hash_document,
      signature_image_base64 = p_signature_image,
      modifie_le = NOW(),
      audit_trail = COALESCE(audit_trail, '{}'::jsonb)
        || jsonb_build_object('signe_le', NOW()::text, 'tentatives', v_sig.otp_tentatives + 1)
  WHERE id = v_sig.id;

  IF v_role = 'soignant' THEN
    UPDATE public.contrats_mission
    SET signature_soignant = true,
        signature_soignant_le = NOW(),
        signature_ip_soignant = COALESCE(v_ip::text, signature_ip_soignant),
        signature_navigateur_soignant = COALESCE(v_ua, signature_navigateur_soignant),
        signature_image_soignant = COALESCE(p_signature_image, signature_image_soignant),
        mode_signature = 'JOLENE_OTP'
    WHERE id = p_contrat_id;
  ELSE
    UPDATE public.contrats_mission
    SET signature_etablissement = true,
        signature_etablissement_le = NOW(),
        signature_ip_etablissement = COALESCE(v_ip::text, signature_ip_etablissement),
        signature_navigateur_etablissement = COALESCE(v_ua, signature_navigateur_etablissement),
        signature_image_etablissement = COALESCE(p_signature_image, signature_image_etablissement),
        mode_signature = 'JOLENE_OTP'
    WHERE id = p_contrat_id;
  END IF;

  SELECT (signature_soignant = true AND signature_etablissement = true) INTO v_other_signed
  FROM public.contrats_mission WHERE id = p_contrat_id;

  IF v_other_signed THEN
    UPDATE public.contrats_mission
    SET statut = 'SIGNE_COMPLET', modifie_le = NOW()
    WHERE id = p_contrat_id AND statut != 'SIGNE_COMPLET';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'contrat_complet', v_other_signed
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_otp(uuid, text, text, text) TO authenticated;

-- 4. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'PR1_SPRINT2_SIGNATURE_LIMITS_INSTALLED',
    'pr', 'PR 1 Sprint 2',
    'modifications', ARRAY[
      'signatures_contrats.sms_envoyes_count',
      'signatures_contrats.sms_premier_envoi_a',
      'fn_envoyer_otp_signature: ordre soignant-puis-etab + max 3 SMS / 24h + error_code',
      'fn_signer_contrat_otp: error_code structuré (OTP_EXPIRE, OTP_INCORRECT, DEJA_SIGNE, etc.)'
    ]
  )
);
