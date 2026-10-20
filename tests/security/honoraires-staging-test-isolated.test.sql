\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $guard$ BEGIN
 IF current_setting('jolene.isolated_sql_test',true) IS DISTINCT FROM 'on'
  OR EXISTS(SELECT FROM pg_tables WHERE schemaname='public' AND tablename='missions') THEN
  RAISE EXCEPTION 'BANQUE_SQL_VIDE_EXCLUSIVEMENT'; END IF;
END $guard$;
CREATE SCHEMA private;
CREATE SCHEMA auth;
CREATE SCHEMA vault;
CREATE SCHEMA net;
CREATE SCHEMA cron;
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
CREATE TABLE public.etablissements(id uuid PRIMARY KEY,nom text);
CREATE TABLE public.soignants(id uuid PRIMARY KEY,mandat_facturation_signe boolean,mandat_facturation_version text,statut_tva_honoraires text DEFAULT 'FRANCHISE_EN_BASE');
CREATE TABLE public.missions(id uuid PRIMARY KEY,etablissement_id uuid,soignant_assigne_id uuid,statut text,type_contrat_applique text,type_paiement_soignant text,
 mode_remuneration text,strategie_facturation text,montant_honoraires_bruts numeric,honoraires_confirmes_le timestamptz,
 debut_le timestamptz,fin_le timestamptz,net_a_payer numeric,total_brut numeric,compte_reel boolean DEFAULT true,
 est_arret_maladie boolean DEFAULT false,remplacement_de_mission_id uuid,
 statut_validation_tva text DEFAULT 'CONFIRMEE',nature_tva_prestation text DEFAULT 'SOIN_THERAPEUTIQUE_EXONERE',
 nature_tva_confirmee_soignant text DEFAULT 'SOIN_THERAPEUTIQUE_EXONERE',nature_tva_confirmee_par uuid);
CREATE TABLE public.presences(mission_id uuid,valide_par_etablissement boolean,pointage_depart_le timestamptz,motif_litige text);
CREATE TABLE public.mission_creneaux(mission_id uuid,debut timestamptz,fin timestamptz,est_pause boolean,type_creneau text);
CREATE TABLE public.factures_honoraires(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),mission_id uuid,soignant_id uuid,etablissement_id uuid,
 numero_facture text,montant_ht numeric,montant_tva numeric,montant_ttc numeric,taux_tva numeric,exoneration_tva boolean,
 date_emission date,date_echeance date,statut text,mandat_version text,periode_debut date,periode_fin date,numero_semaine_iso smallint,annee_iso smallint,
 type_document text DEFAULT 'FACTURE',nature_correction text DEFAULT 'ORIGINALE',est_facture_finale_mission boolean DEFAULT true,
 template_version text DEFAULT 'v1',regime_tva_snapshot text,emise_le timestamptz,pdf_s3_key text,facturx_xml_url text);
