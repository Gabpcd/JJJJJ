-- STAGING-ONLY supplement. Not a production migration, allocator or activation.
-- The future reviewed executor must independently pin project and source SHA.
DO $sms_preflight$
BEGIN
 IF current_user <> 'postgres' OR current_setting('server_version_num')::integer/10000 <> 17
   OR to_regclass('private.signature_sms_test_capacities') IS NOT NULL
   OR (SELECT count(*) FROM vault.decrypted_secrets WHERE name='supabase_url') <> 1
   OR (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='supabase_url')
      IS DISTINCT FROM 'https://mejpriaetwgtcstbgfid.supabase.co'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_envoyer_otp_signature(uuid)'::regprocedure)
      IS DISTINCT FROM '786555c2ebd4bf148204b18cb48e9c1c'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='private.fn_reserver_envoi_sms_idempotent(text,text)'::regprocedure)
      IS DISTINCT FROM 'ced587d411ae661141166122ce6b83c6'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='private.fn_finaliser_envoi_sms_idempotent(text,text,text,text,text)'::regprocedure)
      IS DISTINCT FROM '4b5c611c5c678a9e007348c1d0ee5fea'
   OR EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid IN ('public.fn_envoyer_otp_signature(uuid)'::regprocedure,
     'private.fn_reserver_envoi_sms_idempotent(text,text)'::regprocedure,
     'private.fn_finaliser_envoi_sms_idempotent(text,text,text,text,text)'::regprocedure)
     AND (NOT p.prosecdef OR p.proowner<>'postgres'::regrole
       OR has_function_privilege('anon',p.oid,'EXECUTE') OR NOT has_function_privilege('service_role',p.oid,'EXECUTE')
       OR has_function_privilege('authenticated',p.oid,'EXECUTE') IS DISTINCT FROM (p.oid='public.fn_envoyer_otp_signature(uuid)'::regprocedure)))
 THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_INSTALLATION_REFUSED'; END IF;
END; $sms_preflight$;

CREATE TABLE private.signature_sms_test_capacities (
 id uuid PRIMARY KEY,
 project_ref text NOT NULL CHECK(project_ref='mejpriaetwgtcstbgfid'),
 run_id text NOT NULL UNIQUE CHECK(run_id ~ '^sms-signature-[a-z0-9-]{8,64}$'),
 source_sha text NOT NULL CHECK(source_sha ~ '^[a-f0-9]{40}$'),
 manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[a-f0-9]{64}$'),
 enabled boolean NOT NULL DEFAULT false,
 installed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 revoked_at timestamptz,
 mission_id uuid NOT NULL UNIQUE REFERENCES public.missions(id),
 contrat_id uuid NOT NULL UNIQUE REFERENCES public.contrats_mission(id),
 document_sha256 text NOT NULL CHECK(document_sha256 ~ '^[a-f0-9]{64}$'),
 soignant_id uuid NOT NULL REFERENCES public.soignants(id),
 etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
 soignant_phone text NOT NULL CHECK(soignant_phone ~ '^\+[1-9][0-9]{7,14}$'),
 etablissement_phone text NOT NULL CHECK(etablissement_phone ~ '^\+[1-9][0-9]{7,14}$'),
 twilio_account_sid text NOT NULL CHECK(twilio_account_sid ~ '^AC[0-9a-fA-F]{32}$'),
 sender_phone text NOT NULL CHECK(sender_phone ~ '^\+[1-9][0-9]{7,14}$'),
 max_attempts_per_actor smallint NOT NULL DEFAULT 2 CHECK(max_attempts_per_actor=2),
 soignant_attempts smallint NOT NULL DEFAULT 0 CHECK(soignant_attempts BETWEEN 0 AND 2),
 etablissement_attempts smallint NOT NULL DEFAULT 0 CHECK(etablissement_attempts BETWEEN 0 AND 2),
 CHECK(soignant_id<>etablissement_id),
 CHECK(expires_at>installed_at AND expires_at<=installed_at+interval '60 minutes'),
 CHECK(revoked_at IS NULL OR enabled IS FALSE)
);
ALTER TABLE private.signature_sms_test_capacities OWNER TO postgres;
ALTER TABLE private.signature_sms_test_capacities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.signature_sms_test_capacities FROM PUBLIC,anon,authenticated,service_role;
CREATE UNIQUE INDEX signature_sms_test_one_active_run
 ON private.signature_sms_test_capacities(project_ref) WHERE enabled AND revoked_at IS NULL;

