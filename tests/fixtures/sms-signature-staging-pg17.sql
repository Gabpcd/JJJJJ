-- Synthetic fixture, only loaded by the guarded PG17 CI witness.
-- No provider or pg_net. net.fixture_requests is a local SQL double.
BEGIN;
SET LOCAL statement_timeout='20s';
CREATE TEMP TABLE sms_observations(name text PRIMARY KEY,passed boolean NOT NULL);

CREATE FUNCTION pg_temp.seed_sms(who text,p_expired boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql AS $seed$
BEGIN
 DELETE FROM private.signature_sms_test_capacities;
 DELETE FROM private.sms_dispatch_idempotency;
 DELETE FROM net.fixture_requests;
 PERFORM pg_temp.seed_signature(who);
 UPDATE auth.users SET raw_app_meta_data=raw_app_meta_data||'{"est_compte_test":true}',
   deleted_at=NULL,banned_until=NULL,email_confirmed_at=now();
 UPDATE public.soignants SET telephone='+33600000001',est_compte_test=true,supprime_le=NULL,statut_compte='ACTIF';
 UPDATE public.etablissements SET telephone_contact='+33600000002',est_compte_test=true,supprime_le=NULL;
 INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,soignant_assigne_id)
 VALUES('f1040000-0000-4000-8000-000000000004','f1040000-0000-4000-8000-000000000002','Mission synthétique','IDE',now()+interval '1 day',now()+interval '1 day 1 hour',1,'f1040000-0000-4000-8000-000000000001')
 ON CONFLICT(id) DO UPDATE SET etablissement_id=excluded.etablissement_id,soignant_assigne_id=excluded.soignant_assigne_id;
 INSERT INTO public.preferences_notifications(utilisateur_id,canal_sms)
 VALUES('f1040000-0000-4000-8000-000000000001',true),('f1040000-0000-4000-8000-000000000002',true)
 ON CONFLICT(utilisateur_id) DO UPDATE SET canal_sms=true;
 UPDATE public.signatures_contrats SET sms_envoyes_count=1,sms_premier_envoi_a=now(),otp_envoye_a=now();
 INSERT INTO private.signature_sms_test_capacities(id,project_ref,run_id,source_sha,manifest_sha256,enabled,installed_at,expires_at,
   mission_id,contrat_id,document_sha256,soignant_id,etablissement_id,soignant_phone,etablissement_phone,twilio_account_sid,sender_phone)
 SELECT 'f1040000-0000-4000-8000-000000000008','mejpriaetwgtcstbgfid','sms-signature-pg17-synthetic',repeat('a',40),repeat('b',64),true,
   clock_timestamp()-interval '30 minutes',clock_timestamp()+CASE WHEN p_expired THEN interval '-1 minute' ELSE interval '25 minutes' END,
   mission_id,id,hash_document,soignant_id,etablissement_id,'+33600000001','+33600000002','AC'||repeat('a',32),'+33100000000'
 FROM public.contrats_mission;
END;
$seed$;

CREATE FUNCTION pg_temp.sms_photo() RETURNS jsonb LANGUAGE sql AS $photo$
 SELECT jsonb_build_object('capacity',(SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM private.signature_sms_test_capacities c),
   'contracts',(SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.contrats_mission c),
   'signatures',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.signatures_contrats s),
   'ledger',(SELECT jsonb_agg(to_jsonb(l) ORDER BY idempotency_key) FROM private.sms_dispatch_idempotency l),
   'http',(SELECT jsonb_agg(to_jsonb(r)) FROM net.fixture_requests r));
$photo$;

CREATE FUNCTION pg_temp.sms_admission() RETURNS jsonb LANGUAGE plpgsql AS $admit$
DECLARE r jsonb;
BEGIN
 SET LOCAL ROLE authenticated;
 r:=public.fn_admission_otp_signature_recette('f1040000-0000-4000-8000-000000000003');
 RESET ROLE;
 RETURN r;
END;
$admit$;