CREATE TABLE public.factures(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),mission_id uuid,etablissement_id uuid,facture_honoraire_id uuid,type_document text,statut text);
CREATE TABLE public.factures_honoraires_documents(facture_honoraire_id uuid,pdf_s3_key text,facturx_xml_url text,pdf_sha256 text,xml_sha256 text);
CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,categorie text,definition_md5 text,justification text,recense_le timestamptz);
CREATE TABLE vault.decrypted_secrets(name text,decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES('supabase_url','https://recette.invalid'),('cron_automations_key','fictif');
CREATE TABLE net.requests(id bigint GENERATED ALWAYS AS IDENTITY,body jsonb,headers jsonb,url text);
CREATE TABLE net._http_response(id bigint PRIMARY KEY,status_code integer,timed_out boolean,error_msg text);
CREATE TABLE cron.job(jobid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,jobname text UNIQUE,active boolean,schedule text,command text);
CREATE FUNCTION cron.alter_job(job_id bigint,active boolean) RETURNS void LANGUAGE sql AS $$ UPDATE cron.job SET active=$2 WHERE jobid=$1 $$;
CREATE FUNCTION net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint; BEGIN
 IF url NOT IN (SELECT 'https://recette.invalid/functions/v1/'||x FROM unnest(ARRAY['litige-escalation-cron','email-cron','process-stripe-refunds','escrow-debit-echeance','escrow-release','process-externalisation-actions','weekly-invoicing-cron'])x) OR headers->>'x-jolene-cron-secret'<>'fictif' OR timeout_milliseconds<>55000 THEN RAISE EXCEPTION 'TRANSPORT_INATTENDU'; END IF;
 INSERT INTO net.requests(body,headers,url) VALUES(body,headers,url) RETURNING id INTO n;RETURN n;END $$;
CREATE TABLE private.cron_edge_execution_log(request_id bigint,job_name text,endpoint text,est_sonde_auth boolean,demande_le timestamptz DEFAULT now());
\ir fixtures/honoraires-emission-avant-correctif.sql
-- Disposable PG17 only. These structures model the read-only admission boundary;
-- the real 1075 producer, termination trigger, lease and acknowledgement are used.
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
ALTER TABLE public.soignants ADD est_compte_test boolean DEFAULT true, ADD supprime_le timestamptz,
 ADD statut_compte text DEFAULT 'ACTIF', ADD type_exercice text DEFAULT 'LIBERAL', ADD defacto_opt_in boolean DEFAULT false;
ALTER TABLE public.etablissements ADD est_compte_test boolean DEFAULT true, ADD supprime_le timestamptz,
 ADD est_secteur_public boolean DEFAULT false, ADD chorus_pro_actif boolean DEFAULT false;
ALTER TABLE public.missions ADD intitule text DEFAULT 'TEST documentaire', ADD stripe_payment_intent_id text, ADD stripe_transfer_id text;
ALTER TABLE public.presences ADD soignant_id uuid;
CREATE TABLE auth.users(id uuid PRIMARY KEY,deleted_at timestamptz,email_confirmed_at timestamptz,banned_until timestamptz,raw_app_meta_data jsonb);
CREATE TABLE public.contrats_mission(mission_id uuid,soignant_id uuid,etablissement_id uuid,statut text,
 signature_soignant boolean,signature_etablissement boolean,hash_document text,storage_path text,contenu_html text);
CREATE TABLE public.stripe_transfers(mission_id uuid);
CREATE TABLE public.stripe_payment_flow_claims(resource_key text);
CREATE TABLE private.stripe_connect_avant_transfert(mission_id uuid);
CREATE TABLE private.stripe_connect_release_gate(enabled boolean);
INSERT INTO private.stripe_connect_release_gate VALUES(false);
CREATE TABLE private.stripe_connect_test_capacities(enabled boolean);
CREATE TABLE private.signature_sms_test_capacities(enabled boolean);
CREATE TABLE cron.job_run_details(status text);
CREATE TABLE net.http_request_queue(id bigint);
-- Canonical predicate from 20260729121442, not a forced true/false test stub.
CREATE FUNCTION private.fn_mission_est_reelle(p_mission_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE m.id = p_mission_id
       AND e.est_compte_test IS FALSE
       AND COALESCE(s.est_compte_test, false) IS FALSE
  ), false);
$function$;
\ir ../../supabase/migrations/20261018180050_emettre_honoraires_par_generation_canonique.sql
UPDATE vault.decrypted_secrets SET decrypted_secret='https://mejpriaetwgtcstbgfid.supabase.co' WHERE name='supabase_url';
\ir ../../scripts/ci/honoraires-staging-test.sql

