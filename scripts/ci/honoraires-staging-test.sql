-- STAGE-only recipe supplement, NEVER a production migration.
-- Install empty in one operator transaction after independent project/source checks.
-- No cron, fixture, business row, capability allocation or activation is performed.
DO $install$
BEGIN
 IF current_user<>'postgres' OR current_setting('server_version_num')::integer/10000<>17
   OR to_regclass('private.honoraires_test_capacities') IS NOT NULL
   OR to_regprocedure('public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,text,uuid)') IS NOT NULL
   OR (SELECT count(*) FROM vault.decrypted_secrets WHERE name='supabase_url')<>1
   OR (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='supabase_url')
       IS DISTINCT FROM 'https://mejpriaetwgtcstbgfid.supabase.co'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_prendre_demandes_facturation_honoraires(integer)'::regprocedure)
       IS DISTINCT FROM 'c54107abc9d233ab3d85038b99503b28'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_constater_demande_facturation_honoraires(uuid,uuid)'::regprocedure)
       IS DISTINCT FROM 'd013cf6c035a535ea30c470346a4240a'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_generer_facture_honoraires_mission(uuid)'::regprocedure)
       IS DISTINCT FROM 'ad246c8483393c6e1ad02020de90e71d'
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_INSTALLATION_REFUSED'; END IF;
END $install$;

CREATE TABLE private.honoraires_test_capacities (
 id uuid PRIMARY KEY,
 project_ref text NOT NULL CHECK(project_ref='mejpriaetwgtcstbgfid'),
 source_sha text NOT NULL CHECK(source_sha ~ '^[a-f0-9]{40}$'),
 manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[a-f0-9]{64}$'),
 fixture_owner text NOT NULL CHECK(fixture_owner='connect-test-ci-36975875132-1:c3e2db2cb986c81a58e4c39010c33b487dc14915'),
 soignant_id uuid NOT NULL REFERENCES public.soignants(id)
   CHECK(soignant_id='abba3c93-5408-47bf-96e3-0864c7de3cb7'),
 etablissement_id uuid NOT NULL REFERENCES public.etablissements(id)
   CHECK(etablissement_id='fcaa6c97-46c1-4da9-8f74-1395aed616c5'),
 mission_id uuid NOT NULL UNIQUE REFERENCES public.missions(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 enabled boolean NOT NULL DEFAULT false,
 revoked_at timestamptz,
 invocation_started_at timestamptz,
 CHECK(expires_at>created_at AND expires_at<=created_at+interval '60 minutes'),
 CHECK(revoked_at IS NULL OR enabled IS FALSE)
);
ALTER TABLE private.honoraires_test_capacities OWNER TO postgres;
ALTER TABLE private.honoraires_test_capacities ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.honoraires_test_capacities FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.honoraires_test_capacities FROM PUBLIC,anon,authenticated,service_role;
CREATE UNIQUE INDEX honoraires_test_one_active ON private.honoraires_test_capacities(project_ref)
 WHERE enabled AND revoked_at IS NULL;

CREATE FUNCTION private.fn_honoraires_test_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $immutable$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'HONORAIRES_TEST_IMMUTABLE'; END IF;
 IF (to_jsonb(NEW)-ARRAY['enabled','revoked_at','invocation_started_at'])
     IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['enabled','revoked_at','invocation_started_at'])
   OR (OLD.invocation_started_at IS NOT NULL AND NEW.invocation_started_at IS DISTINCT FROM OLD.invocation_started_at)
   OR (NEW.invocation_started_at IS NOT NULL AND (NEW.invocation_started_at<NEW.created_at OR NEW.invocation_started_at>clock_timestamp()))
   OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at)
   OR (NEW.enabled AND NOT OLD.enabled AND (OLD.invocation_started_at IS NOT NULL OR OLD.revoked_at IS NOT NULL))
   OR (NEW.revoked_at IS NOT NULL AND (NEW.revoked_at<NEW.created_at OR NEW.revoked_at>clock_timestamp()))
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_IMMUTABLE'; END IF;
 RETURN NEW;
