-- PostgreSQL 17 LOCAL ISOLÉ UNIQUEMENT, jamais staging/production.
-- Préparation requise : schéma/migrations réels, rôles Auth, zéro donnée métier,
-- aucun worker ni sortie réseau ; base jolene_candidatures_pg17_test.
-- Le runner doit poser jolene.test_isolated=candidatures_multi_pg17 avant ce
-- fichier. Exemple : PGOPTIONS='-c jolene.test_isolated=candidatures_multi_pg17'
-- psql -X -v ON_ERROR_STOP=1 -d jolene_candidatures_pg17_test -f <ce fichier>.
-- Aucun helper produit remplacé, aucun trigger désactivé, aucun transport appelé.
-- Les claims sont ceux de vrais utilisateurs synthétiques sous SET ROLE ; cela
-- teste PostgreSQL/Auth/RLS, pas une signature JWT, PostgREST ou le frontend.
-- Tout reste dans cette transaction annulée. Un arrêt ON_ERROR_STOP ferme la
-- connexion du runner et annule également la transaction en cas d'échec.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout = '90s';
SET LOCAL lock_timeout = '5s';
SET LOCAL search_path = public, pg_catalog;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $preflight$
DECLARE existe boolean;
BEGIN
  IF current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
     OR current_database() <> 'jolene_candidatures_pg17_test'
     OR current_setting('jolene.test_isolated', true) IS DISTINCT FROM 'candidatures_multi_pg17'
     OR (inet_server_addr() IS NOT NULL AND inet_server_addr() NOT IN ('127.0.0.1'::inet, '::1'::inet))
     OR session_user NOT IN ('postgres', 'supabase_admin')
     OR current_user <> session_user OR auth.uid() IS NOT NULL OR public.est_admin()
  THEN RAISE EXCEPTION 'CAND_MULTI_CONTEXTE_PG17_LOCAL_ISOLE_REQUIS'; END IF;
  IF EXISTS (SELECT 1 FROM auth.users)
     OR EXISTS (SELECT 1 FROM public.soignants)
     OR EXISTS (SELECT 1 FROM public.etablissements)
     OR EXISTS (SELECT 1 FROM public.missions)
     OR EXISTS (SELECT 1 FROM public.externalisation_actions)
  THEN RAISE EXCEPTION 'CAND_MULTI_BASE_SYNTHETIQUE_VIDE_REQUISE'; END IF;
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM cron.job WHERE active)' INTO existe;
    IF existe THEN RAISE EXCEPTION 'CAND_MULTI_CRON_ACTIF_INTERDIT'; END IF;
  END IF;
  IF to_regclass('net.http_request_queue') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM net.http_request_queue)' INTO existe;
    IF existe THEN RAISE EXCEPTION 'CAND_MULTI_FILE_HTTP_NON_VIDE'; END IF;
  END IF;
  -- Comme dans push-candidatures.test.sql, une nouvelle mécanique Auth doit
  -- être instruite, jamais contournée en désactivant le trigger pour le seed.
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
      AND NOT tgisinternal AND tgenabled<>'D' AND (tgtype::integer & 4)<>0)
  THEN RAISE EXCEPTION 'CAND_MULTI_AUTH_INSERT_INATTENDU'; END IF;
  IF to_regprocedure('public.fn_lire_candidatures_mission_habilitee(uuid)') IS NULL
  THEN RAISE EXCEPTION 'CAND_MULTI_MIGRATION_MANQUANTE'; END IF;
END;
$preflight$;

