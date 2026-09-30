-- Recette réelle de la RPC, fixtures synthétiques annulées, aucun octet personnel ni Storage.
BEGIN;
DO $recette$
DECLARE
  etab uuid := '88900000-0000-4000-8000-000000000001';
  sal uuid := '88900000-0000-4000-8000-000000000002';
  tiers uuid := '88900000-0000-4000-8000-000000000003';
  rh uuid := '88900000-0000-4000-8000-000000000004';
  lecture uuid := '88900000-0000-4000-8000-000000000005';
  groupe uuid := '88900000-0000-4000-8000-000000000006';
  autre_etab uuid := '88900000-0000-4000-8000-000000000007';
  pointage uuid := '88900000-0000-4000-8000-000000000008';
  mission1 uuid := '88900000-0000-4000-8000-000000000011';
  contrat1 uuid := '88900000-0000-4000-8000-000000000021';
  r jsonb; acteur uuid;

BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.security_definer_inventory i
    JOIN pg_catalog.pg_proc p ON p.oid='public.fn_contrat_storage_path(uuid)'::regprocedure
    WHERE i.signature='fn_contrat_storage_path(uuid)'
      AND i.categorie='MIXTE_TENANT_ADMIN'
      AND i.definition_md5=pg_catalog.md5(p.prosrc)
  ) THEN RAISE EXCEPTION 'Inventaire du corps contrat absent ou périmé'; END IF;
  -- Sentinelle : rend aussi le test autonome face aux wrappers CI qui retirent
  -- les BEGIN/ROLLBACK externes. Aucun effet ne sort de ce sous-bloc.
  BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  PERFORM set_config('jolene.admin_seed_override_reason','Recette accès contrats : fixtures privées annulées',true);
  INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
  SELECT ('88900000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
    '00000000-0000-0000-0000-000000000000', 'contrat-storage-'||n||'@example.invalid',
    'authenticated','authenticated',jsonb_build_object('role',CASE WHEN n IN(2,3) THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,'is_test_playwright',true),now()
  FROM generate_series(1,8) n;
  INSERT INTO public.soignants(id,email,prenom,nom,profession,type_exercice,est_compte_test)
  VALUES(sal,'contrat-storage-2@example.invalid','Recette','Salarié','IDE','SALARIE',true),
    (tiers,'contrat-storage-3@example.invalid','Recette','Tiers','IDE','SALARIE',true);
  INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
  VALUES(etab,'Recette copies','88900000000001','CLINIQUE_PRIVEE','Test','Paris','75001','contrat-storage-1@example.invalid',true),
    (autre_etab,'Autre recette copies','88900000000007','CLINIQUE_PRIVEE','Test','Paris','75001','contrat-storage-7@example.invalid',true),
    (groupe,'Établissement propre du membre','88900000000006','CLINIQUE_PRIVEE','Test','Paris','75001','contrat-storage-6@example.invalid',true);
  INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
  VALUES(etab,rh,'RH',true),(etab,lecture,'LECTURE_SEULE',true),(etab,groupe,'ADMIN_GROUPE',true),(etab,pointage,'POINTAGE_ONLY',true);
  INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,
    taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,type_paiement_soignant)
  VALUES(mission1,etab,'Mission contrat fictif','IDE','2035-06-18 09:00:00+02','2035-06-18 17:00:00+02',8,20,'TERMINEE',sal,'SALARIE','SALARIE','BULLETIN_PAIE');
  INSERT INTO public.contrats_mission(id,mission_id,etablissement_id,soignant_id,type_contrat,numero_contrat,
    statut,storage_path,hash_document,contenu_html,contenu_html_rendu_le)
  VALUES(contrat1,mission1,etab,sal,'CDD','SYNTHETIQUE-ACCES-CONTRAT','EN_ATTENTE_SIGNATURES',
    'recette/contrat-original.html',repeat('a',64),'<article>Original fictif</article>',now());
  IF has_function_privilege('anon','public.fn_contrat_storage_path(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'RPC accessible à anon'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  FOREACH acteur IN ARRAY ARRAY[etab,sal,rh,lecture,groupe] LOOP
    PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
    IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
    IF r->>'success' IS DISTINCT FROM 'true' OR r->>'storage_path' IS DISTINCT FROM 'recette/contrat-original.html'
      OR r->>'hash_document' IS DISTINCT FROM repeat('a',64) THEN
      RAISE EXCEPTION 'Acteur habilité refusé : % %',acteur,r; END IF;
  END LOOP;
  -- POINTAGE_ONLY, tiers soignant, autre tenant et UID absent : aucune métadonnée.
  FOREACH acteur IN ARRAY ARRAY[pointage,tiers,autre_etab,NULL::uuid] LOOP
    PERFORM set_config('request.jwt.claim.sub',COALESCE(acteur::text,''),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
    IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
    IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' OR r ? 'hash_document' THEN
      RAISE EXCEPTION 'Acteur non habilité accepté : % %',acteur,r; END IF;
  END LOOP;
  EXECUTE 'RESET ROLE';
  -- Préparation suivante : RESET ROLE ne réinitialise pas les claims JWT.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE public.membres_etablissement SET role='POINTAGE_ONLY' WHERE user_id=rh AND etablissement_id=etab;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',rh::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',rh,'role','authenticated')::text,true);
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
  IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' THEN RAISE EXCEPTION 'Permission révoquée acceptée'; END IF;
  EXECUTE 'RESET ROLE';
  -- Préparation suivante : RESET ROLE ne réinitialise pas les claims JWT.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE public.membres_etablissement SET role='RH' WHERE user_id=rh AND etablissement_id=etab;
  UPDATE public.membres_etablissement SET actif=false WHERE user_id=rh AND etablissement_id=etab;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',rh::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',rh,'role','authenticated')::text,true);
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
  IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' THEN RAISE EXCEPTION 'Membre désactivé accepté'; END IF;
  EXECUTE 'RESET ROLE';
  -- Préparation suivante : RESET ROLE ne réinitialise pas les claims JWT.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  -- Auth reste vivant : les marqueurs de fermeture publics doivent suffire.
  UPDATE public.soignants SET supprime_le=now() WHERE id=sal;
  UPDATE public.etablissements SET supprime_le=now() WHERE id=groupe;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  FOREACH acteur IN ARRAY ARRAY[sal,groupe] LOOP
    PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
    IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
    IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' OR r ? 'hash_document' THEN
      RAISE EXCEPTION 'Profil fermé avec Auth valide accepté : %',acteur; END IF;
  END LOOP;
  EXECUTE 'RESET ROLE';
  -- Préparation suivante : RESET ROLE ne réinitialise pas les claims JWT.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE public.soignants SET supprime_le=NULL WHERE id=sal;
  UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=sal;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',sal::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',sal,'role','authenticated')::text,true);
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
  IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' THEN RAISE EXCEPTION 'Auth suspendu accepté'; END IF;
  EXECUTE 'RESET ROLE';
  -- Préparation suivante : RESET ROLE ne réinitialise pas les claims JWT.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE auth.users SET banned_until=NULL,deleted_at=now() WHERE id=sal;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',sal::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',sal,'role','authenticated')::text,true);
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
  IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' THEN RAISE EXCEPTION 'Auth supprimé accepté'; END IF;
  EXECUTE 'RESET ROLE';
  -- Préparation suivante : RESET ROLE ne réinitialise pas les claims JWT.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE auth.users SET deleted_at=NULL WHERE id=sal;
  UPDATE public.etablissements SET supprime_le=now() WHERE id=etab;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',etab::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
  IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' THEN RAISE EXCEPTION 'Propriétaire fermé accepté'; END IF;
  PERFORM set_config('request.jwt.claim.sub',lecture::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',lecture,'role','authenticated')::text,true);
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte utilisateur de recette incorrect'; END IF;
  r := public.fn_contrat_storage_path(contrat1);
  IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'storage_path' THEN RAISE EXCEPTION 'Tenant fermé accepté via membre'; END IF;
  EXECUTE 'RESET ROLE';
  -- Préparation suivante : RESET ROLE ne réinitialise pas les claims JWT.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  IF (SELECT hash_document FROM public.contrats_mission WHERE id=contrat1) IS DISTINCT FROM repeat('a',64) THEN
    RAISE EXCEPTION 'La lecture a altéré la preuve'; END IF;
  RAISE EXCEPTION USING ERRCODE='ZCA01',MESSAGE='ROLLBACK_FIXTURES_CONTRAT_ACCES';
  EXCEPTION WHEN SQLSTATE 'ZCA01' THEN NULL;
  END;
END;
$recette$;
ROLLBACK;
