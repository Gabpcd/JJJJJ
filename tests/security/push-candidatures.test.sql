-- Staging, verrou CI global. Toutes les fixtures et l'outbox restent invisibles
-- aux workers puis ROLLBACK. Aucun token push, appel Edge ou fournisseur.
BEGIN;
SET LOCAL statement_timeout='90s';
SET LOCAL lock_timeout='5s';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT set_config('request.jwt.claim.sub','',true);
CREATE TEMP TABLE push_candidatures_results(scenario integer,resultat jsonb);
GRANT INSERT ON push_candidatures_results TO authenticated;
CREATE FUNCTION pg_temp.push_id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
 SELECT ('71140000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$f$;
DO $preflight$
BEGIN
 IF auth.uid() IS NOT NULL OR public.est_admin() OR session_user NOT IN ('postgres','supabase_admin')
   OR EXISTS(SELECT 1 FROM cron.job WHERE active) OR EXISTS(SELECT 1 FROM net.http_request_queue)
   OR EXISTS(SELECT 1 FROM public.externalisation_actions a WHERE a.statut IN('PENDING','PROCESSING','PENDING_AIFE') AND private.fn_externalisation_est_reelle(a))
 THEN RAISE EXCEPTION 'PUSH_RECETTE_CONTEXTE_NON_ISOLE'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal
   AND tgenabled<>'D' AND (tgtype::integer&4)<>0)
 THEN RAISE EXCEPTION 'PUSH_RECETTE_AUTH_INSERT_INATTENDU'; END IF;
 IF EXISTS(SELECT 1 FROM auth.users WHERE id::text LIKE '71140000-%')
   OR EXISTS(SELECT 1 FROM public.missions WHERE id::text LIKE '71140000-%')
   OR EXISTS(SELECT 1 FROM public.etablissements WHERE siret IN ('71140000000001','71140000000002'))
 THEN RAISE EXCEPTION 'PUSH_RECETTE_COLLISION'; END IF;
 IF has_function_privilege('authenticated','public.fn_preparer_push_candidature_recue(uuid)','execute')
   OR has_function_privilege('anon','public.fn_preparer_push_candidature_recue(uuid)','execute')
   OR NOT has_function_privilege('service_role','public.fn_preparer_push_candidature_recue(uuid)','execute')
   OR has_function_privilege('authenticated','public.fn_externalisations_a_traiter(integer,text,boolean)','execute')
   OR has_function_privilege('anon','public.fn_externalisations_a_traiter(integer,text,boolean)','execute')
   OR NOT has_function_privilege('service_role','public.fn_externalisations_a_traiter(integer,text,boolean)','execute')
   OR has_function_privilege('service_role','private.fn_enfiler_push_candidature_recue(uuid,uuid)','execute')
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ACL'; END IF;
END;
$preflight$;
-- Activer uniquement la règle d'INSERT au sein de la transaction annulée.
-- Aucun ancien compte TEST n'est transformé et aucun trigger n'est désactivé.
UPDATE public.parametres_systeme SET valeur=1 WHERE cle='inscriptions_publiques_actives';
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at,banned_until)
SELECT pg_temp.push_id(n),'00000000-0000-0000-0000-000000000000','push-rollback-'||n||'@example.invalid',
 'authenticated','authenticated',jsonb_build_object('role',CASE WHEN n IN(1,2,10) THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,
 'etablissement_id',pg_temp.push_id(3),'est_compte_test',n IN(10,11)),now(),CASE WHEN n=7 THEN now()+interval '1 day' END
FROM generate_series(1,14) n;
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,est_compte_test,
 source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in)
SELECT pg_temp.push_id(n),'Fixture','Push','push-rollback-'||n||'@example.invalid','IDE','SALARIE','1990-01-01',n=10,
 'RECETTE_PUSH_SQL','PUSHRECETTE'||n,false,false,false FROM unnest(ARRAY[1,2,10]) n;
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,
 est_compte_test,source_acquisition,code_parrainage,sms_actif,chorus_pro_actif,est_secteur_public)
