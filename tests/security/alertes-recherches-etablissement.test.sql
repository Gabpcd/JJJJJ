-- Régression réelle sur staging/local uniquement ; la CI enveloppe aussi la migration.
-- Aucun appel Edge/email : toutes les écritures, profils et évaluations sont annulés.
BEGIN;
SET LOCAL statement_timeout = '90s';
SET LOCAL session_replication_role = replica;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
SELECT ('69300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000', 'alerte-recette-'||n||'@example.invalid',
 'authenticated','authenticated',jsonb_build_object('role',CASE WHEN n<100 THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END),now()
FROM unnest(ARRAY[1,2,3,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118]) n;
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,adresse_lat,adresse_lng,est_compte_test)
VALUES ('69300000-0000-4000-8000-000000000001','Établissement recette alertes','69300000000001','CLINIQUE_PRIVEE','1 rue Recette','Paris','75001','alerte-recette-1@example.invalid',48.8566,2.3522,false);
INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
VALUES ('69300000-0000-4000-8000-000000000001','69300000-0000-4000-8000-000000000002','RH',true);
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,adresse_ville,adresse_lat,adresse_lng,
 note_moyenne,nb_evaluations,score_fiabilite,total_missions_terminees,annees_experience,disponible_urgence,tous_documents_valides,
 bio,est_compte_test,supprime_le,cree_le)
