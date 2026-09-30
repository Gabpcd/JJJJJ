-- RPC réelles + RLS sous identités synthétiques. Aucun appel fournisseur.
-- INSERT de missions directement TERMINEE/EN_COURS/OUVERTE, jamais transition
-- de clôture, paiement, contrat ni purge d'audit. Les profils sont de test.
-- Le sous-bloc sentinelle annule aussi les fixtures lorsque le runner CI retire
-- BEGIN/ROLLBACK externes. Aucune erreur autre que la sentinelle n'est absorbée.
BEGIN;
DO $recette$
DECLARE
  etab uuid := 'a9305700-0000-4000-8000-000000000001';
  sal uuid := 'a9305700-0000-4000-8000-000000000002';
  tiers uuid := 'a9305700-0000-4000-8000-000000000003';
  membre uuid := 'a9305700-0000-4000-8000-000000000004';
  autre_etab uuid := 'a9305700-0000-4000-8000-000000000005';
  membre_tiers uuid := 'a9305700-0000-4000-8000-000000000006';
  sans_profil uuid := 'a9305700-0000-4000-8000-000000000007';
  claim_admin uuid := 'a9305700-0000-4000-8000-000000000008';
  admin_valide uuid := 'a9305700-0000-4000-8000-000000000009';
  membre_avec_etab_propre uuid := 'a9305700-0000-4000-8000-000000000010';
  soignant_en_cours uuid := 'a9305700-0000-4000-8000-000000000011';
  inconnu uuid := 'a9305700-0000-4000-8000-000000000099';
  mission uuid := 'a9305700-0000-4000-8000-000000000101';
  en_cours uuid := 'a9305700-0000-4000-8000-000000000102';
  sans_soignant uuid := 'a9305700-0000-4000-8000-000000000103';
  mission_admin uuid := 'a9305700-0000-4000-8000-000000000104';
  ouverte uuid := 'a9305700-0000-4000-8000-000000000105';
  absente uuid := 'a9305700-0000-4000-8000-000000000199';
  acteur uuid; cible uuid; sens text; r jsonb; refus jsonb; note_etab uuid; note_sal uuid;
  n integer; v_signature text; v_empreinte text; v_categorie text;
