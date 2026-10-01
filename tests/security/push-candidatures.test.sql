-- Staging, verrou CI global. Toutes les fixtures et l'outbox restent invisibles
-- aux workers puis ROLLBACK. Aucun token push, appel Edge ou fournisseur.
BEGIN;
SET LOCAL statement_timeout='90s';
SET LOCAL lock_timeout='5s';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT set_config('request.jwt.claim.sub','',true);
-- Bloque les écritures concurrentes ; acquisition bornée par lock_timeout ci-dessus.
LOCK TABLE public.externalisation_actions IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE push_candidatures_etrangeres AS
 SELECT id,to_jsonb(a) AS ligne FROM public.externalisation_actions a;
ALTER TABLE push_candidatures_etrangeres ADD PRIMARY KEY(id);
CREATE TEMP TABLE push_candidatures_actions_fixture(id uuid PRIMARY KEY);
CREATE TEMP TABLE push_candidatures_results(scenario integer,resultat jsonb);
GRANT INSERT ON push_candidatures_results TO authenticated;
CREATE FUNCTION pg_temp.push_id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
 SELECT ('71140000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid
$f$;
DO $preflight$
BEGIN
 IF auth.uid() IS NOT NULL OR public.est_admin() OR session_user NOT IN ('postgres','supabase_admin')
   OR EXISTS(SELECT 1 FROM cron.job WHERE active) OR EXISTS(SELECT 1 FROM net.http_request_queue)
 THEN RAISE EXCEPTION 'PUSH_RECETTE_CONTEXTE_NON_ISOLE'; END IF;
 -- Aucune mécanique d'UPDATE n'est neutralisée : toute dérive ferme le banc.
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.externalisation_actions'::regclass
   AND tgenabled<>'D' AND (tgtype::integer&16)<>0)
   OR EXISTS(SELECT 1 FROM pg_rewrite WHERE ev_class='public.externalisation_actions'::regclass
     AND ev_type='2' AND ev_enabled<>'D')
 THEN RAISE EXCEPTION 'PUSH_RECETTE_UPDATE_OUTBOX_INATTENDU'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_externalisations_a_traiter(integer,text)'::regprocedure)
      IS DISTINCT FROM '8072a5a972f20c688a3f1000acd35f2b'
   OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.fn_externalisations_a_traiter(integer,text,boolean)'::regprocedure)
      IS DISTINCT FROM '32991bf48c13f2611d44ba068f1bbd3c'
   OR md5(pg_get_functiondef('private.fn_externalisation_est_reelle(public.externalisation_actions)'::regprocedure))
      IS DISTINCT FROM '19210f99b41e9820080825fd5d66b570'
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ELIGIBILITE_DERIVEE'; END IF;
 -- Le SELECT final des claims retrouve aussi une ancienne prise du même worker.
 IF EXISTS(SELECT 1 FROM push_candidatures_etrangeres WHERE ligne->>'cron_lock_par' IN
   ('ancien-push-premier','ancien-push-recette-1','ancien-push-recette-2','ancien-push-recette-3',
    'nouveau-push-sans-capacite','nouveau-push-recette-lot1','nouveau-push-recette-lot2'))
 THEN RAISE EXCEPTION 'PUSH_RECETTE_WORKER_COLLISION'; END IF;
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
-- Les seules dates d'éligibilité sont reportées dans cette transaction annulée.
-- Tous les états et champs métier restent intacts, y compris ceux des actions
-- non réelles. La photo privée n'est jamais renvoyée au client ni journalisée.
UPDATE public.externalisation_actions a
 SET next_retry_at=CASE WHEN a.statut IN ('PENDING','PENDING_AIFE')
       THEN transaction_timestamp()+interval '1 day' ELSE a.next_retry_at END,
     cron_lock_at=CASE WHEN a.statut='PROCESSING'
       THEN transaction_timestamp()+interval '1 day' ELSE a.cron_lock_at END
 FROM push_candidatures_etrangeres e
 WHERE a.id=e.id AND a.statut IN ('PENDING','PENDING_AIFE','PROCESSING');