SELECT ('69300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Recette '||n,'Alertes','alerte-recette-'||n||'@example.invalid',
 CASE WHEN n=102 THEN 'AS' ELSE 'IDE' END::public.type_profession,
 CASE WHEN n=103 THEN 'LIBERAL' ELSE 'SALARIE' END,
 CASE WHEN n=104 THEN 'Lyon' ELSE 'Paris' END,
 CASE WHEN n=118 THEN NULL WHEN n=105 THEN 45.764 ELSE 48.8566 END,
 CASE WHEN n=118 THEN NULL WHEN n=105 THEN 4.8357 ELSE 2.3522 END,
 CASE WHEN n=106 THEN 3 ELSE 4.5 END,CASE WHEN n=114 THEN 2 ELSE 3 END,
 CASE WHEN n=107 THEN 60 ELSE 90 END,CASE WHEN n=115 THEN 2 ELSE 3 END,
 CASE WHEN n=108 THEN 2 ELSE 8 END,n<>109,n<>110,
 CASE WHEN n=111 THEN 'Autre bio' ELSE 'recette-alertes-tag expérience pédiatrie' END,n=113,
 CASE WHEN n=112 THEN now() ELSE NULL END,
 CASE WHEN n=116 THEN now()-interval '2 days' WHEN n=117 THEN now()+interval '1 day' ELSE now()-interval '30 minutes' END
FROM generate_series(101,118) n;
SET LOCAL session_replication_role = origin;

DO $preuve$
DECLARE
 f uuid := '69300000-0000-4000-8000-000000000201';
 criteria jsonb := '{"profession":"IDE","type_exercice":"SALARIE","ville":"Paris","distance_max_km":"25","note_min":"4","score_min":"80","experience_min":"5","disponible_urgence":true,"documents_valides":true,"recherche_texte":"recette-alertes-tag"}';
 v jsonb; a jsonb; key text; expected integer; n integer; r record;
BEGIN
 INSERT INTO public.filtres_sauvegardes(id,utilisateur_id,nom,audience,filtres,alerte_active,frequence_alerte,dernier_check_le)
 VALUES(f,'69300000-0000-4000-8000-000000000002','Recette dix critères','ETAB_RECHERCHE_SOIGNANTS',criteria,true,'IMMEDIATE',now()-interval '1 hour');
 -- Dix critères ensemble : seul le profil conforme et celui de distance inconnue.
 -- Distance inconnue conservée exactement comme dans l'annuaire canonique.
 n := public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour');
 IF n<>2 THEN RAISE EXCEPTION 'Dix critères : attendu 2, obtenu %',n; END IF;
 a := public.fn_obtenir_apercu_filtre(f,now()-interval '1 hour',100);
 IF jsonb_array_length(a)<>2 OR NOT a @> '[{"id":"69300000-0000-4000-8000-000000000101"},{"id":"69300000-0000-4000-8000-000000000118"}]'::jsonb
 THEN RAISE EXCEPTION 'Aperçu hors critères : %',a; END IF;
 IF public.fn_obtenir_apercu_filtre(f,now()-interval '1 hour',1)->0->>'id'<>'69300000-0000-4000-8000-000000000101'
 THEN RAISE EXCEPTION 'Limite/ordre aperçu instable'; END IF;

 -- Retirer chaque critère ramène exactement le contre-exemple correspondant.
 -- Note et score ont chacun aussi un cas immature : ne pas révéler leurs valeurs.
 FOR key,expected IN SELECT * FROM (VALUES ('profession',3),('type_exercice',3),('ville',3),('distance_max_km',3),
   ('note_min',4),('score_min',4),('experience_min',3),('disponible_urgence',3),('documents_valides',3),('recherche_texte',3)) t LOOP
   UPDATE public.filtres_sauvegardes SET filtres=criteria-key WHERE id=f;
   n := public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour');
   IF n<>expected THEN RAISE EXCEPTION 'Critère % ignoré/différent : attendu %, obtenu %',key,expected,n; END IF;
   a := public.fn_obtenir_apercu_filtre(f,now()-interval '1 hour',100);
   IF jsonb_array_length(a)<>n THEN RAISE EXCEPTION 'Aperçu/compteur divergent pour %',key; END IF;
 END LOOP;
 -- False signifie case décochée (aucun filtre), pas exigence de valeur false.
 UPDATE public.filtres_sauvegardes SET filtres=criteria || '{"disponible_urgence":false,"documents_valides":false}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>4 THEN RAISE EXCEPTION 'Checkbox false ne reproduit pas annuaire'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria WHERE id=f;

 -- Fenêtre [since exclu, now inclus], pas de profil futur ni déjà ancien.
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '30 minutes')<>0 THEN RAISE EXCEPTION 'Borne since inclusive ou profil futur inclus'; END IF;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '3 days')<>3 THEN RAISE EXCEPTION 'Ancien profil non pris en compte dans large fenêtre'; END IF;
 -- Critères malformés : aucun cast ne plante et aucun élargissement silencieux.
 FOR v IN SELECT value FROM jsonb_array_elements('[{"score_min":"oops"},{"note_min":6},{"distance_max_km":-1},{"experience_min":1.5},{"documents_valides":"true"},{"profession":"inconnue"},{"inconnu":true},[],null]') LOOP
   UPDATE public.filtres_sauvegardes SET filtres=v WHERE id=f;
   IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 OR public.fn_obtenir_apercu_filtre(f,now()-interval '1 hour',5)<>'[]'::jsonb
   THEN RAISE EXCEPTION 'Filtre invalide accepté : %',v; END IF;
 END LOOP;
 UPDATE public.filtres_sauvegardes SET filtres=criteria WHERE id=f;

 -- Le membre reçoit exactement le périmètre de son établissement (pas son UUID).
 PERFORM set_config('request.jwt.claims','{"sub":"69300000-0000-4000-8000-000000000002","role":"authenticated"}',true);
 v := public.fn_rechercher_soignants_etab('IDE',NULL,'Paris',25,'SALARIE',4,80,5,true,true,'recette-alertes-tag',100,0);
 -- Annuaire inclut les profils anciens et ne filtre pas cree_le : 4, dont le futur de fixture.
 IF v->>'count_total'<>'4' THEN RAISE EXCEPTION 'Annuaire canonique changé : %',v; END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.fn_obtenir_apercu_filtre(f,now()-interval '1 hour',100)) s
   WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'soignants') d WHERE d->>'id'=s->>'id'))
 THEN RAISE EXCEPTION 'IDs aperçu absents de l’annuaire'; END IF;
 -- Casts numériques équivalents au formulaire, notamment "5.0" normalisé à 5.
 UPDATE public.filtres_sauvegardes SET filtres=criteria || '{"experience_min":"5.0"}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>2 THEN RAISE EXCEPTION 'Nombre entier sérialisé en décimal refusé'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria WHERE id=f;
 -- Contrat RPC : ne pas accepter une alerte dont les critères seraient ignorés.
 v := public.fn_creer_filtre_sauvegarde('Critères invalides','ETAB_RECHERCHE_SOIGNANTS','{"score_min":"oops"}',true,'QUOTIDIENNE');
 IF v->>'error' IS NULL THEN RAISE EXCEPTION 'Création RPC critères invalides acceptée'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres='{"score_min":"oops"}',alerte_active=false WHERE id=f;
 v := public.fn_modifier_filtre_sauvegarde(f,NULL,true,NULL);
 IF v->>'error' IS NULL THEN RAISE EXCEPTION 'Activation RPC critères invalides acceptée'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria,alerte_active=true WHERE id=f;
 PERFORM set_config('request.jwt.claims','{}',true);
 UPDATE public.membres_etablissement SET actif=false WHERE user_id='69300000-0000-4000-8000-000000000002';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Membre détaché encore notifié'; END IF;
 UPDATE public.membres_etablissement SET actif=true WHERE user_id='69300000-0000-4000-8000-000000000002';
 UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='69300000-0000-4000-8000-000000000002';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Membre banni encore notifié'; END IF;
 PERFORM set_config('request.jwt.claims','{"sub":"69300000-0000-4000-8000-000000000002","role":"authenticated"}',true);
 IF public.fn_rechercher_soignants_etab()->>'error' IS NULL THEN RAISE EXCEPTION 'Annuaire accessible au compte banni'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 UPDATE auth.users SET banned_until=NULL,deleted_at=now() WHERE id='69300000-0000-4000-8000-000000000002';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Compte supprimé encore notifié'; END IF;
 UPDATE auth.users SET deleted_at=NULL WHERE id='69300000-0000-4000-8000-000000000002';
 UPDATE public.filtres_sauvegardes SET utilisateur_id='69300000-0000-4000-8000-000000000003' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Sans rattachement encore notifié'; END IF;
 UPDATE public.filtres_sauvegardes SET utilisateur_id='69300000-0000-4000-8000-000000000001' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>2 THEN RAISE EXCEPTION 'Propriétaire legacy sans membre exclu'; END IF;
 -- Les profils candidats inactifs sont exclus de l'annuaire ET des alertes.
 UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='69300000-0000-4000-8000-000000000101';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>1 THEN RAISE EXCEPTION 'Profil banni inclus'; END IF;
 UPDATE auth.users SET banned_until=NULL,deleted_at=now() WHERE id='69300000-0000-4000-8000-000000000101';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>1 THEN RAISE EXCEPTION 'Profil auth supprimé inclus'; END IF;
 UPDATE auth.users SET deleted_at=NULL WHERE id='69300000-0000-4000-8000-000000000101';
 UPDATE public.soignants SET statut_compte='SUSPENDU' WHERE id='69300000-0000-4000-8000-000000000101';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>1 THEN RAISE EXCEPTION 'Profil suspendu inclus'; END IF;
 UPDATE public.soignants SET statut_compte='ACTIF' WHERE id='69300000-0000-4000-8000-000000000101';
 -- Fonctions internes non appelables depuis les clients ; RPC annuaire conserve son grant.
 IF has_function_privilege('authenticated','private.fn_resultats_filtre_soignants(uuid,timestamptz)','EXECUTE')
 OR has_function_privilege('anon','private.fn_resultats_recherche_soignants_etab(uuid,text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text)','EXECUTE')
 OR has_function_privilege('authenticated','public.fn_compter_nouveaux_pour_filtre(uuid,timestamptz)','EXECUTE')
 OR has_function_privilege('authenticated','public.fn_evaluer_alertes_filtres(text)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.fn_rechercher_soignants_etab(text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text,integer,integer)','EXECUTE')
 THEN RAISE EXCEPTION 'ACL moteur/recherche incorrectes'; END IF;
