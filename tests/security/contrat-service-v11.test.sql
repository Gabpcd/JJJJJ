-- Validation sous rollback : aucune image réelle, aucun appel réseau.
BEGIN;
DO $test$
DECLARE
  etab uuid := '99011000-0000-4000-8000-000000000001';
  autre uuid := '99011000-0000-4000-8000-000000000002';
  lecture uuid := '99011000-0000-4000-8000-000000000003';
  abandon uuid := '99011000-0000-4000-8000-000000000004';
  purge uuid := '99011000-0000-4000-8000-000000000005';
  purge_auth uuid := '99011000-0000-4000-8000-000000000006';
  proprietaire uuid := '99011000-0000-4000-8000-000000000007';
  p jsonb; nouveau jsonb; resultat jsonb; preuve jsonb; legacy jsonb; document_signe jsonb; lecture_document jsonb;
  cle text := etab::text || '/signatures/contrat-service-test.png';
  refuse boolean;
  v_annule boolean := false;
  v_ids uuid[] := ARRAY[etab,autre,lecture,abandon,purge,purge_auth,proprietaire];
BEGIN
  -- Le DDL draft doit être chargé dans la transaction de recette, jamais par
  -- db push. Ces contrôles ne remplacent pas le préflight des effets transitifs.
  IF session_user NOT IN ('postgres','supabase_admin')
    OR EXISTS(SELECT 1 FROM cron.job WHERE active)
  THEN RAISE EXCEPTION 'Contrat v11 : contexte SQL staging isolé requis'; END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
    AND NOT tgisinternal AND (tgtype::integer & (4|16))<>0 AND tgenabled<>'D')
  THEN RAISE EXCEPTION 'Contrat v11 : trigger Auth INSERT/UPDATE non inventorié'; END IF;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.membres_etablissement WHERE user_id=ANY(v_ids) OR etablissement_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.contrats_service_preparations WHERE etablissement_id=ANY(v_ids) OR prepare_par=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.contrats_service_signatures WHERE etablissement_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE acteur_id=ANY(v_ids) OR id_ressource=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM private.suppressions_compte_confirmees WHERE utilisateur_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM private.suppression_etablissement_context WHERE utilisateur_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='jolene-documents' AND split_part(name,'/',1)=ANY(v_ids::text[]))
  THEN RAISE EXCEPTION 'Contrat v11 : identifiants de fixture déjà présents'; END IF;
  BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
  SELECT ('99011000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
    '00000000-0000-0000-0000-000000000000','contrat-v11-'||n||'@example.invalid',
    'authenticated','authenticated',jsonb_build_object('role','ADMIN_ETABLISSEMENT','is_test_playwright',true),now()
  FROM generate_series(1,7) n;
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
  VALUES(etab,'Recette contrat','99011000000001','CLINIQUE_PRIVEE','1 rue Test','Paris','75001','contrat-v11-1@example.invalid',true),
    (autre,'Autre contrat','99011000000002','CLINIQUE_PRIVEE','2 rue Test','Paris','75001','contrat-v11-2@example.invalid',true),
    (abandon,'Contrat abandonné','99011000000004','CLINIQUE_PRIVEE','4 rue Test','Paris','75001','contrat-v11-4@example.invalid',true),
    (purge,'Contrat fixture','99011000000005','CLINIQUE_PRIVEE','5 rue Test','Paris','75001','contrat-v11-5@example.invalid',true),
    (purge_auth,'Contrat fixture Auth','99011000000006','CLINIQUE_PRIVEE','6 rue Test','Paris','75001','contrat-v11-6@example.invalid',true);
  -- Les cinq profils restent synthétiques ; aucun canal de notification n'est
  -- ouvert pour les étapes signature/anonymisation suivantes.
  UPDATE public.preferences_notifications SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false
    WHERE utilisateur_id=ANY(v_ids);
  IF (SELECT count(*) FROM public.preferences_notifications WHERE utilisateur_id=ANY(v_ids)
    AND NOT canal_email AND NOT canal_sms AND NOT canal_push AND NOT canal_in_app)<>5
  THEN RAISE EXCEPTION 'Contrat v11 : canaux de fixture non fermés'; END IF;
  INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif) VALUES(etab,lecture,'LECTURE_SEULE',true),(etab,proprietaire,'PROPRIETAIRE',true);
  INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('jolene-documents',cle,'{"mimetype":"image/png"}'),
    ('jolene-documents',autre::text||'/signatures/contrat-service-legacy.png','{"mimetype":"image/png"}');

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',etab::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
  IF public.fn_lire_contrat_service_signe()->>'error' IS DISTINCT FROM 'CONTRAT_NON_SIGNE' THEN RAISE EXCEPTION 'Document proposé avant signature'; END IF;
  p := public.fn_preparer_contrat_service_v11();
  IF p->>'preparation_id' IS NULL OR p->>'contenu_hash' IS NULL OR p->>'contenu_texte' IS NULL THEN RAISE EXCEPTION 'Préparation incomplète'; END IF;
  IF p->>'version' IS DISTINCT FROM 'v1.1' OR p->>'success' IS DISTINCT FROM 'true' OR p->>'contenu_texte' NOT LIKE '%Recette contrat%'
    OR p->>'contenu_texte' NOT LIKE '%simulations indicatives%' THEN RAISE EXCEPTION 'Document serveur incorrect : %',p->>'error'; END IF;
  IF public.fn_preparer_contrat_service_v11() IS DISTINCT FROM p THEN RAISE EXCEPTION 'Préparation non idempotente'; END IF;
  -- Résoudre les noms du schéma private pour inspecter les ACL nécessite
  -- postgres. Les rôles visés restent explicitement ceux des clients.
  EXECUTE 'RESET ROLE';
  IF has_table_privilege('authenticated','public.contrats_service_preparations','SELECT')
    OR has_table_privilege('service_role','public.contrats_service_preparations','UPDATE')
    OR has_table_privilege('authenticated','public.contrats_service_preparations','DELETE')
    OR has_table_privilege('service_role','public.contrats_service_preparations','DELETE')
    OR has_function_privilege('authenticated','private.fn_purger_preparations_contrat_non_signees(uuid)','EXECUTE')
    OR has_function_privilege('service_role','private.fn_purger_preparations_contrat_non_signees(uuid)','EXECUTE')
    OR has_function_privilege('anon','public.fn_preparer_contrat_service_v11()','EXECUTE') THEN RAISE EXCEPTION 'ACL préparation ouvertes'; END IF;
  IF NOT has_function_privilege('authenticated','public.fn_lire_contrat_service_signe()','EXECUTE')
    OR has_function_privilege('anon','public.fn_lire_contrat_service_signe()','EXECUTE')
    OR has_function_privilege('service_role','public.fn_lire_contrat_service_signe()','EXECUTE') THEN RAISE EXCEPTION 'ACL consultation incorrectes'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE anon';
  refuse := false;
  BEGIN PERFORM public.fn_lire_contrat_service_signe();
  EXCEPTION WHEN insufficient_privilege THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Consultation anonyme autorisée'; END IF;
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE authenticated';
  resultat := public.fn_signer_contrat_service_v11((p->>'preparation_id')::uuid,repeat('0',64),cle);
  IF resultat->>'error' IS DISTINCT FROM 'PREPARATION_INVALIDE' THEN RAISE EXCEPTION 'Hash altéré accepté'; END IF;
  resultat := public.fn_signer_contrat_service_v11((p->>'preparation_id')::uuid,p->>'contenu_hash',etab::text||'/signatures/contrat-service-absent.png');
  IF resultat->>'error' IS DISTINCT FROM 'SIGNATURE_INVALIDE' THEN RAISE EXCEPTION 'Image absente acceptée'; END IF;

  PERFORM set_config('request.jwt.claim.sub',autre::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',autre,'role','authenticated')::text,true);
  resultat := public.fn_signer_contrat_service_v11((p->>'preparation_id')::uuid,p->>'contenu_hash',cle);
  IF resultat->>'error' IS DISTINCT FROM 'PREPARATION_INVALIDE' THEN RAISE EXCEPTION 'Préparation étrangère acceptée'; END IF;
  resultat := public.fn_signer_contrat_service('v1.0','','test',repeat('f',64),autre::text||'/signatures/contrat-service-legacy.png');
  IF resultat->>'success' IS DISTINCT FROM 'true' OR resultat->>'version' IS DISTINCT FROM 'v1.0' THEN RAISE EXCEPTION 'Client legacy refusé'; END IF;
  PERFORM set_config('request.jwt.claim.sub',lecture::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',lecture,'role','authenticated')::text,true);
  IF public.fn_preparer_contrat_service_v11()->>'error' IS DISTINCT FROM 'ACCES_REFUSE' THEN RAISE EXCEPTION 'Lecture seule autorisée à signer'; END IF;

  EXECUTE 'RESET ROLE';
  SELECT to_jsonb(s) INTO legacy FROM public.contrats_service_signatures s WHERE etablissement_id=autre;
  IF legacy->>'preparation_id' IS NOT NULL THEN RAISE EXCEPTION 'Preuve legacy reconstruite'; END IF;
  UPDATE public.etablissements SET nom='Identité actualisée' WHERE id=etab;
  refuse := false;
  BEGIN UPDATE public.contrats_service_preparations SET contenu_texte='remplacé' WHERE id=(p->>'preparation_id')::uuid;
  EXCEPTION WHEN insufficient_privilege THEN refuse := true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Préparation modifiable'; END IF;
  IF p->>'contenu_hash' IS DISTINCT FROM encode(extensions.digest(convert_to(p->>'contenu_texte','UTF8'),'sha256'),'hex') THEN RAISE EXCEPTION 'Empreinte texte divergente'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',etab::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
  resultat := public.fn_signer_contrat_service_v11((p->>'preparation_id')::uuid,p->>'contenu_hash',cle);
  IF resultat->>'error' IS DISTINCT FROM 'PROFIL_MODIFIE' THEN RAISE EXCEPTION 'Profil changé avant signature accepté'; END IF;
  nouveau := public.fn_preparer_contrat_service_v11();
  IF nouveau->>'success' IS DISTINCT FROM 'true' OR nouveau->>'preparation_id' IS NULL OR nouveau->>'contenu_hash' IS NULL THEN RAISE EXCEPTION 'Nouvelle préparation incomplète'; END IF;
  IF nouveau->>'preparation_id'=p->>'preparation_id' OR nouveau->>'contenu_texte' NOT LIKE '%Identité actualisée%' THEN RAISE EXCEPTION 'Nouvelle lecture non préparée'; END IF;
  resultat := public.fn_signer_contrat_service_v11((nouveau->>'preparation_id')::uuid,nouveau->>'contenu_hash',cle);
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Signature v1.1 refusée : %',resultat->>'error'; END IF;
  EXECUTE 'RESET ROLE';
  SELECT to_jsonb(s) INTO preuve FROM public.contrats_service_signatures s WHERE etablissement_id=etab AND revoked_at IS NULL;
  UPDATE public.etablissements SET adresse_rue='3 rue après signature' WHERE id=etab;
  EXECUTE 'SET LOCAL ROLE authenticated';
  -- Réponse perdue suivie d'une modification : le retry renvoie la preuve, sans revalidation/reconstruction.
  IF public.fn_signer_contrat_service_v11((nouveau->>'preparation_id')::uuid,nouveau->>'contenu_hash',cle) IS DISTINCT FROM resultat THEN RAISE EXCEPTION 'Retry signé non idempotent'; END IF;
  IF public.fn_signer_contrat_service_v11((p->>'preparation_id')::uuid,p->>'contenu_hash',cle)->>'error' IS DISTINCT FROM 'CONTRAT_DEJA_SIGNE' THEN RAISE EXCEPTION 'Deuxième préparation signée'; END IF;
  -- La consultation récupère le snapshot signé après modification du profil,
  -- sans nouvelle préparation, réécriture ni exposition IP/UA/objet Storage.
  lecture_document := public.fn_lire_contrat_service_signe();
  IF lecture_document->>'success' IS DISTINCT FROM 'true' OR lecture_document->>'statut_document' IS DISTINCT FROM 'CONSERVE'
    OR lecture_document->>'etablissement_id' IS DISTINCT FROM etab::text
    OR lecture_document->>'signature_id' IS DISTINCT FROM preuve->>'id'
    OR lecture_document->>'version' IS DISTINCT FROM preuve->>'version'
    OR (lecture_document->>'signed_at')::timestamptz IS DISTINCT FROM (preuve->>'signed_at')::timestamptz
    OR lecture_document->>'preparation_id' IS DISTINCT FROM nouveau->>'preparation_id'
    OR lecture_document->>'contenu_texte' IS DISTINCT FROM nouveau->>'contenu_texte'
    OR lecture_document->>'contenu_hash' IS DISTINCT FROM nouveau->>'contenu_hash'
    OR lecture_document ?| ARRAY['ip_address','user_agent','signature_s3_key','donnees_etablissement','prepare_par'] THEN RAISE EXCEPTION 'Consultation du snapshot incorrecte'; END IF;
  IF public.fn_lire_contrat_service_signe() IS DISTINCT FROM lecture_document THEN RAISE EXCEPTION 'Nouvelle lecture différente'; END IF;
  PERFORM set_config('request.jwt.claim.sub',proprietaire::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',proprietaire,'role','authenticated')::text,true);
  IF public.mon_etablissement_id() IS DISTINCT FROM etab OR public.fn_lire_contrat_service_signe() IS DISTINCT FROM lecture_document THEN RAISE EXCEPTION 'Propriétaire membre ne lit pas le tenant canonique'; END IF;
  PERFORM set_config('request.jwt.claim.sub',lecture::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',lecture,'role','authenticated')::text,true);
  IF public.fn_lire_contrat_service_signe() IS DISTINCT FROM '{"success":false,"error":"ACCES_REFUSE"}'::jsonb THEN RAISE EXCEPTION 'Membre non habilité lit le document'; END IF;
  PERFORM set_config('request.jwt.claim.sub',autre::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',autre,'role','authenticated')::text,true);
  lecture_document := public.fn_lire_contrat_service_signe();
  IF lecture_document->>'statut_document' IS DISTINCT FROM 'HISTORIQUE_SANS_DOCUMENT'
    OR lecture_document->>'etablissement_id' IS DISTINCT FROM autre::text
    OR lecture_document->>'signature_id' IS DISTINCT FROM legacy->>'id'
    OR lecture_document->>'version' IS DISTINCT FROM 'v1.0'
    OR lecture_document->>'contenu_texte' IS NOT NULL OR lecture_document->>'contenu_hash' IS NOT NULL
    OR lecture_document->>'preparation_id' IS NOT NULL THEN RAISE EXCEPTION 'Tenant tiers exposé ou document historique reconstruit'; END IF;
  EXECUTE 'RESET ROLE';
  UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=proprietaire;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',proprietaire::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',proprietaire,'role','authenticated')::text,true);
  IF public.fn_lire_contrat_service_signe() IS DISTINCT FROM '{"success":false,"error":"ACCES_REFUSE"}'::jsonb THEN RAISE EXCEPTION 'Compte désactivé lit le document'; END IF;
  EXECUTE 'RESET ROLE';
  UPDATE auth.users SET banned_until=NULL WHERE id=proprietaire;
  PERFORM set_config('request.jwt.claim.sub',etab::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
  IF (SELECT count(*) FROM public.contrats_service_preparations WHERE etablissement_id=etab) IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'Consultation a créé une préparation'; END IF;
  IF (SELECT contenu_texte FROM public.contrats_service_preparations WHERE id=(nouveau->>'preparation_id')::uuid) IS DISTINCT FROM nouveau->>'contenu_texte' THEN RAISE EXCEPTION 'Consultation a changé le texte'; END IF;
  IF (SELECT count(*) FROM public.contrats_service_signatures WHERE etablissement_id=etab AND revoked_at IS NULL) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Plusieurs signatures actives'; END IF;
  IF preuve IS DISTINCT FROM (SELECT to_jsonb(s) FROM public.contrats_service_signatures s WHERE etablissement_id=etab AND revoked_at IS NULL) THEN RAISE EXCEPTION 'Preuve réécrite'; END IF;
  IF legacy IS DISTINCT FROM (SELECT to_jsonb(s) FROM public.contrats_service_signatures s WHERE etablissement_id=autre AND revoked_at IS NULL) THEN RAISE EXCEPTION 'Legacy modifié'; END IF;
  IF NOT (SELECT contrat_service_signe FROM public.etablissements WHERE id=autre) THEN RAISE EXCEPTION 'Activation legacy révoquée'; END IF;
  refuse := false;
  BEGIN UPDATE public.contrats_service_signatures SET contenu_hash=repeat('0',64) WHERE etablissement_id=etab;
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Preuve signée modifiable'; END IF;
  refuse:=false;
  BEGIN DELETE FROM public.contrats_service_preparations WHERE id=(nouveau->>'preparation_id')::uuid;
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Préparation supprimable'; END IF;
  INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('jolene-documents',etab::text||'/signatures/contrat-service-orpheline.png','{"mimetype":"image/png"}');
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM set_config('storage.allow_delete_query','true',true);
  DELETE FROM storage.objects WHERE bucket_id='jolene-documents' AND name=etab::text||'/signatures/contrat-service-orpheline.png';
  refuse:=false;
  BEGIN DELETE FROM storage.objects WHERE bucket_id='jolene-documents' AND name=cle;
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Cleanup service_role a supprimé la signature'; END IF;
  refuse:=false;
  BEGIN UPDATE storage.objects SET metadata='{}'::jsonb WHERE bucket_id='jolene-documents' AND name=cle;
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Image de signature réécrite'; END IF;
  refuse:=false;
  BEGIN UPDATE storage.objects SET name=etab::text||'/signatures/deplace.png' WHERE bucket_id='jolene-documents' AND name=cle;
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Clé image signée déplacée'; END IF;
  refuse:=false;
  BEGIN UPDATE storage.objects SET bucket_id='copies-bulletins-paie' WHERE bucket_id='jolene-documents' AND name=cle;
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Bucket image signée modifié'; END IF;
  refuse:=false;
  BEGIN DELETE FROM storage.objects WHERE bucket_id='jolene-documents' AND name=autre::text||'/signatures/contrat-service-legacy.png';
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Image legacy supprimable'; END IF;
  EXECUTE 'RESET ROLE';
  UPDATE public.contrats_service_signatures SET revoked_at=now(),motif_revocation='Révocation explicite de recette' WHERE etablissement_id=etab;
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF public.fn_lire_contrat_service_signe()->>'error' IS DISTINCT FROM 'CONTRAT_NON_SIGNE' THEN RAISE EXCEPTION 'Preuve révoquée présentée comme contrat actif'; END IF;
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE service_role';
  refuse:=false;
  BEGIN DELETE FROM storage.objects WHERE bucket_id='jolene-documents' AND name=cle;
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Image révoquée supprimable'; END IF;
  EXECUTE 'RESET ROLE';
  SELECT to_jsonb(doc) INTO document_signe FROM public.contrats_service_preparations doc WHERE id=(nouveau->>'preparation_id')::uuid;
  IF document_signe IS NULL THEN RAISE EXCEPTION 'Document signé absent avant anonymisation'; END IF;
  -- Le parcours réel d'anonymisation supprime les drafts, conserve toute preuve liée.
  EXECUTE 'SET LOCAL ROLE authenticated';
  resultat := public.fn_supprimer_mon_compte_etablissement();
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Anonymisation compte signé bloquée'; END IF;
  EXECUTE 'RESET ROLE';
  IF NOT private.fn_anonymisation_compte_confirmee(etab,'ETABLISSEMENT') THEN RAISE EXCEPTION 'Anonymisation signée non confirmée'; END IF;
  IF EXISTS(SELECT 1 FROM public.contrats_service_preparations WHERE id=(p->>'preparation_id')::uuid) THEN RAISE EXCEPTION 'Draft conservé après anonymisation'; END IF;
  IF document_signe IS DISTINCT FROM (SELECT to_jsonb(doc) FROM public.contrats_service_preparations doc WHERE id=(nouveau->>'preparation_id')::uuid) THEN RAISE EXCEPTION 'Document signé effacé ou changé par anonymisation'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.contrats_service_signatures WHERE preparation_id=(nouveau->>'preparation_id')::uuid AND revoked_at IS NOT NULL) THEN RAISE EXCEPTION 'Preuve révoquée perdue'; END IF;
  IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='jolene-documents' AND name=cle) THEN RAISE EXCEPTION 'Image perdue par anonymisation'; END IF;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',abandon::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',abandon,'role','authenticated')::text,true);
  resultat := public.fn_preparer_contrat_service_v11();
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Préparation abandon impossible'; END IF;
  resultat := public.fn_supprimer_mon_compte_etablissement();
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Anonymisation compte non signé bloquée'; END IF;
  EXECUTE 'RESET ROLE';
  IF NOT private.fn_anonymisation_compte_confirmee(abandon,'ETABLISSEMENT') OR EXISTS(SELECT 1 FROM public.contrats_service_preparations WHERE etablissement_id=abandon) THEN RAISE EXCEPTION 'Snapshot abandonné conservé après anonymisation'; END IF;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',purge::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',purge,'role','authenticated')::text,true);
  resultat := public.fn_preparer_contrat_service_v11();
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Préparation purge impossible'; END IF;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  -- Purge privilégiée d'un compte fixture : le nouveau FK ne bloque pas le hard-delete non signé.
  DELETE FROM public.etablissements WHERE id=purge;
  IF EXISTS(SELECT 1 FROM public.contrats_service_preparations WHERE etablissement_id=purge) THEN RAISE EXCEPTION 'Cascade draft établissement bloquée'; END IF;
  DELETE FROM auth.users WHERE id=purge;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',purge_auth::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',purge_auth,'role','authenticated')::text,true);
  resultat := public.fn_preparer_contrat_service_v11();
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Préparation purge Auth impossible'; END IF;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  -- Ordre inverse : suppression Auth directe avant tout DELETE établissement.
  -- Le runner CI postgres ne peut pas SET ROLE supabase_auth_admin (vérifié LIVE).
  -- La cascade est exercée ici ; l'appel réel Auth Admin reste une recette d'intégration.
  DELETE FROM auth.users WHERE id=purge_auth;
  IF EXISTS(SELECT 1 FROM public.contrats_service_preparations WHERE prepare_par=purge_auth)
    OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=purge_auth)
    OR EXISTS(SELECT 1 FROM auth.users WHERE id=purge_auth) THEN RAISE EXCEPTION 'Cascade draft Auth incorrecte'; END IF;
  RAISE EXCEPTION 'ROLLBACK_CONTRAT_V11' USING ERRCODE='ZX111';
  EXCEPTION WHEN SQLSTATE 'ZX111' THEN
    IF SQLERRM IS DISTINCT FROM 'ROLLBACK_CONTRAT_V11' THEN RAISE; END IF;
    v_annule := true;
  END;
  -- Contrôle après annulation du sous-bloc, avant rollback de la transaction :
  -- aucun DELETE de nettoyage et aucun effacement d'audit hors transaction.
  IF NOT v_annule
    OR EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.membres_etablissement WHERE user_id=ANY(v_ids) OR etablissement_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.contrats_service_preparations WHERE etablissement_id=ANY(v_ids) OR prepare_par=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.contrats_service_signatures WHERE etablissement_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.preferences_notifications WHERE utilisateur_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.notifications WHERE destinataire_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.email_queue WHERE destinataire_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE acteur_id=ANY(v_ids) OR id_ressource=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM private.suppressions_compte_confirmees WHERE utilisateur_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM private.suppression_etablissement_context WHERE utilisateur_id=ANY(v_ids))
    OR EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='jolene-documents' AND split_part(name,'/',1)=ANY(v_ids::text[]))
  THEN RAISE EXCEPTION 'Contrat v11 : annulation transactionnelle non prouvée'; END IF;
END;
$test$;
SELECT 'CONTRAT_V11_SQL_ROLLBACK' AS preuve,true AS annule;
ROLLBACK;