CREATE FUNCTION pg_temp.verifier_isolement_push() RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 IF EXISTS(SELECT 1 FROM push_candidatures_etrangeres e
   LEFT JOIN public.externalisation_actions a ON a.id=e.id
   WHERE a.id IS NULL OR (to_jsonb(a)-'next_retry_at'-'cron_lock_at')
     IS DISTINCT FROM (e.ligne-'next_retry_at'-'cron_lock_at')
   OR a.next_retry_at IS DISTINCT FROM CASE WHEN e.ligne->>'statut' IN ('PENDING','PENDING_AIFE')
     THEN transaction_timestamp()+interval '1 day' ELSE (e.ligne->>'next_retry_at')::timestamptz END
   OR a.cron_lock_at IS DISTINCT FROM CASE WHEN e.ligne->>'statut'='PROCESSING'
     THEN transaction_timestamp()+interval '1 day' ELSE (e.ligne->>'cron_lock_at')::timestamptz END)
 THEN RAISE EXCEPTION 'PUSH_RECETTE_LIGNE_ETRANGERE_MODIFIEE'; END IF;
 -- Prédicat temporel exact commun aux deux versions de claim. Prouver son
 -- absence est plus strict que filtrer un type ou une classification réelle.
 IF EXISTS(SELECT 1 FROM public.externalisation_actions a
   JOIN push_candidatures_etrangeres e ON e.id=a.id
   WHERE (
       (a.statut = 'PENDING'
         AND (a.next_retry_at IS NULL OR a.next_retry_at < now()))
       OR (a.statut = 'PENDING_AIFE'
         AND a.next_retry_at IS NOT NULL AND a.next_retry_at < now())
       OR (a.statut = 'PROCESSING'
         AND a.cron_lock_at < now() - interval '10 minutes')
     ))
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ACTION_ETRANGERE_ELIGIBLE'; END IF;
END;
$f$;
SELECT pg_temp.verifier_isolement_push();
CREATE FUNCTION pg_temp.verifier_claim_push(r jsonb) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 IF r->'success' IS DISTINCT FROM 'true'::jsonb
   OR jsonb_typeof(r->'actions') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'PUSH_RECETTE_CLAIM_INVALIDE'; END IF;
 IF (r->>'count')::integer IS DISTINCT FROM jsonb_array_length(r->'actions')
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'actions') x
     WHERE x->>'id' IS NULL
       OR EXISTS(SELECT 1 FROM push_candidatures_etrangeres e WHERE e.id::text=x->>'id')
       OR NOT EXISTS(SELECT 1 FROM push_candidatures_actions_fixture f WHERE f.id::text=x->>'id'))
 THEN RAISE EXCEPTION 'PUSH_RECETTE_CLAIM_HORS_FIXTURE'; END IF;
 PERFORM pg_temp.verifier_isolement_push();