END;
$preuve$;
-- Cadence et reprise : aucun ancien filtre staging ne participe à la recette.
UPDATE public.filtres_sauvegardes SET alerte_active=false WHERE id<>'69300000-0000-4000-8000-000000000201';
DO $cadence$
DECLARE f uuid:='69300000-0000-4000-8000-000000000201'; n integer; r record; actual integer; q uuid; v jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims','{"sub":"69300000-0000-4000-8000-000000000001","role":"authenticated"}',true);
 DELETE FROM private.alertes_filtres_worker;
 IF public.fn_capacite_alertes_recherches() THEN RAISE EXCEPTION 'Capacité active avant worker compatible'; END IF;
 PERFORM public.fn_reprendre_alertes_filtres();
 IF NOT public.fn_capacite_alertes_recherches() THEN RAISE EXCEPTION 'Capacité absente après worker compatible'; END IF;
 UPDATE private.alertes_filtres_worker SET derniere_execution_le=now()-interval '3 hours';
 IF public.fn_capacite_alertes_recherches() THEN RAISE EXCEPTION 'Capacité active avec worker périmé'; END IF;
 UPDATE private.alertes_filtres_worker SET derniere_execution_le=now()-interval '2 hours 59 minutes';
 IF NOT public.fn_capacite_alertes_recherches() THEN RAISE EXCEPTION 'Capacité absente malgré worker frais'; END IF;
 PERFORM set_config('request.jwt.claims','{"sub":"69300000-0000-4000-8000-000000000003","role":"authenticated"}',true);
 IF public.fn_capacite_alertes_recherches() THEN RAISE EXCEPTION 'Capacité ouverte à un compte sans rattachement'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 FOR r IN SELECT * FROM (VALUES ('IMMEDIATE',interval '59 minutes',interval '1 hour'),('QUOTIDIENNE',interval '23 hours 59 minutes',interval '1 day'),('HEBDOMADAIRE',interval '6 days 23 hours',interval '7 days')) t(freq,trop_tot,eligible) LOOP
  DELETE FROM public.email_queue WHERE id IN(SELECT email_id FROM private.alertes_filtres_livraisons WHERE filtre_id=f);
  UPDATE public.filtres_sauvegardes SET alerte_active=true,frequence_alerte=r.freq::public.filtre_frequence_alerte,dernier_check_le=now()-r.trop_tot WHERE id=f;
  PERFORM * FROM public.fn_evaluer_alertes_filtres(r.freq);
  IF EXISTS(SELECT 1 FROM private.alertes_filtres_livraisons WHERE filtre_id=f) THEN RAISE EXCEPTION 'Fréquence % évaluée trop tôt',r.freq; END IF;
  UPDATE public.filtres_sauvegardes SET dernier_check_le=now()-r.eligible WHERE id=f;
  actual:=public.fn_compter_nouveaux_pour_filtre(f,now()-r.eligible);
  SELECT count(*) INTO n FROM public.fn_evaluer_alertes_filtres(r.freq);
  IF n<>0 THEN RAISE EXCEPTION 'Ancien worker pourrait envoyer le lot en double'; END IF;
  SELECT l.email_id INTO q FROM private.alertes_filtres_livraisons l WHERE l.filtre_id=f;
  IF q IS NULL THEN RAISE EXCEPTION 'Lot % absent',r.freq; END IF;
  SELECT data INTO v FROM public.email_queue WHERE id=q;
  IF (v->>'count')::int<>actual OR jsonb_array_length(v->'soignants')<>least(actual,5) OR v->>'nom_etab'<>'Établissement recette alertes' THEN RAISE EXCEPTION 'Payload exact invalide %',v; END IF;
  IF v->'soignants' @> '[{"id":"69300000-0000-4000-8000-000000000117"}]'::jsonb THEN RAISE EXCEPTION 'Profil futur dans lot'; END IF;
  IF r.freq='IMMEDIATE' AND v->'soignants' @> '[{"id":"69300000-0000-4000-8000-000000000116"}]'::jsonb THEN RAISE EXCEPTION 'Ancien profil dans nouvelle fenêtre'; END IF;
  PERFORM * FROM public.fn_evaluer_alertes_filtres(r.freq);
  IF (SELECT count(*) FROM private.alertes_filtres_livraisons WHERE filtre_id=f)<>1 THEN RAISE EXCEPTION 'Doublon de lot'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.filtres_sauvegardes WHERE id=f AND dernier_check_le=now() AND nb_resultats_dernier_check=actual) THEN RAISE EXCEPTION 'Watermark non atomique'; END IF;
 END LOOP;
 IF NOT public.fn_verifier_livraison_alerte_filtre(q) THEN RAISE EXCEPTION 'Lot valide refusé'; END IF;
 UPDATE public.filtres_sauvegardes SET alerte_active=false WHERE id=f;
 IF public.fn_verifier_livraison_alerte_filtre(q) THEN RAISE EXCEPTION 'Alerte désactivée livrable'; END IF;
 UPDATE public.filtres_sauvegardes SET alerte_active=true WHERE id=f;
 UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='69300000-0000-4000-8000-000000000101';
 IF public.fn_verifier_livraison_alerte_filtre(q) THEN RAISE EXCEPTION 'Profil devenu banni encore livrable'; END IF;
 UPDATE auth.users SET banned_until=NULL WHERE id='69300000-0000-4000-8000-000000000101';
 UPDATE public.email_queue SET statut='ERREUR',erreur='transport simulé 503' WHERE id=q;
 PERFORM public.fn_reporter_echec_alerte_filtre(q);
 PERFORM public.fn_reprendre_alertes_filtres();
 IF (SELECT statut FROM public.email_queue WHERE id=q)<>'ERREUR' THEN RAISE EXCEPTION 'Retry sans délai'; END IF;
 UPDATE private.alertes_filtres_livraisons SET prochaine_tentative_le=now() WHERE email_id=q;
 PERFORM public.fn_reprendre_alertes_filtres();
 IF (SELECT statut FROM public.email_queue WHERE id=q)<>'EN_ATTENTE' OR (SELECT data FROM public.email_queue WHERE id=q)<>v THEN RAISE EXCEPTION 'Retry perd fenêtre/contenu'; END IF;
 UPDATE public.email_queue SET statut='ENVOYE' WHERE id=q;
 PERFORM public.fn_reprendre_alertes_filtres();
 IF (SELECT statut FROM public.email_queue WHERE id=q)<>'ENVOYE' THEN RAISE EXCEPTION 'Lot envoyé rejoué'; END IF;
 IF has_function_privilege('authenticated','public.fn_reprendre_alertes_filtres()','EXECUTE') OR has_function_privilege('authenticated','public.fn_verifier_livraison_alerte_filtre(uuid)','EXECUTE') OR has_table_privilege('authenticated','private.alertes_filtres_livraisons','SELECT') THEN RAISE EXCEPTION 'Outbox accessible au client'; END IF;