CREATE FUNCTION pg_temp.sms_reserve(p_fingerprint text DEFAULT repeat('d',64),p_run text DEFAULT 'sms-signature-pg17-synthetic')
RETURNS jsonb LANGUAGE plpgsql AS $reserve$
DECLARE r jsonb; s public.signatures_contrats; key text;
BEGIN
 SELECT * INTO STRICT s FROM public.signatures_contrats WHERE signataire_user_id=auth.uid();
 key:='otp-signature.'||s.contrat_id::text||'.'||s.signataire_user_id::text||'.'||s.signataire_role||'.'
  ||extract(epoch FROM s.sms_premier_envoi_a)::bigint::text||'.'||s.sms_envoyes_count::text;
 SET LOCAL ROLE service_role;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 r:=public.fn_reserver_sms_signature_recette(p_run,repeat('a',40),repeat('b',64),s.contrat_id,
  'f1040000-0000-4000-8000-000000000004',s.signataire_user_id,
  CASE WHEN s.signataire_role='soignant' THEN '+33600000001' ELSE '+33600000002' END,
  s.otp_code_hash,key,p_fingerprint,'AC'||repeat('a',32),'+33100000000');
 RESET ROLE;
 RETURN r;
END;
$reserve$;

DO $cases$
DECLARE who text; actor uuid; r jsonb; a jsonb; before jsonb; denied boolean; mutation text; label text; key text; code text; h text; used integer; n integer; sig record;
 cid uuid:='f1040000-0000-4000-8000-000000000003';