SELECT pg_temp.push_id(n),'Fixture push',CASE WHEN n=3 THEN '71140000000001' ELSE '71140000000002' END,
 'CLINIQUE_PRIVEE','Adresse fictive','Paris','75001','push-rollback-'||n||'@example.invalid',n=11,
 'RECETTE_PUSH_SQL','PUSHETAB'||n,false,false,false FROM unnest(ARRAY[3,11]) n;
INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
SELECT pg_temp.push_id(3),pg_temp.push_id(n),CASE WHEN n=5 THEN 'LECTURE_SEULE' WHEN n=12 THEN 'POINTAGE_ONLY' WHEN n=14 THEN 'ADMIN_GROUPE' ELSE 'RH' END,n<>6
FROM unnest(ARRAY[4,5,6,7,8,9,12,14]) n;
INSERT INTO public.preferences_notifications(utilisateur_id,canal_email,canal_sms,canal_push,canal_in_app)
SELECT pg_temp.push_id(n),false,false,n<>8,true FROM generate_series(1,14) n
ON CONFLICT(utilisateur_id) DO UPDATE SET canal_email=false,canal_sms=false,canal_push=excluded.canal_push,canal_in_app=true;
INSERT INTO public.preferences_notifications_par_evenement(utilisateur_id,type_evenement,canal,actif)
VALUES(pg_temp.push_id(9),'CANDIDATURE_RECUE','PUSH',false);
INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,duree_heures,
 taux_horaire_base,statut,type_contrat_recherche,mode_attribution,est_urgente)
SELECT pg_temp.push_id(n),pg_temp.push_id(CASE WHEN n=103 THEN 11 ELSE 3 END),'Fixture push rollback','IDE',
 current_date+interval '10 days 09 hours',current_date+interval '10 days 13 hours',4,20,'OUVERTE','SALARIE','CANDIDATURE',false
FROM generate_series(101,104) n;
DO $fixtures$
BEGIN
 IF (SELECT count(*) FROM public.soignants WHERE id IN(pg_temp.push_id(1),pg_temp.push_id(2)) AND est_compte_test IS FALSE)<>2
 OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=pg_temp.push_id(3) AND est_compte_test IS FALSE)
 OR (SELECT count(*) FROM public.mission_creneaux WHERE mission_id IN(pg_temp.push_id(101),pg_temp.push_id(102),pg_temp.push_id(103),pg_temp.push_id(104)) AND type_creneau='PREVISIONNEL')<>4
 THEN RAISE EXCEPTION 'PUSH_RECETTE_FIXTURES_INCOHERENTES'; END IF;