END $cadence$;

-- Les sept critères de l'Explorer soignant (pas de critère date enregistré dans
-- ce formulaire), avec les règles de visibilité et les créneaux Paris.
SET LOCAL session_replication_role=replica;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
SELECT ('69300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000000','alerte-etab-'||n||'@example.invalid','authenticated','authenticated','{"role":"ADMIN_ETABLISSEMENT"}',now() FROM generate_series(4,11) n;
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,adresse_lat,adresse_lng,est_compte_test,supprime_le)
SELECT ('69300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Recette missions '||n,'693000000000'||lpad(n::text,2,'0'),'CLINIQUE_PRIVEE','1 rue Simulation',CASE WHEN n=6 THEN 'Autre ville' ELSE 'Alerte Ville 693' END,'69301','alerte-etab-'||n||'@example.invalid',CASE WHEN n=11 THEN NULL WHEN n=5 THEN 45.764 ELSE 48.8566 END,CASE WHEN n=11 THEN NULL WHEN n=5 THEN 4.8357 ELSE 2.3522 END,n=9,CASE WHEN n=10 THEN now() ELSE NULL END FROM generate_series(4,11) n;
UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='69300000-0000-4000-8000-000000000007';
INSERT INTO public.exclusions(exclu_par,exclu_id,type_exclu_par) VALUES('69300000-0000-4000-8000-000000000008','69300000-0000-4000-8000-000000000101','ETABLISSEMENT');
UPDATE public.soignants SET types_contrat_acceptes='["CDD","LIBERAL"]',rayon_deplacement_km=50 WHERE id='69300000-0000-4000-8000-000000000101';
INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,est_urgente,statut,cree_le,type_contrat_recherche,nb_creneaux)
SELECT ('69300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 ('69300000-0000-4000-8000-'||lpad((CASE n WHEN 407 THEN 5 WHEN 408 THEN 6 WHEN 413 THEN 7 WHEN 414 THEN 8 WHEN 415 THEN 9 WHEN 416 THEN 10 WHEN 417 THEN 11 ELSE 4 END)::text,12,'0'))::uuid,
 'Recette alerte mission '||n,CASE WHEN n=402 THEN 'AS' ELSE 'IDE' END::public.type_profession,
 ((date_trunc('week',now() AT TIME ZONE 'Europe/Paris')+CASE n WHEN 406 THEN interval '7 days 22 hours' WHEN 409 THEN interval '-7 days 10 hours' ELSE interval '7 days 10 hours' END) AT TIME ZONE 'Europe/Paris'),
 ((date_trunc('week',now() AT TIME ZONE 'Europe/Paris')+CASE n WHEN 406 THEN interval '8 days 6 hours' WHEN 409 THEN interval '-7 days 18 hours' ELSE interval '7 days 18 hours' END) AT TIME ZONE 'Europe/Paris'),
 CASE WHEN n=403 THEN 20 ELSE 35 END,n<>404,'OUVERTE',CASE WHEN n=410 THEN now()-interval '2 days' WHEN n=411 THEN now()+interval '1 day' ELSE now()-interval '30 minutes' END,
 CASE WHEN n=405 THEN 'LIBERAL' ELSE 'SALARIE' END,CASE WHEN n=412 THEN 2 ELSE 1 END
FROM generate_series(401,417) n;
SET LOCAL session_replication_role=origin;
DO $missions$
DECLARE f uuid:='69300000-0000-4000-8000-000000000202'; criteria jsonb:='{"profession":"IDE","rayonKm":25,"tauxMin":30,"typeContrat":"CDD","urgentesOnly":true,"horaire":"JOUR","villeRecherche":"Alerte Ville 693"}'; n integer; k text; v jsonb; q uuid;
BEGIN
 INSERT INTO public.filtres_sauvegardes(id,utilisateur_id,nom,audience,filtres,alerte_active,frequence_alerte,dernier_check_le)
 VALUES(f,'69300000-0000-4000-8000-000000000101','Recette sept critères','SOIGNANT_RECHERCHE_MISSIONS',criteria,true,'IMMEDIATE',now()-interval '1 hour');
 n:=public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour');
 IF n<>2 THEN RAISE EXCEPTION 'Sept critères soignant : attendu 2, obtenu %',n; END IF;
 FOREACH k IN ARRAY ARRAY['profession','rayonKm','tauxMin','typeContrat','urgentesOnly','horaire','villeRecherche'] LOOP
  -- Profession vide applique la profession du profil ; sélectionner AS teste le critère.
  UPDATE public.filtres_sauvegardes SET filtres=CASE k WHEN 'profession' THEN criteria||'{"profession":"AS"}' WHEN 'rayonKm' THEN criteria||'{"rayonKm":1000}' ELSE criteria-k END WHERE id=f;
  n:=public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour');
  IF n<>(CASE k WHEN 'profession' THEN 1 WHEN 'horaire' THEN 4 ELSE 3 END) THEN RAISE EXCEPTION 'Critère soignant % ignoré, obtenu %',k,n; END IF;
 END LOOP;
 -- Profession vide = profil avec hiérarchie naturelle ; sélection explicite stricte.
 UPDATE public.soignants SET profession='IADE' WHERE id='69300000-0000-4000-8000-000000000101';
 UPDATE public.filtres_sauvegardes SET filtres=criteria||'{"profession":""}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>2 THEN RAISE EXCEPTION 'Hiérarchie IADE vers IDE perdue'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria||'{"profession":"IADE"}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Profession explicite élargie'; END IF;
 UPDATE public.soignants SET profession='IDE',types_contrat_acceptes='CDD' WHERE id='69300000-0000-4000-8000-000000000101';
 UPDATE public.filtres_sauvegardes SET filtres=criteria-'typeContrat' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>2 THEN RAISE EXCEPTION 'Compatibilité contrat du profil ignorée'; END IF;
 UPDATE public.soignants SET types_contrat_acceptes='["CDD","LIBERAL"]' WHERE id='69300000-0000-4000-8000-000000000101';
 FOR v IN SELECT value FROM jsonb_array_elements('[{"rayonKm":"oops"},{"tauxMin":-1},{"urgentesOnly":"true"},{"horaire":"AUTRE"},{"debut":"2026-09-25"},[]]') LOOP
  UPDATE public.filtres_sauvegardes SET filtres=v WHERE id=f;
  IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Critères soignant invalides élargis %',v; END IF;
 END LOOP;
 UPDATE public.filtres_sauvegardes SET filtres=criteria||'{"villeRecherche":"693"}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>3 THEN RAISE EXCEPTION 'Recherche code postal divergente'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria||'{"horaire":"NUIT"}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>1 THEN RAISE EXCEPTION 'Nuit 20h–7h non respectée'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria||'{"horaire":"WEEKEND"}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Jour ouvré classé week-end'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria||'{"horaire":"INCONNU"}' WHERE id=f;
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Horaire invalide élargi'; END IF;
 UPDATE public.filtres_sauvegardes SET filtres=criteria WHERE id=f;
 v:=public.fn_obtenir_apercu_filtre(f,now()-interval '1 hour',100);
 IF jsonb_array_length(v)<>2 OR NOT v @> '[{"id":"69300000-0000-4000-8000-000000000401"},{"id":"69300000-0000-4000-8000-000000000417"}]'::jsonb THEN RAISE EXCEPTION 'Aperçu mission hors critères %',v; END IF;
 UPDATE public.filtres_sauvegardes SET alerte_active=false WHERE id<>f;
 PERFORM * FROM public.fn_evaluer_alertes_filtres(NULL);
 SELECT email_id INTO q FROM private.alertes_filtres_livraisons WHERE filtre_id=f;
 IF q IS NULL OR NOT public.fn_verifier_livraison_alerte_filtre(q) THEN RAISE EXCEPTION 'Lot soignant non livrable'; END IF;
 IF (SELECT data->'missions' FROM public.email_queue WHERE id=q)<>v THEN RAISE EXCEPTION 'Aperçu et email mission divergent'; END IF;
 UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='69300000-0000-4000-8000-000000000101';
 IF public.fn_verifier_livraison_alerte_filtre(q) OR public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Destinataire soignant banni encore notifié'; END IF;
 UPDATE auth.users SET banned_until=NULL WHERE id='69300000-0000-4000-8000-000000000101';
END $missions$;
SET LOCAL session_replication_role=replica;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES('69300000-0000-4000-8000-000000000012','00000000-0000-0000-0000-000000000000','alerte-minimal@example.invalid','authenticated','authenticated','{}',now());
INSERT INTO public.parcours_inscription(user_id,type_compte,donnees,consentement_cgu_le)
VALUES('69300000-0000-4000-8000-000000000012','SOIGNANT','{"profession":"IDE"}',now());
UPDATE public.etablissements SET statut_verification='VERIFIE',peut_publier_missions=true WHERE id IN('69300000-0000-4000-8000-000000000004','69300000-0000-4000-8000-000000000011');
INSERT INTO public.filtres_sauvegardes(id,utilisateur_id,nom,audience,filtres,alerte_active,dernier_check_le)
VALUES('69300000-0000-4000-8000-000000000203','69300000-0000-4000-8000-000000000012','Alerte compte minimal','SOIGNANT_RECHERCHE_MISSIONS','{"profession":"IDE","rayonKm":25,"tauxMin":30,"typeContrat":"CDD","urgentesOnly":true,"horaire":"JOUR","villeRecherche":"Alerte Ville 693"}',true,now()-interval '1 hour');
SET LOCAL session_replication_role=origin;
DO $minimal$
DECLARE f uuid:='69300000-0000-4000-8000-000000000203'; a jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.soignants WHERE id='69300000-0000-4000-8000-000000000012') THEN RAISE EXCEPTION 'Le compte minimal possède déjà un profil'; END IF;
 a:=public.fn_obtenir_apercu_filtre(f,now()-interval '1 hour',100);
 IF jsonb_array_length(a)<>2 OR NOT a @> '[{"id":"69300000-0000-4000-8000-000000000401"},{"id":"69300000-0000-4000-8000-000000000417"}]'::jsonb THEN RAISE EXCEPTION 'Parcours minimal sans offres publiques exactes %',a; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(a) x WHERE public.fn_mission_publique((x->>'id')::uuid) IS NULL) THEN RAISE EXCEPTION 'Compte minimal reçoit une mission non publique'; END IF;
 UPDATE public.etablissements SET peut_publier_missions=false WHERE id='69300000-0000-4000-8000-000000000004';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>1 THEN RAISE EXCEPTION 'Droit public publication ignoré'; END IF;
 UPDATE public.etablissements SET peut_publier_missions=true WHERE id='69300000-0000-4000-8000-000000000004';
 DELETE FROM public.parcours_inscription WHERE user_id='69300000-0000-4000-8000-000000000012';
 IF public.fn_compter_nouveaux_pour_filtre(f,now()-interval '1 hour')<>0 THEN RAISE EXCEPTION 'Sans profil ni parcours encore notifié'; END IF;
