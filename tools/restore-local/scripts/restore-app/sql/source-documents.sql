-- Runs in the same source-only transaction as source-mission.sql.
-- No Edge generation, payment, financial provider, forged external identifiers or test capability.
DO $restore_documents$
DECLARE
  manifest jsonb := current_setting('jolene.connect_test_fixture_manifest')::jsonb;
  outsider_s uuid := (manifest#>>'{outsiders,soignant,id}')::uuid;
  outsider_e uuid := (manifest#>>'{outsiders,etablissement,id}')::uuid;
  invoice_id uuid := (manifest#>>'{document,id}')::uuid;
  owner_s uuid := (manifest#>>'{actors,soignant,id}')::uuid;
  owner_e uuid := (manifest#>>'{actors,etablissement,id}')::uuid;
  mission_id uuid := (manifest#>>'{ids,mission}')::uuid;
  period_start date := (current_setting('jolene.connect_test_fixture_receipt')::jsonb->>'periodeDebut')::date;
  operation jsonb;
BEGIN
  IF current_database()<>'jolene_candidatures_pg17_test' OR inet_server_addr() IS NOT NULL
    OR current_setting('cron.launch_active_jobs')<>'off' OR current_setting('max_worker_processes')<>'0'
    OR (SELECT count(*) FROM auth.users)<>5 OR (SELECT count(*) FROM auth.identities)<>5
    OR EXISTS(SELECT 1 FROM auth.sessions) OR EXISTS(SELECT 1 FROM auth.refresh_tokens)
    OR EXISTS(SELECT 1 FROM storage.objects) OR EXISTS(SELECT 1 FROM public.factures_honoraires)
    OR (SELECT count(*) FROM auth.users u WHERE u.id IN(outsider_s,outsider_e)
      AND u.email LIKE '%@example.invalid' AND u.raw_app_meta_data->'est_compte_test'='true'::jsonb
      AND u.raw_app_meta_data->>'jolene_connect_fixture_owner'=manifest->>'ownerMarker')<>2
  THEN RAISE EXCEPTION 'RESTORE_SOURCE_DOCUMENT_CONTEXT'; END IF;
  INSERT INTO public.soignants(id,email,prenom,nom,profession,type_exercice,est_compte_test,sms_actif,sms_alertes_actives,defacto_opt_in)
  VALUES(outsider_s,manifest#>>'{outsiders,soignant,email}','AUTRE','SYNTHETIQUE RESTORE','AS','SALARIE',true,false,false,false);
  INSERT INTO public.etablissements(id,nom,siret,type,email_contact,adresse_rue,adresse_ville,adresse_code_postal,
    est_compte_test,peut_publier_missions,sms_actif,chorus_pro_actif)
  VALUES(outsider_e,'AUTRE SYNTHETIQUE RESTORE',manifest#>>'{outsiders,etablissement,siret}','CLINIQUE_PRIVEE',
    manifest#>>'{outsiders,etablissement,email}','Adresse de fixture','Paris TEST','75001',true,false,false,false);
  operation:=public.fn_init_proprietaire_etab(owner_e,owner_e);
  IF operation->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'RESTORE_OWNER'; END IF;
  operation:=public.fn_init_proprietaire_etab(outsider_e,outsider_e);
  IF operation->'success' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'RESTORE_OTHER_OWNER'; END IF;
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id IN(owner_s,owner_e,outsider_s,outsider_e);
  INSERT INTO public.factures_honoraires(id,numero_facture,soignant_id,etablissement_id,mission_id,
    montant_ht,montant_tva,montant_ttc,taux_tva,statut,mandat_version,periode_debut,periode_fin,
    est_facture_finale_mission,quantite_heures_snapshot,taux_horaire_snapshot,pdf_s3_key,facturx_xml_url)
  VALUES(invoice_id,public.next_invoice_number(owner_s),owner_s,owner_e,mission_id,80,0,80,0,'EMISE','1.4',
    period_start,period_start+6,false,4,20,manifest#>>'{document,files,0,key}',manifest#>>'{document,files,1,key}');
  INSERT INTO public.factures_honoraires_documents(facture_honoraire_id,pdf_s3_key,facturx_xml_url,pdf_sha256,xml_sha256,motif_generation)
  VALUES(invoice_id,manifest#>>'{document,files,0,key}',manifest#>>'{document,files,1,key}',
    manifest#>>'{document,files,0,sha256}',manifest#>>'{document,files,1,sha256}','SYNTHETIC_RESTORE_BYTES_NO_GENERATOR_CLAIM');
  IF EXISTS(SELECT 1 FROM public.equipe_admin WHERE actif)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow) OR EXISTS(SELECT 1 FROM public.stripe_transfers)
    OR EXISTS(SELECT 1 FROM public.email_queue) OR EXISTS(SELECT 1 FROM net.http_request_queue)
    OR EXISTS(SELECT 1 FROM vault.secrets) OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'RESTORE_SOURCE_SIDE_EFFECT'; END IF;
END $restore_documents$;
