-- Recette SQL transactionnelle : fixtures privées, aucun PDF réel, aucun
-- transport. L'Edge vérifie les octets séparément ; ces objets Storage sont
-- seulement des lignes fictives pour exercer les contraintes/RLS.
BEGIN;
DO $recette$
DECLARE
  etab uuid := '88700000-0000-4000-8000-000000000001';
  sal uuid := '88700000-0000-4000-8000-000000000002';
  tiers uuid := '88700000-0000-4000-8000-000000000003';
  rh uuid := '88700000-0000-4000-8000-000000000004';
  lecture uuid := '88700000-0000-4000-8000-000000000005';
  groupe uuid := '88700000-0000-4000-8000-000000000006';
  autre_etab uuid := '88700000-0000-4000-8000-000000000007';
  pointage uuid := '88700000-0000-4000-8000-000000000008';
  mission1 uuid := '88700000-0000-4000-8000-000000000011';
  mission2 uuid := '88700000-0000-4000-8000-000000000012';
  idem uuid := '88700000-0000-4000-8000-000000000021';
  idem2 uuid := '88700000-0000-4000-8000-000000000022';
  idem3 uuid := '88700000-0000-4000-8000-000000000023';
  r jsonb; r2 jsonb; r3 jsonb; rgroupe jsonb; copie uuid; copie2 uuid;
  acteur uuid; role_revoque text; refuse boolean; avant_paiements bigint; avant_simulations bigint; avant_contrats bigint;
