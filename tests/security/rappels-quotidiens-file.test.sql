-- Pas de transport : fixtures et toutes les assertions annulées en fin de test.
BEGIN;
SET LOCAL statement_timeout='90s';
SET LOCAL lock_timeout='5s';
-- Management API ne permet pas de changer session_replication_role. Les FK
-- et CHECK restent donc actifs. Les seules fenêtres de suspension concernent
-- les triggers utilisateur du montage des fixtures, jamais les fonctions daily.
LOCK TABLE public.etablissements,public.missions,public.soignants IN ACCESS EXCLUSIVE MODE;
CREATE TEMP TABLE recette_daily_triggers_avant AS
SELECT tgrelid,tgname,tgenabled FROM pg_trigger
WHERE tgrelid IN ('public.etablissements'::regclass,'public.missions'::regclass,'public.soignants'::regclass)
AND NOT tgisinternal;
DO $garde$
BEGIN
 IF EXISTS(SELECT 1 FROM recette_daily_triggers_avant WHERE tgenabled IN('A','R'))
 THEN RAISE EXCEPTION 'Trigger ALWAYS/REPLICA inattendu : recette daily refusée'; END IF;
END $garde$;
-- auth.users LIVE n'a aucun trigger INSERT : aucun droit ni DDL sur Auth.
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES ('69500000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','daily-etab@example.invalid','authenticated','authenticated','{}',now()),
 ('69500000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','daily-soignant@example.invalid','authenticated','authenticated','{}',now());

DO $fixtures$
DECLARE t record;
BEGIN
 -- Deux profils non-test sont nécessaires pour exercer le rappel SMS. Seule
 -- la garde pré-lancement est suspendue, les autres triggers profils restent actifs.
 FOR t IN SELECT * FROM recette_daily_triggers_avant WHERE tgenabled='O'
   AND (tgrelid='public.missions'::regclass AND EXISTS (
     SELECT 1 FROM pg_trigger p WHERE p.tgrelid=recette_daily_triggers_avant.tgrelid
       AND p.tgname=recette_daily_triggers_avant.tgname AND (p.tgtype & 4)<>0)
     OR tgname='trg_forcer_compte_test_prelaunch' AND tgrelid IN ('public.soignants'::regclass,'public.etablissements'::regclass))
 LOOP EXECUTE format('ALTER TABLE %s DISABLE TRIGGER %I',t.tgrelid::regclass,t.tgname); END LOOP;
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
VALUES ('69500000-0000-4000-8000-000000000001','Recette daily','69500000000001','CLINIQUE_PRIVEE','1 rue Fictive','Paris','75001','daily-etab@example.invalid',false);
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,est_compte_test,telephone,sms_actif,sms_alertes_actives)
VALUES ('69500000-0000-4000-8000-000000000002','Recette','Daily','daily-soignant@example.invalid','IDE','SALARIE',false,'+33000000000',true,true);
INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,taux_horaire_base,statut,soignant_assigne_id,type_contrat_applique)
SELECT ('69500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'69500000-0000-4000-8000-000000000001','Recette daily '||n,'IDE',
 CURRENT_DATE+interval '1 day 9 hours',CURRENT_DATE+interval '1 day 17 hours',8,30,'ASSIGNEE','69500000-0000-4000-8000-000000000002','SALARIE'
FROM generate_series(101,130) n;
 -- Exécuter les contraintes différées avant tout ALTER de restauration :
 -- PostgreSQL refuse le DDL sur une table avec événements FK encore en attente.
 -- Ce passage renforce le contrôle des fixtures ; aucune contrainte n'est retirée.
 SET CONSTRAINTS ALL IMMEDIATE;
 -- Restauration exacte avant d'appeler les vraies fonctions testées. Un échec
 -- SQL annule ensemble ce DDL et les fixtures ; aucun état durable ne change.
 FOR t IN SELECT a.* FROM recette_daily_triggers_avant a JOIN pg_trigger p
   ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname WHERE a.tgenabled='O' AND p.tgenabled='D'
 LOOP EXECUTE format('ALTER TABLE %s ENABLE TRIGGER %I',t.tgrelid::regclass,t.tgname); END LOOP;
 IF EXISTS(SELECT 1 FROM recette_daily_triggers_avant a JOIN pg_trigger p
   ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname WHERE p.tgenabled<>a.tgenabled)
 THEN RAISE EXCEPTION 'Triggers non restaurés avant les assertions daily'; END IF;
END $fixtures$;

-- Une panne d'insertion ne peut laisser un reçu qui empêcherait la reprise.
CREATE FUNCTION pg_temp.refuser_file_daily() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN IF NEW.type LIKE 'CRON_DAILY_%' THEN RAISE EXCEPTION 'Panne de file simulée'; END IF; RETURN NEW; END $f$;
CREATE TRIGGER recette_refus_daily BEFORE INSERT ON public.email_queue FOR EACH ROW EXECUTE FUNCTION pg_temp.refuser_file_daily();
DO $preuve$
BEGIN
 BEGIN
   PERFORM public.fn_preparer_rappels_quotidiens();
   RAISE EXCEPTION 'Échec attendu absent';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM<>'Panne de file simulée' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM private.rappels_quotidiens_livraisons WHERE soignant_id='69500000-0000-4000-8000-000000000002')
 THEN RAISE EXCEPTION 'Reçu orphelin après rollback de file'; END IF;
