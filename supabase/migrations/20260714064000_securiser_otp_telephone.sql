-- OTP téléphone : génération CSPRNG, cible non ambiguë, file SMS fonctionnelle
-- et suppression du code en clair après succès, échec terminal ou expiration.

ALTER TABLE public.externalisation_actions
  DROP CONSTRAINT IF EXISTS externalisation_actions_type_action_check;
ALTER TABLE public.externalisation_actions
  ADD CONSTRAINT externalisation_actions_type_action_check
  CHECK (type_action IN (
    'STRIPE_REFUND_PARTIEL',
    'STRIPE_REFUND_TOTAL',
    'STRIPE_PAYMENT',
    'STRIPE_PAYOUT',
    'CHORUS_RECYCLER_FACTURE',
    'CHORUS_RECYCLE_FACTURE',
    'DPAE_ANNULATION',
    'DPAE_ANNULATION_NOTIF',
    'EMAIL_NOTIF',
    'SMS_NOTIF',
    'PUSH_NOTIF',
    'AVOIR_PDF_GENERATION',
    'RECOMPENSE_PARRAINAGE_SOIGNANT',
    'REMBOURSEMENT_AVOIR_SWAN'
  ));

ALTER TABLE public.otps_telephone
  ADD COLUMN IF NOT EXISTS cible_type text,
  ADD COLUMN IF NOT EXISTS cible_id uuid;

ALTER TABLE public.otps_telephone
  DROP CONSTRAINT IF EXISTS otps_telephone_cible_check;
ALTER TABLE public.otps_telephone
  ADD CONSTRAINT otps_telephone_cible_check
  CHECK (
    (cible_type IS NULL AND cible_id IS NULL)
    OR (cible_type IN ('SOIGNANT', 'ETABLISSEMENT') AND cible_id IS NOT NULL)
  );

COMMENT ON COLUMN public.otps_telephone.cible_type IS
  'Famille de profil figée à l émission afin de ne jamais valider deux profils avec le même OTP.';

CREATE OR REPLACE FUNCTION public.fn_generer_code_otp_6_chiffres()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $function$
DECLARE
  v_bytes bytea;
  v_value bigint;