INSERT INTO public.soignants(id,mandat_facturation_signe,mandat_facturation_version) VALUES('abba3c93-5408-47bf-96e3-0864c7de3cb7',true,'1.4');
INSERT INTO public.etablissements(id,nom) VALUES('fcaa6c97-46c1-4da9-8f74-1395aed616c5','TEST');
INSERT INTO auth.users(id,email_confirmed_at,raw_app_meta_data)
SELECT id,now(),jsonb_build_object('role',role,'est_compte_test',true,
 'jolene_connect_fixture_owner','connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915','etablissement_id','fcaa6c97-46c1-4da9-8f74-1395aed616c5')
FROM (VALUES('abba3c93-5408-47bf-96e3-0864c7de3cb7'::uuid,'SOIGNANT'),('fcaa6c97-46c1-4da9-8f74-1395aed616c5'::uuid,'ADMIN_ETABLISSEMENT')) x(id,role);
INSERT INTO public.missions(id,etablissement_id,soignant_assigne_id,statut,type_contrat_applique,mode_remuneration,strategie_facturation,debut_le,fin_le,net_a_payer,total_brut,nature_tva_confirmee_par)
VALUES('11111111-1111-4111-8111-111111111111','fcaa6c97-46c1-4da9-8f74-1395aed616c5','abba3c93-5408-47bf-96e3-0864c7de3cb7','EN_COURS','LIBERAL','TAUX_HORAIRE','FINALE_UNIQUE',now()-interval '1 hour',now()-interval '10 minutes',20,20,'abba3c93-5408-47bf-96e3-0864c7de3cb7');
INSERT INTO public.mission_creneaux VALUES('11111111-1111-4111-8111-111111111111',now()-interval '1 hour',now()-interval '10 minutes',false,'EFFECTIF');
INSERT INTO public.contrats_mission VALUES('11111111-1111-4111-8111-111111111111','abba3c93-5408-47bf-96e3-0864c7de3cb7','fcaa6c97-46c1-4da9-8f74-1395aed616c5','SIGNE_COMPLET',true,true,
 encode(extensions.digest(convert_to('TEST contrat signe','UTF8'),'sha256'),'hex'),'fixture.html','TEST contrat signe');
