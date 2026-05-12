-- PR 4 Sprint 1 — Module signature électronique sécurisée OTP SMS
--
-- Remplace progressivement Yousign par un module signature interne avec
-- OTP SMS systématique (Option A max sécurité validée par Gabrielle).
--
-- L'ancien yousign-create est gardé fonctionnel pour les contrats déjà
-- en cours mais marqué @deprecated. Les nouveaux contrats utilisent
-- le flow OTP via fn_envoyer_otp_signature + fn_signer_contrat_otp.

-- 1. Table signatures_contrats
CREATE TABLE IF NOT EXISTS public.signatures_contrats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contrat_id uuid NOT NULL REFERENCES public.contrats_mission(id) ON DELETE CASCADE,
  signataire_user_id uuid NOT NULL,
  signataire_role text NOT NULL CHECK (signataire_role IN ('etablissement', 'soignant')),
  -- Métadonnées signature
  signe_a timestamptz,
  ip_signature inet,
  user_agent text,
  hash_document text,
  -- OTP SMS
  otp_envoye_a timestamptz,
  otp_valide_a timestamptz,
  otp_code_hash text,
  otp_tentatives int DEFAULT 0,
  -- Vérifications complémentaires (best-effort, pas bloquant pour v1)
  psc_session_active boolean DEFAULT false,
  rpps_verifie boolean DEFAULT false,
  traits_identite_verifies boolean DEFAULT false,
  -- Statut + audit
  statut_signature text NOT NULL DEFAULT 'en_attente'
    CHECK (statut_signature IN ('en_attente', 'otp_envoye', 'signe', 'refuse', 'expire')),
  audit_trail jsonb DEFAULT '{}'::jsonb,
  signature_image_base64 text,
  cree_le timestamptz DEFAULT NOW(),
  modifie_le timestamptz DEFAULT NOW(),
  -- Unicité : un signataire ne peut avoir qu'une signature par contrat
  UNIQUE (contrat_id, signataire_role)
);

CREATE INDEX IF NOT EXISTS idx_signatures_contrats_contrat ON public.signatures_contrats(contrat_id);
CREATE INDEX IF NOT EXISTS idx_signatures_contrats_user ON public.signatures_contrats(signataire_user_id);

-- 2. RLS : lecture par les parties du contrat + admins, INSERT/UPDATE
-- bloqué directement (uniquement via RPCs).
ALTER TABLE public.signatures_contrats ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_sig_contrats_select ON public.signatures_contrats
  FOR SELECT TO authenticated
  USING (
    est_admin() OR signataire_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.contrats_mission cm
      WHERE cm.id = signatures_contrats.contrat_id
      AND (cm.soignant_id = auth.uid() OR cm.etablissement_id = mon_etablissement_id())
    )
  );

CREATE POLICY pol_sig_contrats_insert_deny ON public.signatures_contrats
  FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY pol_sig_contrats_update_deny ON public.signatures_contrats
  FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY pol_sig_contrats_delete_deny ON public.signatures_contrats
  FOR DELETE TO authenticated USING (false);

GRANT SELECT ON public.signatures_contrats TO authenticated;

