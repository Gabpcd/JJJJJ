-- Régression CANVAS : vrais corps installés, contraintes et douze triggers.
-- Fixtures TEST entièrement synthétiques ; aucun Storage, OTP ou fournisseur.
-- Aucun trigger désactivé. L'annulation interne survit aux wrappers CI retirant
-- les BEGIN/ROLLBACK externes. Un retour success ne remplace jamais l'état relu.
BEGIN;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='3s';
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE canvas_controles_resultat(rapport jsonb NOT NULL) ON COMMIT DROP;

DO $test$
DECLARE
  e uuid := '99201900-0000-4000-8000-000000000001';
  s uuid := '99201900-0000-4000-8000-000000000002';
  tiers_s uuid := '99201900-0000-4000-8000-000000000003';
  inconnu uuid := '99201900-0000-4000-8000-000000000004';
  tiers_e uuid := '99201900-0000-4000-8000-000000000005';
  lecture uuid := '99201900-0000-4000-8000-000000000006';
  rh uuid := '99201900-0000-4000-8000-000000000007';
  m uuid := '99201900-0000-4000-8000-000000000011';
  acteurs uuid[] := ARRAY[e,s,tiers_s,inconnu,tiers_e,lecture,rh];
  c uuid; mission_cas uuid; cas record; pin record;
  numero integer := 100;
  validations integer := 0;
  appels integer := 0;
  contraintes integer := 0;
  retour jsonb; second_retour jsonb; avant jsonb; apres jsonb; apres_double jsonb;
  avant_signatures jsonb; apres_signatures jsonb;
  premier_uid uuid; second_uid uuid;
  qr_avant integer; qr_apres integer;
  observations jsonb := '[]'::jsonb;
  corps text;
  code_sql text;
  nom_contrainte text;
  role_sql text;
  login_sql text;
  role_guc text;
  uid_nul boolean;
  refuse_check boolean;
  html text := '<article>FIXTURE ENTIEREMENT FICTIVE CANVAS - SANS VALEUR OFFICIELLE</article>';
  html_cas text;
  empreinte text;
  champs_signature text[];
  net_present boolean := to_regclass('net.http_request_queue') IS NOT NULL;
  reseau_avant bigint := 0;
  reseau_apres bigint := 0;
  triggers_attendus text[] := ARRAY[
    'dec_proteger_signature_contrat','dec_xss_contrat','trg_auto_partager_rib',
    'trg_creer_partage_rib_contrat','trg_dec_auto_generer_qr_mission',
    'trg_dec_email_contrat_a_signer','trg_dec_email_contrat_signe_complet',
    'trg_dec_notif_signature_soignant_recue','trg_dec_push_contrat_a_signer',
    'trg_dec_push_contrat_signe_complet','trg_p0_rbac_contrats_mission','trg_protect_contrat_integrity'];
