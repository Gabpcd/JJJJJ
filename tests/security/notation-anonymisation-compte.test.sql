-- Vraies RPC et triggers sous identités fictives ; aucun appel fournisseur.
-- Toutes les fixtures, leurs audits et les suppressions sont annulés, même
-- lorsque le runner retire BEGIN/ROLLBACK pour sa transaction globale.
BEGIN;
DO $recette$
DECLARE
  e1 uuid := 'a9305800-0000-4000-8000-000000000001';
  s1 uuid := 'a9305800-0000-4000-8000-000000000002';
  e2 uuid := 'a9305800-0000-4000-8000-000000000003';
  s2 uuid := 'a9305800-0000-4000-8000-000000000004';
  membre uuid := 'a9305800-0000-4000-8000-000000000005';
  admin_reel uuid := 'a9305800-0000-4000-8000-000000000006';
  sans_profil uuid := 'a9305800-0000-4000-8000-000000000007';
  m1 uuid := 'a9305800-0000-4000-8000-000000000101';
  m2 uuid := 'a9305800-0000-4000-8000-000000000102';
  m3 uuid := 'a9305800-0000-4000-8000-000000000103';
  absente uuid := 'a9305800-0000-4000-8000-000000000199';
  n1 uuid; n2 uuid; n3 uuid; n4 uuid; n5 uuid;
  acteur uuid; cible uuid; r jsonb; refus jsonb; avant jsonb; temoin jsonb;
  v_signature text; v_md5 text; v_colonne text; v_contrainte text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.notations_missions'::regclass
    AND attname='notateur_id' AND attnotnull)
    OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.notations_missions'::regclass
      AND attname='note_id' AND attnotnull)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.notations_missions'::regclass
      AND conname='notations_missions_auteur_anonymise_check' AND convalidated)
    OR md5((SELECT prosrc FROM pg_proc WHERE oid='public.fn_trg_anonymiser_notations_suppression()'::regprocedure))
      IS DISTINCT FROM 'c1075608a0b29574cd78451c8e9e703d'
  THEN RAISE EXCEPTION 'Schéma ou trigger anonymisation inattendu'; END IF;
  FOR v_signature,v_md5 IN VALUES
    ('fn_modifier_notation_mission(uuid,integer,integer,integer,integer,text)','63f28d2ca3ad4580538aa7de55020edb'),
    ('fn_signaler_notation(uuid,text)','4f58a286981573d8b1096568af11d2f8')
  LOOP
    IF NOT EXISTS (SELECT 1 FROM private.security_definer_inventory i JOIN pg_proc p
      ON p.oid=to_regprocedure('public.'||i.signature)
      WHERE i.signature=v_signature AND i.definition_md5=v_md5 AND md5(p.prosrc)=v_md5
      AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proacl='{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[])
    THEN RAISE EXCEPTION 'Inventaire/droits notation divergents : %',v_signature; END IF;
  END LOOP;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    PERFORM set_config('app.test_mode','true',true);
    PERFORM set_config('jolene.admin_seed_override_reason','Recette anonymisation notation sous rollback',true);
    INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
    SELECT ('a9305800-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      '00000000-0000-0000-0000-000000000000','notation-anonymisation-'||i||'@example.invalid',
      'authenticated','authenticated',jsonb_build_object('role',CASE WHEN i IN(2,4) THEN 'SOIGNANT'
        WHEN i=6 THEN 'ADMIN_PLATEFORME' WHEN i=7 THEN NULL ELSE 'ADMIN_ETABLISSEMENT' END,'is_test_playwright',true),now()
    FROM generate_series(1,7) i;
    INSERT INTO public.soignants(id,email,prenom,nom,profession,type_exercice,est_compte_test)
    VALUES(s1,'notation-anonymisation-2@example.invalid','Recette','Suppression','IDE','SALARIE',true),
      (s2,'notation-anonymisation-4@example.invalid','Recette','Témoin','IDE','SALARIE',true);
    INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
    VALUES(e1,'Structure à fermer','99305800000001','CLINIQUE_PRIVEE','Test','Paris','75001','notation-anonymisation-1@example.invalid',true),
      (e2,'Structure témoin','99305800000003','CLINIQUE_PRIVEE','Test','Paris','75001','notation-anonymisation-3@example.invalid',true);
    INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif) VALUES(e1,membre,'RH',true);
    INSERT INTO public.equipe_admin(user_id,nom,prenom,email,actif,acces_groupes)
    VALUES(admin_reel,'Recette','Admin','notation-anonymisation-6@example.invalid',true,
      ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']::text[]);
    INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,
      taux_horaire_base,statut,soignant_assigne_id,type_contrat_recherche,type_contrat_applique,type_paiement_soignant,est_urgente)
    SELECT ('a9305800-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      CASE WHEN i=2 THEN e2 ELSE e1 END,'Recette anonymisation '||i,'IDE',
      now()+interval '20 years'+i*interval '1 day',now()+interval '20 years 4 hours'+i*interval '1 day',4,20,
      'TERMINEE'::public.statut_mission,CASE WHEN i=2 THEN s2 ELSE s1 END,'SALARIE','SALARIE','BULLETIN_PAIE',false
    FROM generate_series(1,3) i;
    IF (SELECT count(*) FROM public.missions WHERE id IN(m1,m2,m3) AND statut='TERMINEE')<>3
    THEN RAISE EXCEPTION 'Statuts des fixtures altérés'; END IF;
    PERFORM set_config('jolene.admin_seed_override_reason','',true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    FOREACH acteur IN ARRAY ARRAY[e1,s1,e2,s2] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      r:=public.fn_creer_notation_mission(CASE WHEN acteur IN(e1,s1) THEN m1 ELSE m2 END,
        CASE WHEN acteur IN(e1,e2) THEN 'ETAB_VERS_SOIGNANT' ELSE 'SOIGNANT_VERS_ETAB' END,5,5,5,5,NULL);
      IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Notation initiale refusée : %',r; END IF;
      IF acteur=e1 THEN n1:=(r->>'id')::uuid; ELSIF acteur=s1 THEN n2:=(r->>'id')::uuid;
      ELSIF acteur=e2 THEN n3:=(r->>'id')::uuid; ELSE n4:=(r->>'id')::uuid; END IF;
    END LOOP;
    PERFORM set_config('request.jwt.claim.sub',e1::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',e1,'role','authenticated')::text,true);
    r:=public.fn_creer_notation_mission(m3,'ETAB_VERS_SOIGNANT',5,5,5,5,NULL);
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Note non réciproque refusée : %',r; END IF;
    n5:=(r->>'id')::uuid;

    -- Le membre canonique garde le droit de modifier ; un client ne peut
    -- pas contourner le trigger en effaçant lui-même l'auteur via PostgREST.
    PERFORM set_config('request.jwt.claim.sub',membre::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',membre,'role','authenticated')::text,true);
    r:=public.fn_modifier_notation_mission(n1,5,5,5,5,NULL);
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Membre canonique refusé : %',r; END IF;
    BEGIN
      UPDATE public.notations_missions SET notateur_id=NULL,notateur_anonymise=true WHERE id=n1;
      RAISE EXCEPTION 'Client autorisé à anonymiser lui-même une note';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;

    -- Les refus tiers ne révèlent ni existence, ni âge, ni état signalé.
    FOREACH acteur IN ARRAY ARRAY[s2,e2,sans_profil] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      refus:=NULL;
      FOREACH cible IN ARRAY ARRAY[n1,n2,n5,absente,NULL::uuid] LOOP
        r:=public.fn_modifier_notation_mission(cible,1,1,1,1,'Tiers refusé');
        IF r IS DISTINCT FROM '{"success":false,"error":"Accès refusé"}'::jsonb THEN RAISE EXCEPTION 'Modification tiers/oracle : %',r; END IF;
        r:=public.fn_signaler_notation(cible,'Tiers refusé');
        IF r IS DISTINCT FROM '{"success":false,"error":"Vous ne pouvez signaler que les notations vous concernant"}'::jsonb
        THEN RAISE EXCEPTION 'Signalement tiers/oracle : %',r; END IF;
      END LOOP;
    END LOOP;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    BEGIN
      UPDATE public.notations_missions SET notateur_id=NULL,notateur_anonymise=false WHERE id=n3;
      RAISE EXCEPTION 'Auteur NULL non anonymisé accepté';
    EXCEPTION WHEN check_violation THEN
      GET STACKED DIAGNOSTICS v_contrainte=CONSTRAINT_NAME;
      IF v_contrainte<>'notations_missions_auteur_anonymise_check' THEN RAISE; END IF;
    END;
    BEGIN
      UPDATE public.notations_missions SET note_id=NULL WHERE id=n3;
      RAISE EXCEPTION 'Cible NULL acceptée';
    EXCEPTION WHEN not_null_violation THEN
      GET STACKED DIAGNOSTICS v_colonne=COLUMN_NAME;
      IF v_colonne<>'note_id' THEN RAISE; END IF;
    END;
    UPDATE public.notations_missions SET cree_le=now()-interval '8 days' WHERE id=n3;
    SELECT jsonb_agg(to_jsonb(n) ORDER BY n.id) INTO temoin FROM public.notations_missions n WHERE id IN(n3,n4);
    SELECT jsonb_agg(to_jsonb(n)-ARRAY['notateur_id','notateur_anonymise'] ORDER BY n.id) INTO avant
      FROM public.notations_missions n WHERE id IN(n1,n2,n5);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    PERFORM set_config('request.jwt.claim.sub',e2::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',e2,'role','authenticated')::text,true);
    r:=public.fn_modifier_notation_mission(n3,1,1,1,1,NULL);
    IF r->>'error' IS DISTINCT FROM 'Notation non modifiable après 7 jours' THEN RAISE EXCEPTION 'Délai modifié : %',r; END IF;

    -- Fermer l'établissement ayant émis deux notes. Le trigger original doit
    -- fonctionner ; aucune suppression de note ni sortie anticipée du test.
    PERFORM set_config('request.jwt.claim.sub',e1::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',e1,'role','authenticated')::text,true);
    r:=public.fn_supprimer_compte_etablissement_rate_limited();
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Fermeture établissement refusée : %',r; END IF;
    r:=public.fn_supprimer_compte_etablissement_rate_limited();
    IF r->>'deja_anonymise' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Reprise établissement non idempotente : %',r; END IF;
    IF public.fn_compte_auth_actif() IS NOT FALSE THEN RAISE EXCEPTION 'Compte établissement encore actif'; END IF;
    PERFORM set_config('request.jwt.claim.sub',s1::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s1,'role','authenticated')::text,true);
    IF NOT EXISTS(SELECT 1 FROM public.notations_missions WHERE id=n1 AND notateur_id IS NULL AND notateur_anonymise)
      OR EXISTS(SELECT 1 FROM public.notations_missions WHERE id=n5)
    THEN RAISE EXCEPTION 'Note publiée perdue ou double aveugle révélé après fermeture auteur'; END IF;
    r:=public.fn_signaler_notation(n1,'Signalement de la cible active');
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Cible active ne peut plus signaler : %',r; END IF;
    r:=public.fn_signaler_notation(n1,'Doublon');
    IF r->>'error' IS DISTINCT FROM 'Notation déjà signalée' THEN RAISE EXCEPTION 'Doublon signalement accepté'; END IF;

    -- Un admin réel conserve la modification d'une note récente anonymisée.
    PERFORM set_config('request.jwt.claim.sub',admin_reel::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',admin_reel,'role','authenticated')::text,true);
    IF public.est_admin() IS NOT TRUE THEN RAISE EXCEPTION 'Fixture admin invalide'; END IF;
    r:=public.fn_modifier_notation_mission(n1,5,5,5,5,NULL);
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Admin valide refusé après anonymisation : %',r; END IF;
    r:=public.fn_signaler_notation(n2,'Admin non destinataire');
    IF r->>'success' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Nouveau droit admin de signalement'; END IF;

    -- Auteur NULL : tiers actif et ancien membre ne gagnent aucun droit.
    FOREACH acteur IN ARRAY ARRAY[s2,e2,membre,sans_profil] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      IF acteur=membre AND (public.fn_compte_auth_actif() IS NOT TRUE OR public.mon_etablissement_id() IS NOT NULL)
      THEN RAISE EXCEPTION 'RH authentifié conserve le tenant fermé'; END IF;
      r:=public.fn_modifier_notation_mission(n1,1,1,1,1,'NULL refusé');
      IF r->>'error' IS DISTINCT FROM 'Accès refusé' THEN RAISE EXCEPTION 'Auteur NULL attribué au tiers : %',r; END IF;
      r:=public.fn_signaler_notation(n2,'Ancien tenant refusé');
      IF r->>'success' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Ancien tenant encore admis au signalement'; END IF;
    END LOOP;
    PERFORM set_config('request.jwt.claim.sub',s1::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s1,'role','authenticated')::text,true);
    r:=public.fn_supprimer_compte_rate_limited();
    IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Fermeture soignant refusée : %',r; END IF;
    r:=public.fn_supprimer_compte_rate_limited();
    IF r->>'deja_anonymise' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Reprise soignant non idempotente : %',r; END IF;
    FOREACH acteur IN ARRAY ARRAY[s1,e1] LOOP
      PERFORM set_config('request.jwt.claim.sub',acteur::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',acteur,'role','authenticated')::text,true);
      FOREACH cible IN ARRAY ARRAY[n1,n2,absente,NULL::uuid] LOOP
        r:=public.fn_modifier_notation_mission(cible,1,1,1,1,NULL);
        IF r->>'error' IS DISTINCT FROM 'Compte suspendu, supprimé ou désactivé' THEN RAISE EXCEPTION 'Compte fermé modifie : %',r; END IF;
        r:=public.fn_signaler_notation(cible,'Compte fermé');
        IF r->>'error' IS DISTINCT FROM 'Compte suspendu, supprimé ou désactivé' THEN RAISE EXCEPTION 'Compte fermé signale : %',r; END IF;
      END LOOP;
      IF EXISTS(SELECT 1 FROM public.notations_missions WHERE mission_id IN(m1,m3)) THEN RAISE EXCEPTION 'RLS compte fermé ouverte'; END IF;
    END LOOP;
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
    r:=public.fn_modifier_notation_mission(n1,1,1,1,1,NULL);
    IF r->>'error' IS DISTINCT FROM 'Non authentifié' THEN RAISE EXCEPTION 'UID NULL modifie'; END IF;
    r:=public.fn_signaler_notation(n1,NULL);
    IF r->>'error' IS DISTINCT FROM 'Non authentifié' THEN RAISE EXCEPTION 'UID NULL signale'; END IF;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
    IF (SELECT count(*) FROM public.notations_missions WHERE mission_id IN(m1,m2,m3))<>5
      OR EXISTS(SELECT 1 FROM public.notations_missions WHERE id IN(n1,n2,n5) AND (notateur_id IS NOT NULL OR NOT notateur_anonymise))
      OR (SELECT jsonb_agg(to_jsonb(n) ORDER BY n.id) FROM public.notations_missions n WHERE id IN(n3,n4)) IS DISTINCT FROM temoin
      OR (SELECT jsonb_agg((to_jsonb(n)-ARRAY['notateur_id','notateur_anonymise'])||jsonb_build_object('signale',false) ORDER BY n.id)
          FROM public.notations_missions n WHERE id IN(n1,n2,n5)) IS DISTINCT FROM avant
      OR NOT private.fn_anonymisation_compte_confirmee(e1,'ETABLISSEMENT')
      OR NOT private.fn_anonymisation_compte_confirmee(s1,'SOIGNANT')
      OR EXISTS(SELECT 1 FROM auth.users WHERE id IN(e1,s1) AND (deleted_at IS NOT NULL OR banned_until IS NOT NULL))
    THEN RAISE EXCEPTION 'Notes, cible, contenu, publication, témoin ou preuve de fermeture altérés'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.journaux_audit WHERE acteur_id=admin_reel AND action='NOTATION_DONNEE'
      AND details->>'notation_id'=n1::text AND details->>'modification'='true')
    THEN RAISE EXCEPTION 'Modification admin anonymisée sans acteur audit'; END IF;
    RAISE EXCEPTION USING ERRCODE='ZN581',MESSAGE='ROLLBACK_NOTATION_ANONYMISATION';
  EXCEPTION WHEN SQLSTATE 'ZN581' THEN
    IF SQLERRM IS DISTINCT FROM 'ROLLBACK_NOTATION_ANONYMISATION' THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id IN(e1,s1,e2,s2,membre,admin_reel,sans_profil))
    OR EXISTS(SELECT 1 FROM public.missions WHERE id IN(m1,m2,m3))
    OR EXISTS(SELECT 1 FROM public.notations_missions WHERE mission_id IN(m1,m2,m3))
    OR EXISTS(SELECT 1 FROM private.suppressions_compte_confirmees WHERE utilisateur_id IN(e1,s1))
    OR EXISTS(SELECT 1 FROM public.journaux_audit WHERE id_ressource IN(e1,s1,m1,m2,m3,n1,n2,n3,n4,n5))
  THEN RAISE EXCEPTION 'Fixtures anonymisation persistantes après rollback'; END IF;
END;
$recette$;
ROLLBACK;