CREATE FUNCTION pg_temp.cand_id(n integer) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $id$
 SELECT ('71220000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid
$id$;

-- Empreintes des vrais helpers, communes aux catalogues LIVE staging/production
-- du 02/10/2026 06:09 UTC. Refus fermé si le runner importe une approximation.
CREATE TEMP TABLE cand_helpers(signature text PRIMARY KEY, corps_md5 text NOT NULL);
INSERT INTO cand_helpers VALUES
 ('auth.uid()', 'cdef18c69c4f4cbbced2eaf81e628b49'),
 ('private.fn_comptes_meme_cohorte_test(uuid,uuid)', '8dbe1d6bdcf7b10bb3a2662f67475196'),
 ('public.est_admin()', 'ef86d65809c3f76a1ac08eb737796fad'),
 ('public.fn_compte_auth_actif()', '8246c4c1f1b0a8053adb176a06c96766'),
 ('public.fn_get_my_role()', '2e2e76abde5789de4e5f2b28facbc0fd'),
 ('public.fn_role_etablissement_courant(uuid)', 'ceb4e333f4b7f69a3be422b9753b559a'),
 ('public.fn_a_permission_etablissement(text,uuid)', '1ee98c0e7094db4e98277b85ce71c6ec'),
 ('public.mon_etablissement_id()', 'dc3ef839d2920fb33cf6d7b320842c10');
DO $catalogue$
DECLARE v_rpc pg_proc%ROWTYPE;
BEGIN
  IF EXISTS (SELECT 1 FROM cand_helpers h LEFT JOIN pg_proc p
      ON p.oid=to_regprocedure(h.signature) WHERE md5(p.prosrc) IS DISTINCT FROM h.corps_md5)
  THEN RAISE EXCEPTION 'CAND_MULTI_HELPER_LIVE_DIFFERENT'; END IF;
  SELECT * INTO STRICT v_rpc FROM pg_proc
  WHERE oid='public.fn_lire_candidatures_mission_habilitee(uuid)'::regprocedure;
  IF NOT v_rpc.prosecdef OR v_rpc.provolatile <> 's'
     OR pg_get_userbyid(v_rpc.proowner) <> 'postgres'
     OR v_rpc.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
     OR v_rpc.prorettype <> 'jsonb'::regtype
  THEN RAISE EXCEPTION 'CAND_MULTI_RPC_CONFIGURATION'; END IF;
  IF has_function_privilege('anon', v_rpc.oid, 'EXECUTE')
     OR has_function_privilege('service_role', v_rpc.oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_rpc.oid, 'EXECUTE')
     OR EXISTS (SELECT 1 FROM aclexplode(COALESCE(v_rpc.proacl,acldefault('f',v_rpc.proowner))) a
       WHERE a.grantee=0 AND a.privilege_type='EXECUTE')
  THEN RAISE EXCEPTION 'CAND_MULTI_ACL'; END IF;
  IF NOT EXISTS (SELECT 1 FROM private.security_definer_inventory i
      WHERE i.signature='fn_lire_candidatures_mission_habilitee(uuid)'
        AND i.categorie='RPC_UTILISATEUR_AUTH_INTERNE'
        AND i.definition_md5=md5(v_rpc.prosrc) AND length(btrim(i.justification))>0)
  THEN RAISE EXCEPTION 'CAND_MULTI_INVENTAIRE_MD5_PROSRC'; END IF;
END;
$catalogue$;

-- Snapshot catalogue : les lectures et fixtures ne doivent pas changer les
-- définitions, ACL ou policies. Le contrat LIVE de lecture est vérifié plus bas.
CREATE TEMP TABLE cand_policies_avant AS
 SELECT p.polrelid,p.polname,to_jsonb(p)-'oid' AS definition FROM pg_policy p
 WHERE p.polrelid IN ('public.missions'::regclass,'public.candidatures'::regclass,
   'public.mission_creneaux'::regclass,'public.soignants'::regclass,
   'public.etablissements'::regclass,'public.membres_etablissement'::regclass);
CREATE TEMP TABLE cand_catalogue_avant AS
 SELECT p.oid,md5(pg_get_functiondef(p.oid)) AS definition,p.proacl,p.proconfig
 FROM pg_proc p WHERE p.oid IN (SELECT to_regprocedure(signature) FROM cand_helpers)
 OR p.oid='public.fn_lire_candidatures_mission_habilitee(uuid)'::regprocedure;
CREATE TEMP TABLE cand_rls_live(table_nom text, policy_nom text, preuve jsonb);

INSERT INTO cand_rls_live VALUES
 ('candidatures','pol_cand_select','{"roles": ["authenticated"], "using": "soignant_id = (( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin) OR (EXISTS ( SELECT 1\n   FROM missions m\n  WHERE m.id = candidatures.mission_id AND m.etablissement_id = (( SELECT mon_etablissement_id() AS mon_etablissement_id)) AND ( SELECT fn_a_permission_etablissement(''lecture_candidatures''::text, m.etablissement_id) AS fn_a_permission_etablissement)))", "commande": "r", "permissive": true, "with_check": null}'::jsonb),
 ('candidatures','pol_compte_auth_actif_restrictive','{"roles": ["authenticated"], "using": "( SELECT fn_compte_auth_actif() AS fn_compte_auth_actif)", "commande": "*", "permissive": false, "with_check": "( SELECT fn_compte_auth_actif() AS fn_compte_auth_actif)"}'::jsonb),
 ('missions','missions_masquer_etabs_test','{"roles": ["authenticated"], "using": "NOT ( SELECT est_soignant() AS est_soignant) OR private.fn_comptes_meme_cohorte_test(( SELECT auth.uid() AS uid), etablissement_id)", "commande": "r", "permissive": false, "with_check": null}'::jsonb),
 ('missions','pol_compte_auth_actif_restrictive','{"roles": ["authenticated"], "using": "( SELECT fn_compte_auth_actif() AS fn_compte_auth_actif)", "commande": "*", "permissive": false, "with_check": "( SELECT fn_compte_auth_actif() AS fn_compte_auth_actif)"}'::jsonb),
 ('missions','pol_mission_select','{"roles": ["authenticated"], "using": "( SELECT est_admin() AS est_admin) OR etablissement_id = (( SELECT mon_etablissement_id() AS mon_etablissement_id)) AND ( SELECT fn_a_permission_etablissement(''lecture_missions''::text, missions.etablissement_id) AS fn_a_permission_etablissement) OR soignant_assigne_id = (( SELECT auth.uid() AS uid)) OR ( SELECT est_soignant() AS est_soignant) AND statut = ''OUVERTE''::statut_mission AND NOT fn_est_exclu(( SELECT auth.uid() AS uid), etablissement_id)", "commande": "r", "permissive": true, "with_check": null}'::jsonb);

DO $rls_live$
BEGIN
  IF EXISTS (SELECT 1 FROM cand_rls_live e LEFT JOIN pg_policy p
      ON p.polrelid=to_regclass('public.'||e.table_nom) AND p.polname=e.policy_nom
    WHERE jsonb_build_object('roles',(SELECT jsonb_agg(CASE WHEN r=0 THEN 'PUBLIC'
        ELSE pg_get_userbyid(r) END ORDER BY r) FROM unnest(p.polroles) r),
      'using',pg_get_expr(p.polqual,p.polrelid,true),'commande',p.polcmd,
      'permissive',p.polpermissive,'with_check',pg_get_expr(p.polwithcheck,p.polrelid,true))
      IS DISTINCT FROM e.preuve)
    OR EXISTS (SELECT 1 FROM pg_policy p
      WHERE p.polrelid IN ('public.missions'::regclass,'public.candidatures'::regclass)
        AND p.polcmd IN ('r','*') AND NOT EXISTS (SELECT 1 FROM cand_rls_live e
          WHERE p.polrelid=to_regclass('public.'||e.table_nom) AND p.polname=e.policy_nom))
    OR EXISTS (SELECT 1 FROM pg_class WHERE oid IN ('public.missions'::regclass,
      'public.candidatures'::regclass) AND (NOT relrowsecurity OR NOT relforcerowsecurity))
  THEN RAISE EXCEPTION 'CAND_MULTI_RLS_LECTURE_LIVE_MODIFIEE'; END IF;
END;
$rls_live$;

-- Les établissements A=1, B=2, C=3 et supprimés=18/24 sont tous TEST.
-- Acteurs 6/7/8 : vrais ADMIN_GROUPE. 4/5 : RH A+B insérés en ordre inverse.
-- Le témoin 43 est synthétique mais de cohorte opposée (false) pour prouver le
-- filtre ; aucune donnée existante n'est déclassée. Aucun appareil/token créé.
UPDATE public.parametres_systeme SET valeur=1 WHERE cle='inscriptions_publiques_actives';
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,raw_user_meta_data,
 email_confirmed_at,banned_until,deleted_at)