CREATE FUNCTION private.fn_signature_sms_test_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $immutable$
BEGIN
 IF (to_jsonb(NEW)-ARRAY['enabled','revoked_at','soignant_attempts','etablissement_attempts'])
      IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['enabled','revoked_at','soignant_attempts','etablissement_attempts'])
   OR NEW.soignant_attempts<OLD.soignant_attempts OR NEW.etablissement_attempts<OLD.etablissement_attempts
   OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at)
   OR (NEW.enabled AND NOT OLD.enabled AND (OLD.soignant_attempts>0 OR OLD.etablissement_attempts>0))
   OR (NEW.revoked_at IS NOT NULL AND (NEW.revoked_at<NEW.installed_at OR NEW.revoked_at>clock_timestamp()))
 THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_IMMUTABLE'; END IF;
 RETURN NEW;
END; $immutable$;
CREATE TRIGGER signature_sms_test_immutable BEFORE UPDATE ON private.signature_sms_test_capacities
 FOR EACH ROW EXECUTE FUNCTION private.fn_signature_sms_test_immutable();

CREATE FUNCTION private.fn_signature_sms_test_telephone(p_raw text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $phone$
DECLARE v text := regexp_replace(COALESCE(p_raw,''),'[[:space:]().-]','','g');
BEGIN
 IF left(v,2)='00' THEN v:='+'||substr(v,3);
 ELSIF left(v,1)='0' THEN v:='+33'||substr(v,2);
 ELSIF left(v,1)<>'+' THEN v:='+33'||v; END IF;
 IF v !~ '^\+[1-9][0-9]{7,14}$' THEN RETURN NULL; END IF;
 RETURN v;
END; $phone$;

-- Scope returns private data only to owner functions; no client grant.
CREATE FUNCTION private.fn_signature_sms_test_scope(p_contrat_id uuid,p_actor_id uuid)
RETURNS private.signature_sms_test_capacities LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $scope$
DECLARE c private.signature_sms_test_capacities; actor_phone text;
BEGIN
 SELECT * INTO STRICT c FROM private.signature_sms_test_capacities WHERE contrat_id=p_contrat_id;
 actor_phone:=CASE p_actor_id WHEN c.soignant_id THEN c.soignant_phone WHEN c.etablissement_id THEN c.etablissement_phone END;
 IF actor_phone IS NULL OR c.project_ref<>'mejpriaetwgtcstbgfid'
   OR NOT c.enabled OR c.revoked_at IS NOT NULL OR c.installed_at>clock_timestamp() OR c.expires_at<=clock_timestamp()
   OR (SELECT count(*) FROM vault.decrypted_secrets WHERE name='supabase_url')<>1
   OR (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='supabase_url')
       IS DISTINCT FROM 'https://mejpriaetwgtcstbgfid.supabase.co'
   OR NOT EXISTS(SELECT 1 FROM public.soignants s JOIN public.etablissements e ON e.id=c.etablissement_id
     WHERE s.id=c.soignant_id AND s.est_compte_test IS TRUE AND e.est_compte_test IS TRUE
       AND s.supprime_le IS NULL AND e.supprime_le IS NULL AND s.statut_compte::text='ACTIF'
       AND private.fn_signature_sms_test_telephone(s.telephone)=c.soignant_phone
       AND private.fn_signature_sms_test_telephone(e.telephone_contact)=c.etablissement_phone)
   OR (SELECT count(*) FROM auth.users u WHERE u.id IN(c.soignant_id,c.etablissement_id)
       AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
       AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
       AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb)<>2
   OR NOT EXISTS(SELECT 1 FROM public.contrats_mission cm JOIN public.missions m ON m.id=c.mission_id
       WHERE cm.id=c.contrat_id AND cm.mission_id=m.id
         AND cm.soignant_id=c.soignant_id AND cm.etablissement_id=c.etablissement_id
         AND m.soignant_assigne_id=c.soignant_id AND m.etablissement_id=c.etablissement_id
         AND cm.statut NOT IN('ANNULE','EXPIRE','REFUSE','SIGNE_COMPLET')
         AND NULLIF(btrim(cm.storage_path),'') IS NOT NULL AND cm.contenu_html_rendu_le IS NOT NULL
         AND NULLIF(btrim(cm.contenu_html),'') IS NOT NULL
         AND cm.contenu_html !~ '\{\{[[:space:]]*[^}]+[[:space:]]*\}\}'
         AND cm.hash_document=c.document_sha256
         AND encode(extensions.digest(convert_to(cm.contenu_html,'UTF8'),'sha256'),'hex')=c.document_sha256
         AND CASE WHEN p_actor_id=c.soignant_id THEN cm.signature_soignant IS NOT TRUE ELSE cm.signature_etablissement IS NOT TRUE END)
   OR NOT EXISTS(SELECT 1 FROM public.preferences_notifications p WHERE p.utilisateur_id=p_actor_id AND p.canal_sms IS TRUE)
 THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_SCOPE_REFUSED'; END IF;
 RETURN c;
END; $scope$;

-- Explicit caller-bound disclosure: no recipient phone, provider or capacity ID.
CREATE FUNCTION public.fn_admission_otp_signature_recette(p_contrat_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $admission$
DECLARE c private.signature_sms_test_capacities; used smallint; actor_role text; can_validate boolean; otp_expires_at timestamptz;
BEGIN
 IF auth.uid() IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN RETURN jsonb_build_object('admitted',false); END IF;
 c:=private.fn_signature_sms_test_scope(p_contrat_id,auth.uid());
 used:=CASE WHEN auth.uid()=c.soignant_id THEN c.soignant_attempts ELSE c.etablissement_attempts END;
 actor_role:=CASE WHEN auth.uid()=c.soignant_id THEN 'soignant' ELSE 'etablissement' END;
 SELECT s.otp_envoye_a+interval '10 minutes' INTO otp_expires_at FROM public.signatures_contrats s
   WHERE s.contrat_id=c.contrat_id AND s.signataire_user_id=auth.uid() AND s.signataire_role=actor_role
     AND s.statut_signature='otp_envoye' AND s.signe_a IS NULL AND s.otp_valide_a IS NULL
     AND s.otp_code_hash ~ '^[0-9a-f]{64}$' AND COALESCE(s.otp_tentatives,0)<5
     AND s.sms_envoyes_count BETWEEN 1 AND 3 AND s.sms_premier_envoi_a IS NOT NULL
     AND s.otp_envoye_a<=clock_timestamp() AND s.otp_envoye_a>clock_timestamp()-interval '10 minutes';
 can_validate:=otp_expires_at IS NOT NULL;
 RETURN jsonb_build_object('admitted',used<c.max_attempts_per_actor OR can_validate,
   'can_send',used<c.max_attempts_per_actor,'can_validate',can_validate,'otp_expires_at',otp_expires_at,
   'expires_at',c.expires_at,'remaining',c.max_attempts_per_actor-used);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('admitted',false);
END; $admission$;
REVOKE ALL ON FUNCTION public.fn_admission_otp_signature_recette(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.fn_admission_otp_signature_recette(uuid) TO authenticated;

-- Called only by service-role Edge after exact runtime/payload validation.
-- Contract -> capacity -> signature -> existing ledger is the lock order.
CREATE FUNCTION public.fn_reserver_sms_signature_recette(
 p_run_id text,p_source_sha text,p_manifest_sha256 text,p_contrat_id uuid,p_mission_id uuid,p_actor_id uuid,
 p_telephone text,p_otp_hash text,p_idempotency_key text,p_request_fingerprint text,
 p_twilio_account_sid text,p_sender_phone text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $reserve$
DECLARE c private.signature_sms_test_capacities; sig public.signatures_contrats; r jsonb; expected_key text; actor_role text; used smallint;
BEGIN
 IF COALESCE(current_setting('request.jwt.claim.role',true),'')<>'service_role'
   AND COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role' IS DISTINCT FROM 'service_role'
 THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_SERVICE_ONLY'; END IF;
 PERFORM 1 FROM public.contrats_mission WHERE id=p_contrat_id FOR UPDATE;
 SELECT * INTO STRICT c FROM private.signature_sms_test_capacities WHERE contrat_id=p_contrat_id FOR UPDATE;
 c:=private.fn_signature_sms_test_scope(p_contrat_id,p_actor_id);
 actor_role:=CASE WHEN p_actor_id=c.soignant_id THEN 'soignant' ELSE 'etablissement' END;
 used:=CASE WHEN p_actor_id=c.soignant_id THEN c.soignant_attempts ELSE c.etablissement_attempts END;
 IF c.run_id IS DISTINCT FROM p_run_id OR c.source_sha IS DISTINCT FROM p_source_sha
   OR c.mission_id IS DISTINCT FROM p_mission_id
   OR c.manifest_sha256 IS DISTINCT FROM p_manifest_sha256 OR c.twilio_account_sid IS DISTINCT FROM p_twilio_account_sid
   OR c.sender_phone IS DISTINCT FROM p_sender_phone
   OR p_telephone IS DISTINCT FROM (CASE WHEN p_actor_id=c.soignant_id THEN c.soignant_phone ELSE c.etablissement_phone END)
 THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_MANIFEST_REFUSED'; END IF;
 SELECT * INTO STRICT sig FROM public.signatures_contrats
   WHERE contrat_id=p_contrat_id AND signataire_user_id=p_actor_id AND signataire_role=actor_role FOR UPDATE;
 expected_key:='otp-signature.'||p_contrat_id::text||'.'||p_actor_id::text||'.'||actor_role||'.'
   ||extract(epoch FROM sig.sms_premier_envoi_a)::bigint::text||'.'||sig.sms_envoyes_count::text;
 IF p_otp_hash IS NULL OR p_otp_hash !~ '^[a-f0-9]{64}$'
   OR p_idempotency_key IS DISTINCT FROM expected_key OR p_otp_hash IS DISTINCT FROM sig.otp_code_hash
   OR sig.statut_signature IS DISTINCT FROM 'otp_envoye' OR sig.signe_a IS NOT NULL OR sig.otp_valide_a IS NOT NULL
   OR sig.otp_envoye_a IS NULL OR sig.otp_envoye_a>clock_timestamp() OR sig.otp_envoye_a<=clock_timestamp()-interval '10 minutes'
   OR sig.sms_envoyes_count NOT BETWEEN 1 AND 3
 THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_OTP_REFUSED'; END IF;
 r:=private.fn_reserver_envoi_sms_idempotent(p_idempotency_key,p_request_fingerprint);
 IF r->>'statut'='RESERVE' THEN
   IF used>=c.max_attempts_per_actor THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_BUDGET_EXHAUSTED'; END IF;
   UPDATE private.signature_sms_test_capacities
     SET soignant_attempts=soignant_attempts+CASE WHEN p_actor_id=c.soignant_id THEN 1 ELSE 0 END,
       etablissement_attempts=etablissement_attempts+CASE WHEN p_actor_id=c.etablissement_id THEN 1 ELSE 0 END
     WHERE id=c.id;
 END IF;
 RETURN r;
END; $reserve$;
REVOKE ALL ON FUNCTION public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text) TO service_role;

REVOKE ALL ON FUNCTION private.fn_signature_sms_test_telephone(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_signature_sms_test_scope(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_signature_sms_test_immutable() FROM PUBLIC,anon,authenticated,service_role;

DO $sms_postflight$
BEGIN
 IF EXISTS(SELECT 1 FROM private.signature_sms_test_capacities)
   OR has_table_privilege('service_role','private.signature_sms_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_table_privilege('authenticated','private.signature_sms_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_table_privilege('anon','private.signature_sms_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
 THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_NOT_CLOSED'; END IF;
END; $sms_postflight$;