BEGIN
  LOOP
    v_bytes := extensions.gen_random_bytes(4);
    v_value :=
        get_byte(v_bytes, 0)::bigint * 16777216
      + get_byte(v_bytes, 1)::bigint * 65536
      + get_byte(v_bytes, 2)::bigint * 256
      + get_byte(v_bytes, 3)::bigint;

    -- 4 294 000 000 est le plus grand multiple de 1 000 000 inférieur
    -- à 2^32. Le rejet évite tout biais modulo.
    IF v_value < 4294000000 THEN
      RETURN lpad((v_value % 1000000)::text, 6, '0');
    END IF;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_generer_code_otp_6_chiffres()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_generer_code_otp_6_chiffres()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_purger_codes_otp_expires()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.externalisation_actions ea
  SET payload = jsonb_set(
        ea.payload #- '{data,code}',
        '{data,code_purge}',
        'true'::jsonb,
        true
      ),
      statut = CASE
        WHEN ea.statut IN ('PENDING', 'ERROR') THEN 'CANCELLED'
        ELSE ea.statut
      END,
      next_retry_at = CASE
        WHEN ea.statut IN ('PENDING', 'ERROR') THEN NULL
        ELSE ea.next_retry_at
      END,
      cron_lock_at = CASE
        WHEN ea.statut IN ('PENDING', 'ERROR') THEN NULL
        ELSE ea.cron_lock_at
      END,
      cron_lock_par = CASE
        WHEN ea.statut IN ('PENDING', 'ERROR') THEN NULL
        ELSE ea.cron_lock_par
      END
  FROM public.otps_telephone otp
  WHERE ea.type_action = 'SMS_NOTIF'
    AND ea.source = 'AUTRE'
    AND ea.source_id = otp.id
    AND otp.expire_le <= now()
    AND ea.payload #>> '{data,code}' IS NOT NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_purger_codes_otp_expires()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_purger_codes_otp_expires()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_telephone(p_telephone text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_telephone text;
  v_code text;
  v_code_hash text;
  v_otp_id uuid;
  v_count_24h integer;
  v_cible_type text;
  v_cible_id uuid;
  v_etablissement_id uuid;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'NON_AUTHENTIFIE',
      'error', 'Session inactive.'
    );
  END IF;

  v_telephone := regexp_replace(btrim(COALESCE(p_telephone, '')), '[\s().-]+', '', 'g');
  IF v_telephone LIKE '00%' THEN v_telephone := '+' || substring(v_telephone FROM 3); END IF;
  IF v_telephone LIKE '0%' THEN v_telephone := '+33' || substring(v_telephone FROM 2); END IF;
  IF v_telephone !~ '^\+[1-9][0-9]{7,14}$' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TELEPHONE_INVALIDE',
      'error', 'Téléphone invalide. Format attendu : +33 6 12 34 56 78.'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.soignants
    WHERE id = v_uid AND supprime_le IS NULL
  ) THEN
    v_cible_type := 'SOIGNANT';
    v_cible_id := v_uid;
  ELSE
    v_etablissement_id := public.mon_etablissement_id();
    IF v_etablissement_id IS NULL
       OR NOT public.fn_a_permission_etablissement('profil_etab', v_etablissement_id) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'PROFIL_INTROUVABLE',
        'error', 'Aucun profil autorisé pour vérifier ce numéro.'
      );
    END IF;
    v_cible_type := 'ETABLISSEMENT';
    v_cible_id := v_etablissement_id;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('otp-phone:' || v_uid::text, 0));
  PERFORM public.fn_purger_codes_otp_expires();

  SELECT count(*) INTO v_count_24h
  FROM public.otps_telephone
  WHERE user_id = v_uid
    AND cree_le > now() - interval '24 hours';
  IF v_count_24h >= 3 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RATE_LIMIT',
      'error', 'Trop d envois (3 SMS par 24 h maximum). Réessayez plus tard.'
    );
  END IF;

  -- Rend immédiatement inutilisables les codes précédents de ce compte.
  UPDATE public.otps_telephone
  SET utilise = true
  WHERE user_id = v_uid AND utilise IS FALSE;

  v_code := public.fn_generer_code_otp_6_chiffres();
  v_code_hash := extensions.crypt(v_code, extensions.gen_salt('bf', 10));

  INSERT INTO public.otps_telephone (
    user_id, telephone, code_hash, cible_type, cible_id
  ) VALUES (
    v_uid, v_telephone, v_code_hash, v_cible_type, v_cible_id
  )
  RETURNING id INTO v_otp_id;

  IF v_cible_type = 'SOIGNANT' THEN
    UPDATE public.soignants
    SET telephone_en_attente_verification = v_telephone,
        modifie_le = now()
    WHERE id = v_cible_id;
  ELSE
    UPDATE public.etablissements
    SET telephone_en_attente_verification = v_telephone,
        modifie_le = now()
    WHERE id = v_cible_id;
  END IF;

  INSERT INTO public.externalisation_actions (
    type_action, payload, source, source_id
  ) VALUES (
    'SMS_NOTIF',
    jsonb_build_object(
      'telephone', v_telephone,
      'type', 'OTP_VERIFICATION_TELEPHONE',
      'destinataire_id', v_uid,
      'cible_type', v_cible_type,
      'cible_id', v_cible_id,
      'data', jsonb_build_object('code', v_code, 'expire_min', 10)
    ),
    'AUTRE',
    v_otp_id
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := v_cible_type,
    p_action := 'SYSTEM',
    p_type_ressource := 'otp_telephone',
    p_id_ressource := v_otp_id,
    p_details := jsonb_build_object(
      'evenement', 'OTP_TELEPHONE_ENVOYE',
      'telephone_last4', right(regexp_replace(v_telephone, '[^0-9]', '', 'g'), 4),
      'cible_type', v_cible_type,
      'cible_id', v_cible_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'otp_id', v_otp_id,
    'expire_min', 10,
    'telephone_last4', right(regexp_replace(v_telephone, '[^0-9]', '', 'g'), 4)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_envoyer_otp_telephone(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_telephone(text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_verifier_otp_telephone(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_otp public.otps_telephone%ROWTYPE;
  v_cible_type text;
  v_cible_id uuid;
  v_etablissement_id uuid;
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;
  IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INVALIDE');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('otp-phone:' || v_uid::text, 0));
  PERFORM public.fn_purger_codes_otp_expires();

  SELECT * INTO v_otp
  FROM public.otps_telephone
  WHERE user_id = v_uid
    AND utilise IS FALSE
    AND expire_le > now()
  ORDER BY cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'OTP_INEXISTANT_OU_EXPIRE'
    );
  END IF;
  IF v_otp.tentatives >= 5 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TROP_TENTATIVES',
      'error', 'Trop de tentatives. Demandez un nouveau code.'
    );
  END IF;

  UPDATE public.otps_telephone
  SET tentatives = tentatives + 1
  WHERE id = v_otp.id;

  IF extensions.crypt(p_code, v_otp.code_hash) <> v_otp.code_hash THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'CODE_INCORRECT',
      'tentatives_restantes', greatest(0, 5 - (v_otp.tentatives + 1))
    );
  END IF;

  v_cible_type := v_otp.cible_type;
  v_cible_id := v_otp.cible_id;
  -- Compatibilité des OTP historiques créés avant l'ajout de la cible figée.
  IF v_cible_type IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.soignants
      WHERE id = v_uid AND supprime_le IS NULL
    ) THEN
      v_cible_type := 'SOIGNANT';
      v_cible_id := v_uid;
    ELSE
      v_etablissement_id := public.mon_etablissement_id();
      IF v_etablissement_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'PROFIL_INTROUVABLE');
      END IF;
      v_cible_type := 'ETABLISSEMENT';
      v_cible_id := v_etablissement_id;
    END IF;
  END IF;

  IF v_cible_type = 'SOIGNANT' THEN
    IF v_cible_id IS DISTINCT FROM v_uid THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CIBLE_INVALIDE');
    END IF;
    UPDATE public.soignants
    SET telephone = v_otp.telephone,
        telephone_verifie = true,
        telephone_verifie_le = now(),
        telephone_en_attente_verification = NULL,
        modifie_le = now()
    WHERE id = v_cible_id AND supprime_le IS NULL;
  ELSIF v_cible_type = 'ETABLISSEMENT' THEN
    IF public.mon_etablissement_id() IS DISTINCT FROM v_cible_id
       OR NOT public.fn_a_permission_etablissement('profil_etab', v_cible_id) THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CIBLE_INVALIDE');
    END IF;
    UPDATE public.etablissements
    SET telephone_contact = v_otp.telephone,
        telephone_verifie = true,
        telephone_verifie_le = now(),
        telephone_en_attente_verification = NULL,
        modifie_le = now()
    WHERE id = v_cible_id AND supprime_le IS NULL;
  ELSE
    RETURN jsonb_build_object('success', false, 'error_code', 'CIBLE_INVALIDE');
  END IF;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CIBLE_INTROUVABLE');
  END IF;

  UPDATE public.otps_telephone
  SET utilise = true
  WHERE id = v_otp.id;

  -- Le SMS a nécessairement été reçu pour que le code puisse être fourni. On
  -- expurge néanmoins explicitement toute action encore présente ou retraitée.
  UPDATE public.externalisation_actions
  SET payload = jsonb_set(
        payload #- '{data,code}',
        '{data,code_purge}',
        'true'::jsonb,
        true
      )
  WHERE type_action = 'SMS_NOTIF'
    AND source = 'AUTRE'
    AND source_id = v_otp.id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := v_cible_type,
    p_action := 'SYSTEM',
    p_type_ressource := 'otp_telephone',
    p_id_ressource := v_otp.id,
    p_details := jsonb_build_object(
      'evenement', 'OTP_TELEPHONE_VERIFIE',
      'telephone_last4', right(regexp_replace(v_otp.telephone, '[^0-9]', '', 'g'), 4),
      'cible_type', v_cible_type,
      'cible_id', v_cible_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'telephone_last4', right(regexp_replace(v_otp.telephone, '[^0-9]', '', 'g'), 4),
    'cible_type', v_cible_type
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_verifier_otp_telephone(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_verifier_otp_telephone(text)
  TO authenticated, service_role;

-- Conserve les garanties d'acquittement concurrent de la migration financière
-- précédente et ajoute uniquement l'expurgation du secret OTP.
CREATE OR REPLACE FUNCTION public.fn_externalisation_succes(
  p_id uuid,
  p_resultat jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_action public.externalisation_actions%ROWTYPE;
  v_rows integer;
BEGIN
  IF p_id IS NULL
     OR (p_resultat IS NOT NULL AND jsonb_typeof(p_resultat) <> 'object') THEN
    RAISE EXCEPTION 'Acquittement externalisation invalide' USING ERRCODE = '22023';
  END IF;

  SELECT ea.* INTO v_action
  FROM public.externalisation_actions ea
  WHERE ea.id = p_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action externalisation introuvable' USING ERRCODE = 'P0001';
  END IF;
  IF v_action.statut = 'DONE' THEN
    RETURN jsonb_build_object('success', true, 'already_done', true);
  END IF;
  IF v_action.statut = 'CANCELLED' THEN
    RAISE EXCEPTION 'Action externalisation annulée' USING ERRCODE = 'P0001';
  END IF;
  IF v_action.statut NOT IN ('PROCESSING', 'PENDING', 'ERROR', 'PENDING_AIFE') THEN
    RAISE EXCEPTION 'État externalisation non acquittable: %', v_action.statut;
  END IF;

  UPDATE public.externalisation_actions
  SET statut = 'DONE',
      traite_le = now(),
      resultat = COALESCE(p_resultat, '{}'::jsonb),
      payload = CASE
        WHEN v_action.type_action = 'SMS_NOTIF' THEN jsonb_set(
          payload #- '{data,code}', '{data,code_purge}', 'true'::jsonb, true
        )
        ELSE payload
      END,
      derniere_erreur = NULL,
      cron_lock_at = NULL,
      cron_lock_par = NULL,
      next_retry_at = NULL
  WHERE id = p_id AND statut = v_action.statut;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Acquittement externalisation concurrent refusé';
  END IF;
  RETURN jsonb_build_object('success', true, 'statut', 'DONE');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_externalisation_echec(
  p_id uuid,
  p_erreur text,
  p_special_statut text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_action public.externalisation_actions%ROWTYPE;
  v_new_tentatives integer;
  v_new_statut text;
  v_next_retry timestamptz;
  v_rows integer;
BEGIN
  IF p_id IS NULL OR btrim(COALESCE(p_erreur, '')) = '' THEN
    RAISE EXCEPTION 'Échec externalisation invalide' USING ERRCODE = '22023';
  END IF;
  SELECT ea.* INTO v_action
  FROM public.externalisation_actions ea
  WHERE ea.id = p_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action externalisation introuvable' USING ERRCODE = 'P0001';
  END IF;
  IF v_action.statut = 'DONE' THEN
    RETURN jsonb_build_object('success', true, 'already_done', true);
  END IF;
  IF v_action.statut = 'CANCELLED' THEN
    RETURN jsonb_build_object('success', true, 'cancelled', true);
  END IF;

  IF p_special_statut = 'PENDING_AIFE' THEN
    v_new_statut := 'PENDING_AIFE';
    v_next_retry := now() + interval '24 hours';
    v_new_tentatives := v_action.tentatives;
  ELSIF p_special_statut IS NOT NULL THEN
    RAISE EXCEPTION 'Statut spécial externalisation invalide' USING ERRCODE = '22023';
  ELSE
    v_new_tentatives := COALESCE(v_action.tentatives, 0) + 1;
    IF v_new_tentatives >= 3 THEN
      v_new_statut := 'ERROR';
      v_next_retry := NULL;
    ELSIF v_new_tentatives = 1 THEN
      v_new_statut := 'PENDING';
      v_next_retry := now() + interval '1 minute';
    ELSE
      v_new_statut := 'PENDING';
      v_next_retry := now() + interval '5 minutes';
    END IF;
  END IF;

  UPDATE public.externalisation_actions
  SET statut = v_new_statut,
      tentatives = v_new_tentatives,
      derniere_tentative_le = now(),
      derniere_erreur = left(p_erreur, 1000),
      next_retry_at = v_next_retry,
      cron_lock_at = NULL,
      cron_lock_par = NULL,
      traite_le = CASE WHEN v_new_statut = 'ERROR' THEN now() ELSE traite_le END,
      payload = CASE
        WHEN v_new_statut = 'ERROR' AND v_action.type_action = 'SMS_NOTIF' THEN jsonb_set(
          payload #- '{data,code}', '{data,code_purge}', 'true'::jsonb, true
        )
        ELSE payload
      END
  WHERE id = p_id AND statut = v_action.statut;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Échec externalisation concurrent refusé';
  END IF;

  IF v_new_statut = 'ERROR' THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details,
      navigateur_acteur
    ) VALUES (
      '00000000-0000-0000-0000-000000000000'::uuid,
      'SYSTEME', 'SYSTEM', 'externalisation_action', p_id,
      jsonb_build_object(
        'evenement', 'EXTERNALISATION_ECHEC_DEFINITIF',
        'type_action', v_action.type_action,
        'tentatives', v_new_tentatives,
        'derniere_erreur', left(p_erreur, 200)
      ),
      'fn_externalisation_echec'
    );
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'statut', v_new_statut,
    'tentatives', v_new_tentatives
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_externalisation_succes(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_externalisation_echec(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_externalisation_succes(uuid, jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_externalisation_echec(uuid, text, text)
  TO service_role;