SELECT pg_temp.cand_id(n),'00000000-0000-0000-0000-000000000000',
 'cand-multi-'||n||'@example.invalid','authenticated','authenticated',
 jsonb_build_object('role',CASE WHEN n IN (6,7,8) THEN 'ADMIN_GROUPE'
    WHEN n IN (21,40,41,42,43) THEN 'SOIGNANT' ELSE 'ADMIN_ETABLISSEMENT' END,
   'etablissement_id',pg_temp.cand_id(CASE WHEN n=1 THEN 1 ELSE 2 END),
   'est_compte_test',n<>43,'is_test_playwright',n<>43),
 CASE WHEN n=21 THEN jsonb_build_object('role','ADMIN_ETABLISSEMENT','etablissement_id',pg_temp.cand_id(2)) ELSE '{}'::jsonb END,
 CASE WHEN n<>14 THEN now() END,CASE WHEN n=12 THEN now()+interval '1 day' END,
 CASE WHEN n=13 THEN now() END
FROM unnest(ARRAY[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,18,19,20,21,23,24,40,41,42,43]) n;
INSERT INTO public.groupes_sante(id,nom,email_admin)
VALUES (pg_temp.cand_id(90),'Groupe synthétique A+B','groupe-cand-multi@example.invalid');
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,
 adresse_code_postal,email_contact,est_compte_test,groupe_sante_id,source_acquisition,
 code_parrainage,sms_actif,chorus_pro_actif,est_secteur_public,supprime_le)
SELECT pg_temp.cand_id(n),'Établissement synthétique '||n,'7122000000'||lpad(n::text,4,'0'),
 'CLINIQUE_PRIVEE','Adresse fictive','Paris','75001','cand-multi-'||n||'@example.invalid',
 true,CASE WHEN n IN (1,2) THEN pg_temp.cand_id(90) END,'RECETTE_CAND_MULTI_SQL',
 'CANDMULTIE'||n,false,false,false,CASE WHEN n IN (18,24) THEN now() END