END;
$fixtures$;
-- Vrais acteurs et véritables RPC ; SALARIE autorise la candidature avec rappel
-- de documents, sans créer de qualification ou de contrat signé fictif.
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.push_id(1))::text,true);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.push_candidatures_results VALUES(1,public.fn_postuler_mission(pg_temp.push_id(101),'Message privé non transmis au push','SALARIE'));
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.push_id(2))::text,true);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.push_candidatures_results VALUES(2,public.fn_enregistrer_swipe(pg_temp.push_id(102),'LIKE','SALARIE'));
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.push_id(10))::text,true);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.push_candidatures_results VALUES(3,public.fn_postuler_mission(pg_temp.push_id(103),'Cohorte TEST','SALARIE'));
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $preuves$
DECLARE c uuid; n uuid; a uuid; r jsonb; d uuid; revendique integer;
BEGIN
 IF (SELECT resultat->'success' FROM push_candidatures_results WHERE scenario=1) IS DISTINCT FROM 'true'::jsonb
 OR (SELECT resultat->'ok' FROM push_candidatures_results WHERE scenario=2) IS DISTINCT FROM 'true'::jsonb
 OR (SELECT resultat->'success' FROM push_candidatures_results WHERE scenario=3) IS DISTINCT FROM 'true'::jsonb
 THEN RAISE EXCEPTION 'PUSH_RECETTE_PRODUCTEUR_REFUSE'; END IF;
 IF (SELECT count(*) FROM public.externalisation_actions WHERE payload->>'mission_id' IN(pg_temp.push_id(101)::text,pg_temp.push_id(102)::text))<>6
 OR EXISTS(SELECT 1 FROM public.externalisation_actions WHERE payload->>'mission_id'=pg_temp.push_id(103)::text)
 THEN RAISE EXCEPTION 'PUSH_RECETTE_FILE_NON_EXACTE'; END IF;
 IF EXISTS(SELECT 1 FROM public.externalisation_actions WHERE payload->>'mission_id' IN(pg_temp.push_id(101)::text,pg_temp.push_id(102)::text)
 AND (payload->>'destinataire_id' NOT IN(pg_temp.push_id(3)::text,pg_temp.push_id(4)::text,pg_temp.push_id(14)::text)
 OR payload::text LIKE '%Message privé%')) THEN RAISE EXCEPTION 'PUSH_RECETTE_DESTINATAIRE_OU_CONTENU'; END IF;
 -- Deux anciennes actions du même ensemble restent traitables dans l'ordre.
 INSERT INTO public.externalisation_actions(id,type_action,source,payload,cree_le)
 VALUES (pg_temp.push_id(201),'PUSH_NOTIF','AUTRE',jsonb_build_object('mission_id',pg_temp.push_id(101)),transaction_timestamp()-interval '2 hours'),
        (pg_temp.push_id(202),'PUSH_NOTIF','AUTRE',jsonb_build_object('mission_id',pg_temp.push_id(101)),transaction_timestamp()-interval '1 hour');
 r:=public.fn_externalisations_a_traiter(1,'ancien-push-premier');
 IF (r->>'count')::integer<>1 OR r#>>'{actions,0,id}'<>pg_temp.push_id(201)::text
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ORDRE_OU_BUDGET_LEGACY'; END IF;
 -- Trois passages d'un ancien worker : aucune prise ni tentative du type neuf.
 FOR r IN SELECT public.fn_externalisations_a_traiter(50,'ancien-push-recette-'||i) FROM generate_series(1,3) i LOOP NULL; END LOOP;
 IF EXISTS(SELECT 1 FROM public.externalisation_actions WHERE payload->>'mission_id' IN(pg_temp.push_id(101)::text,pg_temp.push_id(102)::text)
   AND type_action='PUSH_CANDIDATURE_RECUE'
   AND (statut<>'PENDING' OR tentatives<>0)) THEN RAISE EXCEPTION 'PUSH_RECETTE_ANCIEN_WORKER_A_CONSOMME'; END IF;
 IF (SELECT count(*) FROM public.externalisation_actions
   WHERE id IN(pg_temp.push_id(201),pg_temp.push_id(202)) AND type_action='PUSH_NOTIF'
     AND statut='PROCESSING' AND tentatives=0)<>2
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ANCIENNES_ACTIONS_NON_TRAITEES'; END IF;
 r:=public.fn_externalisations_a_traiter(50,'nouveau-push-sans-capacite',false);
 IF (r->>'count')::integer<>0 THEN RAISE EXCEPTION 'PUSH_RECETTE_CAPACITE_REFUSEE'; END IF;
 r:=public.fn_externalisations_a_traiter(2,'nouveau-push-recette-lot1',true);
 revendique:=(r->>'count')::integer;
 IF revendique<>2 THEN RAISE EXCEPTION 'PUSH_RECETTE_BUDGET_NOUVEAU'; END IF;
 r:=public.fn_externalisations_a_traiter(50,'nouveau-push-recette-lot2',true);
 IF (r->>'count')::integer<>4 THEN RAISE EXCEPTION 'PUSH_RECETTE_NOUVEAU_WORKER_CLAIM'; END IF;
 SELECT id INTO c FROM public.candidatures WHERE mission_id=pg_temp.push_id(101);
 SELECT id INTO n FROM public.notifications WHERE id_ressource=c AND type='CANDIDATURE_RECUE';
 -- Ré-enfilage interne : index unique, même action et même clé de reprise.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.push_id(1))::text,true);
 PERFORM private.fn_enfiler_push_candidature_recue(c,n);
 IF (SELECT count(*) FROM public.externalisation_actions WHERE source_id=c AND type_action='PUSH_CANDIDATURE_RECUE')<>3
 THEN RAISE EXCEPTION 'PUSH_RECETTE_DOUBLON'; END IF;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 SELECT id INTO a FROM public.externalisation_actions WHERE source_id=c AND payload->>'destinataire_id'=pg_temp.push_id(4)::text;
 UPDATE public.externalisation_actions SET statut='PROCESSING' WHERE id=a;
 r:=public.fn_preparer_push_candidature_recue(a);
 IF r->'eligible' IS DISTINCT FROM 'true'::jsonb OR r#>>'{payload,data,candidature_id}'<>c::text THEN RAISE EXCEPTION 'PUSH_RECETTE_PROVENANCE'; END IF;
 UPDATE public.membres_etablissement SET actif=false WHERE user_id=pg_temp.push_id(4);
 IF public.fn_preparer_push_candidature_recue(a)->>'raison' IS DISTINCT FROM 'destinataire_inactif' THEN RAISE EXCEPTION 'PUSH_RECETTE_MEMBRE_REVOQUE'; END IF;
 UPDATE public.membres_etablissement SET actif=true WHERE user_id=pg_temp.push_id(4);
 UPDATE public.preferences_notifications SET canal_push=false WHERE utilisateur_id=pg_temp.push_id(4);
 IF public.fn_preparer_push_candidature_recue(a)->>'raison' IS DISTINCT FROM 'preference_desactivee' THEN RAISE EXCEPTION 'PUSH_RECETTE_PREFERENCE_TARDIVE'; END IF;
 UPDATE public.preferences_notifications SET canal_push=true WHERE utilisateur_id=pg_temp.push_id(4);
 UPDATE public.externalisation_actions SET payload=jsonb_set(payload,'{data,soignant_id}',to_jsonb(pg_temp.push_id(2))) WHERE id=a;
 BEGIN
   PERFORM public.fn_preparer_push_candidature_recue(a);
   RAISE EXCEPTION 'PUSH_RECETTE_FORGERIE_ACCEPTEE';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM<>'PUSH_CANDIDATURE_PROVENANCE_INVALIDE' THEN RAISE; END IF;
 END;
 -- Un ancien événement ne peut être enfilé par le helper, même avec UID exact.
 UPDATE public.candidatures SET cree_le=transaction_timestamp()-interval '1 day' WHERE id=c;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.push_id(1))::text,true);
 BEGIN
   PERFORM private.fn_enfiler_push_candidature_recue(c,n);
   RAISE EXCEPTION 'PUSH_RECETTE_RETROACTIF_ACCEPTE';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM<>'PUSH_CANDIDATURE_EVENEMENT_INVALIDE' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 IF EXISTS(SELECT 1 FROM net.http_request_queue) THEN RAISE EXCEPTION 'PUSH_RECETTE_HTTP_INTERDIT'; END IF;
