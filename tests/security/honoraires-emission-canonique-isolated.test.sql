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
CREATE FUNCTION private.fn_mission_est_reelle(uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT compte_reel FROM public.missions WHERE id=$1 $$;
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
INSERT INTO public.etablissements VALUES('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','Fictif');
INSERT INTO public.soignants(id,mandat_facturation_signe,mandat_facturation_version) VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true,'1.4');
INSERT INTO public.missions(id,etablissement_id,soignant_assigne_id,statut,type_contrat_applique,mode_remuneration,strategie_facturation,debut_le,fin_le,net_a_payer,total_brut)
SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','TERMINEE','LIBERAL','TAUX_HORAIRE','FINALE_UNIQUE','2026-10-18 17:30Z','2026-10-18 17:40Z',7.57,7.57 FROM generate_series(1,8)n;
UPDATE public.missions SET nature_tva_confirmee_par=soignant_assigne_id;
-- Vrai HEBDO clôturé sans historique : le corps ancien insère une finale
-- prématurée qui bloque la finale canonique et laisse proposer ses semaines.
UPDATE public.missions SET strategie_facturation='HEBDO_ET_FINALE',debut_le='2026-10-05 08:00Z',fin_le='2026-10-18 17:00Z'
 WHERE id='00000000-0000-4000-8000-000000000008';