FROM unnest(ARRAY[1,2,3,18,24]) n;
INSERT INTO public.admins_groupe_sante(groupe_id,utilisateur_id,role)
SELECT pg_temp.cand_id(90),pg_temp.cand_id(n),'ADMINISTRATEUR' FROM unnest(ARRAY[6,7,8]) n;
INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
SELECT pg_temp.cand_id(etab),pg_temp.cand_id(acteur),role,actif
FROM (VALUES
 (1,1,'PROPRIETAIRE',true),(2,1,'RH',true),(3,3,'PROPRIETAIRE',true),
 (1,4,'RH',true),(2,4,'RH',true),(2,5,'RH',true),(1,5,'RH',true),
 (2,6,'ADMIN_GROUPE',true),(1,7,'ADMIN_GROUPE',true),(2,8,'RH',true),
 (2,9,'RH',false),(2,10,'LECTURE_SEULE',true),(2,11,'POINTAGE_ONLY',true),
 (2,12,'RH',true),(2,13,'RH',true),(2,14,'RH',true),
 (2,18,'RH',true),(2,19,'PROPRIETAIRE',true),(2,20,'RH',true)
) v(etab,acteur,role,actif);
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,date_naissance,
 est_compte_test,source_acquisition,code_parrainage,sms_actif,sms_alertes_actives,defacto_opt_in,
 supprime_le,score_fiabilite,total_missions_terminees,note_moyenne,nb_evaluations,telephone)
SELECT pg_temp.cand_id(n),'Camille'||n,'NomPrive'||n,'cand-multi-'||n||'@example.invalid',
 'IDE','SALARIE','1990-01-01',n<>43,'RECETTE_CAND_MULTI_SQL','CANDMULTIS'||n,false,false,false,
 CASE WHEN n=42 THEN now() END,CASE WHEN n=40 THEN 84 ELSE 70 END,
 CASE WHEN n=40 THEN 12 ELSE 0 END,CASE WHEN n=40 THEN 4.6 END,
 CASE WHEN n=40 THEN 5 ELSE 0 END,'0100000040'
FROM unnest(ARRAY[21,40,41,42,43]) n;
DO $famille_soignant$
BEGIN
 BEGIN
   INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
   VALUES(pg_temp.cand_id(2),pg_temp.cand_id(21),'RH',true);
   RAISE EXCEPTION 'CAND_MULTI_FAMILLE_SOIGNANT_ADHESION_ACCEPTEE';
 EXCEPTION WHEN check_violation THEN
   IF SQLERRM IS DISTINCT FROM 'Ce compte appartient deja a un espace incompatible'
   THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM public.membres_etablissement WHERE user_id=pg_temp.cand_id(21))
 THEN RAISE EXCEPTION 'CAND_MULTI_FAMILLE_SOIGNANT_ROLLBACK_PARTIEL'; END IF;
END;
$famille_soignant$;
INSERT INTO public.preferences_notifications(utilisateur_id,canal_email,canal_sms,canal_push,canal_in_app)
SELECT id,false,false,false,false FROM auth.users
ON CONFLICT(utilisateur_id) DO UPDATE SET canal_email=false,canal_sms=false,canal_push=false,canal_in_app=false;
INSERT INTO public.missions(id,etablissement_id,intitule,profession_requise,debut_le,fin_le,
 duree_heures,taux_horaire_base,statut,type_contrat_recherche,mode_attribution,est_urgente)
SELECT pg_temp.cand_id(n),pg_temp.cand_id(CASE n WHEN 101 THEN 1 WHEN 103 THEN 3 WHEN 104 THEN 24 ELSE 2 END),
 'Mission synthétique '||n,'IDE',current_date+interval '10 days 09 hours',
 current_date+interval '10 days 13 hours',4,20,'OUVERTE','SALARIE','CANDIDATURE',false
FROM generate_series(101,105) n;
-- Le trigger réel a créé le créneau initial. Ajouter ensuite les témoins de
-- tri, pause et effectif AVANT les candidatures (planning verrouillé ensuite).
INSERT INTO public.mission_creneaux(id,mission_id,debut,fin,est_pause,type_pause,type_creneau,ordre)
VALUES
 (pg_temp.cand_id(302),pg_temp.cand_id(102),current_date+interval '12 days 09 hours',current_date+interval '12 days 13 hours',false,NULL,'PREVISIONNEL',3),
 (pg_temp.cand_id(301),pg_temp.cand_id(102),current_date+interval '11 days 09 hours',current_date+interval '11 days 13 hours',false,NULL,'PREVISIONNEL',2),
 (pg_temp.cand_id(303),pg_temp.cand_id(102),current_date+interval '10 days 13 hours',current_date+interval '10 days 14 hours',true,'PAUSE','PREVISIONNEL',4),
 (pg_temp.cand_id(304),pg_temp.cand_id(102),current_date+interval '10 days 09 hours',current_date+interval '10 days 12 hours',false,NULL,'EFFECTIF',1);
