-- ============================================================================
-- Sprint 6 PR 9 — OTP SMS vérification téléphone (P1-12)
-- ============================================================================
-- Workflow OTP SMS pour vérifier numéro téléphone à l'inscription
-- + modification téléphone. Réutilise infra Twilio existante (Sprint 2 signature).
-- Rate limit 3 SMS / 24h par numéro pour anti-abus.
-- ============================================================================

-- Colonnes verification téléphone
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS telephone_verifie boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS telephone_verifie_le timestamptz,
  ADD COLUMN IF NOT EXISTS telephone_en_attente_verification text;

ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS telephone_verifie boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS telephone_verifie_le timestamptz,
  ADD COLUMN IF NOT EXISTS telephone_en_attente_verification text;

-- Table OTPs téléphone (séparée des OTPs signature contrat)
CREATE TABLE IF NOT EXISTS public.otps_telephone (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  telephone text NOT NULL,
  code_hash text NOT NULL,
  tentatives int NOT NULL DEFAULT 0,
  utilise boolean NOT NULL DEFAULT false,
  cree_le timestamptz NOT NULL DEFAULT now(),
  expire_le timestamptz NOT NULL DEFAULT (now() + INTERVAL '10 minutes')
);

CREATE INDEX IF NOT EXISTS idx_otps_telephone_user ON public.otps_telephone(user_id, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_otps_telephone_phone ON public.otps_telephone(telephone, cree_le DESC);

ALTER TABLE public.otps_telephone ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "otps_tel_self_select" ON public.otps_telephone;
CREATE POLICY "otps_tel_self_select" ON public.otps_telephone
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- RPC : demander envoi OTP SMS
CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_telephone(p_telephone text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_code text;
  v_code_hash text;
  v_otp_id uuid;
  v_count_24h int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  -- Format téléphone E164 simplifié (sans pays pour MVP, regex large)
  IF p_telephone IS NULL OR p_telephone !~ '^\+?[0-9 ]{9,15}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TELEPHONE_INVALIDE',
                                'error', 'Téléphone invalide. Format attendu : +33 6 12 34 56 78');
  END IF;

  -- Rate limit 3 SMS / 24h par user (anti-abus)
  SELECT COUNT(*) INTO v_count_24h FROM public.otps_telephone
  WHERE user_id = v_uid AND cree_le > NOW() - INTERVAL '24 hours';
  IF v_count_24h >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'RATE_LIMIT',
                                'error', 'Trop d''envois (3 SMS / 24h max). Réessayez plus tard.');
  END IF;

  -- Génération code 6 chiffres
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  -- Hash bcrypt pour stockage (jamais le code en clair)
  v_code_hash := extensions.crypt(v_code, extensions.gen_salt('bf', 8));

  INSERT INTO public.otps_telephone (user_id, telephone, code_hash)
  VALUES (v_uid, p_telephone, v_code_hash)
  RETURNING id INTO v_otp_id;

  -- Mémoriser le numéro en attente sur le profil
  UPDATE public.soignants SET telephone_en_attente_verification = p_telephone WHERE id = v_uid;
  UPDATE public.etablissements SET telephone_en_attente_verification = p_telephone
    WHERE id = public.mon_etablissement_id();

  -- Audit + déclenchement Twilio via externalisation_actions
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('SMS_NOTIF', jsonb_build_object(
    'telephone', p_telephone,
    'type', 'OTP_VERIFICATION_TELEPHONE',
    'data', jsonb_build_object('code', v_code, 'expire_min', 10)
  ), 'AUTRE', v_otp_id);

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'otp_telephone', v_otp_id,
    jsonb_build_object('evenement', 'OTP_TELEPHONE_ENVOYE', 'telephone', p_telephone)
  );

  RETURN jsonb_build_object('success', true, 'otp_id', v_otp_id, 'expire_min', 10);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_telephone(text) TO authenticated;

-- RPC : vérifier code OTP
CREATE OR REPLACE FUNCTION public.fn_verifier_otp_telephone(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_otp RECORD;
  v_etab_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INVALIDE');
  END IF;

  -- Trouver le dernier OTP actif pour ce user
  SELECT * INTO v_otp FROM public.otps_telephone
  WHERE user_id = v_uid AND utilise = false AND expire_le > NOW()
  ORDER BY cree_le DESC LIMIT 1;

  IF v_otp.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_INEXISTANT_OU_EXPIRE');
  END IF;

  -- Blocage après 5 tentatives
  IF v_otp.tentatives >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TROP_TENTATIVES',
                                'error', 'Trop de tentatives. Demandez un nouveau code.');
  END IF;

  -- Incrémenter tentatives avant vérif
  UPDATE public.otps_telephone SET tentatives = tentatives + 1 WHERE id = v_otp.id;

  -- Vérifier hash
  IF extensions.crypt(p_code, v_otp.code_hash) != v_otp.code_hash THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT',
                                'tentatives_restantes', 5 - (v_otp.tentatives + 1));
  END IF;

  -- Code correct : marquer OTP utilisé + téléphone vérifié sur profil
  UPDATE public.otps_telephone SET utilise = true WHERE id = v_otp.id;

  IF EXISTS (SELECT 1 FROM public.soignants WHERE id = v_uid) THEN
    UPDATE public.soignants
    SET telephone = v_otp.telephone,
        telephone_verifie = true,
        telephone_verifie_le = NOW(),
        telephone_en_attente_verification = NULL
    WHERE id = v_uid;
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NOT NULL THEN
    UPDATE public.etablissements
    SET telephone_contact = v_otp.telephone,
        telephone_verifie = true,
        telephone_verifie_le = NOW(),
        telephone_en_attente_verification = NULL
    WHERE id = v_etab_id;
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'SOIGNANT', 'SYSTEM', 'otp_telephone', v_otp.id,
    jsonb_build_object('evenement', 'OTP_TELEPHONE_VERIFIE', 'telephone', v_otp.telephone)
  );

  RETURN jsonb_build_object('success', true, 'telephone', v_otp.telephone);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_verifier_otp_telephone(text) TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT6_PR9_OTP_SMS_TELEPHONE_INSTALLED',
    'pr', 'PR 9 Sprint 6',
    'rpcs', jsonb_build_array('fn_envoyer_otp_telephone', 'fn_verifier_otp_telephone'),
    'table', 'otps_telephone',
    'colonnes_ajoutees', jsonb_build_array('soignants.telephone_verifie', 'etablissements.telephone_verifie')
  )
);
