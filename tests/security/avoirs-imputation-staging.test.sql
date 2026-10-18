-- STAGE CI isolé : RLS, triggers métier et helpers d'imputation réels.
-- Fixtures SQL de maintenance synthétiques ; aucun login, MFA, justificatif,
-- paiement, fournisseur ni validation UI n'est prouvé par ce banc.
-- Aucune fonction/ACL/contrainte/trigger n'est remplacée ou désactivée.
-- La sentinelle interne annule aussi le seed si le runner retire le ROLLBACK.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';
SELECT set_config('request.jwt.claim.sub','',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

DO $recette$
DECLARE
  e constant uuid := 'a0185100-0000-4000-8000-000000000001';
  origine constant uuid := 'a0185100-0000-4000-8000-000000000010';
  avoir40 constant uuid := 'a0185100-0000-4000-8000-000000000011';
  avoir20 constant uuid := 'a0185100-0000-4000-8000-000000000012';
  avoir_centime constant uuid := 'a0185100-0000-4000-8000-000000000013';
  mensuelle constant uuid := 'a0185100-0000-4000-8000-000000000020';
  soldee constant uuid := 'a0185100-0000-4000-8000-000000000021';
  centime constant uuid := 'a0185100-0000-4000-8000-000000000022';
  mission_origine constant uuid := 'a0185100-0000-4000-8000-000000000030';
  mission_mensuelle constant uuid := 'a0185100-0000-4000-8000-000000000031';
  mission_soldee constant uuid := 'a0185100-0000-4000-8000-000000000032';
  mission_centime constant uuid := 'a0185100-0000-4000-8000-000000000033';
  r jsonb; detail_avant jsonb; documents_avant jsonb; n integer; nom text;
  annule boolean := false;
BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL
    OR auth.role() IS DISTINCT FROM 'service_role' OR public.est_admin()
    OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'AVOIRS STAGE : maintenance isolée et tous les crons inactifs requis'; END IF;
  FOREACH nom IN ARRAY ARRAY['jolene.admin_seed_override_reason','jolene.generate_invoice_context',
    'jolene.creer_mission_context','jolene.admin_override_gel','jolene.admin_override_reason',
    'jolene.admin_correction_mission_id','jolene.admin_correction_reason','app.internal_operation'] LOOP
    IF nullif(current_setting(nom,true),'') IS NOT NULL
    THEN RAISE EXCEPTION 'AVOIRS STAGE : contexte de contournement interdit : %',nom; END IF;
  END LOOP;
  FOREACH nom IN ARRAY ARRAY['jolene.sync_in_progress','jolene.system_update','jolene.planning_exact_managed'] LOOP
    IF coalesce(current_setting(nom,true),'') NOT IN ('','false')
    THEN RAISE EXCEPTION 'AVOIRS STAGE : synchronisation forcée interdite : %',nom; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
      AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled<>'D')
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid IN ('public.etablissements'::regclass,
      'public.missions'::regclass,'public.mission_creneaux'::regclass,'public.factures'::regclass,
      'public.stripe_payment_flow_claims'::regclass,'private.avoirs_commission_sources'::regclass,
      'private.avoirs_commission_mouvements'::regclass)
      AND NOT tgisinternal AND tgenabled NOT IN ('O','A'))
  THEN RAISE EXCEPTION 'AVOIRS STAGE : trigger Auth non inventorié ou trigger métier désactivé'; END IF;
  IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN ('public.factures'::regclass,
      'private.avoirs_commission_sources'::regclass,'private.avoirs_commission_mouvements'::regclass)
      AND NOT (relrowsecurity AND relforcerowsecurity))
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.factures'::regclass
      AND tgname IN ('aa_garder_facture_imputation','trg_avoirs_restitution','trg_avoirs_rapprochement')
      AND tgenabled IN ('O','A'))<>3
  THEN RAISE EXCEPTION 'AVOIRS STAGE : protections RLS/triggers manquantes'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=e)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=e OR siret='99185100000001')
    OR EXISTS(SELECT 1 FROM public.factures WHERE id IN(origine,avoir40,avoir20,avoir_centime,mensuelle,soldee,centime))
    OR EXISTS(SELECT 1 FROM public.missions WHERE id IN(mission_origine,mission_mensuelle,mission_soldee,mission_centime))
  THEN RAISE EXCEPTION 'AVOIRS STAGE : fixture déjà présente'; END IF;

  BEGIN
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    VALUES(e,'00000000-0000-0000-0000-000000000000','avoirs-staging-rollback@example.invalid',
      'authenticated','authenticated',
      '{"role":"ADMIN_ETABLISSEMENT","est_compte_test":true,"is_test_playwright":true}',now());
    INSERT INTO public.preferences_notifications(utilisateur_id,canal_email,canal_sms,canal_push,canal_in_app)
    VALUES(e,false,false,false,false) ON CONFLICT(utilisateur_id) DO UPDATE
      SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false;
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,
      email_contact,est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,
      statut_verification,peut_publier_missions,est_secteur_public,rist_plafond_actif,mode_paiement_commission)
    VALUES(e,'Fixture avoirs SQL annulée','99185100000001','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001',
      'avoirs-staging-rollback@example.invalid',true,'RECETTE_AVOIRS_SQL','AVOIRSSTAGE018',false,false,
      'EN_ATTENTE',false,false,false,'SEPA_DEBIT');

    -- Pièces synthétiques, jamais argent encaissé ni corrigé. La numérotation
    -- de fixture reste hors des séries numériques partagées et sans nextval.
    INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,
      montant_ht,montant_tva,montant_ttc,date_emission,date_echeance,nombre_missions,mode_paiement)
    VALUES
      (origine,e,'JOL-2026-H-A018510010','FACTURE','EMISE',200,40,240,now(),current_date+30,1,'STRIPE'),
      (mensuelle,e,'JOL-2026-H-A018510020','FACTURE','BROUILLON',100,20,120,now(),current_date+30,1,'STRIPE'),
      (soldee,e,'JOL-2026-H-A018510021','FACTURE','BROUILLON',16.67,3.33,20,now(),current_date+30,1,'STRIPE');
    -- Voie SQL de maintenance existante : pas d'assignation, de contrat ni de
    -- pointage utilisateur simulé. Les moteurs calculent les missions ; leurs
    -- montants ne sont pas injectés. Seul le lien documentaire sert au helper.
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
      duree_heures,taux_horaire_base,statut,type_contrat_recherche,type_contrat_applique,
      choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente,facture_id)
    VALUES
      (mission_origine,e,'AVOIRS SQL origine synthétique','IDE',current_date+7+time '09:00',current_date+7+time '13:00',
        4,20,'TERMINEE','SALARIE','SALARIE','SALARIE','BULLETIN_PAIE','DIRECT','FINALE_UNIQUE',false,origine),
      (mission_mensuelle,e,'AVOIRS SQL mensuelle synthétique','IDE',current_date+8+time '09:00',current_date+8+time '13:00',
        4,20,'TERMINEE','SALARIE','SALARIE','SALARIE','BULLETIN_PAIE','DIRECT','FINALE_UNIQUE',false,mensuelle),
      (mission_soldee,e,'AVOIRS SQL solde synthétique','IDE',current_date+9+time '09:00',current_date+9+time '13:00',
        4,20,'TERMINEE','SALARIE','SALARIE','SALARIE','BULLETIN_PAIE','DIRECT','FINALE_UNIQUE',false,soldee);
    IF (SELECT count(*) FROM public.missions WHERE id IN(mission_origine,mission_mensuelle,mission_soldee)
      AND type_contrat_applique='SALARIE' AND statut='TERMINEE' AND fige_le IS NULL)<>3
      OR (SELECT count(*) FROM public.mission_creneaux WHERE mission_id IN(mission_origine,mission_mensuelle,mission_soldee)
        AND type_creneau='PREVISIONNEL')<>3
    THEN RAISE EXCEPTION 'AVOIRS STAGE : historique maintenance/planning inattendu'; END IF;
    INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,facture_precedente_id,
      montant_ht,montant_tva,montant_ttc,date_emission,date_echeance,nombre_missions)
    VALUES(avoir40,e,'JOL-2026-A-A018510011','AVOIR','EMISE',origine,33.33,6.67,40,now(),current_date+30,1);
    SELECT jsonb_agg(to_jsonb(f) ORDER BY id) INTO documents_avant FROM public.factures f WHERE id IN(origine,avoir40);
    r:=private.fn_inscrire_avoir_commission(avoir40,mission_origine,'LITIGE_SALARIE');
    IF r->>'eligible' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'AVOIRS STAGE : source refusée %',r; END IF;
    r:=private.fn_emettre_facture_mensuelle_avec_avoirs(mensuelle);
    IF (r->>'montant_avoirs_imputes')::numeric IS DISTINCT FROM 40
      OR (r->>'montant_a_payer')::numeric IS DISTINCT FROM 80
      OR NOT EXISTS(SELECT 1 FROM public.factures WHERE id=mensuelle AND statut='EMISE'
        AND montant_ht=100 AND montant_tva=20 AND montant_ttc=120 AND montant_avoirs_imputes=40
        AND montant_a_payer=80 AND NOT rapprochement_paiement_requis)
      OR documents_avant IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(f) ORDER BY id)
        FROM public.factures f WHERE id IN(origine,avoir40))
    THEN RAISE EXCEPTION 'AVOIRS STAGE : 120 TTC - 40 avoir = 80 externe ou immuabilité incorrecte'; END IF;
    INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,facture_precedente_id,
      montant_ht,montant_tva,montant_ttc,date_emission,date_echeance,nombre_missions)
    VALUES(avoir20,e,'JOL-2026-A-A018510012','AVOIR','EMISE',origine,16.67,3.33,20,now(),current_date+30,1);
    r:=private.fn_inscrire_avoir_commission(avoir20,mission_origine,'LITIGE_SALARIE');
    IF r->>'eligible' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'AVOIRS STAGE : seconde source refusée %',r; END IF;
    r:=private.fn_emettre_facture_mensuelle_avec_avoirs(soldee);
    IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id=soldee AND statut='PAYEE' AND mode_paiement='AVOIR'
      AND montant_ht=16.67 AND montant_tva=3.33 AND montant_ttc=20 AND montant_avoirs_imputes=20
      AND montant_a_payer=0 AND date_paiement IS NOT NULL AND stripe_payment_intent_id IS NULL
      AND stripe_invoice_id IS NULL AND stripe_hosted_url IS NULL AND virement_reference IS NULL)
      OR (SELECT count(*) FROM private.avoirs_commission_sources WHERE etablissement_id=e)<>2
      OR (SELECT count(*) FROM private.avoirs_commission_mouvements WHERE etablissement_id=e AND nature='IMPUTATION')<>2
      OR (SELECT sum(montant_cents) FROM private.avoirs_commission_mouvements WHERE etablissement_id=e) IS DISTINCT FROM 6000
    THEN RAISE EXCEPTION 'AVOIRS STAGE : solde par avoir sans Stripe ou ledger incorrect'; END IF;

    -- Les outbox documentaires restent transactionnelles, jamais réservées ni
    -- envoyées. Le zéro est une émission soldée, pas un email d'encaissement.
    IF NOT EXISTS(SELECT 1 FROM private.facturation_email_livraisons WHERE document_id=mensuelle
      AND evenement='EMISSION' AND corps#>>'{data,montant_ttc}'='120.00'
      AND corps#>>'{data,montant_avoirs_imputes}'='40.00' AND corps#>>'{data,montant_a_payer}'='80.00')
      OR NOT EXISTS(SELECT 1 FROM private.facturation_email_livraisons WHERE document_id=soldee
        AND evenement='EMISSION' AND corps#>>'{data,mode_paiement}'='AVOIR' AND corps#>>'{data,montant_a_payer}'='0.00')
      OR EXISTS(SELECT 1 FROM private.facturation_email_livraisons WHERE destinataire_id=e
        AND (evenement='PAIEMENT' OR tentatives<>0 OR premiere_tentative_le IS NOT NULL OR reservation IS NOT NULL))
      OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id=e AND (coalesce(envoye,false) OR envoye_le IS NOT NULL))
      OR EXISTS(SELECT 1 FROM public.stripe_payment_flow_claims WHERE resource_key IN
        ('FACTURE:'||origine::text,'FACTURE:'||mensuelle::text,'FACTURE:'||soldee::text,
         'MISSION:'||mission_origine::text,'MISSION:'||mission_mensuelle::text,'MISSION:'||mission_soldee::text))
      OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id IN(mission_origine,mission_mensuelle,mission_soldee))
      OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE acteur_id=e AND action='OVERRIDE_ANTI_SEED')
    THEN RAISE EXCEPTION 'AVOIRS STAGE : file documentaire, transport ou override inattendu'; END IF;

    -- Reliquat inférieur au minimum Stripe : seule l'imputation ouvre le
    -- virement pour cet établissement SEPA, sans modifier le centime dû.
    INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,facture_precedente_id,
      montant_ht,montant_tva,montant_ttc,date_emission,date_echeance,nombre_missions)
    VALUES(avoir_centime,e,'JOL-2026-A-A018510013','AVOIR','EMISE',origine,100,20,120,now(),current_date+30,1);
    r:=private.fn_inscrire_avoir_commission(avoir_centime,mission_origine,'LITIGE_SALARIE');
    IF r->>'eligible' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'AVOIRS STAGE : source centime refusée'; END IF;
    INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,
      montant_ht,montant_tva,montant_ttc,date_emission,date_echeance,nombre_missions)
    VALUES(centime,e,'JOL-2026-H-A018510022','FACTURE','BROUILLON',100.01,20,120.01,now(),current_date+30,1);
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
      duree_heures,taux_horaire_base,statut,type_contrat_recherche,type_contrat_applique,
      choix_contrat_soignant,type_paiement_soignant,mode_paiement_soignant,strategie_facturation,est_urgente,facture_id)
    VALUES(mission_centime,e,'AVOIRS SQL reliquat synthétique','IDE',current_date+10+time '09:00',current_date+10+time '13:00',
      4,20,'TERMINEE','SALARIE','SALARIE','SALARIE','BULLETIN_PAIE','DIRECT','FINALE_UNIQUE',false,centime);
    PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(centime);
    IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id=centime AND montant_ttc=120.01
      AND montant_avoirs_imputes=120 AND montant_a_payer=0.01 AND statut='EMISE')
      OR private.fn_admission_virement_commission(centime)->>'virement_autorise' IS DISTINCT FROM 'true'
      OR private.fn_admission_virement_commission(mensuelle)->>'motif' IS DISTINCT FROM 'PAIEMENT_SEPA_AUTOMATIQUE'
    THEN RAISE EXCEPTION 'AVOIRS STAGE : exception virement petit solde SEPA incorrecte'; END IF;

    -- Vrai rôle DB utilisateur et vraie RLS : aucun rôle admin/AAL2 synthétique.
    PERFORM set_config('request.jwt.claim.sub',e::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated')::text,true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    IF current_user<>'authenticated' OR auth.uid() IS DISTINCT FROM e OR public.est_admin()
      OR public.fn_a_permission_etablissement('lecture_paiement',e) IS NOT TRUE
    THEN RAISE EXCEPTION 'AVOIRS STAGE : identité/permission de lecture de fixture incorrecte'; END IF;
    r:=public.fn_detail_facture(mensuelle);
    IF (r#>>'{facture,montant_ttc}')::numeric IS DISTINCT FROM 120
      OR (r#>>'{facture,montant_avoirs_imputes}')::numeric IS DISTINCT FROM 40
      OR (r#>>'{facture,montant_a_payer}')::numeric IS DISTINCT FROM 80
      OR r#>>'{facture,rapprochement_paiement_requis}' IS DISTINCT FROM 'false'
    THEN RAISE EXCEPTION 'AVOIRS STAGE : RPC détail brut/imputé/net incorrecte : %',r; END IF;
    detail_avant:=r;
    IF (SELECT count(*) FROM public.factures WHERE etablissement_id=e)<>7
    THEN RAISE EXCEPTION 'AVOIRS STAGE : lecture propriétaire RLS incorrecte'; END IF;
    BEGIN
      UPDATE public.factures SET montant_avoirs_imputes=0 WHERE id=mensuelle;
      GET DIAGNOSTICS n=ROW_COUNT;
      IF n<>0 THEN RAISE EXCEPTION 'AVOIRS STAGE : écriture agrégat utilisateur acceptée'; END IF;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
      UPDATE public.factures SET rapprochement_paiement_requis=true WHERE id=mensuelle;
      GET DIAGNOSTICS n=ROW_COUNT;
      IF n<>0 THEN RAISE EXCEPTION 'AVOIRS STAGE : écriture flag utilisateur acceptée'; END IF;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
      UPDATE private.avoirs_commission_mouvements SET montant_cents=1 WHERE facture_id=mensuelle;
      RAISE EXCEPTION 'AVOIRS STAGE : accès privé utilisateur accepté';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
      PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(mensuelle);
      RAISE EXCEPTION 'AVOIRS STAGE : helper privé utilisateur accessible';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    IF public.fn_detail_facture(mensuelle) IS DISTINCT FROM detail_avant
    THEN RAISE EXCEPTION 'AVOIRS STAGE : relecture SQL différente après refus'; END IF;
    r:=public.fn_detail_facture(soldee);
    IF r#>>'{facture,statut}' IS DISTINCT FROM 'PAYEE' OR r#>>'{facture,mode_paiement}' IS DISTINCT FROM 'AVOIR'
      OR (r#>>'{facture,montant_a_payer}')::numeric IS DISTINCT FROM 0
    THEN RAISE EXCEPTION 'AVOIRS STAGE : RPC détail solde par avoir incorrecte'; END IF;
    EXECUTE 'RESET ROLE';
    IF has_table_privilege('authenticated','private.avoirs_commission_sources','SELECT,INSERT,UPDATE,DELETE')
      OR has_table_privilege('authenticated','private.avoirs_commission_mouvements','SELECT,INSERT,UPDATE,DELETE')
      OR has_function_privilege('authenticated','private.fn_inscrire_avoir_commission(uuid,uuid,text)','EXECUTE')
    THEN RAISE EXCEPTION 'AVOIRS STAGE : privilège privé utilisateur présent'; END IF;
    RAISE EXCEPTION USING ERRCODE='ZT018',MESSAGE='AVOIRS_STAGING_ROLLBACK_OK';
  EXCEPTION WHEN SQLSTATE 'ZT018' THEN
    IF SQLERRM<>'AVOIRS_STAGING_ROLLBACK_OK' THEN RAISE; END IF;
    annule:=true;
  END;

  IF NOT annule OR current_user NOT IN ('postgres','supabase_admin')
    OR EXISTS(SELECT 1 FROM auth.users WHERE id=e)
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=e)
    OR EXISTS(SELECT 1 FROM public.missions WHERE etablissement_id=e)
    OR EXISTS(SELECT 1 FROM public.mission_creneaux WHERE mission_id IN(mission_origine,mission_mensuelle,mission_soldee,mission_centime))
    OR EXISTS(SELECT 1 FROM public.factures WHERE etablissement_id=e)
    OR EXISTS(SELECT 1 FROM private.avoirs_commission_sources WHERE etablissement_id=e)
    OR EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements WHERE etablissement_id=e)
    OR EXISTS(SELECT 1 FROM private.facturation_email_livraisons WHERE destinataire_id=e)
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id=e)
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=e)
    OR EXISTS(SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id=e)
    OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE acteur_id=e OR id_ressource IN
      (origine,avoir40,avoir20,avoir_centime,mensuelle,soldee,centime,mission_origine,mission_mensuelle,mission_soldee,mission_centime))
  THEN RAISE EXCEPTION 'AVOIRS STAGE : résidu de fixture après sentinelle'; END IF;
END $recette$;
SELECT 'AVOIRS_IMPUTATION_STAGING_ROLLBACK' AS preuve,true AS annule,3 AS scenarios_financiers;
ROLLBACK;