-- Une adhésion active de famille SOIGNANT est interdite par le trigger réel
-- fn_protect_famille_compte_membre_etablissement : aucun faux positif SOIGNANT+RH
-- n’est fabriqué ici en neutralisant cette protection. Le soignant tiers 21
-- est testé en refus ; le rôle groupe est créé sans contourner ce trigger.
-- Seed administratif direct : ce test vise la lecture, pas fn_postuler_mission
-- ni l'enqueue. Les vrais triggers d'intégrité s'exécutent avec UID système.
INSERT INTO public.candidatures(id,mission_id,soignant_id,message,statut,type_contrat_choisi,cree_le,motif_refus)
VALUES
 (pg_temp.cand_id(201),pg_temp.cand_id(102),pg_temp.cand_id(41),'Candidature B première','EN_ATTENTE','SALARIE',now()-interval '2 hours','Motif privé non projeté'),
 (pg_temp.cand_id(202),pg_temp.cand_id(102),pg_temp.cand_id(40),'Candidature B seconde','EN_ATTENTE','SALARIE',now()-interval '1 hour',NULL),
 (pg_temp.cand_id(203),pg_temp.cand_id(102),pg_temp.cand_id(42),'Candidat supprimé exclu','REFUSEE','SALARIE',now()-interval '3 hours',NULL),
 (pg_temp.cand_id(204),pg_temp.cand_id(102),pg_temp.cand_id(43),'Autre cohorte exclue','REFUSEE','SALARIE',now()-interval '4 hours',NULL),
 (pg_temp.cand_id(205),pg_temp.cand_id(101),pg_temp.cand_id(40),'Candidature A','EN_ATTENTE','SALARIE',now(),NULL),
 (pg_temp.cand_id(206),pg_temp.cand_id(103),pg_temp.cand_id(40),'Candidature C privée','EN_ATTENTE','SALARIE',now(),NULL);

DO $fixtures$
BEGIN
 IF (SELECT count(*) FROM public.etablissements WHERE est_compte_test IS TRUE)<>5
   OR (SELECT count(*) FROM public.soignants WHERE est_compte_test IS FALSE)<>1
   OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=pg_temp.cand_id(43) AND est_compte_test IS FALSE)
   OR private.fn_comptes_meme_cohorte_test(pg_temp.cand_id(43),pg_temp.cand_id(2)) IS DISTINCT FROM false
   OR private.fn_comptes_meme_cohorte_test(pg_temp.cand_id(40),pg_temp.cand_id(2)) IS DISTINCT FROM true
   OR (SELECT count(*) FROM public.mission_creneaux WHERE mission_id=pg_temp.cand_id(102)
       AND type_creneau='PREVISIONNEL' AND NOT est_pause)<>3
   OR (SELECT nb_creneaux FROM public.missions WHERE id=pg_temp.cand_id(102))<>3
   OR (SELECT jsonb_build_array(score_fiabilite,total_missions_terminees,note_moyenne,nb_evaluations)
       FROM public.soignants WHERE id=pg_temp.cand_id(40)) IS DISTINCT FROM '[84,12,4.6,5]'::jsonb
 THEN RAISE EXCEPTION 'CAND_MULTI_FIXTURES_NON_DISCRIMINANTES'; END IF;
END;
$fixtures$;

-- Comparaison exacte à la projection autorisée, sans SELECT * ni nom complet.
CREATE TEMP TABLE cand_attendus(mission_id uuid PRIMARY KEY,resultat jsonb);
INSERT INTO cand_attendus
SELECT m.id,jsonb_build_object('mission',jsonb_build_object('id',m.id,'intitule',m.intitule,
 'etablissement_id',m.etablissement_id,'etablissement_nom',e.nom,'statut',m.statut,
 'mode_attribution',m.mode_attribution,'nb_creneaux',m.nb_creneaux,'profession_requise',m.profession_requise,
 'specialite_medicale_requise',m.specialite_medicale_requise),
 'creneaux',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',mc.id,'mission_id',mc.mission_id,
   'debut',mc.debut,'fin',mc.fin,'est_pause',false,'type_creneau','PREVISIONNEL') ORDER BY mc.debut,mc.id)
   FROM public.mission_creneaux mc WHERE mc.mission_id=m.id AND NOT mc.est_pause
   AND mc.type_creneau='PREVISIONNEL'),'[]'::jsonb),
 'candidatures',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'soignant_id',c.soignant_id,
   'message',c.message,'statut',c.statut,'cree_le',c.cree_le,'soignant',
   jsonb_build_object('id',s.id,'prenom',s.prenom,'nom','N.','nom_anonymise',true,
     'profession',s.profession,'specialite_medicale',s.specialite_medicale,'type_exercice',s.type_exercice,
     'est_etudiant',s.est_etudiant,'score_fiabilite',s.score_fiabilite,'total_missions_terminees',s.total_missions_terminees,
     'note_moyenne',s.note_moyenne,'nb_evaluations',s.nb_evaluations,'etudiant_details',s.etudiant_details,
     'tous_documents_valides',s.tous_documents_valides)) ORDER BY c.cree_le,c.id)
   FROM public.candidatures c JOIN public.soignants s ON s.id=c.soignant_id
   WHERE c.mission_id=m.id AND c.id IN (pg_temp.cand_id(201),pg_temp.cand_id(202),pg_temp.cand_id(205),pg_temp.cand_id(206))),
   '[]'::jsonb)) FROM public.missions m JOIN public.etablissements e ON e.id=m.etablissement_id;