END $minimal$;
-- Géométrie temporelle : bornes exactes, week-end et heure Paris pendant DST.
SET LOCAL session_replication_role=replica;
DO $horaires$
DECLARE v_id uuid:='69300000-0000-4000-8000-000000000401';
BEGIN
 UPDATE public.missions SET debut_le='2027-03-26 19:00+01',fin_le='2027-03-26 20:00+01' WHERE missions.id=v_id;
 IF private.fn_mission_correspond_horaire(v_id,'NUIT') OR NOT private.fn_mission_correspond_horaire(v_id,'JOUR') THEN RAISE EXCEPTION 'Fin à 20h classée nuit'; END IF;
 UPDATE public.missions SET debut_le='2027-03-26 20:00+01',fin_le='2027-03-27 07:00+01' WHERE missions.id=v_id;
 IF NOT private.fn_mission_correspond_horaire(v_id,'NUIT') OR NOT private.fn_mission_correspond_horaire(v_id,'WEEKEND') THEN RAISE EXCEPTION 'Vendredi nuit débordant samedi mal classé'; END IF;
 UPDATE public.missions SET debut_le='2027-03-28 00:00+01',fin_le='2027-03-28 07:00+02' WHERE missions.id=v_id;
 IF NOT private.fn_mission_correspond_horaire(v_id,'NUIT') OR NOT private.fn_mission_correspond_horaire(v_id,'WEEKEND') THEN RAISE EXCEPTION 'DST Paris mal classé'; END IF;
 UPDATE public.missions SET nb_creneaux=2 WHERE missions.id=v_id;
 IF private.fn_mission_correspond_horaire(v_id,'NUIT') THEN RAISE EXCEPTION 'Période multi-créneaux vide considérée planning exact'; END IF;
 INSERT INTO public.mission_creneaux(mission_id,debut,fin,type_creneau,est_pause,ordre) VALUES(v_id,'2027-03-29 10:00+02','2027-03-29 18:00+02','PREVISIONNEL',false,1),(v_id,'2027-03-30 10:00+02','2027-03-30 18:00+02','PREVISIONNEL',false,2),(v_id,'2027-03-29 22:00+02','2027-03-29 23:00+02','PREVISIONNEL',true,3);
 IF private.fn_mission_correspond_horaire(v_id,'NUIT') OR NOT private.fn_mission_correspond_horaire(v_id,'JOUR') THEN RAISE EXCEPTION 'Pause comptée dans les horaires travaillés'; END IF;
END $horaires$;
SET LOCAL session_replication_role=origin;
SELECT 'Dix critères, aperçu exact, cadence, déduplication, réessai et destinataires valides : OK' AS preuve;
ROLLBACK;