INSERT INTO public.mission_creneaux VALUES('00000000-0000-4000-8000-000000000008','2026-10-05 08:00Z','2026-10-18 17:00Z',false,'EFFECTIF');
-- Reproduire réellement le défaut de l'ancien corps sur une mission distincte.
UPDATE public.missions SET statut='EN_COURS' WHERE id='00000000-0000-4000-8000-000000000008';
UPDATE public.missions SET statut='TERMINEE' WHERE id='00000000-0000-4000-8000-000000000008';
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM public.factures_honoraires WHERE mission_id='00000000-0000-4000-8000-000000000008' AND statut='EMISE' AND pdf_s3_key IS NULL AND facturx_xml_url IS NULL) THEN RAISE EXCEPTION 'ANCIEN_DEFAUT_NON_REPRODUIT'; END IF;
END $$;
DO $ancien_listeur$
DECLARE r jsonb;
BEGIN
 r:=public.fn_lister_missions_a_facturer('2026-10-19');
 IF EXISTS(SELECT FROM jsonb_array_elements(r->'finales') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000008')
 OR (SELECT count(*) FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000008')<>2
 THEN RAISE EXCEPTION 'ANCIEN_BLOCAGE_FINALE_OU_HEBDOS_COUVERTS_NON_REPRODUITS'; END IF;
END $ancien_listeur$;
CREATE TEMP TABLE historique_fh AS SELECT md5(to_jsonb(f)::text) empreinte FROM public.factures_honoraires f;
CREATE TEMP TABLE ancien_listeur_acl AS SELECT proowner,proacl,proconfig FROM pg_proc WHERE oid='public.fn_lister_missions_a_facturer(date)'::regprocedure;
INSERT INTO private.security_definer_inventory SELECT 'fn_lister_missions_a_facturer(date)','SERVICE_ONLY_REVOQUE',md5(prosrc),'fixture',now() FROM pg_proc WHERE oid='public.fn_lister_missions_a_facturer(date)'::regprocedure;
INSERT INTO private.security_definer_inventory SELECT 'fn_generer_facture_honoraires_mission(uuid)','SERVICE_ONLY_REVOQUE',md5(prosrc),'fixture',now() FROM pg_proc WHERE oid='public.fn_generer_facture_honoraires_mission(uuid)'::regprocedure;
INSERT INTO private.security_definer_inventory SELECT p.oid::regprocedure::text,'SERVICE_ONLY_REVOQUE',md5(p.prosrc),'fixture',now()
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.prosecdef;
CREATE TEMP TABLE anciennes_acl AS SELECT p.oid,p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.prosecdef;
\ir ../../supabase/migrations/20261018180050_emettre_honoraires_par_generation_canonique.sql
DO $$ BEGIN
 IF EXISTS(SELECT FROM private.demandes_facturation_honoraires) THEN RAISE EXCEPTION 'BACKFILL_INTERDIT'; END IF;
 IF (SELECT count(*) FROM public.factures_honoraires)<>1 THEN RAISE EXCEPTION 'HISTORIQUE_MODIFIE'; END IF;
 IF has_function_privilege('authenticated','public.fn_prendre_demandes_facturation_honoraires(integer)','EXECUTE') OR has_function_privilege('anon','public.fn_constater_demande_facturation_honoraires(uuid,uuid)','EXECUTE') OR has_table_privilege('authenticated','private.demandes_facturation_honoraires','INSERT') THEN RAISE EXCEPTION 'ACL_OUVERTES'; END IF;
END $$;
UPDATE public.missions SET statut='EN_COURS' WHERE id='00000000-0000-4000-8000-000000000001';
UPDATE public.missions SET statut='TERMINEE' WHERE id='00000000-0000-4000-8000-000000000001';
SELECT public.fn_generer_facture_honoraires_mission('00000000-0000-4000-8000-000000000001');
DO $test$
DECLARE r jsonb; t uuid; f uuid; c uuid; count_before integer;
BEGIN
 IF (SELECT count(*) FROM private.demandes_facturation_honoraires)<>1 OR (SELECT count(*) FROM public.factures_honoraires)<>1 THEN RAISE EXCEPTION 'CLOTURE_NON_DURABLE_OU_PREMATUREE'; END IF;
 r:=public.fn_prendre_demandes_facturation_honoraires(1);t:=(r->0->>'token')::uuid;
 IF jsonb_array_length(r)<>1 OR r->0->'body' IS DISTINCT FROM '{"mission_id":"00000000-0000-4000-8000-000000000001"}'::jsonb THEN RAISE EXCEPTION 'PRISE_INVALIDE'; END IF;
 IF public.fn_prendre_demandes_facturation_honoraires(1)<>'[]'::jsonb THEN RAISE EXCEPTION 'BAIL_REPRIS'; END IF;
 -- Un HTTP supposé réussi sans pièce n'acquitte jamais.
 r:=public.fn_constater_demande_facturation_honoraires('00000000-0000-4000-8000-000000000001',t);
 IF (r->>'success')::boolean IS DISTINCT FROM false OR EXISTS(SELECT FROM private.demandes_facturation_honoraires WHERE terminee_le IS NOT NULL) THEN RAISE EXCEPTION 'ACQUIT_INCOMPLET'; END IF;
 UPDATE private.demandes_facturation_honoraires SET prochain_essai_le=now();
 r:=public.fn_prendre_demandes_facturation_honoraires(1);t:=(r->0->>'token')::uuid;
 INSERT INTO public.factures_honoraires(mission_id,soignant_id,etablissement_id,statut,template_version,regime_tva_snapshot,emise_le,pdf_s3_key,facturx_xml_url)
 VALUES('00000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','EMISE','v2_facturx','EXONERE_ART_261_4_1',now(),'fictif.pdf','fictif.xml') RETURNING id INTO f;
 INSERT INTO public.factures_honoraires_documents VALUES(f,'fictif.pdf','fictif.xml',repeat('a',64),repeat('b',64));
 r:=public.fn_constater_demande_facturation_honoraires('00000000-0000-4000-8000-000000000001',t);
 IF (r->>'success')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'COMMISSION_ABSENTE_ACQUITTEE'; END IF;
 UPDATE private.demandes_facturation_honoraires SET prochain_essai_le=now();
 r:=public.fn_prendre_demandes_facturation_honoraires(1);t:=(r->0->>'token')::uuid;
 INSERT INTO public.factures(mission_id,etablissement_id,facture_honoraire_id,type_document,statut)
 VALUES('00000000-0000-4000-8000-000000000001','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',f,'FACTURE','EMISE') RETURNING id INTO c;
 r:=public.fn_constater_demande_facturation_honoraires('00000000-0000-4000-8000-000000000001',t);
 IF (r->>'success')::boolean IS DISTINCT FROM true OR (r->>'facture_id')::uuid<>f OR (r->>'facture_commission_id')::uuid<>c THEN RAISE EXCEPTION 'CONSTAT_COMPLET_REFUSE'; END IF;
 IF public.fn_constater_demande_facturation_honoraires('00000000-0000-4000-8000-000000000001',t) IS DISTINCT FROM r THEN RAISE EXCEPTION 'REJEU_NON_IDEMPOTENT'; END IF;
 IF public.fn_prendre_demandes_facturation_honoraires(1)<>'[]'::jsonb THEN RAISE EXCEPTION 'DEMANDE_TERMINEE_REPRISE'; END IF;
 BEGIN PERFORM public.fn_constater_demande_facturation_honoraires('00000000-0000-4000-8000-000000000001',gen_random_uuid());RAISE EXCEPTION 'MAUVAIS_TOKEN_ACCEPTE'; EXCEPTION WHEN check_violation THEN NULL; END;
END $test$;
-- Le drain refuse les TEST et toute mutation ultérieure de stratégie.
UPDATE public.missions SET compte_reel=false WHERE id='00000000-0000-4000-8000-000000000002';
SELECT public.fn_generer_facture_honoraires_mission('00000000-0000-4000-8000-000000000002');
SELECT public.fn_generer_facture_honoraires_mission('00000000-0000-4000-8000-000000000003');
UPDATE public.missions SET strategie_facturation='HEBDO_ET_FINALE' WHERE id='00000000-0000-4000-8000-000000000003';
DO $$ BEGIN
 IF public.fn_prendre_demandes_facturation_honoraires(3)<>'[]'::jsonb OR (SELECT count(*) FROM private.demandes_facturation_honoraires)<>3 THEN RAISE EXCEPTION 'ISOLATION_STRATEGIE_OU_TEST'; END IF;
END $$;
-- Le vrai producteur et le vrai listeur continuent le circuit quotidien
-- HEBDO. Ni queue nouvelle ni FH legacy : seules les périodes canoniques restent.
UPDATE public.missions SET strategie_facturation='HEBDO_ET_FINALE',debut_le='2026-10-05 08:00Z',fin_le='2026-10-18 17:00Z'
 WHERE id IN('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006');
UPDATE public.missions SET strategie_facturation='HEBDO_ET_FINALE',statut='EN_COURS',debut_le='2026-10-05 08:00Z',fin_le='2026-10-26 17:00Z'
 WHERE id='00000000-0000-4000-8000-000000000007';
INSERT INTO public.mission_creneaux
 SELECT id,debut_le,fin_le,false,'EFFECTIF' FROM public.missions
 WHERE id IN('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000007');
-- La clôture déclenche réellement le trigger historique conservé.
UPDATE public.missions SET statut='EN_COURS' WHERE id='00000000-0000-4000-8000-000000000005';
UPDATE public.missions SET statut='TERMINEE' WHERE id='00000000-0000-4000-8000-000000000005';
DO $hebdo$
DECLARE r jsonb; produit jsonb; historique jsonb; f uuid; avant jsonb; apres jsonb; rejet text;
BEGIN
 produit:=public.fn_generer_facture_honoraires_mission('00000000-0000-4000-8000-000000000005');
 IF produit->>'emission_en_attente' IS DISTINCT FROM 'true' OR produit ? 'facture_id'
 OR EXISTS(SELECT FROM private.demandes_facturation_honoraires WHERE mission_id IN('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000007'))
 OR EXISTS(SELECT FROM public.factures_honoraires WHERE mission_id='00000000-0000-4000-8000-000000000005')
 THEN RAISE EXCEPTION 'HEBDO_CLOTURE_PIECE_OU_QUEUE_PREMATUREE'; END IF;
 -- Pas d'avance de calendrier ; le lendemain, une seule finale et zéro semaine
 -- couverte dans le même résultat, avant toute réservation/génération.
 r:=public.fn_lister_missions_a_facturer('2026-10-18');
 IF EXISTS(SELECT FROM jsonb_array_elements(r->'finales') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000005') THEN RAISE EXCEPTION 'FINALE_AVANT_LENDEMAIN'; END IF;
 r:=public.fn_lister_missions_a_facturer('2026-10-19');
 SELECT jsonb_agg(x) INTO avant FROM jsonb_array_elements(r->'finales') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000005';
 IF jsonb_array_length(avant) IS DISTINCT FROM 1 OR avant->0->>'periode_debut' IS DISTINCT FROM '2026-10-05'
 OR avant->0->>'periode_fin' IS DISTINCT FROM '2026-10-18'
 OR EXISTS(SELECT FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000005')
 THEN RAISE EXCEPTION 'FINALE_HEBDO_SANS_HISTORIQUE_NON_CANONIQUE'; END IF;
 -- Une semaine existante conserve la branche facture déjà existante et ne
 -- laisse à la finale que le résiduel. Aucun calcul de montant n'est remplacé.
 INSERT INTO public.factures_honoraires(mission_id,soignant_id,etablissement_id,statut,periode_debut,periode_fin,numero_semaine_iso,annee_iso,est_facture_finale_mission,montant_ht)
 VALUES('00000000-0000-4000-8000-000000000006','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','PAYEE','2026-10-05','2026-10-11',41,2026,false,80) RETURNING id INTO f;
 SELECT to_jsonb(fh) INTO historique FROM public.factures_honoraires fh WHERE id=f;
 produit:=public.fn_generer_facture_honoraires_mission('00000000-0000-4000-8000-000000000006');
 IF produit->>'facture_id' IS DISTINCT FROM f::text OR produit ? 'emission_en_attente'
 OR EXISTS(SELECT FROM private.demandes_facturation_honoraires WHERE mission_id='00000000-0000-4000-8000-000000000006')
 OR (SELECT to_jsonb(fh) FROM public.factures_honoraires fh WHERE id=f) IS DISTINCT FROM historique
 THEN RAISE EXCEPTION 'HEBDO_EXISTANTE_MODIFIEE'; END IF;
 r:=public.fn_lister_missions_a_facturer('2026-10-19');
 SELECT jsonb_agg(x) INTO apres FROM jsonb_array_elements(r->'finales') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000006';
 IF jsonb_array_length(apres) IS DISTINCT FROM 1 OR apres->0->>'periode_debut' IS DISTINCT FROM '2026-10-12'
 OR apres->0->>'periode_fin' IS DISTINCT FROM '2026-10-18'
 OR EXISTS(SELECT FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000006')
 THEN RAISE EXCEPTION 'RESIDUEL_HEBDO_MODIFIE'; END IF;
 -- Après émission d'une finale, aucun jour suivant ne repropose ses semaines.
 INSERT INTO public.factures_honoraires(mission_id,soignant_id,etablissement_id,statut,periode_debut,periode_fin,est_facture_finale_mission)
 VALUES('00000000-0000-4000-8000-000000000005','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','EMISE','2026-10-05','2026-10-18',true) RETURNING id INTO f;
 r:=public.fn_lister_missions_a_facturer('2026-10-20');
 IF EXISTS(SELECT FROM jsonb_array_elements((r->'finales')||(r->'hebdo')) x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000005') THEN RAISE EXCEPTION 'SEMAINES_REPROPOSEES_APRES_FINALE'; END IF;
 -- Une mission en cours garde exactement ses deux semaines closes légitimes.
 SELECT jsonb_agg(x ORDER BY x->>'periode_debut') INTO avant FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000007';
 IF jsonb_array_length(avant) IS DISTINCT FROM 2 OR avant->0->>'periode_debut' IS DISTINCT FROM '2026-10-05'
 OR avant->0->>'periode_fin' IS DISTINCT FROM '2026-10-11'
 OR avant->1->>'periode_debut' IS DISTINCT FROM '2026-10-12'
 OR avant->1->>'periode_fin' IS DISTINCT FROM '2026-10-18'
 OR EXISTS(SELECT FROM jsonb_array_elements(r->'finales') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000007') THEN RAISE EXCEPTION 'HEBDO_LEGITIME_EN_COURS_SUPPRIME'; END IF;
 -- Le même chevauchement que la garde de réservation couvre aussi les pièces
 -- actives sans numéro ISO. Les statuts inactifs ne masquent pas une semaine.
 INSERT INTO public.factures_honoraires(mission_id,soignant_id,etablissement_id,statut,periode_debut,periode_fin,est_facture_finale_mission)
 VALUES('00000000-0000-4000-8000-000000000007','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','EN_GENERATION','2026-10-07','2026-10-08',true) RETURNING id INTO f;
 r:=public.fn_lister_missions_a_facturer('2026-10-20');
 IF (SELECT count(*) FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000007')<>1
 OR EXISTS(SELECT FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000007' AND x->>'periode_debut'='2026-10-05') THEN RAISE EXCEPTION 'CHEVAUCHEMENT_ACTIF_IGNORE'; END IF;
 FOREACH rejet IN ARRAY ARRAY['ANNULEE','REMPLACEE','ERREUR_GENERATION'] LOOP
  UPDATE public.factures_honoraires SET statut=rejet WHERE id=f;
  r:=public.fn_lister_missions_a_facturer('2026-10-20');
  SELECT jsonb_agg(x ORDER BY x->>'periode_debut') INTO apres FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000007';
  IF apres IS DISTINCT FROM avant THEN RAISE EXCEPTION 'PIECE_INACTIVE_BLOQUE_HEBDO'; END IF;
 END LOOP;
 UPDATE public.factures_honoraires SET statut='EMISE',type_document='AVOIR' WHERE id=f;
 r:=public.fn_lister_missions_a_facturer('2026-10-20');
 SELECT jsonb_agg(x ORDER BY x->>'periode_debut') INTO apres FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000007';
 IF apres IS DISTINCT FROM avant THEN RAISE EXCEPTION 'AVOIR_BLOQUE_HEBDO'; END IF;
 UPDATE public.factures_honoraires SET type_document='FACTURE',nature_correction='COMPLEMENT' WHERE id=f;
 r:=public.fn_lister_missions_a_facturer('2026-10-20');
 SELECT jsonb_agg(x ORDER BY x->>'periode_debut') INTO apres FROM jsonb_array_elements(r->'hebdo') x WHERE x->>'mission_id'='00000000-0000-4000-8000-000000000007';
 IF apres IS DISTINCT FROM avant THEN RAISE EXCEPTION 'COMPLEMENT_BLOQUE_HEBDO'; END IF;
 IF NOT EXISTS(SELECT FROM historique_fh h JOIN public.factures_honoraires fh ON md5(to_jsonb(fh)::text)=h.empreinte)
 OR (SELECT count(*) FROM private.demandes_facturation_honoraires)<>3 THEN RAISE EXCEPTION 'HISTORIQUE_OU_DEMANDES_MODIFIES'; END IF;
 IF EXISTS(SELECT FROM ancien_listeur_acl a JOIN pg_proc p ON p.oid='public.fn_lister_missions_a_facturer(date)'::regprocedure WHERE a.proowner IS DISTINCT FROM p.proowner OR a.proacl IS DISTINCT FROM p.proacl OR a.proconfig IS DISTINCT FROM p.proconfig)
 OR has_function_privilege('authenticated','public.fn_lister_missions_a_facturer(date)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.fn_lister_missions_a_facturer(date)','EXECUTE') THEN RAISE EXCEPTION 'LISTEUR_DROITS_CONFIG_MODIFIES'; END IF;
END $hebdo$;
-- Le dispatcher réel garde le corps quotidien vide ; seul le nouveau job a
-- mode=demandes. Le transport est local fermé, aucune requête HTTP n'est envoyée.
SELECT private.fn_appeler_edge_critique('weekly-invoicing-cron',false);
SELECT private.fn_appeler_edge_critique('honoraires-emission-demandes',false);
INSERT INTO cron.job(jobname,active,schedule,command)
SELECT n,false,'fixture','fixture' FROM unnest(ARRAY['litige-escalation-cron','email-cron-hourly-immediate','email-cron-daily','process-stripe-refunds-15min','escrow-debit-echeance','escrow-release','jolene_process_externalisations','weekly-invoicing-cron','honoraires-emission-demandes','jolene-monitor-crons-edge-critiques'])n;
DO $cron$
DECLARE probes jsonb; result jsonb; id_nouveau bigint; source text;
BEGIN
 IF (SELECT r.body FROM net.requests r JOIN private.cron_edge_execution_log l ON l.request_id=r.id WHERE l.job_name='weekly-invoicing-cron') IS DISTINCT FROM '{}'::jsonb
 OR (SELECT r.body FROM net.requests r JOIN private.cron_edge_execution_log l ON l.request_id=r.id WHERE l.job_name='honoraires-emission-demandes') IS DISTINCT FROM '{"mode":"demandes"}'::jsonb THEN RAISE EXCEPTION 'DISPATCH_MODE_INVALIDE'; END IF;
 source:=pg_get_functiondef('private.fn_reconcilier_crons_edge_critiques_inactifs()'::regprocedure);
 IF position('(''weekly-invoicing-cron'', ''0 4,5 * * *'')' in source)=0 OR position('WHERE EXTRACT(HOUR FROM now() AT TIME ZONE %L) = 6' in source)=0
 OR position('(''honoraires-emission-demandes'', ''*/5 * * * *'')' in source)=0 THEN RAISE EXCEPTION 'CADENCE_QUOTIDIENNE_MODIFIEE'; END IF;
 probes:=private.fn_sonder_crons_edge_critiques();
 IF (SELECT count(*) FROM jsonb_object_keys(probes))<>9 THEN RAISE EXCEPTION 'SONDE_MANQUANTE'; END IF;
 id_nouveau:=(probes->>'honoraires-emission-demandes')::bigint;
 IF NOT EXISTS(SELECT FROM net.requests WHERE id=id_nouveau AND headers->>'x-jolene-cron-probe'='auth-only' AND body='{"mode":"demandes"}'::jsonb) THEN RAISE EXCEPTION 'NOUVELLE_SONDE_METIER'; END IF;
 BEGIN PERFORM private.fn_etat_sondes_crons_edge_critiques(probes-'honoraires-emission-demandes');RAISE EXCEPTION 'SONDE_ABSENTE_ACCEPTEE'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 INSERT INTO net._http_response SELECT value::text::bigint,CASE WHEN value::text::bigint=id_nouveau THEN 500 ELSE 200 END,false,NULL FROM jsonb_each(probes);
 result:=private.fn_etat_sondes_crons_edge_critiques(probes);
 IF result->>'success' IS DISTINCT FROM 'false' OR result->>'ok' IS DISTINCT FROM '8' THEN RAISE EXCEPTION 'NOUVELLE_SONDE_500_IGNOREE'; END IF;
 BEGIN PERFORM private.fn_activer_crons_edge_critiques(probes,'AUTH_PROBES_OK');RAISE EXCEPTION 'ACTIVATION_500_ACCEPTEE'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 IF EXISTS(SELECT FROM cron.job WHERE active) THEN RAISE EXCEPTION 'ACTIVATION_PARTIELLE'; END IF;
 UPDATE net._http_response SET status_code=200 WHERE id=id_nouveau;
 result:=private.fn_activer_crons_edge_critiques(probes,'AUTH_PROBES_OK');
 IF result->>'success' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'jobs_actives')<>10 OR (SELECT count(*) FROM cron.job WHERE active)<>10 THEN RAISE EXCEPTION 'ACTIVATION_INCOMPLETE'; END IF;
 result:=private.fn_desactiver_crons_edge_critiques();
 IF result->>'success' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'critiques_desactives')<>10 OR EXISTS(SELECT FROM cron.job WHERE active) THEN RAISE EXCEPTION 'DESACTIVATION_INCOMPLETE'; END IF;
 IF EXISTS(SELECT FROM anciennes_acl a JOIN pg_proc p ON p.oid=a.oid WHERE a.proacl IS DISTINCT FROM p.proacl) THEN RAISE EXCEPTION 'ANCIENNES_ACL_CHANGEES'; END IF;
 IF EXISTS(SELECT FROM private.security_definer_inventory i JOIN pg_proc p ON p.oid=to_regprocedure(i.signature) WHERE i.definition_md5<>md5(p.prosrc)) THEN RAISE EXCEPTION 'INVENTAIRE_DERIVE'; END IF;
END $cron$;
ROLLBACK;