CREATE TEMP TABLE cand_claims AS
 SELECT id,jsonb_build_object('role','authenticated','sub',id,'app_metadata',raw_app_meta_data,
   'user_metadata',raw_user_meta_data) AS claims FROM auth.users;
INSERT INTO cand_claims VALUES(pg_temp.cand_id(16),jsonb_build_object('role','authenticated','sub',pg_temp.cand_id(16)));
CREATE TEMP TABLE cand_resultats(scenario text PRIMARY KEY,verdict text NOT NULL);
CREATE TEMP TABLE cand_membres_avant AS SELECT id,to_jsonb(m) AS ligne FROM public.membres_etablissement m;
CREATE TEMP TABLE cand_donnees_avant AS
 SELECT 'missions' AS table_nom,id,to_jsonb(m) AS ligne FROM public.missions m
 UNION ALL SELECT 'candidatures',id,to_jsonb(c) FROM public.candidatures c
 UNION ALL SELECT 'creneaux',id,to_jsonb(c) FROM public.mission_creneaux c;
GRANT SELECT ON cand_claims,cand_attendus TO authenticated;
GRANT INSERT ON cand_resultats TO authenticated;

CREATE FUNCTION pg_temp.cand_acteur(n integer) RETURNS void LANGUAGE plpgsql AS $acteur$
DECLARE claims jsonb;
BEGIN
 SELECT c.claims INTO STRICT claims FROM pg_temp.cand_claims c WHERE id=pg_temp.cand_id(n);
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claims',claims::text,true);
 IF current_user<>'authenticated' OR auth.uid() IS DISTINCT FROM pg_temp.cand_id(n)
 THEN RAISE EXCEPTION 'CAND_MULTI_ACTEUR_REEL_ABSENT'; END IF;
END;
$acteur$;

CREATE FUNCTION pg_temp.cand_verifier(scenario text,n integer,cible integer,autorise boolean)
RETURNS void LANGUAGE plpgsql AS $verifier$
DECLARE r jsonb; attendu jsonb; scope_avant uuid; refuse boolean:=false;
BEGIN
 PERFORM pg_temp.cand_acteur(n);
 scope_avant:=public.mon_etablissement_id();
 BEGIN
   r:=public.fn_lire_candidatures_mission_habilitee(pg_temp.cand_id(cible));
 EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM IS DISTINCT FROM 'Mission indisponible ou accès refusé' THEN RAISE; END IF;
   refuse:=true;
 END;
 IF autorise THEN
   SELECT resultat INTO STRICT attendu FROM pg_temp.cand_attendus WHERE mission_id=pg_temp.cand_id(cible);
   IF refuse OR r IS DISTINCT FROM attendu THEN
     RAISE EXCEPTION 'CAND_MULTI_PROJECTION_OU_ACCES: %',scenario;
   END IF;
 ELSE
   IF NOT refuse OR r IS NOT NULL THEN RAISE EXCEPTION 'CAND_MULTI_REFUS_NON_UNIFORME: %',scenario; END IF;
 END IF;
 IF public.mon_etablissement_id() IS DISTINCT FROM scope_avant
 THEN RAISE EXCEPTION 'CAND_MULTI_SCOPE_GLOBAL_MODIFIE: %',scenario; END IF;
 INSERT INTO pg_temp.cand_resultats VALUES(scenario,CASE WHEN autorise THEN 'LECTURE_EXACTE' ELSE '42501_UNIFORME' END);
END;
$verifier$;