BEGIN
 IF has_function_privilege('anon','public.fn_admission_otp_signature_recette(uuid)','EXECUTE')
  OR has_function_privilege('service_role','public.fn_admission_otp_signature_recette(uuid)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.fn_admission_otp_signature_recette(uuid)','EXECUTE')
  OR has_function_privilege('anon','public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text)','EXECUTE')
  OR NOT has_function_privilege('service_role','public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'SMS_RPC_ACL_INVALID'; END IF;
 FOREACH label IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF has_table_privilege(label,'private.signature_sms_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    OR has_function_privilege(label,'private.fn_signature_sms_test_scope(uuid,uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'SMS_PRIVATE_CAPACITY_EXPOSED'; END IF;
  denied:=false;
  EXECUTE 'SET LOCAL ROLE '||quote_ident(label);
  BEGIN PERFORM id FROM private.signature_sms_test_capacities;
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  RESET ROLE;
  IF denied IS NOT TRUE THEN RAISE EXCEPTION 'SMS_CAPACITY_DIRECT_READ_ALLOWED'; END IF;
 END LOOP;
 INSERT INTO sms_observations VALUES('closed-capacity-and-rpc-acl',true);

 FOREACH who IN ARRAY ARRAY['soignant','etablissement'] LOOP
  actor:=CASE WHEN who='soignant' THEN 'f1040000-0000-4000-8000-000000000001'::uuid ELSE 'f1040000-0000-4000-8000-000000000002'::uuid END;
  PERFORM pg_temp.seed_sms(who);
  a:=pg_temp.sms_admission();
  IF a->'admitted' IS DISTINCT FROM 'true'::jsonb OR a->'can_send' IS DISTINCT FROM 'true'::jsonb OR (a->>'remaining')::int<>2
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k NOT IN('admitted','can_send','can_validate','remaining','expires_at'))
  THEN RAISE EXCEPTION 'SMS_ADMISSION_INITIAL_INVALID'; END IF;
  INSERT INTO sms_observations VALUES('initial-caller-bound-admission-'||who,true);

  FOREACH label IN ARRAY ARRAY['disabled','revoked','expired','phone-drift','not-test-profile','not-test-auth','banned','deleted-auth','deleted-profile','preference-off','mission-actor-drift','document-drift','project-drift'] LOOP
   PERFORM pg_temp.seed_sms(who,label='expired');
   IF label='disabled' THEN UPDATE private.signature_sms_test_capacities SET enabled=false;
   ELSIF label='revoked' THEN UPDATE private.signature_sms_test_capacities SET enabled=false,revoked_at=clock_timestamp();
   ELSIF label='phone-drift' THEN UPDATE public.soignants SET telephone='+33600000009';
   ELSIF label='not-test-profile' THEN UPDATE public.soignants SET est_compte_test=false;
   ELSIF label='not-test-auth' THEN UPDATE auth.users SET raw_app_meta_data=raw_app_meta_data||'{"est_compte_test":false}' WHERE id=actor;
   ELSIF label='banned' THEN UPDATE auth.users SET banned_until=now()+interval '1 hour' WHERE id=actor;
   ELSIF label='deleted-auth' THEN UPDATE auth.users SET deleted_at=now() WHERE id=actor;
   ELSIF label='deleted-profile' THEN UPDATE public.soignants SET supprime_le=now();
   ELSIF label='preference-off' THEN UPDATE public.preferences_notifications SET canal_sms=false WHERE utilisateur_id=actor;
   ELSIF label='mission-actor-drift' THEN UPDATE public.missions SET soignant_assigne_id=NULL;
   ELSIF label='document-drift' THEN UPDATE public.contrats_mission SET hash_document=repeat('e',64);
   ELSIF label='project-drift' THEN UPDATE vault.decrypted_secrets SET decrypted_secret='https://flripxtsyegjshnhzjkz.supabase.co' WHERE name='supabase_url'; END IF;
   before:=pg_temp.sms_photo();
   a:=pg_temp.sms_admission();
   denied:=false;
   BEGIN PERFORM pg_temp.sms_reserve(); EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='SIGNATURE_SMS_TEST_SCOPE_REFUSED'; END;
   IF a->'admitted' IS DISTINCT FROM 'false'::jsonb OR denied IS NOT TRUE OR pg_temp.sms_photo() IS DISTINCT FROM before
   THEN RAISE EXCEPTION 'SMS_SCOPE_DENIAL_MUTATED_OR_ALLOWED'; END IF;
   UPDATE vault.decrypted_secrets SET decrypted_secret='https://mejpriaetwgtcstbgfid.supabase.co' WHERE name='supabase_url';
   INSERT INTO sms_observations VALUES('scope-refuses-'||who||'-'||label,true);
  END LOOP;

  PERFORM pg_temp.seed_sms(who);
  before:=pg_temp.sms_photo(); denied:=false;
  BEGIN PERFORM pg_temp.sms_reserve(repeat('d',64),'sms-signature-foreign-run');
  EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='SIGNATURE_SMS_TEST_MANIFEST_REFUSED'; END;
  IF denied IS NOT TRUE OR pg_temp.sms_photo() IS DISTINCT FROM before THEN RAISE EXCEPTION 'SMS_MANIFEST_NOT_BOUND'; END IF;
  INSERT INTO sms_observations VALUES('manifest-run-refused-'||who,true);

  PERFORM set_config('request.jwt.claim.sub','f1040000-0000-4000-8000-000000000099',true);
  a:=pg_temp.sms_admission();
  IF a IS DISTINCT FROM '{"admitted":false}'::jsonb THEN RAISE EXCEPTION 'SMS_FOREIGN_ACTOR_ADMITTED'; END IF;
  INSERT INTO sms_observations VALUES('foreign-actor-gets-no-admission-detail-'||who,true);

  FOREACH label IN ARRAY ARRAY['EN_COURS','ENVOYE','INDETERMINE','CONFLIT'] LOOP
   PERFORM pg_temp.seed_sms(who);
   r:=pg_temp.sms_reserve();
   IF r->>'statut'<>'RESERVE' THEN RAISE EXCEPTION 'SMS_FIRST_RESERVATION_FAILED'; END IF;
   IF label IN('ENVOYE','INDETERMINE') THEN
    SELECT idempotency_key INTO key FROM private.sms_dispatch_idempotency;
    SET LOCAL ROLE service_role;
    PERFORM public.fn_finaliser_envoi_sms_idempotent(key,repeat('d',64),label,'SM'||repeat('a',32),NULL);
    RESET ROLE;
   END IF;
   before:=pg_temp.sms_photo();
   r:=pg_temp.sms_reserve(CASE WHEN label='CONFLIT' THEN repeat('e',64) ELSE repeat('d',64) END);
   IF r->>'statut' IS DISTINCT FROM (CASE WHEN label='ENVOYE' THEN 'DEJA_ENVOYE' ELSE label END)
     OR pg_temp.sms_photo() IS DISTINCT FROM before
   THEN RAISE EXCEPTION 'SMS_IDEMPOTENCE_MUTATED_OR_REPEATED'; END IF;
   INSERT INTO sms_observations VALUES('idempotence-keeps-'||who||'-'||label,true);
  END LOOP;

  PERFORM pg_temp.seed_sms(who); r:=pg_temp.sms_reserve();
  SELECT idempotency_key INTO key FROM private.sms_dispatch_idempotency;
  FOR n IN 1..2 LOOP
   SET LOCAL ROLE service_role;
   PERFORM public.fn_finaliser_envoi_sms_idempotent(key,repeat('d',64),'ERREUR',NULL,'synthetic provider rejection');
   RESET ROLE;
   IF n=1 THEN
    r:=pg_temp.sms_reserve();
    IF r->>'statut'<>'RESERVE' THEN RAISE EXCEPTION 'SMS_EXPLICIT_FAILURE_NOT_RETRYABLE'; END IF;
   ELSE
    before:=pg_temp.sms_photo(); denied:=false;
    BEGIN PERFORM pg_temp.sms_reserve();
    EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='SIGNATURE_SMS_TEST_BUDGET_EXHAUSTED'; END;
    IF denied IS NOT TRUE OR pg_temp.sms_photo() IS DISTINCT FROM before
    THEN RAISE EXCEPTION 'SMS_FAILURE_RETRY_ESCAPED_BUDGET'; END IF;
   END IF;
  END LOOP;
  INSERT INTO sms_observations VALUES('explicit-failure-retry-consumes-budget-and-rolls-back-on-exhaustion-'||who,true);

  -- Two real sender RPC executions, SQL HTTP doubles and real reservations.
  -- On return from SMS #2, validate its current OTP despite remaining=0.
  PERFORM pg_temp.seed_sms(who); DELETE FROM public.signatures_contrats;
  FOR n IN 1..2 LOOP
   SET LOCAL ROLE authenticated;
   r:=public.fn_envoyer_otp_signature(cid);
   RESET ROLE;
   IF r->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'SMS_SENDER_RPC_FAILED'; END IF;
   r:=pg_temp.sms_reserve();
   IF r->>'statut'<>'RESERVE' THEN RAISE EXCEPTION 'SMS_PROVIDER_RESERVATION_FAILED'; END IF;
   SELECT idempotency_key INTO key FROM private.sms_dispatch_idempotency WHERE statut='EN_COURS';
   SET LOCAL ROLE service_role;
   PERFORM public.fn_finaliser_envoi_sms_idempotent(key,repeat('d',64),'ENVOYE','SM'||repeat('a',32),NULL);
   RESET ROLE;
  END LOOP;
  a:=pg_temp.sms_admission();
  IF a->'admitted' IS DISTINCT FROM 'true'::jsonb OR a->'can_send' IS DISTINCT FROM 'false'::jsonb
    OR a->'can_validate' IS DISTINCT FROM 'true'::jsonb OR (a->>'remaining')::int<>0
  THEN RAISE EXCEPTION 'SMS_SECOND_OTP_NOT_ADMITTED_AT_ZERO_BUDGET'; END IF;
  FOREACH mutation IN ARRAY ARRAY[
   'UPDATE public.signatures_contrats SET otp_envoye_a=now()-interval ''11 minutes''',
   'UPDATE public.signatures_contrats SET otp_tentatives=5',
   'UPDATE public.signatures_contrats SET otp_code_hash=NULL'
  ] LOOP
   -- Roll back only the invalid-code mutation; preserve the real second OTP.
   BEGIN
    EXECUTE mutation;
    a:=pg_temp.sms_admission();
    IF a->'admitted' IS DISTINCT FROM 'false'::jsonb OR a->'can_validate' IS DISTINCT FROM 'false'::jsonb
    THEN RAISE EXCEPTION 'SMS_INVALID_OTP_ADMITTED_WITH_ZERO_BUDGET'; END IF;
    RAISE EXCEPTION 'SMS_FIXTURE_RESTORE';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'SMS_FIXTURE_RESTORE' THEN RAISE; END IF; END;
  END LOOP;
  INSERT INTO sms_observations VALUES('zero-budget-invalid-current-otp-refused-'||who,true);
  before:=pg_temp.sms_photo();
  SET LOCAL ROLE authenticated;
  r:=public.fn_envoyer_otp_signature(cid);
  RESET ROLE;
  IF r->'success' IS DISTINCT FROM 'false'::jsonb OR pg_temp.sms_photo() IS DISTINCT FROM before
  THEN RAISE EXCEPTION 'SMS_ZERO_BUDGET_RESEND_MUTATED_OTP'; END IF;
  SELECT substring(body->>'contenu' from ' ([0-9]{6}) ') INTO STRICT code FROM net.fixture_requests WHERE body->>'idempotency_key'=key;
  SELECT hash_document INTO h FROM public.contrats_mission WHERE id=cid;
  SET LOCAL ROLE authenticated;
  r:=public.fn_signer_contrat_otp(cid,code,h,NULL);
  RESET ROLE;
  IF r->'success' IS DISTINCT FROM 'true'::jsonb OR (SELECT count(*) FROM net.fixture_requests)<>2
   OR NOT EXISTS(SELECT 1 FROM public.signatures_contrats WHERE statut_signature='signe' AND signataire_user_id=actor AND hash_document=h)
  THEN RAISE EXCEPTION 'SMS_SECOND_OTP_SIGNATURE_FAILED'; END IF;
  INSERT INTO sms_observations VALUES('second-sms-zero-budget-no-resend-valid-signature-'||who,true);
 END LOOP;

 FOREACH mutation IN ARRAY ARRAY[
  'UPDATE private.signature_sms_test_capacities SET source_sha=repeat(''e'',40)',
  'UPDATE private.signature_sms_test_capacities SET expires_at=expires_at+interval ''1 minute''',
  'UPDATE private.signature_sms_test_capacities SET soignant_phone=''+33600000009''',
  'UPDATE private.signature_sms_test_capacities SET soignant_attempts=0'
 ] LOOP
  PERFORM pg_temp.seed_sms('soignant'); UPDATE private.signature_sms_test_capacities SET soignant_attempts=1;
  before:=pg_temp.sms_photo(); denied:=false;
  BEGIN EXECUTE mutation; EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='SIGNATURE_SMS_TEST_IMMUTABLE'; END;
  IF denied IS NOT TRUE OR pg_temp.sms_photo() IS DISTINCT FROM before THEN RAISE EXCEPTION 'SMS_IMMUTABILITY_FAILED'; END IF;
 END LOOP;
 INSERT INTO sms_observations VALUES('immutable-identity-expiry-phone-monotone-budget',true);
 PERFORM pg_temp.seed_sms('soignant'); UPDATE private.signature_sms_test_capacities SET enabled=false,revoked_at=clock_timestamp();
 before:=pg_temp.sms_photo(); denied:=false;
 BEGIN UPDATE private.signature_sms_test_capacities SET revoked_at=NULL,enabled=true;
 EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='SIGNATURE_SMS_TEST_IMMUTABLE'; END;
 IF denied IS NOT TRUE OR pg_temp.sms_photo() IS DISTINCT FROM before THEN RAISE EXCEPTION 'SMS_REVOCATION_REVERSED'; END IF;
 INSERT INTO sms_observations VALUES('revocation-is-irreversible',true);
END;
$cases$;
SELECT jsonb_object_agg(name,passed) FROM sms_observations;
COMMIT;