BEGIN
  IF session_user NOT IN ('postgres','supabase_admin') OR current_user<>session_user THEN
    RAISE EXCEPTION 'CANVAS_TEST_PRIVILEGED_CONTEXT_REQUIRED'; END IF;
  -- Même précondition que contrat-service-v11 : ne pas déclencher une création
  -- Auth/profil ou un transport qui n'appartient pas au graphe relu de ce banc.
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & (4|16))<>0 AND tgenabled<>'D') THEN
    RAISE EXCEPTION 'CANVAS_TEST_AUTH_TRIGGER_NOT_REVIEWED'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(acteurs))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=ANY(acteurs))
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=ANY(acteurs))
    OR EXISTS(SELECT 1 FROM public.missions WHERE id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.contrats_mission WHERE id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.signatures_contrats WHERE id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.documents_soignants WHERE soignant_id=ANY(acteurs)
      OR id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.file_revue_manuelle WHERE id_entite=ANY(acteurs)) THEN
    RAISE EXCEPTION 'CANVAS_TEST_FIXTURE_COLLISION'; END IF;

  -- Les nouvelles définitions doivent être recensées, jamais épinglées sur
  -- les anciens corps vulnérables du témoin de diagnostic.
  FOR pin IN SELECT * FROM (VALUES
    ('fn_signer_contrat_soignant(uuid,text)','RPC_UTILISATEUR_AUTH_INTERNE'),
    ('fn_signer_contrat_etablissement(uuid,text)','MIXTE_TENANT_ADMIN')
  ) x(signature,categorie) LOOP
    IF NOT EXISTS(SELECT 1 FROM private.security_definer_inventory i
      JOIN pg_proc p ON p.oid=to_regprocedure('public.'||pin.signature)
      WHERE i.signature=pin.signature AND i.categorie=pin.categorie
        AND i.definition_md5=md5(p.prosrc) AND p.prosecdef) THEN
      RAISE EXCEPTION 'CANVAS_TEST_NEW_BODY_INVENTORY_MISMATCH: %',pin.signature;
    END IF;
  END LOOP;
  FOR pin IN SELECT * FROM (VALUES
    ('public.dec_proteger_signature_contrat()','74fc529a241273583515084a5e27a1d5'),
    ('public.fn_protect_contrat_integrity()','fd7ae0eebe94fd2a0e31efc4166ebda3'),
    ('public.fn_enforce_etablissement_rbac_trigger()','b3c7c595d6a159b623f91cb1ac5168cc'),
    ('public.dec_email_contrat_a_signer()','b8fa47fa053ba25fdb81c8940b681bfe'),
    ('public.dec_email_contrat_signe_complet()','df65f43984b5745a0c5a0cdaf15b66c9'),
    ('public.dec_notif_signature_soignant_recue()','1c07fc484466358ba0975d2ba2b8a4b9'),
    ('public.dec_push_contrat_a_signer()','3d2227081bec9d55d34d2a232a703b43'),
    ('public.dec_push_contrat_signe_complet()','5900565c77313d0ca019c5b933c1b9d0'),
    ('private.fn_contrat_lie_compte_test(uuid,uuid,uuid)','0d4dc700821172a61e4a95c44ac9568d'),
    ('public.fn_documents_ok_pour_mission(uuid,text)','813fe0eb1f1276b6d0595ffc4ad3e131'),
    ('public.fn_type_document_preuve_compatible(public.type_document,public.type_document)','78567117b6c8c13f35342c7fb7cbfd0f'),
    ('public.dec_auto_generer_qr_mission()','1b2076185abc0af8abad4c15d7a16e76'),
    ('public.trg_exiger_conformite_code_pointage()','bb1dd3b63e484abe3b478be0355b041d'),
    ('public.fn_exiger_conformite_demarrage_mission(uuid,uuid)','cdf6ca0b2ada39f86cc67f1acc5efd86'),
    ('public.fn_proteger_ecriture_document_soignant()','c490ce823768b0a23cd264ab17601155'),
    ('public.fn_proteger_tentative_verification_document()','454c5a96a63212715ce02e05252792bb'),
    ('public.fn_remplacer_preuves_documentaires_actives()','d3c8b5c807aacd605b065227c21bef9e'),
    ('public.dec_check_coherence_apres_doc_identite()','a7b63c1a57635ece14e593d448d35797'),
    ('public.fn_verifier_coherence_identite(uuid)','c743094421c90c375c2d34e875fa2792'),
    ('public.fn_recalculer_tous_documents_valides()','a032034a6ee0096e722e38abad2a3ee3'),
    ('public.fn_calculer_tous_documents_valides(uuid)','07ca4f4ed74acc2bbfaaf62454043d9e'),
    ('public.fn_trg_bloquer_documents_sante()','89ddba57700bd5566ecca29a260010d3'),
    ('public.fn_trg_recalculer_preuves_etudiant_document()','c078f7408c883a9e414078c717f84b4f')
  ) x(signature,expected_md5) LOOP
    SELECT p.prosrc INTO corps FROM pg_proc p WHERE p.oid=to_regprocedure(pin.signature);
    IF corps IS NULL OR md5(corps) IS DISTINCT FROM pin.expected_md5 THEN
      RAISE EXCEPTION 'CANVAS_TEST_DEPENDENCY_CHANGED: %',pin.signature;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.contrats_mission'::regclass
    AND NOT tgisinternal AND tgname=ANY(triggers_attendus) AND tgenabled='O')<>12
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.contrats_mission'::regclass
      AND NOT tgisinternal AND (tgenabled<>'O' OR tgname<>ALL(triggers_attendus))) THEN
    RAISE EXCEPTION 'CANVAS_TEST_REAL_TRIGGERS_REQUIRED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.contrats_mission'::regclass
    AND conname='contrats_mission_statut_check' AND convalidated) THEN
    RAISE EXCEPTION 'CANVAS_TEST_STATUS_CHECK_REQUIRED'; END IF;
  -- Les deux preuves divergentes ci-dessous sont des lignes synthétiques
  -- ajoutées directement dans le sous-bloc annulé, jamais un OTP réellement émis.
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.signatures_contrats'::regclass
    AND NOT tgisinternal AND tgenabled<>'D') THEN
    RAISE EXCEPTION 'CANVAS_TEST_SIGNATURE_LEDGER_TRIGGER_NOT_REVIEWED'; END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.documents_soignants'::regclass
    AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND tgenabled='O')<>7
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.documents_soignants'::regclass
      AND NOT tgisinternal AND (tgtype::integer & 4)<>0 AND (tgenabled<>'O' OR tgname<>ALL(ARRAY[
        'trg_10_remplacer_preuves_documentaires_actives','trg_bloquer_documents_sante',
        'trg_check_coherence_doc_identite','trg_proteger_ecriture_document_soignant',
        'trg_proteger_tentative_verification_document','trg_recalculer_docs_valides',
        'trg_recalculer_preuves_etudiant_document_insert_delete']::text[]))) THEN
    RAISE EXCEPTION 'CANVAS_TEST_DOCUMENT_INSERT_TRIGGERS_CHANGED'; END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.qr_codes_mission'::regclass
    AND NOT tgisinternal AND tgenabled='O')<>2
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.qr_codes_mission'::regclass
      AND NOT tgisinternal AND (tgenabled<>'O' OR tgname<>ALL(ARRAY[
        'trg_01_exiger_conformite_qr_mission','trg_p0_rbac_qr_codes']::text[]))) THEN
    RAISE EXCEPTION 'CANVAS_TEST_QR_TRIGGERS_CHANGED'; END IF;
  IF has_function_privilege('anon','public.fn_signer_contrat_soignant(uuid,text)','EXECUTE')
    OR has_function_privilege('anon','public.fn_signer_contrat_etablissement(uuid,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.fn_signer_contrat_soignant(uuid,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.fn_signer_contrat_etablissement(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'CANVAS_TEST_RPC_ACL_CHANGED'; END IF;
  IF net_present THEN EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO reseau_avant; END IF;

  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    PERFORM set_config('request.headers','{}',true);
    PERFORM set_config('jolene.admin_seed_override_reason','NON-REGRESSION CANVAS SYNTHETIQUE SOUS ROLLBACK',true);
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    SELECT id,'00000000-0000-0000-0000-000000000000',adresse,'authenticated','authenticated',
      jsonb_build_object('role',role_app,'is_test_playwright',true,'test_owner','canvas-controles-20261019'),now()
    FROM (VALUES
      (e,'canvas-controles-etab@example.invalid','ADMIN_ETABLISSEMENT'),
      (s,'canvas-controles-soignant@example.invalid','SOIGNANT'),
      (tiers_s,'canvas-controles-tiers-s@example.invalid','SOIGNANT'),
      (inconnu,'canvas-controles-inconnu@example.invalid','INCONNU'),
      (tiers_e,'canvas-controles-tiers-e@example.invalid','ADMIN_ETABLISSEMENT'),
      (lecture,'canvas-controles-lecture@example.invalid','ADMIN_ETABLISSEMENT'),
      (rh,'canvas-controles-rh@example.invalid','ADMIN_ETABLISSEMENT')
    ) u(id,adresse,role_app);
    INSERT INTO public.soignants(id,email,prenom,nom,date_naissance,profession,type_exercice,est_compte_test)
    VALUES(s,'canvas-controles-soignant@example.invalid','Fixture','Salarie',DATE '1990-01-01','IDE','SALARIE',true),
      (tiers_s,'canvas-controles-tiers-s@example.invalid','Fixture','Tiers',NULL,'IDE','SALARIE',true);
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
    VALUES(e,'ETABLISSEMENT FICTIF CANVAS','99201900000001','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001','canvas-controles-etab@example.invalid',true),
      (tiers_e,'AUTRE ETABLISSEMENT FICTIF CANVAS','99201900000005','CLINIQUE_PRIVEE','Adresse fictive','Paris','75001','canvas-controles-tiers-e@example.invalid',true);
    INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
    VALUES(e,lecture,'LECTURE_SEULE',true),(e,rh,'RH',true);
    UPDATE public.preferences_notifications
      SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
      WHERE utilisateur_id=ANY(acteurs);
    -- Forme synthétique du témoin contrat-storage-acces, sans présence,
    -- qualification ni fichier. Aucun travail réellement effectué n'est affirmé.
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,
      taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,type_paiement_soignant)
    VALUES(m,e,'MISSION SYNTHETIQUE CONTROLES CANVAS','IDE','2035-06-18 09:00:00+02',
      '2035-06-18 17:00:00+02',8,20,'TERMINEE',s,'SALARIE','SALARIE','BULLETIN_PAIE');
    IF private.fn_contrat_lie_compte_test(m,s,e) IS NOT TRUE
      OR (SELECT count(*) FROM public.soignants WHERE id=ANY(ARRAY[s,tiers_s]) AND est_compte_test IS TRUE)<>2
      OR (SELECT count(*) FROM public.etablissements WHERE id=ANY(ARRAY[e,tiers_e]) AND est_compte_test IS TRUE)<>2 THEN
      RAISE EXCEPTION 'CANVAS_TEST_SYNTHETIC_SCOPE_NOT_CLOSED'; END IF;

    -- Même forme que rpps-diploma-exemption, sans dispense RPPS : seules les
    -- quatre preuves IDE critiques du régime salarié sont préparées. Ces lignes
    -- sont entièrement fictives, sans fichier Storage ni contrôle officiel/IA.
    -- La CNI reprend l'identité fictive du profil pour laisser les vrais triggers
    -- calculer sa cohérence sans créer une revue manuelle incidente.
    IF (SELECT array_agg(drp.type_document::text ORDER BY drp.type_document::text)
      FROM public.documents_requis_par_profession drp WHERE drp.profession='IDE'
        AND drp.est_critique IS TRUE AND drp.type_exercice_requis IN ('TOUS','SALARIE_ONLY'))
      IS DISTINCT FROM ARRAY['CARTE_IDENTITE','DIPLOME','RIB','RPPS_ADELI']::text[]
      OR public.fn_documents_ok_pour_mission(s,'SALARIE') IS NOT FALSE THEN
      RAISE EXCEPTION 'CANVAS_TEST_DOCUMENT_RULES_OR_EMPTY_BASELINE_CHANGED'; END IF;
    INSERT INTO public.documents_soignants(id,soignant_id,type_document,s3_cle,nom_fichier,
      statut_verification,est_critique,valide_depuis,valide_jusqua,verifie_le,
      resultat_ia,nom_extrait_ia,prenom_extrait_ia,coherence_nom)
    SELECT ('99201900-0000-4000-8000-'||lpad((800+row_number() OVER(ORDER BY drp.type_document::text))::text,12,'0'))::uuid,
      s,drp.type_document,s::text||'/documents/synthetique-canvas-'||lower(drp.type_document::text)||'.pdf',
      'FIXTURE-SANS-VALEUR-OFFICIELLE-'||drp.type_document::text||'.pdf','VERIFIE',true,current_date,
      CASE WHEN drp.a_expiration THEN DATE '2099-12-31' ELSE NULL END,now(),
      jsonb_build_object('fixture_synthetique',true,'qualification_officielle',false,'analyse_ia_effectuee',false)
        || CASE WHEN drp.type_document='CARTE_IDENTITE'
          THEN '{"date_naissance_extraite":"1990-01-01"}'::jsonb ELSE '{}'::jsonb END,
      CASE WHEN drp.type_document='CARTE_IDENTITE' THEN 'Salarie' ELSE NULL END,
      CASE WHEN drp.type_document='CARTE_IDENTITE' THEN 'Fixture' ELSE NULL END,
      CASE WHEN drp.type_document='CARTE_IDENTITE' THEN true ELSE NULL END
    FROM public.documents_requis_par_profession drp WHERE drp.profession='IDE'
      AND drp.est_critique IS TRUE AND drp.type_exercice_requis IN ('TOUS','SALARIE_ONLY');
    IF public.fn_documents_ok_pour_mission(s,'SALARIE') IS NOT TRUE
      OR (SELECT count(*) FROM public.documents_soignants WHERE soignant_id=s AND statut_verification='VERIFIE'
        AND supprime_le IS NULL AND revoque_le IS NULL)<>4
      OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=s AND rpps_verifie IS NOT TRUE
        AND identite_verifiee IS TRUE AND coherence_identite='COHERENT')
      OR EXISTS(SELECT 1 FROM public.file_revue_manuelle WHERE id_entite=ANY(acteurs)) THEN
      RAISE EXCEPTION 'CANVAS_TEST_SYNTHETIC_DOCUMENT_READINESS_FAILED'; END IF;

    FOR cas IN SELECT * FROM (VALUES
      ('VALIDE_S','S',s,'EN_ATTENTE_SIGNATURES','VALID',false,'SUCCESS',false),
      ('VALIDE_E','E',e,'EN_ATTENTE_SIGNATURES','VALID',false,'SUCCESS',false),
      ('MEMBRE_RH','E',rh,'EN_ATTENTE_SIGNATURES','VALID',false,'SUCCESS',false),
      ('MEMBRE_LECTURE','E',lecture,'EN_ATTENTE_SIGNATURES','VALID',false,'NON_AUTORISE',false),
      ('TIERS_E','E',tiers_e,'EN_ATTENTE_SIGNATURES','VALID',false,'NON_AUTORISE',false),
      ('TIERS_S_VERS_S','S',tiers_s,'EN_ATTENTE_SIGNATURES','VALID',false,'NON_AUTORISE',false),
      ('TIERS_S_VERS_E','E',tiers_s,'EN_ATTENTE_SIGNATURES','VALID',false,'NON_AUTORISE',false),
      ('INCONNU_VERS_E','E',inconnu,'EN_ATTENTE_SIGNATURES','VALID',false,'NON_AUTORISE',false),
      ('ANON_VERS_E','ANON',NULL::uuid,'EN_ATTENTE_SIGNATURES','VALID',false,'42501',false),
      ('BANNI_S','S',s,'EN_ATTENTE_SIGNATURES','VALID',true,'NON_AUTHENTIFIE',false),
      ('BANNI_E','E',e,'EN_ATTENTE_SIGNATURES','VALID',true,'NON_AUTHENTIFIE',false),
      ('ANNULE_S','S',s,'ANNULE','VALID',false,'CONTRAT_INACTIF',false),
      ('ANNULE_E','E',e,'ANNULE','VALID',false,'CONTRAT_INACTIF',false),
      ('EXPIRE_S','S',s,'EXPIRE','VALID',false,'CONTRAT_INACTIF',false),
      ('EXPIRE_E','E',e,'EXPIRE','VALID',false,'CONTRAT_INACTIF',false),
      ('REFUSE_S','S',s,'REFUSE','VALID',false,'CONTRAT_INACTIF',false),
      ('REFUSE_E','E',e,'REFUSE','VALID',false,'CONTRAT_INACTIF',false),
      ('HASH_INCOHERENT_S','S',s,'EN_ATTENTE_SIGNATURES','BAD_HASH',false,'HASH_DOCUMENT_CHANGE',false),
      ('HASH_INCOHERENT_E','E',e,'EN_ATTENTE_SIGNATURES','BAD_HASH',false,'HASH_DOCUMENT_CHANGE',false),
      ('HASH_ABSENT_S','S',s,'EN_ATTENTE_SIGNATURES','HASH_ABSENT',false,'HASH_DOCUMENT_CHANGE',false),
      ('PLACEHOLDER_E','E',e,'EN_ATTENTE_SIGNATURES','PLACEHOLDER',false,'HASH_DOCUMENT_CHANGE',false),
      ('PREUVE_RENDU_ABSENT_S','S',s,'EN_ATTENTE_SIGNATURES','NO_RENDER',false,'HASH_DOCUMENT_CHANGE',false),
      ('PREUVE_CHEMIN_ABSENT_E','E',e,'EN_ATTENTE_SIGNATURES','NO_PATH',false,'HASH_DOCUMENT_CHANGE',false),
      ('DOUBLE_S','S',s,'EN_ATTENTE_SIGNATURES','VALID',false,'SUCCESS',true),
      ('DOUBLE_E','E',e,'EN_ATTENTE_SIGNATURES','VALID',false,'SUCCESS',true)
    ) x(nom,rpc,uid,statut_initial,preuve,banni,attendu,double_appel) LOOP
      numero:=numero+1;
      c:=('99201900-0000-4000-8000-'||lpad(numero::text,12,'0'))::uuid;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claim.role','service_role',true);
      PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
      PERFORM set_config('jolene.signature_soignant_en_cours','',true);
      retour:=NULL; second_retour:=NULL; code_sql:=NULL; nom_contrainte:=NULL; refuse_check:=false;
      html_cas:=html||CASE WHEN cas.preuve='PLACEHOLDER' THEN '<p>{{ champ_non_rendu }}</p>' ELSE '' END;
      empreinte:=CASE WHEN cas.preuve='HASH_ABSENT' THEN NULL WHEN cas.preuve='BAD_HASH' THEN repeat('0',64)
        ELSE encode(extensions.digest(convert_to(html_cas,'UTF8'),'sha256'),'hex') END;
      BEGIN
        INSERT INTO public.contrats_mission(id,mission_id,etablissement_id,soignant_id,type_contrat,numero_contrat,
          statut,mode_signature,signature_soignant,signature_etablissement,contenu_html,hash_document,storage_path,contenu_html_rendu_le)
        VALUES(c,m,e,s,'CDD','SYNTHETIQUE-CANVAS-CONTROLES-'||numero,cas.statut_initial,'CANVAS',false,false,
          html_cas,empreinte,CASE WHEN cas.preuve='NO_PATH' THEN NULL ELSE 'synthetique-non-stocke/'||c||'/original.html' END,
          CASE WHEN cas.preuve='NO_RENDER' THEN NULL ELSE now() END);
      EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS nom_contrainte=CONSTRAINT_NAME;
        IF cas.statut_initial<>'REFUSE' OR nom_contrainte IS DISTINCT FROM 'contrats_mission_statut_check' THEN
          RAISE EXCEPTION 'CANVAS_TEST_FIXTURE_CHECK_UNEXPECTED: %',cas.nom; END IF;
        refuse_check:=true;
      END;
      IF refuse_check THEN
        validations:=validations+1; contraintes:=contraintes+1;
        observations:=observations||jsonb_build_array(jsonb_build_object('case',cas.nom,'passed',true,
          'mode','STATUS_CHECK_REJECTED_FIXTURE','rpcCalled',false));
        CONTINUE;
      END IF;
      SELECT to_jsonb(cm) INTO avant FROM public.contrats_mission cm WHERE cm.id=c;
      IF avant->>'contenu_html' IS DISTINCT FROM html_cas
        OR avant->>'hash_document' IS DISTINCT FROM empreinte
        OR (cas.preuve='PLACEHOLDER' AND avant->>'contenu_html' !~ '\{\{[[:space:]]*[^}]+[[:space:]]*\}\}') THEN
        RAISE EXCEPTION 'CANVAS_TEST_FIXTURE_PROOF_UNEXPECTED: %',cas.nom; END IF;
      IF cas.banni THEN UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=cas.uid; END IF;
      IF cas.rpc='ANON' THEN EXECUTE 'SET LOCAL ROLE anon'; ELSE EXECUTE 'SET LOCAL ROLE authenticated'; END IF;
      PERFORM set_config('request.jwt.claim.sub',COALESCE(cas.uid::text,''),true);
      PERFORM set_config('request.jwt.claim.role',CASE WHEN cas.rpc='ANON' THEN 'anon' ELSE 'authenticated' END,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',cas.uid,
        'role',CASE WHEN cas.rpc='ANON' THEN 'anon' ELSE 'authenticated' END)::text,true);
      EXECUTE 'SELECT current_user::text,session_user::text,current_setting(''role'',true),auth.uid() IS NULL'
        INTO role_sql,login_sql,role_guc,uid_nul;
      IF role_sql IS DISTINCT FROM (CASE WHEN cas.rpc='ANON' THEN 'anon' ELSE 'authenticated' END)
        OR uid_nul IS DISTINCT FROM (cas.uid IS NULL) THEN
        RAISE EXCEPTION 'CANVAS_TEST_ROLE_CONTEXT_INVALID: %',cas.nom; END IF;
      BEGIN
        IF cas.rpc='S' THEN
          EXECUTE 'SELECT public.fn_signer_contrat_soignant($1,$2)' INTO retour USING c,'image-fictive-sans-valeur';
        ELSE
          EXECUTE 'SELECT public.fn_signer_contrat_etablissement($1,$2)' INTO retour USING c,'image-fictive-sans-valeur';
        END IF;
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code_sql=RETURNED_SQLSTATE;
      END;
      appels:=appels+1;
      EXECUTE 'RESET ROLE';
      SELECT to_jsonb(cm) INTO apres FROM public.contrats_mission cm WHERE cm.id=c;
      IF cas.attendu='SUCCESS' THEN
        champs_signature:=ARRAY['statut','modifie_le']::text[] || (CASE WHEN cas.rpc='S' THEN
          ARRAY['signature_soignant','signature_soignant_le','signature_image_soignant','signature_navigateur_soignant']::text[]
          ELSE ARRAY['signature_etablissement','signature_etablissement_le','signature_image_etablissement','signature_navigateur_etablissement']::text[] END);
        IF code_sql IS NOT NULL OR retour->>'success' IS DISTINCT FROM 'true'
          OR apres->>'statut' IS DISTINCT FROM (CASE WHEN cas.rpc='S' THEN 'SIGNE_SOIGNANT' ELSE 'SIGNE_ETABLISSEMENT' END)
          OR apres->>(CASE WHEN cas.rpc='S' THEN 'signature_soignant' ELSE 'signature_etablissement' END) IS DISTINCT FROM 'true'
          OR apres->>(CASE WHEN cas.rpc='S' THEN 'signature_etablissement' ELSE 'signature_soignant' END) IS DISTINCT FROM 'false'
          OR apres->>(CASE WHEN cas.rpc='S' THEN 'signature_soignant_le' ELSE 'signature_etablissement_le' END) IS NULL
          OR (apres-champs_signature) IS DISTINCT FROM (avant-champs_signature) THEN
          RAISE EXCEPTION 'CANVAS_TEST_POSITIVE_CONTROL_FAILED: %',cas.nom; END IF;
      ELSIF cas.attendu='42501' THEN
        IF code_sql IS DISTINCT FROM '42501' OR apres IS DISTINCT FROM avant THEN
          RAISE EXCEPTION 'CANVAS_TEST_ANON_NOT_REFUSED'; END IF;
      ELSE
        IF code_sql IS NOT NULL OR retour->>'error_code' IS DISTINCT FROM cas.attendu
          OR retour->>'success' IS DISTINCT FROM 'false' OR apres IS DISTINCT FROM avant THEN
          RAISE EXCEPTION 'CANVAS_TEST_REFUSAL_OR_IMMUTABILITY_FAILED: %',cas.nom; END IF;
      END IF;
      IF cas.double_appel THEN
        EXECUTE 'SET LOCAL ROLE authenticated';
        IF cas.rpc='S' THEN
          EXECUTE 'SELECT public.fn_signer_contrat_soignant($1,$2)' INTO second_retour USING c,'autre-image-fictive';
        ELSE
          EXECUTE 'SELECT public.fn_signer_contrat_etablissement($1,$2)' INTO second_retour USING c,'autre-image-fictive';
        END IF;
        appels:=appels+1;
        EXECUTE 'RESET ROLE';
        SELECT to_jsonb(cm) INTO apres_double FROM public.contrats_mission cm WHERE cm.id=c;
        IF second_retour->>'error' IS DISTINCT FROM 'Déjà signé' OR second_retour->>'success'='true'
          OR apres_double IS DISTINCT FROM apres THEN
          RAISE EXCEPTION 'CANVAS_TEST_DOUBLE_CALL_CHANGED_EVIDENCE: %',cas.nom; END IF;
      END IF;
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claim.role','service_role',true);
      PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
      IF cas.banni THEN UPDATE auth.users SET banned_until=NULL WHERE id=cas.uid; END IF;
      validations:=validations+1;
      observations:=observations||jsonb_build_array(jsonb_build_object('case',cas.nom,'passed',true,
        'mode','REAL_RPC_DYNAMIC_ROLE','currentUserAtCall',role_sql,'sessionUserAtCall',login_sql,
        'roleSettingAtCall',role_guc,'authUidNullAtCall',uid_nul,'secondCallChecked',cas.double_appel));
    END LOOP;
    -- Deux séquences de vraies RPC, puis les mêmes secondes signatures avec
    -- une preuve signée divergente dans le ledger. Les 25 cas précédents restent
    -- inchangés. Chaque première signature est relue avant le second appel.
    FOR cas IN SELECT * FROM (VALUES
      ('COMPLET_S_APRES_E','E','S',false),
      ('COMPLET_E_APRES_S','S','E',false),
      ('HASH_SIGNATURE_DIVERGENT_S','E','S',true),
      ('HASH_SIGNATURE_DIVERGENT_E','S','E',true)
    ) x(nom,premiere_rpc,rpc,hash_divergent) LOOP
      numero:=numero+1;
      c:=('99201900-0000-4000-8000-'||lpad(numero::text,12,'0'))::uuid;
      mission_cas:=('99201900-0000-4000-8000-'||lpad((1000+numero)::text,12,'0'))::uuid;
      premier_uid:=CASE WHEN cas.premiere_rpc='S' THEN s ELSE e END;
      second_uid:=CASE WHEN cas.rpc='S' THEN s ELSE e END;
      EXECUTE 'RESET ROLE';
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claim.role','service_role',true);
      PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
      PERFORM set_config('jolene.signature_soignant_en_cours','',true);
      empreinte:=encode(extensions.digest(convert_to(html,'UTF8'),'sha256'),'hex');
      -- Une mission distincte et espacée par cas impose un QR initialement
      -- absent, sans collision de planning ni réutilisation du QR du cas avant.
      INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,
        taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,type_paiement_soignant)
      VALUES(mission_cas,e,'MISSION SYNTHETIQUE SEQUENCE CANVAS','IDE',
        timestamptz '2035-06-18 09:00:00+02'+(numero-125)*interval '2 days',
        timestamptz '2035-06-18 17:00:00+02'+(numero-125)*interval '2 days',
        8,20,'ASSIGNEE',s,'SALARIE','SALARIE','BULLETIN_PAIE');
      IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=mission_cas AND statut='ASSIGNEE'
        AND soignant_assigne_id=s AND etablissement_id=e)
        OR private.fn_contrat_lie_compte_test(mission_cas,s,e) IS NOT TRUE
        OR public.fn_documents_ok_pour_mission(s,'SALARIE') IS NOT TRUE THEN
        RAISE EXCEPTION 'CANVAS_TEST_ASSIGNED_SEQUENCE_NOT_READY: %',cas.nom; END IF;
      SELECT count(*) INTO qr_avant FROM public.qr_codes_mission WHERE mission_id=mission_cas;
      IF qr_avant<>0 THEN RAISE EXCEPTION 'CANVAS_TEST_SEQUENCE_QR_NOT_EMPTY: %',cas.nom; END IF;
      INSERT INTO public.contrats_mission(id,mission_id,etablissement_id,soignant_id,type_contrat,numero_contrat,
        statut,mode_signature,signature_soignant,signature_etablissement,contenu_html,hash_document,storage_path,contenu_html_rendu_le)
      VALUES(c,mission_cas,e,s,'CDD','SYNTHETIQUE-CANVAS-CONTROLES-'||numero,'EN_ATTENTE_SIGNATURES','CANVAS',false,false,
        html,empreinte,'synthetique-non-stocke/'||c||'/original.html',now());
      SELECT to_jsonb(cm) INTO avant FROM public.contrats_mission cm WHERE cm.id=c;
      IF avant->>'contenu_html' IS DISTINCT FROM html OR avant->>'hash_document' IS DISTINCT FROM empreinte THEN
        RAISE EXCEPTION 'CANVAS_TEST_SEQUENCE_FIXTURE_INVALID: %',cas.nom; END IF;

      EXECUTE 'SET LOCAL ROLE authenticated';
      PERFORM set_config('request.jwt.claim.sub',premier_uid::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',premier_uid,'role','authenticated')::text,true);
      PERFORM set_config('request.headers','{"user-agent":"canvas-fixture-premiere-signature"}',true);
      EXECUTE 'SELECT current_user::text,session_user::text,current_setting(''role'',true),auth.uid() IS NULL'
        INTO role_sql,login_sql,role_guc,uid_nul;
      IF role_sql IS DISTINCT FROM 'authenticated' OR uid_nul IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'CANVAS_TEST_FIRST_ROLE_CONTEXT_INVALID: %',cas.nom; END IF;
      IF cas.premiere_rpc='S' THEN
        EXECUTE 'SELECT public.fn_signer_contrat_soignant($1,$2)' INTO retour USING c,'image-fictive-premiere-signature';
      ELSE
        EXECUTE 'SELECT public.fn_signer_contrat_etablissement($1,$2)' INTO retour USING c,'image-fictive-premiere-signature';
      END IF;
      appels:=appels+1;
      EXECUTE 'RESET ROLE';
      SELECT to_jsonb(cm) INTO apres FROM public.contrats_mission cm WHERE cm.id=c;
      IF EXISTS(SELECT 1 FROM public.qr_codes_mission WHERE mission_id=mission_cas) THEN
        RAISE EXCEPTION 'CANVAS_TEST_QR_CREATED_BEFORE_BOTH_SIGNATURES: %',cas.nom; END IF;
      champs_signature:=ARRAY['statut','modifie_le']::text[] || (CASE WHEN cas.premiere_rpc='S' THEN
        ARRAY['signature_soignant','signature_soignant_le','signature_image_soignant','signature_navigateur_soignant']::text[]
        ELSE ARRAY['signature_etablissement','signature_etablissement_le','signature_image_etablissement','signature_navigateur_etablissement']::text[] END);
      IF retour->>'success' IS DISTINCT FROM 'true'
        OR apres->>'statut' IS DISTINCT FROM (CASE WHEN cas.premiere_rpc='S' THEN 'SIGNE_SOIGNANT' ELSE 'SIGNE_ETABLISSEMENT' END)
        OR apres->>(CASE WHEN cas.premiere_rpc='S' THEN 'signature_soignant' ELSE 'signature_etablissement' END) IS DISTINCT FROM 'true'
        OR apres->>(CASE WHEN cas.premiere_rpc='S' THEN 'signature_soignant_le' ELSE 'signature_etablissement_le' END) IS NULL
        OR apres->>(CASE WHEN cas.premiere_rpc='S' THEN 'signature_image_soignant' ELSE 'signature_image_etablissement' END) IS DISTINCT FROM 'image-fictive-premiere-signature'
        OR apres->>(CASE WHEN cas.premiere_rpc='S' THEN 'signature_navigateur_soignant' ELSE 'signature_navigateur_etablissement' END) IS DISTINCT FROM 'canvas-fixture-premiere-signature'
        OR (apres-champs_signature) IS DISTINCT FROM (avant-champs_signature) THEN
        RAISE EXCEPTION 'CANVAS_TEST_FIRST_SIGNATURE_INVALID: %',cas.nom; END IF;
      avant:=apres;
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claim.role','service_role',true);
      PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
      PERFORM set_config('jolene.signature_soignant_en_cours','',true);
      IF cas.hash_divergent THEN
        INSERT INTO public.signatures_contrats(id,contrat_id,signataire_user_id,signataire_role,
          signe_a,hash_document,statut_signature,user_agent,signature_image_base64,audit_trail)
        VALUES(c,c,premier_uid,CASE WHEN cas.premiere_rpc='S' THEN 'soignant' ELSE 'etablissement' END,
          now(),repeat('0',64),'signe','preuve-ledger-synthetique','image-ledger-fictive',
          '{"fixture_synthetique":true,"otp_reel_emis":false}'::jsonb);
        IF NOT EXISTS(SELECT 1 FROM public.signatures_contrats sc WHERE sc.id=c AND sc.contrat_id=c
          AND sc.statut_signature='signe' AND sc.hash_document IS DISTINCT FROM empreinte) THEN
          RAISE EXCEPTION 'CANVAS_TEST_DIVERGENT_LEDGER_FIXTURE_INVALID: %',cas.nom; END IF;
      END IF;
      SELECT COALESCE(jsonb_agg(to_jsonb(sc) ORDER BY sc.id),'[]'::jsonb) INTO avant_signatures
        FROM public.signatures_contrats sc WHERE sc.contrat_id=c;

      EXECUTE 'SET LOCAL ROLE authenticated';
      PERFORM set_config('request.jwt.claim.sub',second_uid::text,true);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',second_uid,'role','authenticated')::text,true);
      PERFORM set_config('request.headers','{"user-agent":"canvas-fixture-seconde-signature"}',true);
      EXECUTE 'SELECT current_user::text,session_user::text,current_setting(''role'',true),auth.uid() IS NULL'
        INTO role_sql,login_sql,role_guc,uid_nul;
      IF role_sql IS DISTINCT FROM 'authenticated' OR uid_nul IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'CANVAS_TEST_SECOND_ROLE_CONTEXT_INVALID: %',cas.nom; END IF;
      code_sql:=NULL; second_retour:=NULL;
      BEGIN
        IF cas.rpc='S' THEN
          EXECUTE 'SELECT public.fn_signer_contrat_soignant($1,$2)' INTO second_retour USING c,'image-fictive-seconde-signature';
        ELSE
          EXECUTE 'SELECT public.fn_signer_contrat_etablissement($1,$2)' INTO second_retour USING c,'image-fictive-seconde-signature';
        END IF;
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code_sql=RETURNED_SQLSTATE;
      END;
      appels:=appels+1;
      EXECUTE 'RESET ROLE';
      SELECT to_jsonb(cm) INTO apres FROM public.contrats_mission cm WHERE cm.id=c;
      SELECT COALESCE(jsonb_agg(to_jsonb(sc) ORDER BY sc.id),'[]'::jsonb) INTO apres_signatures
        FROM public.signatures_contrats sc WHERE sc.contrat_id=c;
      SELECT count(*) INTO qr_apres FROM public.qr_codes_mission WHERE mission_id=mission_cas;
      IF apres_signatures IS DISTINCT FROM avant_signatures THEN
        RAISE EXCEPTION 'CANVAS_TEST_SIGNED_LEDGER_CHANGED: %',cas.nom; END IF;
      IF cas.hash_divergent THEN
        IF code_sql IS NOT NULL OR second_retour->>'success' IS DISTINCT FROM 'false'
          OR second_retour->>'error_code' IS DISTINCT FROM 'HASH_DOCUMENT_CHANGE' OR apres IS DISTINCT FROM avant
          OR qr_apres IS DISTINCT FROM qr_avant THEN
          RAISE EXCEPTION 'CANVAS_TEST_SIGNED_HASH_NOT_REFUSED: %',cas.nom; END IF;
      ELSE
        champs_signature:=ARRAY['statut','modifie_le']::text[] || (CASE WHEN cas.rpc='S' THEN
          ARRAY['signature_soignant','signature_soignant_le','signature_image_soignant','signature_navigateur_soignant']::text[]
          ELSE ARRAY['signature_etablissement','signature_etablissement_le','signature_image_etablissement','signature_navigateur_etablissement']::text[] END);
        IF code_sql IS NOT NULL OR second_retour->>'success' IS DISTINCT FROM 'true'
          OR apres->>'statut' IS DISTINCT FROM 'SIGNE_COMPLET'
          OR apres->>'signature_soignant' IS DISTINCT FROM 'true'
          OR apres->>'signature_etablissement' IS DISTINCT FROM 'true'
          OR apres->>(CASE WHEN cas.rpc='S' THEN 'signature_soignant_le' ELSE 'signature_etablissement_le' END) IS NULL
          OR apres->>(CASE WHEN cas.rpc='S' THEN 'signature_image_soignant' ELSE 'signature_image_etablissement' END) IS DISTINCT FROM 'image-fictive-seconde-signature'
          OR apres->>(CASE WHEN cas.rpc='S' THEN 'signature_navigateur_soignant' ELSE 'signature_navigateur_etablissement' END) IS DISTINCT FROM 'canvas-fixture-seconde-signature'
          OR (apres-champs_signature) IS DISTINCT FROM (avant-champs_signature) THEN
          RAISE EXCEPTION 'CANVAS_TEST_COMPLETION_OR_FIRST_PROOF_CHANGED: %',cas.nom; END IF;
        IF qr_apres<>1 OR NOT EXISTS(SELECT 1 FROM public.qr_codes_mission
          WHERE mission_id=mission_cas AND type='UNIVERSEL' AND actif IS TRUE AND nb_scans=0
            AND NULLIF(token,'') IS NOT NULL AND expire_le>now() AND expire_le<=now()+interval '7 days') THEN
          RAISE EXCEPTION 'CANVAS_TEST_COMPLETE_SIGNATURE_QR_NOT_CREATED: %',cas.nom; END IF;
      END IF;
      PERFORM set_config('request.jwt.claim.sub','',true);
      PERFORM set_config('request.jwt.claim.role','service_role',true);
      PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
      PERFORM set_config('request.headers','{}',true);
      validations:=validations+1;
      observations:=observations||jsonb_build_array(jsonb_build_object('case',cas.nom,'passed',true,
        'mode','REAL_RPC_DYNAMIC_ROLE','currentUserAtCall',role_sql,'sessionUserAtCall',login_sql,
        'roleSettingAtCall',role_guc,'authUidNullAtCall',uid_nul,'firstSignaturePreserved',true,
        'signedLedgerPreserved',true,'divergentSignedHashChecked',cas.hash_divergent,
        'assignedMissionDocumentGateChecked',true,'qrCountBefore',qr_avant,'qrCountAfter',qr_apres,
        'qrCreatedAfterBothSignatures',NOT cas.hash_divergent,'qrUnchangedOnRefusal',cas.hash_divergent));
    END LOOP;
    IF validations<>29 OR jsonb_array_length(observations)<>29 THEN RAISE EXCEPTION 'CANVAS_TEST_CASE_COUNT'; END IF;
    IF net_present THEN EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO reseau_apres; END IF;
    IF reseau_apres IS DISTINCT FROM reseau_avant THEN RAISE EXCEPTION 'CANVAS_TEST_UNEXPECTED_NET_QUEUE_CHANGE'; END IF;
    RAISE EXCEPTION USING ERRCODE='ZCV02',MESSAGE='ROLLBACK_ALL_CANVAS_CONTROL_FIXTURES';
  EXCEPTION WHEN SQLSTATE 'ZCV02' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(acteurs))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=ANY(acteurs))
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=ANY(acteurs))
    OR EXISTS(SELECT 1 FROM public.missions WHERE id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.contrats_mission WHERE id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.signatures_contrats WHERE id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.documents_soignants WHERE soignant_id=ANY(acteurs)
      OR id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.qr_codes_mission WHERE mission_id::text LIKE '99201900-0000-4000-8000-%')
    OR EXISTS(SELECT 1 FROM public.file_revue_manuelle WHERE id_entite=ANY(acteurs)) THEN
    RAISE EXCEPTION 'CANVAS_TEST_INNER_ROLLBACK_FAILED'; END IF;
  INSERT INTO pg_temp.canvas_controles_resultat VALUES(jsonb_build_object(
    'schema','jolene-canvas-controls/v1','casesPassed',validations,'rpcCalls',appels,
    'statusConstraintChecks',contraintes,'fixturesRolledBackBeforeReport',true,
    'netRequestQueueUnchanged',reseau_apres=reseau_avant,'frontendVerified',false,
    'providerIntegrationProven',false,'cases',observations));
END;
$test$;
SELECT rapport FROM pg_temp.canvas_controles_resultat;
ROLLBACK;