SET LOCAL ROLE authenticated;
DO $parcours$
DECLARE n integer; cible integer; r jsonb;
BEGIN
 PERFORM pg_temp.cand_acteur(1);
 IF public.mon_etablissement_id() IS DISTINCT FROM pg_temp.cand_id(1)
   OR EXISTS(SELECT 1 FROM public.missions WHERE id=pg_temp.cand_id(102))
   OR EXISTS(SELECT 1 FROM public.candidatures WHERE mission_id=pg_temp.cand_id(102))
 THEN RAISE EXCEPTION 'CAND_MULTI_SECONDAIRE_DEJA_ETENDU_PAR_RLS'; END IF;
 PERFORM pg_temp.cand_verifier('proprietaire_A_lit_B',1,102,true);
 PERFORM pg_temp.cand_verifier('proprietaire_A_lit_A',1,101,true);
 PERFORM pg_temp.cand_verifier('relecture_B',1,102,true);
 FOREACH n IN ARRAY ARRAY[4,5] LOOP
   PERFORM pg_temp.cand_verifier('RH_ordre_'||n||'_A',n,101,true);
   PERFORM pg_temp.cand_verifier('RH_ordre_'||n||'_B',n,102,true);
 END LOOP;
 FOREACH n IN ARRAY ARRAY[6,7,8] LOOP
   PERFORM pg_temp.cand_acteur(n);
   IF public.fn_get_my_role()->>'role' IS DISTINCT FROM 'ADMIN_GROUPE'
     OR auth.jwt()->'app_metadata'->>'role' IS DISTINCT FROM 'ADMIN_GROUPE'
   THEN RAISE EXCEPTION 'CAND_MULTI_FAUX_ROLE_GROUPE: %',n; END IF;
   PERFORM pg_temp.cand_verifier('vrai_groupe_'||n||'_B',n,102,n<>7);
 END LOOP;
 FOREACH n IN ARRAY ARRAY[2,19,20] LOOP
   PERFORM pg_temp.cand_verifier('habilite_'||n||'_B',n,102,true);
 END LOOP;
 PERFORM pg_temp.cand_verifier('B_sans_candidature',1,105,true);
 -- Lecture canonique LECTURE_SEULE conservée, aucune permission de traitement.
 PERFORM pg_temp.cand_acteur(10);
 IF NOT EXISTS(SELECT 1 FROM public.missions WHERE id=pg_temp.cand_id(102))
   OR NOT EXISTS(SELECT 1 FROM public.candidatures WHERE id=pg_temp.cand_id(201))
 THEN RAISE EXCEPTION 'CAND_MULTI_LECTURE_SEULE_CANONIQUE_REGRESSE'; END IF;
 FOREACH n IN ARRAY ARRAY[9,10,11,12,13,14,15,16,18,21,23] LOOP
   PERFORM pg_temp.cand_verifier('refus_acteur_'||n,n,102,false);
 END LOOP;
 -- Tiers C, UUID inexistant, NULL et établissement supprimé : même refus.
 FOREACH n IN ARRAY ARRAY[1,4,5,6,7,8,19,20] LOOP
   FOREACH cible IN ARRAY ARRAY[103,999,104,NULL::integer] LOOP
     PERFORM pg_temp.cand_verifier('refus_cible_'||n||'_'||COALESCE(cible::text,'NULL'),n,cible,false);
   END LOOP;
 END LOOP;
 PERFORM pg_temp.cand_verifier('proprietaire_C_lit_C',3,103,true);
 PERFORM pg_temp.cand_verifier('proprietaire_C_refuse_B',3,102,false);
 -- Authenticated sans identité n'est ni un propriétaire ni un compte actif.
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 BEGIN
   PERFORM public.fn_lire_candidatures_mission_habilitee(pg_temp.cand_id(102));
   RAISE EXCEPTION 'CAND_MULTI_SANS_IDENTITE_ACCEPTE';
 EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM IS DISTINCT FROM 'Mission indisponible ou accès refusé' THEN RAISE; END IF;
 END;
 INSERT INTO pg_temp.cand_resultats VALUES('authenticated_sans_identite','42501_UNIFORME');
END;
$parcours$;
RESET ROLE;

-- Révocation après une lecture réussie, puis rétrogradation : le même jeton
-- ancien doit être refusé, les autres membres conservent leur habilitation.
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SAVEPOINT droits_tardifs;
UPDATE public.membres_etablissement SET actif=false
WHERE user_id=pg_temp.cand_id(1) AND etablissement_id=pg_temp.cand_id(2);
SET LOCAL ROLE authenticated;
SELECT pg_temp.cand_verifier('revoque_apres_lecture',1,102,false);
SELECT pg_temp.cand_verifier('autre_RH_apres_revocation',4,102,true);
SELECT pg_temp.cand_verifier('groupe_apres_revocation',6,102,true);
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
UPDATE public.membres_etablissement SET actif=true,role='LECTURE_SEULE'
WHERE user_id=pg_temp.cand_id(1) AND etablissement_id=pg_temp.cand_id(2);
SET LOCAL ROLE authenticated;
SELECT pg_temp.cand_verifier('retrograde_apres_lecture',1,102,false);
SELECT pg_temp.cand_verifier('autre_RH_apres_retrogradation',5,102,true);
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
-- Le helper historique connaît encore l'UUID propriétaire B ; l'adhésion
-- explicitement révoquée doit toutefois bloquer le nouveau lecteur.
INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
VALUES(pg_temp.cand_id(2),pg_temp.cand_id(2),'PROPRIETAIRE',false);
SET LOCAL ROLE authenticated;
SELECT pg_temp.cand_verifier('proprietaire_historique_revoque',2,102,false);
RESET ROLE;
-- Assertions enregistrées avant rollback du sous-scénario, sans leur résultat
-- client : seuls leurs noms/verdicts sont conservés par le log du runner.
SELECT scenario,verdict FROM cand_resultats WHERE scenario IN (
 'revoque_apres_lecture','autre_RH_apres_revocation','groupe_apres_revocation',
 'retrograde_apres_lecture','autre_RH_apres_retrogradation','proprietaire_historique_revoque') ORDER BY scenario;