END $immutable$;
ALTER FUNCTION private.fn_honoraires_test_immutable() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.fn_honoraires_test_immutable() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER honoraires_test_immutable BEFORE UPDATE OR DELETE ON private.honoraires_test_capacities
 FOR EACH ROW EXECUTE FUNCTION private.fn_honoraires_test_immutable();

CREATE FUNCTION public.fn_demande_honoraires_recette(
 p_capacity_id uuid,p_mission_id uuid,p_source_sha text,p_manifest_sha256 text,
 p_created_at timestamptz,p_expires_at timestamptz,p_action text,p_token uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET timezone='UTC' AS $recipe$
DECLARE
 cap private.honoraires_test_capacities%ROWTYPE;
 demande private.demandes_facturation_honoraires%ROWTYPE;
 bail uuid; relation text; active_other boolean;
BEGIN
 -- The Edge credential check is not a substitute for RPC-level service auth.
 IF COALESCE(auth.jwt()->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role'
   OR p_action IS NULL OR p_action NOT IN('PRENDRE','INVOQUER')
   OR (SELECT count(*) FROM vault.decrypted_secrets WHERE name='supabase_url')<>1
   OR (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='supabase_url')
       IS DISTINCT FROM 'https://mejpriaetwgtcstbgfid.supabase.co'
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_SCOPE_REFUSED' USING ERRCODE='42501'; END IF;
 SELECT * INTO cap FROM private.honoraires_test_capacities c WHERE c.id=p_capacity_id FOR UPDATE;
 IF NOT FOUND OR NOT cap.enabled OR cap.revoked_at IS NOT NULL
   OR cap.created_at>clock_timestamp() OR cap.expires_at<=clock_timestamp()
   OR cap.mission_id IS DISTINCT FROM p_mission_id OR cap.source_sha IS DISTINCT FROM p_source_sha
   OR cap.manifest_sha256 IS DISTINCT FROM p_manifest_sha256
   OR cap.created_at IS DISTINCT FROM p_created_at OR cap.expires_at IS DISTINCT FROM p_expires_at
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_SCOPE_REFUSED'; END IF;

 -- Read-only admission conditions. No scheduling, draining or transport here.
 IF EXISTS(SELECT FROM cron.job WHERE active)
   OR EXISTS(SELECT FROM cron.job_run_details WHERE status IN('starting','running'))
   OR EXISTS(SELECT FROM net.http_request_queue)
   OR (SELECT count(*) FROM private.stripe_connect_release_gate)<>1
   OR EXISTS(SELECT FROM private.stripe_connect_release_gate WHERE enabled)
   OR EXISTS(SELECT FROM private.demandes_facturation_honoraires d
     WHERE d.mission_id<>cap.mission_id AND d.terminee_le IS NULL AND d.expire_le>clock_timestamp())
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_prendre_demandes_facturation_honoraires(integer)'::regprocedure)
       IS DISTINCT FROM 'c54107abc9d233ab3d85038b99503b28'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_constater_demande_facturation_honoraires(uuid,uuid)'::regprocedure)
       IS DISTINCT FROM 'd013cf6c035a535ea30c470346a4240a'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_generer_facture_honoraires_mission(uuid)'::regprocedure)
       IS DISTINCT FROM 'ad246c8483393c6e1ad02020de90e71d'
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_ENVIRONMENT_REFUSED'; END IF;
 FOREACH relation IN ARRAY ARRAY['private.stripe_connect_test_capacities','private.signature_sms_test_capacities'] LOOP
  IF to_regclass(relation) IS NOT NULL THEN
   EXECUTE format('SELECT EXISTS(SELECT FROM %s WHERE enabled)',to_regclass(relation)) INTO active_other;
   IF active_other THEN RAISE EXCEPTION 'HONORAIRES_TEST_OTHER_CAPACITY'; END IF;
  END IF;
 END LOOP;
 IF NOT EXISTS(SELECT FROM public.soignants s JOIN public.etablissements e ON e.id=cap.etablissement_id
   WHERE s.id=cap.soignant_id AND s.est_compte_test IS TRUE AND e.est_compte_test IS TRUE
     AND s.supprime_le IS NULL AND e.supprime_le IS NULL AND s.statut_compte::text='ACTIF'
     AND s.type_exercice::text IN('LIBERAL','MIXTE') AND s.mandat_facturation_signe IS TRUE
     AND s.mandat_facturation_version='1.4' AND COALESCE(s.defacto_opt_in,false) IS FALSE
     AND e.est_secteur_public IS FALSE AND e.chorus_pro_actif IS FALSE)
   OR (SELECT count(*) FROM auth.users u WHERE u.id IN(cap.soignant_id,cap.etablissement_id)
     AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
     AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
     AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
     AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=cap.fixture_owner
     AND u.raw_app_meta_data->>'role'=CASE WHEN u.id=cap.soignant_id THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END
     AND (u.id=cap.soignant_id OR u.raw_app_meta_data->>'etablissement_id'=cap.etablissement_id::text))<>2
   OR private.fn_mission_est_reelle(cap.mission_id) IS DISTINCT FROM false
   OR NOT EXISTS(SELECT FROM public.missions m WHERE m.id=cap.mission_id
     AND m.etablissement_id=cap.etablissement_id AND m.soignant_assigne_id=cap.soignant_id
     AND m.statut='TERMINEE' AND m.type_contrat_applique='LIBERAL'
     AND m.mode_remuneration='TAUX_HORAIRE' AND m.strategie_facturation='FINALE_UNIQUE'
     AND m.intitule LIKE 'TEST%' AND m.stripe_payment_intent_id IS NULL AND m.stripe_transfer_id IS NULL
     AND m.statut_validation_tva='CONFIRMEE' AND m.nature_tva_confirmee_par=cap.soignant_id
     AND m.nature_tva_confirmee_soignant=m.nature_tva_prestation)
   OR NOT EXISTS(SELECT FROM public.contrats_mission c WHERE c.mission_id=cap.mission_id
     AND c.soignant_id=cap.soignant_id AND c.etablissement_id=cap.etablissement_id
     AND c.statut='SIGNE_COMPLET' AND c.signature_soignant IS TRUE AND c.signature_etablissement IS TRUE
     AND c.hash_document ~ '^[a-f0-9]{64}$' AND nullif(c.storage_path,'') IS NOT NULL
     AND encode(extensions.digest(convert_to(c.contenu_html,'UTF8'),'sha256'),'hex')=c.hash_document)
   OR EXISTS(SELECT FROM public.presences p WHERE p.mission_id=cap.mission_id
     AND (p.soignant_id<>cap.soignant_id OR p.valide_par_etablissement IS NOT TRUE
       OR p.pointage_depart_le IS NULL OR p.motif_litige IS NOT NULL))
   OR NOT EXISTS(SELECT FROM public.mission_creneaux c WHERE c.mission_id=cap.mission_id AND c.type_creneau='EFFECTIF' AND NOT c.est_pause AND c.fin IS NOT NULL)
   OR EXISTS(SELECT FROM public.mission_creneaux c WHERE c.mission_id=cap.mission_id AND c.type_creneau='EFFECTIF' AND c.fin IS NULL)
   OR EXISTS(SELECT FROM public.stripe_transfers t WHERE t.mission_id=cap.mission_id)
   OR EXISTS(SELECT FROM private.stripe_connect_avant_transfert o WHERE o.mission_id=cap.mission_id)
   OR EXISTS(SELECT FROM public.stripe_payment_flow_claims c WHERE c.resource_key='MISSION:'||cap.mission_id::text)
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_COHORT_REFUSED'; END IF;

 -- Only the durable request produced by the real termination trigger is used.
 -- Lock order capacity -> request. The regular taker never locks a capacity.
 SELECT * INTO demande FROM private.demandes_facturation_honoraires d WHERE d.mission_id=cap.mission_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'HONORAIRES_TEST_REQUEST_MISSING'; END IF;
 IF demande.terminee_le IS NOT NULL THEN
  IF p_action<>'PRENDRE' OR cap.invocation_started_at IS NULL THEN RAISE EXCEPTION 'HONORAIRES_TEST_STATE_REFUSED'; END IF;
  RETURN jsonb_build_object('state','TERMINEE','mission_id',cap.mission_id,
    'facture_id',demande.facture_id,'facture_commission_id',demande.facture_commission_id);
 END IF;
 IF p_action='INVOQUER' THEN
  IF cap.invocation_started_at IS NOT NULL OR p_token IS NULL OR demande.token IS DISTINCT FROM p_token
    OR demande.expire_le IS NULL OR demande.expire_le<=clock_timestamp()
    OR EXISTS(SELECT FROM public.factures_honoraires f WHERE f.mission_id=cap.mission_id)
    OR EXISTS(SELECT FROM public.factures f WHERE f.mission_id=cap.mission_id)
  THEN RAISE EXCEPTION 'HONORAIRES_TEST_INVOCATION_REFUSED'; END IF;
  UPDATE private.honoraires_test_capacities SET invocation_started_at=clock_timestamp() WHERE id=cap.id;
  RETURN jsonb_build_object('state','AUTORISEE','mission_id',cap.mission_id);
 END IF;
 IF p_token IS NOT NULL THEN RAISE EXCEPTION 'HONORAIRES_TEST_TOKEN_REFUSED'; END IF;
 IF demande.prochain_essai_le>clock_timestamp() OR demande.expire_le>clock_timestamp() THEN
  RETURN jsonb_build_object('state','OCCUPEE','mission_id',cap.mission_id);
 END IF;
 IF cap.invocation_started_at IS NULL AND (
   EXISTS(SELECT FROM public.factures_honoraires f WHERE f.mission_id=cap.mission_id)
   OR EXISTS(SELECT FROM public.factures f WHERE f.mission_id=cap.mission_id))
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_ALREADY_INVOICED'; END IF;
 bail:=gen_random_uuid();
 UPDATE private.demandes_facturation_honoraires SET token=bail,
   expire_le=least(clock_timestamp()+interval '10 minutes',cap.expires_at),tentatives=tentatives+1
   WHERE mission_id=cap.mission_id;
 RETURN jsonb_build_object('state','PRISE','mission_id',cap.mission_id,'token',bail,
   'invoke',cap.invocation_started_at IS NULL);
END $recipe$;
ALTER FUNCTION public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid) TO service_role;

DO $closed$
DECLARE role_name text;
BEGIN
 IF EXISTS(SELECT FROM private.honoraires_test_capacities)
   OR EXISTS(SELECT FROM pg_policy WHERE polrelid='private.honoraires_test_capacities'::regclass)
   OR NOT EXISTS(SELECT FROM pg_class WHERE oid='private.honoraires_test_capacities'::regclass
      AND relowner='postgres'::regrole AND relrowsecurity AND relforcerowsecurity)
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_INSTALLATION_NOT_CLOSED'; END IF;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF has_table_privilege(role_name,'private.honoraires_test_capacities','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_function_privilege(role_name,'private.fn_honoraires_test_immutable()','EXECUTE')
  THEN RAISE EXCEPTION 'HONORAIRES_TEST_INSTALLATION_ACL'; END IF;
 END LOOP;
 IF has_function_privilege('anon','public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid)','EXECUTE')
   OR has_function_privilege('authenticated','public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('service_role','public.fn_demande_honoraires_recette(uuid,uuid,text,text,timestamptz,timestamptz,text,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'HONORAIRES_TEST_INSTALLATION_ACL'; END IF;
END $closed$;