END $preuve$;
DROP TRIGGER recette_refus_daily ON public.email_queue;

DO $preuve$
DECLARE e uuid; sms uuid; c uuid; v jsonb; n integer; cle jsonb; t record;
BEGIN
 FOR cle IN SELECT to_jsonb(p) FROM (VALUES
   ('public.fn_preparer_rappels_quotidiens()'),('public.fn_lire_rappel_quotidien(uuid)'),
   ('public.fn_acquitter_rappel_quotidien(uuid,text)'),('public.fn_reprendre_rappels_quotidiens()')) p(signature) LOOP
   IF has_function_privilege('authenticated',cle->>'signature','execute') OR has_function_privilege('anon',cle->>'signature','execute')
     OR NOT has_function_privilege('service_role',cle->>'signature','execute') THEN RAISE EXCEPTION 'Droits de fonction incorrects : %',cle; END IF;
 END LOOP;
 IF has_table_privilege('authenticated','private.rappels_quotidiens_livraisons','SELECT') OR has_table_privilege('service_role','private.rappels_quotidiens_livraisons','INSERT')
 THEN RAISE EXCEPTION 'Reçus privés accessibles directement'; END IF;
 PERFORM public.fn_preparer_rappels_quotidiens();
 SELECT count(*) INTO n FROM private.rappels_quotidiens_livraisons WHERE soignant_id='69500000-0000-4000-8000-000000000002';
 IF n<>120 THEN RAISE EXCEPTION '30 missions doivent produire 120 livraisons, reçu %',n; END IF;
 IF EXISTS(SELECT 1 FROM public.rappels_contrat_travail WHERE mission_id::text LIKE '69500000-%')
 THEN RAISE EXCEPTION 'Contrat comptabilisé avant transport'; END IF;
 PERFORM public.fn_preparer_rappels_quotidiens();
 IF (SELECT count(*) FROM private.rappels_quotidiens_livraisons WHERE soignant_id='69500000-0000-4000-8000-000000000002')<>120
 THEN RAISE EXCEPTION 'Doublon de préparation'; END IF;
 SELECT email_id INTO e FROM private.rappels_quotidiens_livraisons WHERE mission_id='69500000-0000-4000-8000-000000000101' AND nature='MISSION_EMAIL';
 SELECT email_id INTO sms FROM private.rappels_quotidiens_livraisons WHERE mission_id='69500000-0000-4000-8000-000000000101' AND nature='MISSION_SMS';
 SELECT email_id INTO c FROM private.rappels_quotidiens_livraisons WHERE mission_id='69500000-0000-4000-8000-000000000101' AND nature='CONTRAT_ETAB';
 v:=public.fn_lire_rappel_quotidien(e); cle:=v;
 IF v->>'valide'<>'true' OR v->'corps'->>'type'<>'RAPPEL_MISSION' OR v->'corps'->>'destinataire_id'<>'69500000-0000-4000-8000-000000000002'
 THEN RAISE EXCEPTION 'Contrat email J-1 changé'; END IF;
 IF public.fn_lire_rappel_quotidien(sms)->'corps'->>'type'<>'RAPPEL_MISSION_J1'
 THEN RAISE EXCEPTION 'Type SMS ne passe plus par les préférences canoniques'; END IF;
 UPDATE private.rappels_quotidiens_livraisons SET jour=CURRENT_DATE-1 WHERE email_id IN(e,sms,c);
 IF public.fn_lire_rappel_quotidien(e)->>'valide'<>'false' OR public.fn_lire_rappel_quotidien(sms)->>'valide'<>'false'
 THEN RAISE EXCEPTION 'Rappel demain accepté après changement de jour'; END IF;
 IF public.fn_lire_rappel_quotidien(c)->>'valide'<>'true' THEN RAISE EXCEPTION 'Contrat futur annulé par la borne J-1'; END IF;
 UPDATE private.rappels_quotidiens_livraisons SET jour=CURRENT_DATE WHERE email_id IN(e,sms,c);
 PERFORM public.fn_acquitter_rappel_quotidien(e,'ERREUR');
 IF (SELECT statut FROM public.email_queue WHERE id=e)<>'ERREUR' THEN RAISE EXCEPTION 'Échec perdu'; END IF;
 PERFORM public.fn_reprendre_rappels_quotidiens();
 IF (SELECT statut FROM public.email_queue WHERE id=e)<>'ERREUR' THEN RAISE EXCEPTION 'Backoff ignoré'; END IF;
 UPDATE private.rappels_quotidiens_livraisons SET prochaine_tentative_le=now()-interval '1 second' WHERE email_id=e;
 PERFORM public.fn_reprendre_rappels_quotidiens();
 IF public.fn_lire_rappel_quotidien(e)<>cle THEN RAISE EXCEPTION 'Identité/contenu changés au réessai'; END IF;
 PERFORM public.fn_acquitter_rappel_quotidien(c,'ANNULE');
 IF EXISTS(SELECT 1 FROM public.rappels_contrat_travail WHERE mission_id='69500000-0000-4000-8000-000000000101')
 THEN RAISE EXCEPTION 'Opt-out compté comme envoi de contrat'; END IF;
 SELECT email_id INTO c FROM private.rappels_quotidiens_livraisons WHERE mission_id='69500000-0000-4000-8000-000000000101' AND nature='CONTRAT_SOIGNANT';
 PERFORM public.fn_acquitter_rappel_quotidien(c,'ENVOYE');
 PERFORM public.fn_acquitter_rappel_quotidien(c,'ENVOYE');
 IF (SELECT count(*) FROM public.rappels_contrat_travail WHERE mission_id='69500000-0000-4000-8000-000000000101' AND cible_soignant AND NOT cible_etab AND envoye_le=CURRENT_DATE)<>1
 THEN RAISE EXCEPTION 'Acquittement cible/date/idempotence incorrect'; END IF;
 PERFORM public.fn_acquitter_rappel_quotidien(c,'ANNULE');
 IF (SELECT statut FROM public.email_queue WHERE id=c)<>'ENVOYE' THEN RAISE EXCEPTION 'Envoi confirmé rétrogradé'; END IF;

 UPDATE public.soignants SET sms_alertes_actives=false WHERE id='69500000-0000-4000-8000-000000000002';
 IF public.fn_lire_rappel_quotidien(sms)->>'valide'<>'false' THEN RAISE EXCEPTION 'SMS opt-out non respecté'; END IF;
 UPDATE public.soignants SET sms_alertes_actives=true,telephone='+33000000001' WHERE id='69500000-0000-4000-8000-000000000002';
 IF public.fn_lire_rappel_quotidien(sms)->>'valide'<>'false' THEN RAISE EXCEPTION 'Ancien téléphone encore notifié'; END IF;
 -- Changement d'assignation artificiel pour tester la relecture du reçu,
 -- sans déclencher d'acte d'annulation. FK actives, triggers UPDATE restaurés
 -- avant fn_lire_rappel_quotidien ; aucune fonction daily n'est remplacée.
 FOR t IN SELECT a.* FROM recette_daily_triggers_avant a JOIN pg_trigger p
   ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname
   WHERE a.tgrelid='public.missions'::regclass AND a.tgenabled='O' AND (p.tgtype & 16)<>0
 LOOP EXECUTE format('ALTER TABLE %s DISABLE TRIGGER %I',t.tgrelid::regclass,t.tgname); END LOOP;
 UPDATE public.missions SET soignant_assigne_id=NULL WHERE id='69500000-0000-4000-8000-000000000101';
 FOR t IN SELECT a.* FROM recette_daily_triggers_avant a JOIN pg_trigger p
   ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname WHERE a.tgenabled='O' AND p.tgenabled='D'
 LOOP EXECUTE format('ALTER TABLE %s ENABLE TRIGGER %I',t.tgrelid::regclass,t.tgname); END LOOP;
 IF EXISTS(SELECT 1 FROM recette_daily_triggers_avant a JOIN pg_trigger p
   ON p.tgrelid=a.tgrelid AND p.tgname=a.tgname WHERE p.tgenabled<>a.tgenabled)
 THEN RAISE EXCEPTION 'Triggers non restaurés après la désassignation simulée'; END IF;
 IF public.fn_lire_rappel_quotidien(e)->>'valide'<>'false' THEN RAISE EXCEPTION 'Rappel envoyé après désassignation'; END IF;
END $preuve$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