-- The real trigger creates the request; admission never inserts a request.
UPDATE public.missions SET statut='TERMINEE' WHERE id='11111111-1111-4111-8111-111111111111';
DO $$ BEGIN
 IF (SELECT count(*) FROM private.demandes_facturation_honoraires)<>1
 OR EXISTS(SELECT FROM public.factures_honoraires)
 OR public.fn_prendre_demandes_facturation_honoraires(3)<>'[]'::jsonb
 THEN RAISE EXCEPTION 'PRODUCER_OR_TEST_ISOLATION_BROKEN'; END IF;
 IF EXISTS(SELECT FROM private.honoraires_test_capacities)
 OR has_table_privilege('service_role','private.honoraires_test_capacities','SELECT,INSERT,UPDATE,DELETE')
 OR has_function_privilege('anon','public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid)','EXECUTE')
 OR has_function_privilege('authenticated','public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'INSTALL_NOT_CLOSED'; END IF;
END $$;
INSERT INTO private.honoraires_test_capacities(id,project_ref,source_sha,manifest_sha256,fixture_owner,soignant_id,etablissement_id,mission_id,created_at,expires_at)
VALUES('22222222-2222-4222-8222-222222222222','mejpriaetwgtcstbgfid',repeat('a',40),repeat('b',64),
 'connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915','abba3c93-5408-47bf-96e3-0864c7de3cb7','fcaa6c97-46c1-4da9-8f74-1395aed616c5','11111111-1111-4111-8111-111111111111',now(),now()+interval '30 minutes');
CREATE FUNCTION pg_temp.recipe(action text,token uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.fn_demande_honoraires_recette(id,mission_id,source_sha,manifest_sha256,created_at,expires_at,action,token) FROM private.honoraires_test_capacities
$$;
CREATE FUNCTION pg_temp.refused(command text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM=expected THEN RETURN; END IF; RAISE;
 END;
 RAISE EXCEPTION 'EXPECTED_REFUSAL_MISSING: %',expected;
END $$;
SELECT pg_temp.refused($q$SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_SCOPE_REFUSED');
UPDATE private.honoraires_test_capacities SET enabled=true;
-- Each failing admission rolls back its fixture alteration, without a lease.
SELECT pg_temp.refused($q$UPDATE auth.users SET raw_app_meta_data=raw_app_meta_data-'jolene_connect_fixture_owner'; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE auth.users SET raw_app_meta_data=jsonb_set(raw_app_meta_data,'{est_compte_test}','false'); SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.soignants SET est_compte_test=false; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.etablissements SET est_compte_test=false; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.soignants SET defacto_opt_in=true; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.soignants SET mandat_facturation_signe=false; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.missions SET strategie_facturation='HEBDO_ET_FINALE'; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.missions SET nature_tva_confirmee_par=gen_random_uuid(); SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.contrats_mission SET contenu_html='modifie'; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE public.etablissements SET est_secteur_public=true; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_COHORT_REFUSED');
SELECT pg_temp.refused($q$UPDATE vault.decrypted_secrets SET decrypted_secret='https://flripxtsyegjshnhzjkz.supabase.co' WHERE name='supabase_url'; SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_SCOPE_REFUSED');
SELECT pg_temp.refused($q$SELECT set_config('request.jwt.claims','{"role":"authenticated"}',true); SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_SCOPE_REFUSED');
SELECT pg_temp.refused($q$INSERT INTO cron.job(jobname,active) VALUES('fictif',true); SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_ENVIRONMENT_REFUSED');
SELECT pg_temp.refused($q$INSERT INTO net.http_request_queue VALUES(1); SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_ENVIRONMENT_REFUSED');
SELECT pg_temp.refused($q$INSERT INTO private.signature_sms_test_capacities VALUES(true); SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_OTHER_CAPACITY');
SELECT pg_temp.refused($q$UPDATE private.honoraires_test_capacities SET source_sha=repeat('c',40)$q$,'HONORAIRES_TEST_IMMUTABLE');
SELECT pg_temp.refused($q$UPDATE private.honoraires_test_capacities SET expires_at=expires_at+interval '1 minute'$q$,'HONORAIRES_TEST_IMMUTABLE');
SELECT pg_temp.refused($q$DELETE FROM private.honoraires_test_capacities$q$,'HONORAIRES_TEST_IMMUTABLE');
DO $lease$
DECLARE r jsonb;t uuid;
BEGIN
 IF (SELECT tentatives FROM private.demandes_facturation_honoraires)<>0 THEN RAISE EXCEPTION 'REFUSAL_RESERVED_A_LEASE'; END IF;
 r:=pg_temp.recipe('PRENDRE');t:=(r->>'token')::uuid;
 IF r->>'state'<>'PRISE' OR r->>'invoke'<>'true' OR t IS NULL THEN RAISE EXCEPTION 'FIRST_LEASE_REFUSED'; END IF;
 IF pg_temp.recipe('PRENDRE')->>'state'<>'OCCUPEE' THEN RAISE EXCEPTION 'LEASE_REENTERED'; END IF;
 PERFORM pg_temp.refused($q$SELECT pg_temp.recipe('INVOQUER',gen_random_uuid())$q$,'HONORAIRES_TEST_INVOCATION_REFUSED');
 IF pg_temp.recipe('INVOQUER',t)->>'state'<>'AUTORISEE' THEN RAISE EXCEPTION 'INVOCATION_REFUSED'; END IF;
 PERFORM pg_temp.refused(format('SELECT pg_temp.recipe(''INVOQUER'',%L)',t),'HONORAIRES_TEST_INVOCATION_REFUSED');
 PERFORM pg_temp.refused($q$UPDATE private.honoraires_test_capacities SET invocation_started_at=NULL$q$,'HONORAIRES_TEST_IMMUTABLE');
 -- Simulate response loss: never invoke again, even after the old lease expires.
 UPDATE private.demandes_facturation_honoraires SET expire_le=clock_timestamp()-interval '1 second';
 r:=pg_temp.recipe('PRENDRE');t:=(r->>'token')::uuid;
 IF r->>'invoke'<>'false' THEN RAISE EXCEPTION 'AMBIGUOUS_RESPONSE_REINVOKED'; END IF;
 IF public.fn_constater_demande_facturation_honoraires('11111111-1111-4111-8111-111111111111',t)->>'success'<>'false' THEN RAISE EXCEPTION 'NO_DOCUMENTS_ACKNOWLEDGED'; END IF;
END $lease$;
-- Document rows below are SQL fixtures, NOT generated/downloaded PDF evidence.
INSERT INTO public.factures_honoraires(id,mission_id,soignant_id,etablissement_id,statut,template_version,regime_tva_snapshot,emise_le,pdf_s3_key,facturx_xml_url)
VALUES('44444444-4444-4444-8444-444444444444','11111111-1111-4111-8111-111111111111','abba3c93-5408-47bf-96e3-0864c7de3cb7','fcaa6c97-46c1-4da9-8f74-1395aed616c5','EMISE','v2_facturx','EXONERE_ART_261_4_1',now(),'fixture.pdf','fixture.xml');
INSERT INTO public.factures_honoraires_documents VALUES('44444444-4444-4444-8444-444444444444','fixture.pdf','fixture.xml',repeat('a',64),repeat('b',64));
INSERT INTO public.factures(id,mission_id,etablissement_id,facture_honoraire_id,type_document,statut)
VALUES('55555555-5555-4555-8555-555555555555','11111111-1111-4111-8111-111111111111','fcaa6c97-46c1-4da9-8f74-1395aed616c5','44444444-4444-4444-8444-444444444444','FACTURE','EMISE');
UPDATE private.demandes_facturation_honoraires SET prochain_essai_le=clock_timestamp();
DO $ack$
DECLARE r jsonb;t uuid;before_state jsonb;
BEGIN
 r:=pg_temp.recipe('PRENDRE');t:=(r->>'token')::uuid;
 IF r->>'invoke'<>'false' THEN RAISE EXCEPTION 'REPLAY_REINVOKED'; END IF;
 IF public.fn_constater_demande_facturation_honoraires('11111111-1111-4111-8111-111111111111',t)->>'success'<>'true' THEN RAISE EXCEPTION 'CANONICAL_ACK_FAILED'; END IF;
 SELECT to_jsonb(d) INTO before_state FROM private.demandes_facturation_honoraires d;
 r:=pg_temp.recipe('PRENDRE');
 IF r->>'state'<>'TERMINEE' OR (r->>'facture_id')::uuid<>'44444444-4444-4444-8444-444444444444'
 OR (SELECT to_jsonb(d) FROM private.demandes_facturation_honoraires d) IS DISTINCT FROM before_state
 OR (SELECT count(*) FROM public.factures_honoraires)<>1 OR (SELECT count(*) FROM public.factures)<>1
 OR EXISTS(SELECT FROM net.requests) OR EXISTS(SELECT FROM cron.job WHERE active)
 THEN RAISE EXCEPTION 'REPLAY_CHANGED_DOCUMENTS_OR_LEASE'; END IF;
END $ack$;
UPDATE private.honoraires_test_capacities SET enabled=false,revoked_at=clock_timestamp();
SELECT pg_temp.refused($q$SELECT pg_temp.recipe('PRENDRE')$q$,'HONORAIRES_TEST_SCOPE_REFUSED');
SELECT pg_temp.refused($q$UPDATE private.honoraires_test_capacities SET enabled=true,revoked_at=NULL$q$,'HONORAIRES_TEST_IMMUTABLE');
ROLLBACK;
