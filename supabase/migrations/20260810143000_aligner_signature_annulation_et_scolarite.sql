BEGIN;

-- Les articles L.1242-12/L.1242-13 imposent l'écrit et sa transmission, pas
-- un ordre de signature. Chaque partie peut donc demander son OTP en premier.
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
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-sms',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret FROM vault.decrypted_secrets
           WHERE name = 'service_role_key' LIMIT 1
        )
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

CREATE OR REPLACE FUNCTION public.fn_signer_contrat_otp(
  p_contrat_id uuid,
  p_otp_code text,
  p_hash_document text DEFAULT NULL::text,
  p_signature_image text DEFAULT NULL::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_sig record;
  v_contrat record;
  v_expected_hash text;
  v_role text;
  v_ip inet;
  v_ua text;
  v_contrat_complet boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE', 'error', 'Non authentifié');
  END IF;

  SELECT cm.signature_soignant, cm.signature_etablissement, cm.statut
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

  v_expected_hash := encode(digest(p_otp_code || '|' || p_contrat_id::text || '|' || v_uid::text, 'sha256'), 'hex');
  IF v_expected_hash != v_sig.otp_code_hash THEN
    UPDATE public.signatures_contrats SET otp_tentatives = otp_tentatives + 1, modifie_le = now() WHERE id = v_sig.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'OTP_INCORRECT', 'error', 'Code incorrect.', 'tentatives_restantes', 5 - (v_sig.otp_tentatives + 1));
  END IF;

  v_role := v_sig.signataire_role;
  v_ip := NULLIF(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', '')::inet;
  v_ua := current_setting('request.headers', true)::jsonb->>'user-agent';

  UPDATE public.signatures_contrats
     SET statut_signature = 'signe', otp_valide_a = now(), signe_a = now(),
         ip_signature = v_ip, user_agent = v_ua, hash_document = p_hash_document,
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
$function$;

REVOKE ALL ON FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_otp(uuid,text,text,text) TO authenticated, service_role;

-- NOW() rendait à tort cette fonction IMMUTABLE. Les intervalles sont
-- disjoints et une mission commencée prime sur toute fenêtre ou règle ASAP.
CREATE OR REPLACE FUNCTION public.fn_calculer_penalite_annulation_soignant(
  p_acceptee_a timestamptz,
  p_debut_mission timestamptz,
  p_est_asap boolean
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $function$
DECLARE
  v_delta_retract interval := now() - p_acceptee_a;
  v_delta_mission interval := p_debut_mission - now();
BEGIN
  IF v_delta_mission <= interval '0' THEN
    RETURN jsonb_build_object('libre', false, 'points', -30, 'motif', 'NO_SHOW', 'signalement_admin', true);
  END IF;
  IF v_delta_retract < interval '30 minutes' THEN
    RETURN jsonb_build_object('libre', true, 'points', 0, 'motif', 'fenetre_retractation_30min');
  END IF;
  IF p_est_asap AND v_delta_mission < interval '2 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -25, 'motif', 'ASAP_ANNULEE_APRES_FENETRE');
  END IF;
  IF v_delta_mission < interval '1 hour' THEN
    RETURN jsonb_build_object('libre', false, 'points', -30, 'motif', 'ANNULATION_MOINS_1H', 'signalement_admin', false);
  END IF;
  IF v_delta_mission < interval '12 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -10, 'motif', 'ANNULATION_1_12H');
  END IF;
  IF v_delta_mission < interval '24 hours' THEN
    RETURN jsonb_build_object('libre', false, 'points', -5, 'motif', 'ANNULATION_12_24H');
  END IF;
  RETURN jsonb_build_object('libre', true, 'points', 0, 'motif', 'neutre_delai_long');
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_calculer_penalite_annulation_soignant(timestamptz,timestamptz,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculer_penalite_annulation_soignant(timestamptz,timestamptz,boolean) TO authenticated, service_role;

ALTER TABLE public.evenements_score_soignant
  DROP CONSTRAINT evenements_score_soignant_type_evenement_check;
ALTER TABLE public.evenements_score_soignant
  ADD CONSTRAINT evenements_score_soignant_type_evenement_check CHECK (
    type_evenement = ANY (ARRAY[
      'ANNULATION_12_24H',
      'ANNULATION_1_12H',
      'ANNULATION_MOINS_1H',
      'ASAP_ANNULEE_APRES_FENETRE',
      'NO_SHOW',
      'LITIGE_TORT_RECONNU',
      'NOTE_BASSE_RECUE',
      'EVALUATION_NEGATIVE',
      'BONUS_AMBASSADEUR',
      'BONUS_FIDELITE',
      'FRAUDE_GPS',
      'AUTRE'
    ]::text[])
  );

-- Le frontend urgence tentait auparavant de réactiver directement une
-- candidature refusée/expirée. Cette mutation contournait la RPC métier et
-- était de toute façon rejetée par le trigger de transitions. La réactivation
-- devient atomique et réservée à fn_proposer_mission_soignant.
CREATE OR REPLACE FUNCTION public.fn_protect_candidature_statut()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  IF public.est_admin() THEN RETURN NEW; END IF;

  -- Les réponses à une proposition passent par la RPC canonique, qui pose ce
  -- contexte borné à la mission. Sans cette branche, le trigger confondrait la
  -- réponse du soignant avec une modification directe de sa candidature.
  IF current_setting('jolene.candidature_rpc_mission_id', true) = OLD.mission_id::text THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
      RAISE EXCEPTION 'Modification interdite';
    END IF;
    IF OLD.statut = 'PROPOSEE'
       AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE') THEN
      NEW.message := OLD.message;
      RETURN NEW;
    END IF;
    IF OLD.statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE')
       AND NEW.statut = 'REFUSEE' THEN
      NEW.message := OLD.message;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
  END IF;

  IF auth.uid() = OLD.soignant_id THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
    IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

    IF NEW.statut IS DISTINCT FROM OLD.statut THEN
      IF OLD.statut = 'EN_ATTENTE' AND NEW.statut = 'ANNULEE' THEN
        RETURN NEW;
      ELSIF OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut = 'ANNULEE' THEN
        RETURN NEW;
      ELSIF OLD.statut = 'ACCEPTEE' AND NEW.statut = 'ANNULEE'
            AND COALESCE(current_setting('jolene.annulation_soignant_ctx', true), '') = 'true' THEN
        RETURN NEW;
      ELSE
        RAISE EXCEPTION 'Vous ne pouvez pas modifier le statut de votre candidature (% → %)', OLD.statut, NEW.statut;
      END IF;
    END IF;

    IF NEW.message IS DISTINCT FROM OLD.message AND OLD.statut != 'EN_ATTENTE' THEN
      RAISE EXCEPTION 'Vous ne pouvez plus modifier votre message';
    END IF;

    NEW.motif_refus := OLD.motif_refus;
    NEW.traite_le := OLD.traite_le;
    RETURN NEW;
  END IF;

  IF public.mon_etablissement_id() IS NOT NULL THEN
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
    IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

    IF NEW.statut IS DISTINCT FROM OLD.statut THEN
      IF OLD.statut IN ('REFUSEE', 'EXPIREE', 'ANNULEE')
         AND NEW.statut = 'PROPOSEE'
         AND current_setting('jolene.candidature_reactivation_ctx', true)
             = OLD.mission_id::text || ':' || OLD.soignant_id::text THEN
        RETURN NEW;
      ELSIF NOT (
        (OLD.statut = 'EN_ATTENTE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
        OR (OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
        OR (OLD.statut = 'PROPOSEE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE'))
      ) THEN
        RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Accès refusé à cette candidature';
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_protect_candidature_statut() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_candidature_statut() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_proposer_mission_soignant(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_candidature_id uuid;
  v_candidature_statut text;
BEGIN
  SELECT * INTO v_mission FROM public.missions WHERE id = p_mission_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF NOT public.est_admin()
     AND v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object('error', 'La mission n’est plus ouverte');
  END IF;

  SELECT * INTO v_soignant
    FROM public.soignants
   WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant n’est pas compatible avec la profession requise par la mission (' ||
        v_mission.profession_requise::text || ').'
    );
  END IF;
  IF public.fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Ce soignant est dans votre liste d’exclusions.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id, p_soignant_id, p_choix_contrat
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';
  IF NOT public.fn_documents_ok_pour_mission(p_soignant_id, v_choix) THEN
    RETURN jsonb_build_object(
      'error', 'Ce soignant n’a pas encore les documents validés pour une mission ' || lower(v_choix) || '.',
      'documents_requis_pour', v_choix
    );
  END IF;

  UPDATE public.candidatures
     SET statut = 'EXPIREE', traite_le = now()
   WHERE mission_id = p_mission_id
     AND soignant_id = p_soignant_id
     AND statut = 'PROPOSEE'
     AND cree_le < now() - interval '2 hours';

  SELECT id, statut
    INTO v_candidature_id, v_candidature_statut
    FROM public.candidatures
   WHERE mission_id = p_mission_id
     AND soignant_id = p_soignant_id
   FOR UPDATE;

  IF FOUND AND v_candidature_statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE', 'ACCEPTEE') THEN
    RETURN jsonb_build_object('error', 'Cette mission a déjà été proposée à ce soignant.');
  END IF;

  IF v_candidature_id IS NULL THEN
    INSERT INTO public.candidatures(
      mission_id, soignant_id, statut, type_contrat_choisi
    ) VALUES (
      p_mission_id, p_soignant_id, 'PROPOSEE', v_choix
    ) RETURNING id INTO v_candidature_id;
  ELSE
    PERFORM set_config(
      'jolene.candidature_reactivation_ctx',
      p_mission_id::text || ':' || p_soignant_id::text,
      true
    );
    UPDATE public.candidatures
       SET statut = 'PROPOSEE',
           type_contrat_choisi = v_choix,
           traite_le = NULL,
           motif_refus = NULL,
           cree_le = now()
     WHERE id = v_candidature_id;
    PERFORM set_config('jolene.candidature_reactivation_ctx', '', true);
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := auth.uid(),
    p_type_acteur := CASE WHEN public.est_admin() THEN 'ADMIN' ELSE 'ADMIN_ETABLISSEMENT' END,
    p_action := 'MISSION_PROPOSEE_SOIGNANT',
    p_type_ressource := 'candidature',
    p_id_ressource := v_candidature_id,
    p_details := jsonb_build_object(
      'mission_id', p_mission_id,
      'soignant_id', p_soignant_id,
      'profession_requise', v_mission.profession_requise::text,
      'type_contrat_choisi', v_choix,
      'reactivation', v_candidature_statut IS NOT NULL
    )
  );

  INSERT INTO public.notifications(destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (
    p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Mission proposée',
    'Un établissement vous propose la mission « ' || public.fn_html_escape(v_mission.intitule) ||
      ' » en ' || lower(v_choix) || '.',
    '/soignant/missions/' || p_mission_id, 'SOIGNANT'
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_persiste', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'reactivation', v_candidature_statut IS NOT NULL
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_proposer_mission_soignant(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_proposer_mission_soignant(uuid,uuid,text) TO authenticated, service_role;

-- L'emploi temporaire d'un étudiant comme AS reste un emploi salarié dans un
-- établissement de santé ou médico-social, au sein d'une équipe comportant un
-- IDE pendant les activités. La confirmation visible dans l'interface est
-- aussi exigée et auditée par le serveur au moment exact de l'assignation.
DO $rename_planning$
BEGIN
  IF pg_catalog.to_regprocedure(
    'public.fn_traiter_candidature_planning_v1_internal_20260810(uuid,text,jsonb,text)'
  ) IS NULL THEN
    ALTER FUNCTION public.fn_traiter_candidature_planning_v1(uuid, text, jsonb, text)
      RENAME TO fn_traiter_candidature_planning_v1_internal_20260810;
  END IF;
END
$rename_planning$;

REVOKE ALL ON FUNCTION public.fn_traiter_candidature_planning_v1_internal_20260810(
  uuid, text, jsonb, text
) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_traiter_candidature_planning_v1(
  p_candidature_id uuid,
  p_decision text,
  p_creneaux_confirmes jsonb DEFAULT NULL::jsonb,
  p_motif text DEFAULT NULL::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_cadre record;
  v_temporaire_as boolean := false;
  v_result jsonb;
BEGIN
  SELECT
    c.soignant_id,
    c.type_contrat_choisi::text AS type_contrat_choisi,
    s.est_etudiant,
    s.scolarite_verifiee,
    s.scolarite_profession_autorisee::text AS profession_autorisee,
    s.profession::text AS profession,
    m.id AS mission_id,
    m.profession_requise::text AS profession_requise,
    m.type_contrat_recherche,
    m.etablissement_id,
    e.type::text AS type_etablissement
    INTO v_cadre
    FROM public.candidatures c
    JOIN public.soignants s ON s.id = c.soignant_id AND s.supprime_le IS NULL
    JOIN public.missions m ON m.id = c.mission_id
    JOIN public.etablissements e ON e.id = m.etablissement_id AND e.supprime_le IS NULL
   WHERE c.id = p_candidature_id;

  IF FOUND THEN
    v_temporaire_as := COALESCE(v_cadre.est_etudiant, false)
      AND COALESCE(v_cadre.scolarite_verifiee, false)
      AND v_cadre.profession_autorisee = 'AS';
  END IF;

  IF upper(btrim(COALESCE(p_decision, ''))) = 'ACCEPTEE' AND v_temporaire_as THEN
    IF v_cadre.profession <> 'AS' OR v_cadre.profession_requise <> 'AS' THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'CADRE_ETUDIANT_PROFESSION_INVALIDE',
        'error', 'Cette passerelle étudiante est limitée aux activités temporaires d’aide-soignant.'
      );
    END IF;
    IF v_cadre.type_contrat_recherche = 'LIBERAL'
       OR (v_cadre.type_contrat_recherche = 'TOUS' AND upper(COALESCE(v_cadre.type_contrat_choisi, '')) = 'LIBERAL') THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'CADRE_ETUDIANT_SALARIAT_REQUIS',
        'error', 'Un étudiant exerçant temporairement comme aide-soignant doit être recruté en salariat.'
      );
    END IF;
    IF v_cadre.type_etablissement NOT IN (
      'HOPITAL_PUBLIC', 'CLINIQUE_PRIVEE', 'EHPAD', 'SSIAD', 'HAD',
      'CENTRE_SANTE', 'IME', 'MAS', 'FAM', 'ESPIC'
    ) THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'CADRE_ETUDIANT_STRUCTURE_INELIGIBLE',
        'error', 'Cette passerelle étudiante est réservée aux établissements de santé et médico-sociaux éligibles.'
      );
    END IF;
    IF p_motif IS DISTINCT FROM 'CADRE_ETUDIANT_AS_CONFIRME' THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'CADRE_ETUDIANT_A_CONFIRMER',
        'error', 'Confirmez le salariat et la présence d’un infirmier diplômé d’État dans l’équipe pendant les activités.'
      );
    END IF;
  END IF;

  v_result := public.fn_traiter_candidature_planning_v1_internal_20260810(
    p_candidature_id,
    p_decision,
    p_creneaux_confirmes,
    p_motif
  );

  IF v_temporaire_as
     AND upper(btrim(COALESCE(p_decision, ''))) = 'ACCEPTEE'
     AND COALESCE((v_result->>'success')::boolean, false) THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := auth.uid(),
      p_type_acteur := 'ADMIN_ETABLISSEMENT',
      p_action := 'CADRE_ETUDIANT_AS_CONFIRME',
      p_type_ressource := 'mission',
      p_id_ressource := v_cadre.mission_id,
      p_details := jsonb_build_object(
        'candidature_id', p_candidature_id,
        'soignant_id', v_cadre.soignant_id,
        'contrat_salarie', true,
        'structure_eligible', v_cadre.type_etablissement,
        'ide_dans_equipe_pendant_activites', true
      )
    );
  END IF;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_traiter_candidature_planning_v1(
  uuid, text, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_traiter_candidature_planning_v1(
  uuid, text, jsonb, text
) TO authenticated, service_role;

-- Ces deux équivalences ne peuvent pas être déduites d'une seule année :
-- elles exigent des autorisations/stages/certificats distincts.
UPDATE public.equivalences_scolarite
   SET actif = false
 WHERE (formation = 'MEDECINE_DFASM' AND profession_autorisee::text = 'IDE')
    OR (formation = 'PHARMACIE' AND profession_autorisee::text = 'PHARMACIEN');

-- L'annexe I de l'arrêté du 3 février 2022 inclut aussi les étudiants en
-- pédicurie-podologie admis en deuxième année, sous conditions de crédits,
-- stages, UE et formation aux soins d'urgence. Cette filière manquait du
-- produit alors qu'elle est éligible au même emploi temporaire d'AS.
INSERT INTO public.equivalences_scolarite (
  formation, libelle_formation, annee_validee_min,
  profession_autorisee, base_reglementaire, actif
) VALUES (
  'PEDICURE_PODOLOGIE',
  'Pédicurie-podologie',
  1,
  'AS',
  'Arrêté du 3 février 2022, annexe I : admission en 2e année, 48 ECTS dont 9 de stages, UE requises, soins d’urgence niveau 2 et stage sanitaire ou médico-social de 4 semaines.',
  true
)
ON CONFLICT (formation, annee_validee_min, profession_autorisee) DO UPDATE
SET libelle_formation = EXCLUDED.libelle_formation,
    base_reglementaire = EXCLUDED.base_reglementaire,
    actif = true;

-- Le recalcul historique avait une liste fermée de cursus et ignorait donc la
-- pédicurie-podologie. On conserve son implémentation durcie, puis on complète
-- uniquement cette passerelle avec les mêmes preuves courantes et vérifiées.
DO $rename_preuves_etudiant$
BEGIN
  IF pg_catalog.to_regprocedure(
    'public.fn_recalculer_preuves_etudiant_internal_20260810(uuid)'
  ) IS NULL THEN
    ALTER FUNCTION public.fn_recalculer_preuves_etudiant(uuid)
      RENAME TO fn_recalculer_preuves_etudiant_internal_20260810;
  END IF;
END
$rename_preuves_etudiant$;

REVOKE ALL ON FUNCTION public.fn_recalculer_preuves_etudiant_internal_20260810(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_recalculer_preuves_etudiant_internal_20260810(uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_recalculer_preuves_etudiant(
  p_soignant_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_preuve record;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true),
    ''
  );
BEGIN
  PERFORM public.fn_recalculer_preuves_etudiant_internal_20260810(p_soignant_id);

  SELECT ds.id, ds.verifie_le, x.formation, x.annee_validee
    INTO v_preuve
    FROM public.documents_soignants ds
    JOIN public.soignants s
      ON s.id = ds.soignant_id
     AND s.supprime_le IS NULL
    CROSS JOIN LATERAL (
      SELECT
        upper(NULLIF(btrim(ds.resultat_ia->>'scolarite_formation'), '')) AS formation,
        CASE
          WHEN COALESCE(ds.resultat_ia->>'scolarite_annee_validee', '') ~ '^\d{1,2}$'
            THEN (ds.resultat_ia->>'scolarite_annee_validee')::integer
          ELSE NULL
        END AS annee_validee
    ) x
   WHERE ds.soignant_id = p_soignant_id
     AND s.profession = 'AS'
     AND ds.type_document = 'ATTESTATION_SCOLARITE'
     AND ds.statut_verification = 'VERIFIE'
     AND ds.supprime_le IS NULL
     AND ds.verifie_le IS NOT NULL
     AND ds.coherence_nom IS TRUE
     AND ds.valide_depuis BETWEEN current_date - 400 AND current_date
     AND (ds.valide_jusqua IS NULL OR ds.valide_jusqua > current_date)
     AND COALESCE(ds.resultat_ia->>'verdict_serveur', '') = 'VERIFIE'
     AND COALESCE(ds.resultat_ia->>'type_correspond', 'false') = 'true'
     AND COALESCE(ds.resultat_ia->>'document_lisible', 'false') = 'true'
     AND COALESCE(ds.resultat_ia->>'document_complet', 'false') = 'true'
     AND COALESCE(ds.resultat_ia->>'conditions_scolarite_confirmees', 'false') = 'true'
     AND x.formation = 'PEDICURE_PODOLOGIE'
     AND x.annee_validee BETWEEN 1 AND 3
     AND EXISTS (
       SELECT 1
         FROM public.fn_professions_autorisees_scolarite(
           x.formation,
           x.annee_validee
         ) AS autorisee(profession)
        WHERE autorisee.profession = s.profession
     )
   ORDER BY ds.valide_depuis DESC, ds.verifie_le DESC, ds.id DESC
   LIMIT 1;

  IF FOUND THEN
    PERFORM set_config('jolene.system_update', 'true', true);
    UPDATE public.soignants
       SET scolarite_formation = v_preuve.formation,
           scolarite_annee_validee = v_preuve.annee_validee,
           scolarite_profession_autorisee = 'AS',
           scolarite_verifiee = true,
           scolarite_verifiee_le = v_preuve.verifie_le,
           est_etudiant = true,
           modifie_le = now()
     WHERE id = p_soignant_id
       AND supprime_le IS NULL;
    PERFORM set_config('jolene.system_update', v_previous_system_update, true);
  END IF;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);
  RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_recalculer_preuves_etudiant(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_recalculer_preuves_etudiant(uuid)
  TO service_role;

-- Le contrôle humain affiché par l'interface doit également être imposé par
-- le serveur. On conserve l'implémentation durcie existante derrière un nom
-- interne et on expose une façade qui exige puis journalise l'attestation du
-- contrôle réglementaire pour les documents de scolarité.
DO $rename_moderation_document$
BEGIN
  IF pg_catalog.to_regprocedure(
    'public.fn_admin_moderer_document_internal_20260810(uuid,text,text,jsonb,text)'
  ) IS NULL THEN
    ALTER FUNCTION public.fn_admin_moderer_document(uuid, text, text, jsonb, text)
      RENAME TO fn_admin_moderer_document_internal_20260810;
  END IF;
END
$rename_moderation_document$;

REVOKE ALL ON FUNCTION public.fn_admin_moderer_document_internal_20260810(
  uuid, text, text, jsonb, text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_moderer_document(
  p_document_id uuid,
  p_action text,
  p_motif text,
  p_validation_manuelle jsonb,
  p_raison_override text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_type_document text;
  v_soignant_id uuid;
  v_result jsonb;
  v_previous_moderation text := COALESCE(
    current_setting('jolene.document_moderation_rpc', true),
    ''
  );
BEGIN
  SELECT type_document::text, soignant_id INTO v_type_document, v_soignant_id
    FROM public.documents_soignants
   WHERE id = p_document_id;

  IF upper(COALESCE(p_action, '')) = 'VALIDER'
     AND v_type_document = 'ATTESTATION_SCOLARITE'
     AND COALESCE(p_validation_manuelle -> 'conditions_scolarite_confirmees', 'false'::jsonb)
         IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'Confirmez le contrôle des crédits, stages, unités d’enseignement et attestations réglementaires : l’année seule ne suffit pas'
      USING ERRCODE = '23514';
  END IF;

  v_result := public.fn_admin_moderer_document_internal_20260810(
    p_document_id,
    p_action,
    p_motif,
    COALESCE(p_validation_manuelle, '{}'::jsonb) - 'conditions_scolarite_confirmees',
    p_raison_override
  );

  IF COALESCE((v_result ->> 'success')::boolean, false)
     AND upper(COALESCE(p_action, '')) = 'VALIDER'
     AND v_type_document = 'ATTESTATION_SCOLARITE' THEN
    PERFORM set_config('jolene.document_moderation_rpc', 'true', true);
    UPDATE public.documents_soignants
       SET resultat_ia = COALESCE(resultat_ia, '{}'::jsonb)
             || jsonb_build_object(
               'conditions_scolarite_confirmees', true,
               'conditions_scolarite_confirmees_le', now(),
               'conditions_scolarite_confirmees_par', auth.uid()
             )
     WHERE id = p_document_id;
    PERFORM set_config('jolene.document_moderation_rpc', v_previous_moderation, true);

    -- Le recalcul est rejoué après avoir persisté la confirmation humaine :
    -- les cursus qui exigent ce marqueur ne peuvent pas être ouverts avant.
    PERFORM public.fn_recalculer_preuves_etudiant(v_soignant_id);

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := auth.uid(),
      p_type_acteur := 'ADMIN',
      p_action := 'CONDITIONS_SCOLARITE_CONFIRMEES',
      p_type_ressource := 'document',
      p_id_ressource := p_document_id,
      p_details := jsonb_build_object(
        'controle', 'credits_stages_unites_attestations_reglementaires',
        'annee_seule_insuffisante', true
      )
    );
  END IF;

  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('jolene.document_moderation_rpc', v_previous_moderation, true);
  RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_moderer_document(
  uuid, text, text, jsonb, text
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_moderer_document(
  uuid, text, text, jsonb, text
) TO authenticated;

WITH reviewed(signature, qualified_signature, categorie, justification) AS (
  VALUES
    ('fn_envoyer_otp_signature(uuid)', 'public.fn_envoyer_otp_signature(uuid)', 'RPC_UTILISATEUR_AUTH_INTERNE', 'RPC authentifiée : chaque partie peut demander son OTP dans n’importe quel ordre, avec rate-limit et idempotence conservés.'),
    ('fn_signer_contrat_otp(uuid,text,text,text)', 'public.fn_signer_contrat_otp(uuid,text,text,text)', 'RPC_UTILISATEUR_AUTH_INTERNE', 'RPC authentifiée : signature OTP sérialisée et état partiel exact quel que soit l’ordre des parties.'),
    ('fn_protect_candidature_statut()', 'public.fn_protect_candidature_statut()', 'SERVICE_ONLY_REVOQUE', 'Trigger interne : protège les transitions de candidature et n’autorise une réactivation établissement que dans le contexte atomique de la RPC métier.'),
    ('fn_proposer_mission_soignant(uuid,uuid,text)', 'public.fn_proposer_mission_soignant(uuid,uuid,text)', 'MIXTE_TENANT_ADMIN', 'RPC établissement/admin : contrôle d’éligibilité complet et réactivation atomique des anciennes propositions, sans mutation directe du frontend.'),
    ('fn_traiter_candidature_planning_v1_internal_20260810(uuid,text,jsonb,text)', 'public.fn_traiter_candidature_planning_v1_internal_20260810(uuid,text,jsonb,text)', 'SERVICE_ONLY_REVOQUE', 'Implémentation durcie du traitement avec confirmation du planning exact, conservée derrière le garde réglementaire étudiant.'),
    ('fn_traiter_candidature_planning_v1(uuid,text,jsonb,text)', 'public.fn_traiter_candidature_planning_v1(uuid,text,jsonb,text)', 'MIXTE_TENANT_ADMIN', 'RPC établissement : bloque l’assignation d’un étudiant AS hors salariat, structure éligible ou confirmation de présence IDE, puis audite cette confirmation.'),
    ('fn_recalculer_preuves_etudiant_internal_20260810(uuid)', 'public.fn_recalculer_preuves_etudiant_internal_20260810(uuid)', 'SERVICE_ONLY_REVOQUE', 'Implémentation historique durcie du recalcul des preuves étudiantes, conservée derrière la façade complète.'),
    ('fn_recalculer_preuves_etudiant(uuid)', 'public.fn_recalculer_preuves_etudiant(uuid)', 'SERVICE_ONLY_REVOQUE', 'Recalcul documentaire serveur : complète la passerelle pédicurie-podologie uniquement après revue humaine réglementaire.'),
    ('fn_admin_moderer_document_internal_20260810(uuid,text,text,jsonb,text)', 'public.fn_admin_moderer_document_internal_20260810(uuid,text,text,jsonb,text)', 'SERVICE_ONLY_REVOQUE', 'Implémentation interne durcie de la modération documentaire, appelée uniquement par la façade contextualisée.'),
    ('fn_admin_moderer_document(uuid,text,text,jsonb,text)', 'public.fn_admin_moderer_document(uuid,text,text,jsonb,text)', 'ADMIN_EST_ADMIN_VALIDE', 'Façade back-office AAL2 : exige et journalise le contrôle réglementaire détaillé des attestations de scolarité avant validation.')
)
INSERT INTO private.security_definer_inventory (
  signature, categorie, definition_md5, justification, recense_le
)
SELECT r.signature, r.categorie, pg_catalog.md5(p.prosrc), r.justification, now()
  FROM reviewed r
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(r.qualified_signature)
 WHERE p.prosecdef IS TRUE
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

NOTIFY pgrst, 'reload schema';

COMMIT;