BEGIN
  FOR v_signature,v_empreinte,v_categorie IN VALUES
    ('fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)', '430c4e6bb8dce83da949ba41642f3590', 'MIXTE_TENANT_ADMIN'),
    ('fn_lister_missions_a_noter_etab()', '0b3bff2c5588245287087d681698c2c9', 'RPC_UTILISATEUR_AUTH_INTERNE')
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM private.security_definer_inventory i
      JOIN pg_proc p ON p.oid=to_regprocedure('public.'||v_signature)
      WHERE i.signature=v_signature AND i.categorie=v_categorie
        AND i.definition_md5=v_empreinte AND md5(p.prosrc)=v_empreinte
        AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
        AND p.proacl='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]
    ) THEN RAISE EXCEPTION 'Empreinte, inventaire ou droits notation divergents : %',v_signature; END IF;
  END LOOP;

  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    PERFORM set_config('app.test_mode','true',true);
    PERFORM set_config('jolene.admin_seed_override_reason','Recette notation authentifiée, fixtures transactionnelles annulées',true);
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    SELECT ('a9305700-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      '00000000-0000-0000-0000-000000000000','notation-rollback-'||i||'@example.invalid',
      'authenticated','authenticated',jsonb_build_object('role',
        CASE WHEN i IN(2,3,11) THEN 'SOIGNANT' WHEN i IN(8,9) THEN 'ADMIN_PLATEFORME'
          WHEN i=7 THEN NULL ELSE 'ADMIN_ETABLISSEMENT' END,'is_test_playwright',true),now()
    FROM generate_series(1,11) i;
    INSERT INTO public.soignants(id,email,prenom,nom,profession,type_exercice,est_compte_test)
    VALUES(sal,'notation-rollback-2@example.invalid','Recette','Salarié','IDE','SALARIE',true),
      (tiers,'notation-rollback-3@example.invalid','Recette','Tiers','IDE','SALARIE',true),
      (soignant_en_cours,'notation-rollback-11@example.invalid','Recette','En cours','IDE','SALARIE',true);
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
    VALUES(etab,'Recette notation','99305700000001','CLINIQUE_PRIVEE','Test','Paris','75001','notation-rollback-1@example.invalid',true),
      (autre_etab,'Autre recette notation','99305700000005','CLINIQUE_PRIVEE','Test','Paris','75001','notation-rollback-5@example.invalid',true),
      (membre_avec_etab_propre,'Tenant propre distinct','99305700000010','CLINIQUE_PRIVEE','Test','Paris','75001','notation-rollback-10@example.invalid',true);
    -- Prescripteur = membre RH existant ; aucune nouvelle valeur d'énumération.
    INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
    VALUES(etab,membre,'RH',true),(autre_etab,membre_tiers,'RH',true),
      (etab,membre_avec_etab_propre,'RH',true);
    INSERT INTO public.equipe_admin(user_id,nom,prenom,email,actif,acces_groupes)
    VALUES(admin_valide,'Recette','Admin','notation-rollback-9@example.invalid',true,
      ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']::text[]);
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,
      taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,type_paiement_soignant,est_urgente)
    SELECT ('a9305700-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      etab,'Recette notation '||i,'IDE',now()+interval '20 years'+i*interval '1 day',
      now()+interval '20 years 4 hours'+i*interval '1 day',4,20,
      (CASE WHEN i=2 THEN 'EN_COURS' WHEN i=5 THEN 'OUVERTE' ELSE 'TERMINEE' END)::public.statut_mission,
      CASE WHEN i=2 THEN soignant_en_cours WHEN i IN(3,5) THEN NULL ELSE sal END,
      'SALARIE','SALARIE','BULLETIN_PAIE',false
    FROM generate_series(1,5) i;
    -- Le trigger de cohérence normalise EN_COURS sans assignation en OUVERTE.
    -- Ce soignant dédié préserve EN_COURS sans empêcher la suspension de sal.
    IF EXISTS (
      SELECT 1
      FROM (VALUES
        (mission,'TERMINEE'::public.statut_mission,sal),
        (en_cours,'EN_COURS'::public.statut_mission,soignant_en_cours),
        (sans_soignant,'TERMINEE'::public.statut_mission,NULL::uuid),
        (mission_admin,'TERMINEE'::public.statut_mission,sal),
        (ouverte,'OUVERTE'::public.statut_mission,NULL::uuid)
      ) attendu(id,statut,soignant_id)
      LEFT JOIN public.missions m ON m.id=attendu.id
      WHERE m.id IS NULL OR m.statut IS DISTINCT FROM attendu.statut
        OR m.soignant_assigne_id IS DISTINCT FROM attendu.soignant_id
    ) THEN RAISE EXCEPTION 'Statuts ou affectations des cinq missions de recette altérés'; END IF;
    -- Dates futures imposées par le trigger anti-publication passée. Le statut
    -- synthétique termine le seed, pas un workflow métier de fin de mission.
    PERFORM set_config('jolene.admin_seed_override_reason','',true);
    r:=public.fn_creer_notation_mission(mission,'ETAB_VERS_SOIGNANT',5,4,5,4,NULL);
    IF r IS DISTINCT FROM '{"success":false,"error":"Non authentifié"}'::jsonb THEN
      RAISE EXCEPTION 'Service sans identité accepté : %',r; END IF;
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.role','authenticated',true);

    -- Deux sens × cibles existantes de statuts distincts, sans assignation,
    -- absente et NULL : aucun oracle de statut, litige ou existence pour les tiers.
    FOREACH acteur IN ARRAY ARRAY[tiers,membre_tiers,sans_profil,claim_admin,inconnu,NULL::uuid] LOOP
      PERFORM set_config('request.jwt.claim.sub',COALESCE(acteur::text,''),true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'Contexte JWT invalide'; END IF;
      IF acteur=claim_admin AND public.est_admin() IS NOT FALSE THEN RAISE EXCEPTION 'Claim admin accepté sans équipe'; END IF;
      IF acteur=sans_profil AND public.fn_compte_auth_actif() IS NOT TRUE THEN RAISE EXCEPTION 'Fixture sans profil mal construite'; END IF;
      FOREACH sens IN ARRAY ARRAY['ETAB_VERS_SOIGNANT','SOIGNANT_VERS_ETAB'] LOOP
        refus:=NULL;
        FOREACH cible IN ARRAY ARRAY[mission,en_cours,sans_soignant,ouverte,absente,NULL::uuid] LOOP
          r:=public.fn_creer_notation_mission(cible,sens,5,4,5,4,'Refus attendu');
          IF r->>'success' IS DISTINCT FROM 'false' OR r ? 'id' THEN
            RAISE EXCEPTION 'Acteur tiers admis : % % %',acteur,sens,r; END IF;
          IF refus IS NOT NULL AND r IS DISTINCT FROM refus THEN RAISE EXCEPTION 'Oracle métier : % % %',acteur,sens,r; END IF;
          refus:=r;
        END LOOP;
      END LOOP;
    END LOOP;

    PERFORM set_config('request.jwt.claim.sub',etab::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',etab,'role','authenticated')::text,true);
    r:=public.fn_creer_notation_mission(mission,'SOIGNANT_VERS_ETAB',5,4,5,4,NULL);
    IF r->>'success' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Établissement admis comme soignant'; END IF;
    r:=public.fn_creer_notation_mission(en_cours,'ETAB_VERS_SOIGNANT',5,4,5,4,NULL);
    IF r->>'error' IS DISTINCT FROM 'Seules les missions TERMINEE peuvent être notées' THEN RAISE EXCEPTION 'Garde métier déplacée : %',r; END IF;
    r:=public.fn_creer_notation_mission(sans_soignant,'ETAB_VERS_SOIGNANT',5,4,5,4,NULL);
    IF r->>'error' IS DISTINCT FROM 'Mission sans soignant assigné' THEN RAISE EXCEPTION 'Mission non assignée notée : %',r; END IF;
    r:=public.fn_creer_notation_mission(mission,NULL,5,4,5,4,NULL);
    IF r->>'error' IS DISTINCT FROM 'Sens invalide' THEN RAISE EXCEPTION 'Sens NULL admis'; END IF;

    -- Propriétaire, membre RH et membre possédant un autre établissement voient
    -- tous la même mission avant notation ; le tenant de membre est prioritaire.
    FOREACH acteur IN ARRAY ARRAY[etab,membre,membre_avec_etab_propre] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      IF public.mon_etablissement_id() IS DISTINCT FROM etab THEN RAISE EXCEPTION 'Tenant canonique non retenu'; END IF;
      r:=public.fn_lister_missions_a_noter_etab();
      IF r->>'success' IS DISTINCT FROM 'true' OR NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(r->'missions') x WHERE x->>'mission_id'=mission::text
      ) THEN RAISE EXCEPTION 'Mission à noter absente avant notation : %',r; END IF;
    END LOOP;
    PERFORM set_config('request.jwt.claim.sub',membre::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',membre,'role','authenticated')::text,true);
    r:=public.fn_creer_notation_mission(mission,'ETAB_VERS_SOIGNANT',5,4,5,4,'Recette établissement');
    IF r->>'success' IS DISTINCT FROM 'true' OR r->>'tardive' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Membre RH refusé : %',r; END IF;
    note_etab:=(r->>'id')::uuid;
    IF NOT EXISTS(SELECT 1 FROM public.notations_missions WHERE id=note_etab
      AND notateur_id=etab AND note_id=sal AND publie_le IS NULL) THEN
      RAISE EXCEPTION 'Auteur canonique, cible ou phase non publiée incorrects'; END IF;
    FOREACH acteur IN ARRAY ARRAY[etab,membre,membre_avec_etab_propre] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      r:=public.fn_lister_missions_a_noter_etab();
      IF r->>'success' IS DISTINCT FROM 'true' OR EXISTS (
        SELECT 1 FROM jsonb_array_elements(r->'missions') x WHERE x->>'mission_id'=mission::text
      ) THEN RAISE EXCEPTION 'Mission déjà notée encore proposée au même tenant : %',r; END IF;
      r:=public.fn_creer_notation_mission(mission,'ETAB_VERS_SOIGNANT',1,1,1,1,'Doublon refusé');
      IF r->>'error' IS DISTINCT FROM 'Mission déjà notée pour ce sens' THEN RAISE EXCEPTION 'Doublon accepté : %',r; END IF;
    END LOOP;

    PERFORM set_config('request.jwt.claim.sub',sal::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',sal,'role','authenticated')::text,true);
    IF EXISTS(SELECT 1 FROM public.notations_missions WHERE mission_id=mission) THEN
      RAISE EXCEPTION 'RLS révèle la note reçue avant réciprocité'; END IF;
    IF public.fn_lister_notations_recues(20) IS DISTINCT FROM '[]'::jsonb THEN
      RAISE EXCEPTION 'RPC révèle la note reçue avant réciprocité'; END IF;
    r:=public.fn_creer_notation_mission(mission,'SOIGNANT_VERS_ETAB',4,5,4,5,'Recette soignant');
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Soignant assigné refusé : %',r; END IF;
    note_sal:=(r->>'id')::uuid;
    SELECT count(*) INTO n FROM public.notations_missions WHERE mission_id=mission AND publie_le=now();
    IF n<>2 THEN RAISE EXCEPTION 'Les deux notes ne sont pas publiées simultanément : %',n; END IF;
    FOREACH acteur IN ARRAY ARRAY[sal,etab,membre,membre_avec_etab_propre] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      r:=public.fn_lister_notations_recues(20);
      IF jsonb_array_length(r) IS DISTINCT FROM 1 OR r->0->>'mission_id' IS DISTINCT FROM mission::text THEN
        RAISE EXCEPTION 'Note reçue après réciprocité absente : % %',acteur,r; END IF;
    END LOOP;
    PERFORM set_config('request.jwt.claim.sub',tiers::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',tiers,'role','authenticated')::text,true);
    IF EXISTS(SELECT 1 FROM public.notations_missions WHERE mission_id=mission) OR public.fn_lister_notations_recues(20)<>'[]'::jsonb THEN
      RAISE EXCEPTION 'Tiers lit une note publiée qui ne le concerne pas'; END IF;
    r:=public.fn_signaler_notation(note_etab,'Refus tiers');
    IF r->>'error' IS DISTINCT FROM 'Vous ne pouvez signaler que les notations vous concernant' THEN RAISE EXCEPTION 'Signalement tiers admis : %',r; END IF;
    PERFORM set_config('request.jwt.claim.sub',sal::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',sal,'role','authenticated')::text,true);
    r:=public.fn_signaler_notation(note_etab,'Signalement synthétique annulé');
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Signalement cible refusé : %',r; END IF;

    -- La famille ADMIN ne peut pas devenir membre d'un établissement.
    -- L'admin réel sans tenant conserve son accès : l'auteur doit être
    -- l'établissement de la mission contrôlée, jamais l'UID de l'admin.
    PERFORM set_config('request.jwt.claim.sub',admin_valide::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',admin_valide,'role','authenticated')::text,true);
    IF public.est_admin() IS NOT TRUE OR public.mon_etablissement_id() IS NOT NULL THEN RAISE EXCEPTION 'Fixture admin sans tenant invalide'; END IF;
    r:=public.fn_creer_notation_mission(mission_admin,'ETAB_VERS_SOIGNANT',5,5,5,5,'Recette admin');
    IF r->>'success' IS DISTINCT FROM 'true' OR NOT EXISTS (
      SELECT 1 FROM public.notations_missions WHERE id=(r->>'id')::uuid AND notateur_id=etab AND note_id=sal AND publie_le IS NULL
    ) THEN RAISE EXCEPTION 'Admin valide ou auteur canonique incorrect : %',r; END IF;

    -- Auth encore vivant : fermeture publique puis suspension Auth doivent
    -- chacune suffire. RESET ROLE ne remet pas les claims à zéro.
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    UPDATE public.soignants SET supprime_le=now() WHERE id=sal;
    UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=membre;
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    FOREACH acteur IN ARRAY ARRAY[sal,membre] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      FOREACH sens IN ARRAY ARRAY['ETAB_VERS_SOIGNANT','SOIGNANT_VERS_ETAB'] LOOP
        r:=public.fn_creer_notation_mission(mission_admin,sens,5,5,5,5,NULL);
        IF r->>'error' IS DISTINCT FROM 'Compte suspendu, supprimé ou désactivé' THEN RAISE EXCEPTION 'Compte fermé/suspendu admis : % %',acteur,r; END IF;
      END LOOP;
    END LOOP;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    UPDATE auth.users SET banned_until=NULL WHERE id=membre;
    UPDATE public.membres_etablissement SET actif=false WHERE user_id=membre AND etablissement_id=etab;
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claim.sub',membre::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',membre,'role','authenticated')::text,true);
    IF public.fn_compte_auth_actif() IS NOT TRUE OR public.mon_etablissement_id() IS NOT NULL THEN
      RAISE EXCEPTION 'Fixture membre révoqué incorrecte'; END IF;
    FOREACH cible IN ARRAY ARRAY[mission,absente,NULL::uuid] LOOP
      r:=public.fn_creer_notation_mission(cible,'ETAB_VERS_SOIGNANT',5,5,5,5,NULL);
      IF r IS DISTINCT FROM '{"success":false,"error":"Accès non autorisé à cette mission."}'::jsonb THEN
        RAISE EXCEPTION 'Membre révoqué accepté ou oracle : %',r; END IF;
    END LOOP;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    IF (SELECT count(*) FROM public.notations_missions WHERE mission_id IN(mission,en_cours,sans_soignant,mission_admin,ouverte))<>3 THEN
      RAISE EXCEPTION 'Un refus a créé une notation'; END IF;
    RAISE EXCEPTION USING ERRCODE='ZN501',MESSAGE='ROLLBACK_NOTATION_REVERSE';
  EXCEPTION WHEN SQLSTATE 'ZN501' THEN NULL;
  END;
  -- L'annulation porte aussi sur les audits, scores et éventuelles files créées
  -- dans le sous-bloc : aucun DELETE métier ni purge d'audit pour nettoyer.
  IF EXISTS(SELECT 1 FROM auth.users WHERE id IN(etab,sal,tiers,membre,autre_etab,membre_tiers,sans_profil,claim_admin,admin_valide,membre_avec_etab_propre,soignant_en_cours))
    OR EXISTS(SELECT 1 FROM public.soignants WHERE id IN(sal,tiers,soignant_en_cours))
    OR EXISTS(SELECT 1 FROM public.missions WHERE id IN(mission,en_cours,sans_soignant,mission_admin,ouverte))
    OR EXISTS(SELECT 1 FROM public.notations_missions WHERE mission_id IN(mission,en_cours,sans_soignant,mission_admin,ouverte))
    OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE id_ressource IN(mission,en_cours,sans_soignant,mission_admin,ouverte,note_etab,note_sal)) THEN
    RAISE EXCEPTION 'Fixtures notation persistantes malgré la sentinelle'; END IF;
END;
$recette$;
ROLLBACK;