END;
$f$;
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
 INSERT INTO push_candidatures_actions_fixture
 SELECT id FROM public.externalisation_actions
 WHERE payload->>'mission_id' IN(pg_temp.push_id(101)::text,pg_temp.push_id(102)::text);
 INSERT INTO push_candidatures_actions_fixture VALUES(pg_temp.push_id(201)),(pg_temp.push_id(202));
 -- Deux anciennes actions du même ensemble restent traitables dans l'ordre.
 INSERT INTO public.externalisation_actions(id,type_action,source,payload,cree_le)
 VALUES (pg_temp.push_id(201),'PUSH_NOTIF','AUTRE',jsonb_build_object('mission_id',pg_temp.push_id(101)),transaction_timestamp()-interval '2 hours'),
        (pg_temp.push_id(202),'PUSH_NOTIF','AUTRE',jsonb_build_object('mission_id',pg_temp.push_id(101)),transaction_timestamp()-interval '1 hour');
 r:=public.fn_externalisations_a_traiter(1,'ancien-push-premier');
 PERFORM pg_temp.verifier_claim_push(r);
 IF (r->>'count')::integer<>1 OR r#>>'{actions,0,id}'<>pg_temp.push_id(201)::text
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ORDRE_OU_BUDGET_LEGACY'; END IF;
 -- Trois passages d'un ancien worker : aucune prise ni tentative du type neuf.
 FOR r IN SELECT public.fn_externalisations_a_traiter(50,'ancien-push-recette-'||i) FROM generate_series(1,3) i LOOP
   PERFORM pg_temp.verifier_claim_push(r);
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.externalisation_actions WHERE payload->>'mission_id' IN(pg_temp.push_id(101)::text,pg_temp.push_id(102)::text)
   AND type_action='PUSH_CANDIDATURE_RECUE'
   AND (statut<>'PENDING' OR tentatives<>0)) THEN RAISE EXCEPTION 'PUSH_RECETTE_ANCIEN_WORKER_A_CONSOMME'; END IF;
 IF (SELECT count(*) FROM public.externalisation_actions
   WHERE id IN(pg_temp.push_id(201),pg_temp.push_id(202)) AND type_action='PUSH_NOTIF'
     AND statut='PROCESSING' AND tentatives=0)<>2
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ANCIENNES_ACTIONS_NON_TRAITEES'; END IF;
 r:=public.fn_externalisations_a_traiter(50,'nouveau-push-sans-capacite',false);
 PERFORM pg_temp.verifier_claim_push(r);
 IF (r->>'count')::integer<>0 THEN RAISE EXCEPTION 'PUSH_RECETTE_CAPACITE_REFUSEE'; END IF;
 r:=public.fn_externalisations_a_traiter(2,'nouveau-push-recette-lot1',true);
 PERFORM pg_temp.verifier_claim_push(r);
 revendique:=(r->>'count')::integer;
 IF revendique<>2 THEN RAISE EXCEPTION 'PUSH_RECETTE_BUDGET_NOUVEAU'; END IF;
 r:=public.fn_externalisations_a_traiter(50,'nouveau-push-recette-lot2',true);
 PERFORM pg_temp.verifier_claim_push(r);
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
-- Aucun nouvel objet de file hors des huit actions explicitement recensées.
DO $restauration$
BEGIN
 PERFORM pg_temp.verifier_isolement_push();
 IF EXISTS(SELECT 1 FROM public.externalisation_actions a
   WHERE NOT EXISTS(SELECT 1 FROM push_candidatures_etrangeres e WHERE e.id=a.id)
     AND NOT EXISTS(SELECT 1 FROM push_candidatures_actions_fixture f WHERE f.id=a.id))
 THEN RAISE EXCEPTION 'PUSH_RECETTE_ACTION_AJOUTEE_HORS_FIXTURE'; END IF;
 UPDATE public.externalisation_actions a
   SET next_retry_at=(e.ligne->>'next_retry_at')::timestamptz,
       cron_lock_at=(e.ligne->>'cron_lock_at')::timestamptz
   FROM push_candidatures_etrangeres e WHERE a.id=e.id
     AND e.ligne->>'statut' IN ('PENDING','PENDING_AIFE','PROCESSING');
 IF EXISTS(SELECT 1 FROM push_candidatures_etrangeres e
   LEFT JOIN public.externalisation_actions a ON a.id=e.id
   WHERE to_jsonb(a) IS DISTINCT FROM e.ligne)
 THEN RAISE EXCEPTION 'PUSH_RECETTE_RESTAURATION_INEXACTE'; END IF;
 IF EXISTS(SELECT 1 FROM net.http_request_queue)
 THEN RAISE EXCEPTION 'PUSH_RECETTE_HTTP_INTERDIT'; END IF;
END;
$restauration$;
ROLLBACK;