ROLLBACK TO SAVEPOINT droits_tardifs;

-- Exercice de l'ACL réelle, avec l'UID d'un acteur autorisé : la négation ne
-- peut pas être un faux positif dû à l'absence d'identité ou à la garde métier.
SELECT set_config('request.jwt.claims',jsonb_build_object('role','anon','sub',pg_temp.cand_id(1))::text,true);
SET LOCAL ROLE anon;
DO $anon$
BEGIN
 BEGIN
   PERFORM public.fn_lire_candidatures_mission_habilitee('71220000-0000-4000-8000-000000000102');
   RAISE EXCEPTION 'CAND_MULTI_ANON_EXECUTE_ACCEPTE';
 EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM = 'Mission indisponible ou accès refusé' THEN
     RAISE EXCEPTION 'CAND_MULTI_ANON_ATTEINT_LE_CORPS'; END IF;
 END;
END;
$anon$;
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('role','service_role','sub',pg_temp.cand_id(1))::text,true);
SET LOCAL ROLE service_role;
DO $service$
BEGIN
 BEGIN
   PERFORM public.fn_lire_candidatures_mission_habilitee('71220000-0000-4000-8000-000000000102');
   RAISE EXCEPTION 'CAND_MULTI_SERVICE_EXECUTE_ACCEPTE';
 EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM = 'Mission indisponible ou accès refusé' THEN
     RAISE EXCEPTION 'CAND_MULTI_SERVICE_ATTEINT_LE_CORPS'; END IF;
 END;
END;
$service$;
RESET ROLE;

DO $invariants_finaux$
DECLARE existe boolean;
BEGIN
 IF EXISTS ((SELECT id,to_jsonb(m) FROM public.membres_etablissement m
     EXCEPT SELECT id,ligne FROM cand_membres_avant)
     UNION ALL (SELECT id,ligne FROM cand_membres_avant
       EXCEPT SELECT id,to_jsonb(m) FROM public.membres_etablissement m))
 THEN RAISE EXCEPTION 'CAND_MULTI_MEMBRES_MODIFIES'; END IF;
 IF EXISTS (SELECT 1 FROM cand_donnees_avant d LEFT JOIN (
     SELECT 'missions' AS table_nom,id,to_jsonb(m) AS ligne FROM public.missions m
     UNION ALL SELECT 'candidatures',id,to_jsonb(c) FROM public.candidatures c
     UNION ALL SELECT 'creneaux',id,to_jsonb(c) FROM public.mission_creneaux c
   ) a USING(table_nom,id) WHERE d.ligne IS DISTINCT FROM a.ligne)
 THEN RAISE EXCEPTION 'CAND_MULTI_LECTURE_A_MODIFIE_DONNEES'; END IF;
 IF EXISTS ((SELECT p.polrelid,p.polname,to_jsonb(p)-'oid' FROM pg_policy p
     WHERE p.polrelid IN (SELECT polrelid FROM cand_policies_avant)
     EXCEPT SELECT * FROM cand_policies_avant)
     UNION ALL (SELECT * FROM cand_policies_avant EXCEPT
       SELECT p.polrelid,p.polname,to_jsonb(p)-'oid' FROM pg_policy p
       WHERE p.polrelid IN (SELECT polrelid FROM cand_policies_avant)))
 THEN RAISE EXCEPTION 'CAND_MULTI_POLICY_MODIFIEE'; END IF;
 IF EXISTS (SELECT 1 FROM cand_catalogue_avant a LEFT JOIN pg_proc p USING(oid)
     WHERE md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM a.definition
       OR p.proacl IS DISTINCT FROM a.proacl OR p.proconfig IS DISTINCT FROM a.proconfig)
 THEN RAISE EXCEPTION 'CAND_MULTI_HELPER_OU_RPC_MODIFIE'; END IF;
 IF EXISTS(SELECT 1 FROM public.externalisation_actions)
 THEN RAISE EXCEPTION 'CAND_MULTI_EXTERNALISATION_INTERDITE'; END IF;
 IF to_regclass('net.http_request_queue') IS NOT NULL THEN
   EXECUTE 'SELECT EXISTS (SELECT 1 FROM net.http_request_queue)' INTO existe;
   IF existe THEN RAISE EXCEPTION 'CAND_MULTI_HTTP_INTERDIT'; END IF;
 END IF;
END;
$invariants_finaux$;
SELECT scenario,verdict FROM cand_resultats ORDER BY scenario;
SELECT 'Adhésion SOIGNANT rejetée 23514 ; ACL anon/service_role refusée, authenticated exercée ; inventaire md5(prosrc), policies et données inchangés' AS assertions_catalogue;
ROLLBACK;