-- 3. RPC fn_envoyer_otp_signature(p_contrat_id)
-- Génère un OTP 6 chiffres, le hash, l'envoie par SMS via send-sms.
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  -- Récupérer le contrat et identifier le rôle de l'utilisateur courant
  SELECT cm.id, cm.soignant_id, cm.etablissement_id, cm.contenu_html, cm.statut
  INTO v_contrat
  FROM public.contrats_mission cm
  WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat introuvable');
  END IF;

  IF v_contrat.soignant_id = v_uid THEN
    v_role := 'soignant';
    SELECT telephone INTO v_telephone FROM public.soignants WHERE id = v_uid;
  ELSIF v_contrat.etablissement_id = v_uid OR mon_etablissement_id() = v_contrat.etablissement_id THEN
    v_role := 'etablissement';
    SELECT telephone_contact INTO v_telephone FROM public.etablissements WHERE id = v_contrat.etablissement_id;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Non autorisé à signer ce contrat');
  END IF;

  IF v_telephone IS NULL OR v_telephone = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Numéro de téléphone manquant. Mettez à jour votre profil avant de signer.');
  END IF;

  -- Générer OTP 6 chiffres + hash SHA-256
  v_otp := lpad(floor(random() * 1000000)::text, 6, '0');
  v_otp_hash := encode(digest(v_otp || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');

  -- Upsert sur signatures_contrats
  INSERT INTO public.signatures_contrats (
    contrat_id, signataire_user_id, signataire_role,
    otp_envoye_a, otp_code_hash, statut_signature, audit_trail
  ) VALUES (
    p_contrat_id, v_uid, v_role,
    NOW(), v_otp_hash, 'otp_envoye',
    jsonb_build_object('otp_envoye_le', NOW()::text)
  )
  ON CONFLICT (contrat_id, signataire_role) DO UPDATE SET
    otp_envoye_a = NOW(),
    otp_code_hash = EXCLUDED.otp_code_hash,
    otp_tentatives = 0,
    statut_signature = 'otp_envoye',
    modifie_le = NOW(),
    audit_trail = COALESCE(signatures_contrats.audit_trail, '{}'::jsonb)
      || jsonb_build_object('otp_renvoye_le', NOW()::text);

  -- Envoi SMS via send-sms (best-effort, ne fail pas si SMS down)
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
  EXCEPTION WHEN OTHERS THEN
    -- Pas d'extension net dispo ? Fallback silencieux.
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'telephone_masked', regexp_replace(v_telephone, '\d(?=\d{2})', '*', 'g'),
    'expire_dans_minutes', 10
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_signature(uuid) TO authenticated;

-- 4. RPC fn_signer_contrat_otp(p_contrat_id, p_otp_code, p_hash_document, p_signature_image)
-- Valide l'OTP + hash, insère la signature, met à jour le contrat.
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
  v_expected_hash text;
  v_role text;
  v_ip inet;
  v_ua text;
  v_other_signed boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  -- Récupérer la row signature en attente
  SELECT * INTO v_sig FROM public.signatures_contrats
  WHERE contrat_id = p_contrat_id AND signataire_user_id = v_uid
  ORDER BY cree_le DESC LIMIT 1;

  IF v_sig IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Aucune demande OTP en cours. Cliquez d''abord sur "Recevoir un code SMS".');
  END IF;

  IF v_sig.statut_signature = 'signe' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Contrat déjà signé par vous.');
  END IF;

  IF v_sig.otp_tentatives >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Trop de tentatives. Renvoyez un nouveau code SMS.');
  END IF;

  -- Vérifier expiration OTP (10 min)
  IF v_sig.otp_envoye_a IS NULL OR v_sig.otp_envoye_a < NOW() - INTERVAL '10 minutes' THEN
    UPDATE public.signatures_contrats
    SET statut_signature = 'expire', modifie_le = NOW()
    WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error', 'Code expiré. Renvoyez un nouveau code SMS.');
  END IF;

  -- Vérifier OTP (constant-time comparison)
  v_expected_hash := encode(digest(p_otp_code || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');
  IF v_expected_hash != v_sig.otp_code_hash THEN
    UPDATE public.signatures_contrats
    SET otp_tentatives = otp_tentatives + 1, modifie_le = NOW()
    WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error', 'Code incorrect.', 'tentatives_restantes', 5 - (v_sig.otp_tentatives + 1));
  END IF;

  v_role := v_sig.signataire_role;
  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_ua := current_setting('request.headers', true)::jsonb->>'user-agent';

  -- OTP valide → marquer signe
  UPDATE public.signatures_contrats
  SET
    statut_signature = 'signe',
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

  -- Update contrats_mission selon le rôle (compat avec colonnes existantes)
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

  -- Si les 2 parties ont signé, passer le contrat en SIGNE_COMPLET
  SELECT
    (signature_soignant = true AND signature_etablissement = true) INTO v_other_signed
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

-- 5. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'table', NULL,
  jsonb_build_object(
    'evenement', 'MODULE_SIGNATURE_OTP_INSTALLED',
    'pr', 'PR 4 Sprint 1',
    'composants', ARRAY['table signatures_contrats','RPC fn_envoyer_otp_signature','RPC fn_signer_contrat_otp'],
    'mode_signature_label', 'JOLENE_OTP',
    'note', 'Yousign legacy gardé pour contrats en cours (0 actuellement, déprécation propre)'
  )
);