BEGIN
  -- Sentinelle : rend aussi le test autonome face aux wrappers CI qui retirent
  -- les BEGIN/ROLLBACK externes. Aucun effet ne sort de ce sous-bloc.
  BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  PERFORM set_config('jolene.admin_seed_override_reason','Recette copies bulletin : fixtures privées annulées',true);
  INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
  SELECT ('88700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
    '00000000-0000-0000-0000-000000000000', 'copies-bulletins-'||n||'@example.invalid',
    'authenticated','authenticated',jsonb_build_object('role',CASE WHEN n IN(2,3) THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,'is_test_playwright',true),now()
  FROM generate_series(1,8) n;
  INSERT INTO public.soignants(id,email,prenom,nom,profession,type_exercice,est_compte_test)
  VALUES(sal,'copies-bulletins-2@example.invalid','Recette','Salarié','IDE','SALARIE',true),
    (tiers,'copies-bulletins-3@example.invalid','Recette','Tiers','IDE','SALARIE',true);
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
  VALUES(etab,'Recette copies','88700000000001','CLINIQUE_PRIVEE','Test','Paris','75001','copies-bulletins-1@example.invalid',true),
    (autre_etab,'Autre recette copies','88700000000007','CLINIQUE_PRIVEE','Test','Paris','75001','copies-bulletins-7@example.invalid',true),
    (groupe,'Établissement propre du membre','88700000000006','CLINIQUE_PRIVEE','Test','Paris','75001','copies-bulletins-6@example.invalid',true);
  INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
  VALUES(etab,rh,'RH',true),(etab,lecture,'LECTURE_SEULE',true),(etab,groupe,'ADMIN_GROUPE',true),(etab,pointage,'POINTAGE_ONLY',true);
  INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,
    taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,type_paiement_soignant)
  VALUES(mission1,etab,'Mission copie A','IDE','2035-06-18 09:00:00+02','2035-06-18 17:00:00+02',8,20,'TERMINEE',sal,'SALARIE','SALARIE','BULLETIN_PAIE'),
    (mission2,etab,'Mission copie B','IDE','2035-06-19 09:00:00+02','2035-06-19 17:00:00+02',8,20,'TERMINEE',sal,'SALARIE','SALARIE','BULLETIN_PAIE');
  SELECT count(*) INTO avant_paiements FROM public.paiements_soignant WHERE mission_id IN(mission1,mission2);
  SELECT count(*) INTO avant_simulations FROM public.bulletins_paie WHERE mission_id IN(mission1,mission2);
  SELECT count(*) INTO avant_contrats FROM public.contrats_mission WHERE mission_id IN(mission1,mission2);

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',etab::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
  IF has_function_privilege('authenticated','public.fn_publier_copie_bulletin_interne(uuid,uuid,text,bigint)','EXECUTE')
    OR has_table_privilege('service_role','public.copies_bulletins_paie','INSERT')
    OR has_table_privilege('service_role','public.copies_bulletins_paie','UPDATE')
    OR has_table_privilege('service_role','public.copies_bulletins_paie','DELETE')
    OR has_table_privilege('service_role','public.copies_bulletins_paie','TRUNCATE')
    OR has_table_privilege('authenticated','public.copies_bulletins_paie','INSERT')
    OR has_table_privilege('authenticated','public.copies_bulletins_paie','UPDATE')
    OR has_table_privilege('authenticated','public.copies_bulletins_paie','SELECT') THEN
    RAISE EXCEPTION 'ACL copies ouvertes'; END IF;
  r := public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],idem,repeat('a',64),123);
  copie := (r->>'id')::uuid;
  IF r->>'statut'<>'RESERVEE' OR (r->>'version')::integer<>1 THEN RAISE EXCEPTION 'Réservation invalide'; END IF;
  r2 := public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission2,mission1],idem,repeat('a',64),123);
  IF r2<>r THEN RAISE EXCEPTION 'Rejeu non idempotent'; END IF;
  refuse:=false;
  BEGIN
    PERFORM public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],idem,repeat('b',64),123);
  EXCEPTION WHEN invalid_parameter_value THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Autre contenu accepté pour même intention'; END IF;
  refuse:=false;
  BEGIN
    PERFORM public.fn_reserver_copie_bulletin(etab,tiers,'2035-06-01','2035-06-30',ARRAY[mission1],idem2,repeat('a',64),123);
  EXCEPTION WHEN invalid_parameter_value THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Mission autre salarié acceptée'; END IF;
  IF public.fn_lister_copies_bulletins(etab) <> '[]'::jsonb THEN RAISE EXCEPTION 'Intention exposée comme publiée'; END IF;
  INSERT INTO storage.objects(bucket_id,name) VALUES('copies-bulletins-paie',r->>'storage_path');
  refuse:=false;
  BEGIN INSERT INTO storage.objects(bucket_id,name) VALUES('copies-bulletins-paie','foreign/original.pdf');
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Chemin non réservé accepté'; END IF;
  IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='copies-bulletins-paie') THEN RAISE EXCEPTION 'Storage lisible directement'; END IF;
  UPDATE storage.objects SET metadata='{"remplace":true}' WHERE bucket_id='copies-bulletins-paie';
  -- Storage peut refuser même un DELETE auquel la RLS ne rend aucune ligne.
  -- Dans les deux cas, l'assertion privilégiée ci-dessous exige le blob intact.
  BEGIN
    DELETE FROM storage.objects WHERE bucket_id='copies-bulletins-paie';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  -- Les acteurs non habilités ne peuvent ni publier ni lire les métadonnées.
  FOREACH acteur IN ARRAY ARRAY[rh,lecture,pointage,autre_etab,tiers] LOOP
    PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
    refuse:=false;
    BEGIN PERFORM public.fn_lister_copies_bulletins(etab); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Métadonnées accessibles à acteur interdit'; END IF;
    refuse:=false;
    BEGIN PERFORM public.fn_acces_copie_bulletin(copie,'finaliser'); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Finalisation accessible à acteur interdit'; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',groupe::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',groupe,'role','authenticated')::text,true);
  IF public.fn_lister_copies_bulletins(etab)<>'[]'::jsonb THEN RAISE EXCEPTION 'Liste groupe incorrecte'; END IF;
  rgroupe:=public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],idem,repeat('d',64),126);
  INSERT INTO storage.objects(bucket_id,name) VALUES('copies-bulletins-paie',rgroupe->>'storage_path');
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='copies-bulletins-paie' AND name=r->>'storage_path' AND metadata IS NULL) THEN
    RAISE EXCEPTION 'Blob modifié/supprimé par client'; END IF;
  -- Expiration et renouvellement conservent le même objet et la même intention.
  UPDATE public.copies_bulletins_paie SET expire_le=now()-interval '1 minute' WHERE id=copie;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',etab::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
  refuse:=false;
  BEGIN PERFORM public.fn_acces_copie_bulletin(copie,'finaliser'); EXCEPTION WHEN object_not_in_prerequisite_state THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Finalisation réservation expirée acceptée'; END IF;
  r2:=public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],idem,repeat('a',64),123);
  IF r2<>r THEN RAISE EXCEPTION 'Renouvellement change identité'; END IF;
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  refuse:=false;
  BEGIN PERFORM public.fn_publier_copie_bulletin_interne(copie,etab,repeat('b',64),123); EXCEPTION WHEN invalid_parameter_value THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Digest faux accepté'; END IF;
  r2:=public.fn_publier_copie_bulletin_interne(copie,etab,repeat('a',64),123);
  IF public.fn_publier_copie_bulletin_interne(copie,etab,repeat('a',64),123)<>r2 THEN RAISE EXCEPTION 'Publication rejouée divergente'; END IF;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM private.audit_copies_bulletins WHERE copie_id=copie AND action='PUBLICATION')<>1
    OR (SELECT count(*) FROM public.notifications WHERE id_ressource=copie)<>1 THEN RAISE EXCEPTION 'Publication duplique audit/notification'; END IF;

  -- Acteur qui gère cet établissement mais dont le propre compte établissement
  -- est supprimé : recontrôle aussi à publication privilégiée après accès.
  UPDATE public.etablissements SET supprime_le=now() WHERE id=groupe;
  EXECUTE 'SET LOCAL ROLE service_role';
  refuse:=false;
  BEGIN PERFORM public.fn_publier_copie_bulletin_interne((rgroupe->>'id')::uuid,groupe,repeat('d',64),126);
  EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Acteur propre supprimé accepté à publication'; END IF;
  EXECUTE 'RESET ROLE'; UPDATE public.etablissements SET supprime_le=NULL WHERE id=groupe;

  -- Une révocation explicite prime sur Auth ID = établissement, même si les
  -- anciennes app_metadata disent encore ADMIN_ETABLISSEMENT.
  INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
    VALUES(etab,autre_etab,'PROPRIETAIRE',true)
    ON CONFLICT(etablissement_id,user_id) DO UPDATE SET role='PROPRIETAIRE',actif=true;
  FOREACH role_revoque IN ARRAY ARRAY['RH','LECTURE_SEULE','INACTIF'] LOOP
    INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
      VALUES(etab,etab,CASE WHEN role_revoque='INACTIF' THEN 'PROPRIETAIRE' ELSE role_revoque END,role_revoque<>'INACTIF')
      ON CONFLICT(etablissement_id,user_id) DO UPDATE SET role=EXCLUDED.role,actif=EXCLUDED.actif;
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub',etab::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
    refuse:=false;
    BEGIN PERFORM public.fn_lister_copies_bulletins(etab); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Fallback legacy contourne lecture révoquée'; END IF;
    refuse:=false;
    BEGIN PERFORM public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],idem,repeat('a',64),123);
    EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Fallback legacy contourne réservation révoquée'; END IF;
    refuse:=false;
    BEGIN PERFORM public.fn_acces_copie_bulletin(copie,'finaliser'); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Fallback legacy contourne finalisation révoquée'; END IF;
    refuse:=false;
    BEGIN PERFORM public.fn_acces_copie_bulletin(copie,'telecharger'); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Fallback legacy contourne téléchargement révoqué'; END IF;
    refuse:=false;
    BEGIN PERFORM public.fn_retirer_copie_bulletin(copie); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Fallback legacy contourne retrait révoqué'; END IF;
    EXECUTE 'RESET ROLE'; EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM set_config('request.jwt.claim.sub','',true); PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    refuse:=false;
    BEGIN PERFORM public.fn_publier_copie_bulletin_interne(copie,etab,repeat('a',64),123); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
    IF NOT refuse THEN RAISE EXCEPTION 'Fallback legacy contourne publication privilégiée révoquée'; END IF;
    EXECUTE 'RESET ROLE';
  END LOOP;
  UPDATE public.membres_etablissement SET role='PROPRIETAIRE',actif=true WHERE etablissement_id=etab AND user_id=etab;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',sal::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',sal,'role','authenticated')::text,true);
  IF jsonb_array_length(public.fn_lister_copies_bulletins())<>1 THEN RAISE EXCEPTION 'Salarié ne retrouve pas copie'; END IF;
  PERFORM public.fn_acces_copie_bulletin(copie,'telecharger');
  PERFORM set_config('request.jwt.claim.sub',tiers::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',tiers,'role','authenticated')::text,true);
  IF public.fn_lister_copies_bulletins()<>'[]'::jsonb THEN RAISE EXCEPTION 'Copie tiers exposée'; END IF;
  refuse:=false;
  BEGIN PERFORM public.fn_acces_copie_bulletin(copie,'telecharger'); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'PDF tiers exposé'; END IF;

  -- Les horaires acceptés restent protégés. La fixture privilégiée peut être
  -- réaffectée : le destinataire de la copie publiée doit néanmoins rester figé.
  -- La correction reste aussi possible si une autre mission a été supprimée.
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM public.paiements_soignant WHERE mission_id IN(mission1,mission2))<>avant_paiements
    OR (SELECT count(*) FROM public.bulletins_paie WHERE mission_id IN(mission1,mission2))<>avant_simulations
    OR (SELECT count(*) FROM public.contrats_mission WHERE mission_id IN(mission1,mission2))<>avant_contrats THEN
    RAISE EXCEPTION 'Publication initiale modifie paie/paiement/contrat'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true); PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  refuse:=false;
  BEGIN
    UPDATE public.missions SET debut_le='2035-07-18 09:00:00+02',fin_le='2035-07-18 17:00:00+02' WHERE id=mission1;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Les horaires ne peuvent plus être modifiés après acceptation.' THEN RAISE; END IF;
    refuse:=true;
  END;
  IF NOT refuse OR NOT EXISTS(SELECT 1 FROM public.missions WHERE id=mission1
    AND debut_le='2035-06-18 09:00:00+02' AND fin_le='2035-06-18 17:00:00+02') THEN
    RAISE EXCEPTION 'Horaires historiques modifiables'; END IF;
  UPDATE public.missions SET soignant_assigne_id=tiers WHERE id=mission1;
  IF (SELECT soignant_assigne_id FROM public.missions WHERE id=mission1) IS DISTINCT FROM tiers THEN
    RAISE EXCEPTION 'Réaffectation de fixture historique non effectuée'; END IF;
  DELETE FROM public.missions WHERE id=mission2;
  IF EXISTS(SELECT 1 FROM public.missions WHERE id=mission2) THEN RAISE EXCEPTION 'Mission fixture non supprimée'; END IF;
  SELECT count(*) INTO avant_paiements FROM public.paiements_soignant WHERE mission_id IN(mission1,mission2);
  SELECT count(*) INTO avant_simulations FROM public.bulletins_paie WHERE mission_id IN(mission1,mission2);
  SELECT count(*) INTO avant_contrats FROM public.contrats_mission WHERE mission_id IN(mission1,mission2);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  -- Deux intentions peuvent préparer le même remplacement, une seule publie.
  PERFORM set_config('request.jwt.claim.sub',etab::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
  refuse:=false;
  BEGIN
    PERFORM public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],
      '88700000-0000-4000-8000-000000000024',repeat('e',64),127);
  EXCEPTION WHEN invalid_parameter_value THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Nouvelle série accepte des missions vivantes invalides'; END IF;
  refuse:=false;
  BEGIN
    PERFORM public.fn_reserver_copie_bulletin(etab,tiers,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],
      '88700000-0000-4000-8000-000000000025',repeat('f',64),128,copie,'CONTENU');
  EXCEPTION WHEN serialization_failure THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Remplacement permet de changer le salarié historique'; END IF;
  r2:=public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],idem2,repeat('b',64),124,copie,'CONTENU');
  r3:=public.fn_reserver_copie_bulletin(etab,sal,'2035-06-01','2035-06-30',ARRAY[mission1,mission2],idem3,repeat('c',64),125,copie,'AUTRE');
  copie2:=(r2->>'id')::uuid;
  INSERT INTO storage.objects(bucket_id,name) VALUES('copies-bulletins-paie',r2->>'storage_path'),('copies-bulletins-paie',r3->>'storage_path');
  EXECUTE 'RESET ROLE'; EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM set_config('request.jwt.claim.sub','',true); PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  PERFORM public.fn_publier_copie_bulletin_interne(copie2,etab,repeat('b',64),124);
  refuse:=false;
  BEGIN PERFORM public.fn_publier_copie_bulletin_interne((r3->>'id')::uuid,etab,repeat('c',64),125); EXCEPTION WHEN serialization_failure THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Remplacement concurrent écrase version'; END IF;
  EXECUTE 'RESET ROLE';
  IF (SELECT statut FROM public.copies_bulletins_paie WHERE id=copie)<>'REMPLACEE' THEN RAISE EXCEPTION 'Version précédente perdue'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',sal::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',sal,'role','authenticated')::text,true);
  PERFORM public.fn_acces_copie_bulletin(copie2,'telecharger');
  IF jsonb_array_length(public.fn_lister_copies_bulletins(NULL,mission2))<>2 THEN RAISE EXCEPTION 'Historique mission supprimée perdu'; END IF;
  PERFORM set_config('request.jwt.claim.sub',tiers::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',tiers,'role','authenticated')::text,true);
  refuse:=false;
  BEGIN PERFORM public.fn_acces_copie_bulletin(copie2,'telecharger'); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Réaffectation mission divulgue ancien bulletin au nouveau salarié'; END IF;
  EXECUTE 'RESET ROLE';
  UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=sal;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',sal::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',sal,'role','authenticated')::text,true);
  refuse:=false;
  BEGIN PERFORM public.fn_acces_copie_bulletin(copie2,'telecharger'); EXCEPTION WHEN insufficient_privilege THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'JWT suspendu accepté'; END IF;
  EXECUTE 'RESET ROLE'; UPDATE auth.users SET banned_until=NULL WHERE id=sal;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.fn_signaler_copie_bulletin(copie2,'DESTINATAIRE');
  PERFORM public.fn_signaler_copie_bulletin(copie2,'DESTINATAIRE');
  refuse:=false;
  BEGIN PERFORM public.fn_acces_copie_bulletin(copie2,'telecharger'); EXCEPTION WHEN object_not_in_prerequisite_state THEN refuse:=true; END;
  IF NOT refuse THEN RAISE EXCEPTION 'Copie signalée mauvais destinataire encore lisible'; END IF;
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM public.signalements_copies_bulletins WHERE copie_id=copie2)<>1 THEN RAISE EXCEPTION 'Signalement dupliqué'; END IF;
  IF (SELECT count(*) FROM public.paiements_soignant WHERE mission_id IN(mission1,mission2))<>avant_paiements
    OR (SELECT count(*) FROM public.bulletins_paie WHERE mission_id IN(mission1,mission2))<>avant_simulations
    OR (SELECT count(*) FROM public.contrats_mission WHERE mission_id IN(mission1,mission2))<>avant_contrats THEN
    RAISE EXCEPTION 'Copie modifie paie/paiement/contrat'; END IF;
  RAISE EXCEPTION USING ERRCODE='ZCB01',MESSAGE='ROLLBACK_FIXTURES_COPIES';
  EXCEPTION WHEN SQLSTATE 'ZCB01' THEN NULL;
  END;
END;
$recette$;
ROLLBACK;