END;
$preuves$;
-- Panne de queue : candidature + notification doivent disparaître ensemble.
CREATE FUNCTION pg_temp.refuser_push_recette() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN IF NEW.payload->>'mission_id'=pg_temp.push_id(104)::text THEN RAISE EXCEPTION 'PUSH_RECETTE_PANNE_QUEUE'; END IF; RETURN NEW; END;
$f$;
CREATE TRIGGER recette_push_refus BEFORE INSERT ON public.externalisation_actions FOR EACH ROW EXECUTE FUNCTION pg_temp.refuser_push_recette();
DO $atomicite$
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',pg_temp.push_id(1))::text,true);
 BEGIN
   PERFORM public.fn_postuler_mission(pg_temp.push_id(104),'Panne de file','SALARIE');
   RAISE EXCEPTION 'PUSH_RECETTE_PANNE_ABSENTE';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'PUSH_RECETTE_PANNE_QUEUE' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM public.candidatures WHERE mission_id=pg_temp.push_id(104))
   OR EXISTS(SELECT 1 FROM public.notifications WHERE lien='/etablissement/missions/'||pg_temp.push_id(104)::text)
   OR EXISTS(SELECT 1 FROM public.externalisation_actions WHERE payload->>'mission_id'=pg_temp.push_id(104)::text)
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ROLLBACK_PARTIEL'; END IF;
END;
$atomicite$;
ROLLBACK;
