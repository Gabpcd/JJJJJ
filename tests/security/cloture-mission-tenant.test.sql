-- Vraies fixtures, vrais helpers d'identité/tenant et vraie RPC. Aucun trigger
-- désactivé, aucune fonction remplacée. Les files restent dans le ROLLBACK.
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

INSERT INTO auth.users(id, instance_id, email, role, aud, raw_app_meta_data, email_confirmed_at, banned_until, deleted_at)
SELECT ('9c100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000'::uuid,
 'cloture-tenant-' || n || '@example.invalid', 'authenticated', 'authenticated',
 jsonb_build_object('role', CASE WHEN n IN (1,2) THEN 'SOIGNANT'
   WHEN n IN (10,11,13) THEN 'ADMIN_PLATEFORME' ELSE 'ADMIN_ETABLISSEMENT' END,
   'is_test_playwright', true), now(),
 CASE WHEN n IN (9,13) THEN now()+interval '1 day' END,
 CASE WHEN n=12 THEN now() END
FROM generate_series(1,14) n;

INSERT INTO public.soignants(id, prenom, nom, email, profession, est_compte_test)
SELECT ('9c100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'Fixture', 'Cloture', 'cloture-tenant-' || n || '@example.invalid', 'IDE', true
FROM generate_series(1,2) n;

INSERT INTO public.etablissements(id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact, est_compte_test)
SELECT ('9c100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'Fixture clôture ' || n, '9919300000' || lpad(n::text,4,'0'), 'CLINIQUE_PRIVEE',
 '1 rue du Test', 'Paris', '75001', 'cloture-etab-' || n || '@example.invalid', true
FROM unnest(ARRAY[14,20,21]) n;

INSERT INTO public.membres_etablissement(etablissement_id,user_id,role,actif)
SELECT ('9c100000-0000-4000-8000-' || lpad((CASE WHEN n=7 THEN 21 ELSE 20 END)::text,12,'0'))::uuid,
 ('9c100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 CASE n WHEN 4 THEN 'RH' WHEN 5 THEN 'LECTURE_SEULE' WHEN 6 THEN 'POINTAGE_ONLY' ELSE 'PROPRIETAIRE' END,
 n<>8
FROM unnest(ARRAY[3,4,5,6,7,8,9,12]) n;

INSERT INTO public.equipe_admin(user_id,nom,prenom,email,actif,acces_groupes)
SELECT ('9c100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 'Fixture', 'Admin', 'cloture-tenant-' || n || '@example.invalid', true,
 ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']::text[]
FROM unnest(ARRAY[10,13]) n;

-- La mission commence depuis moins d'une heure, conformément au vrai trigger
-- anti-publication passée. EN_COURS est un état de fixture, pas une attribution.
SELECT public.fn_test_seed_mission(jsonb_build_object(
 'id','9c100000-0000-4000-8000-000000000030',
 'etablissement_id','9c100000-0000-4000-8000-000000000020',
 'intitule','Fixture clôture tenant', 'profession_requise','IDE',
 'debut_le',now()-interval '45 minutes', 'fin_le',now()-interval '15 minutes',
 'taux_horaire_base',25, 'statut','EN_COURS',
 'soignant_assigne_id','9c100000-0000-4000-8000-000000000001',
 'type_contrat_recherche','SALARIE','type_contrat_applique','SALARIE'));
INSERT INTO public.mission_creneaux(mission_id,debut,fin,ordre,type_creneau,est_pause)
VALUES('9c100000-0000-4000-8000-000000000030', now()-interval '45 minutes', now()-interval '15 minutes', 1,'EFFECTIF',false);
-- Les GUC de seed ne doivent pas participer aux autorisations testées.
SELECT set_config('app.internal_operation', '', true);
SELECT set_config('jolene.creer_mission_context', '', true);
SELECT set_config('app.test_bypass_protections', '', true);
SELECT set_config('request.jwt.claim.role', '', true);

DO $acl$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_terminer_mission(uuid)'::regprocedure
   AND (NOT p.prosecdef OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
     OR has_function_privilege('anon',p.oid,'EXECUTE')
     OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',p.oid,'EXECUTE'))) THEN
   RAISE EXCEPTION 'ACL ou search_path de clôture altérés';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN private.security_definer_inventory i
   ON to_regprocedure(i.signature)=p.oid
   WHERE p.oid='public.fn_terminer_mission(uuid)'::regprocedure AND i.definition_md5=md5(p.prosrc)) THEN
   RAISE EXCEPTION 'Inventaire de la clôture non conforme au correctif';
 END IF;
END $acl$;

SET LOCAL ROLE authenticated;
DO $refus_uniformes$
DECLARE n integer; cible uuid; r jsonb;
BEGIN
 -- Sans tenant (dont le soignant assigné), tiers, droit insuffisant, membre
 -- révoqué, compte banni/supprimé, faux admin et admin banni : même refus.
 FOREACH n IN ARRAY ARRAY[1,2,5,6,7,8,9,11,12,13,99,0] LOOP
   PERFORM set_config('request.jwt.claims',
     CASE WHEN n=0 THEN '{"role":"authenticated"}' ELSE jsonb_build_object(
       'role','authenticated','sub','9c100000-0000-4000-8000-'||lpad(n::text,12,'0'),
       'app_metadata',jsonb_build_object('role','ADMIN_PLATEFORME','etablissement_id','9c100000-0000-4000-8000-000000000020'))::text END,true);
   FOREACH cible IN ARRAY ARRAY['9c100000-0000-4000-8000-000000000030'::uuid,
     '9c100000-0000-4000-8000-000000000099'::uuid,NULL::uuid] LOOP
     r:=public.fn_terminer_mission(cible);
     IF r IS DISTINCT FROM '{"success":false,"error":"Accès refusé"}'::jsonb THEN
       RAISE EXCEPTION 'Accès/statut divulgué pour acteur % cible % : %',n,cible,r;
     END IF;
   END LOOP;
 END LOOP;
END $refus_uniformes$;
RESET ROLE;
DO $aucun_effet$
BEGIN
 IF (SELECT statut FROM public.missions WHERE id='9c100000-0000-4000-8000-000000000030') <> 'EN_COURS'
   OR EXISTS(SELECT 1 FROM public.notifications WHERE titre='Mission terminée ✅'
     AND destinataire_id='9c100000-0000-4000-8000-000000000001') THEN
   RAISE EXCEPTION 'Un refus a produit une clôture/notification';
 END IF;
END $aucun_effet$;

-- La possession d'une clé service seule ne constitue pas une identité humaine.
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $service_sans_identite$
BEGIN
 IF public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030')
   IS DISTINCT FROM '{"success":false,"error":"Accès refusé"}'::jsonb THEN
   RAISE EXCEPTION 'Service sans identité autorisé';
 END IF;
END $service_sans_identite$;
RESET ROLE;

SAVEPOINT cloture_autorisee;
SET LOCAL ROLE authenticated;
DO $positifs$
DECLARE n integer; r jsonb;
BEGIN
 FOREACH n IN ARRAY ARRAY[3,4,10] LOOP
   BEGIN
     PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
       'sub','9c100000-0000-4000-8000-'||lpad(n::text,12,'0'))::text,true);
     r:=public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030');
     IF r->>'success' IS DISTINCT FROM 'true' OR r->>'cloture_anticipee_admin' IS DISTINCT FROM 'false' THEN
       RAISE EXCEPTION 'Clôture autorisée refusée acteur % : %',n,r;
     END IF;
     r:=public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030');
     IF r->>'success' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Double clôture acceptée'; END IF;
     -- Seule cette sentinelle annule la clôture pour le prochain acteur.
     RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='fin du cas positif';
   EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
   END;
 END LOOP;
END $positifs$;
RESET ROLE;
ROLLBACK TO SAVEPOINT cloture_autorisee;

-- Propriétaire historique sans ligne membres : comportement légitime conservé.
SAVEPOINT proprietaire_historique;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
UPDATE public.missions SET etablissement_id='9c100000-0000-4000-8000-000000000014'
WHERE id='9c100000-0000-4000-8000-000000000030';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"9c100000-0000-4000-8000-000000000014"}',true);
DO $historique$
BEGIN
 IF (public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030')->>'success') IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'Propriétaire historique refusé';
 END IF;
END $historique$;
RESET ROLE;
ROLLBACK TO SAVEPOINT proprietaire_historique;

-- Départ absent et segment ouvert restent bloquants après autorisation.
SAVEPOINT depart_absent;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DELETE FROM public.mission_creneaux WHERE mission_id='9c100000-0000-4000-8000-000000000030' AND type_creneau='EFFECTIF';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"9c100000-0000-4000-8000-000000000003"}',true);
DO $sans_depart$
BEGIN
 IF public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030')->>'error_code' IS DISTINCT FROM 'AUCUN_DEPART' THEN
   RAISE EXCEPTION 'Absence de départ non bloquante'; END IF;
END $sans_depart$;
RESET ROLE;
ROLLBACK TO SAVEPOINT depart_absent;

SAVEPOINT segment_ouvert;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
UPDATE public.mission_creneaux SET fin=NULL WHERE mission_id='9c100000-0000-4000-8000-000000000030' AND type_creneau='EFFECTIF';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"9c100000-0000-4000-8000-000000000003"}',true);
DO $segment$
BEGIN
 IF public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030')->>'error_code' IS DISTINCT FROM 'SEGMENT_OUVERT' THEN
   RAISE EXCEPTION 'Segment ouvert non bloquant'; END IF;
END $segment$;
RESET ROLE;
ROLLBACK TO SAVEPOINT segment_ouvert;

-- Un créneau futur exige toujours arbitrage admin + litige actif.
SAVEPOINT cloture_anticipee;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
UPDATE public.mission_creneaux SET fin=now()+interval '15 minutes'
WHERE mission_id='9c100000-0000-4000-8000-000000000030' AND type_creneau='PREVISIONNEL';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"9c100000-0000-4000-8000-000000000003"}',true);
DO $trop_tot$
BEGIN
 IF public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030')->>'error_code' IS DISTINCT FROM 'AVANT_DERNIER_CRENEAU' THEN
   RAISE EXCEPTION 'Clôture propriétaire anticipée autorisée'; END IF;
END $trop_tot$;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"9c100000-0000-4000-8000-000000000010"}',true);
DO $admin_sans_litige$
BEGIN
 IF public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030')->>'error_code' IS DISTINCT FROM 'LITIGE_ACTIF_REQUIS' THEN
   RAISE EXCEPTION 'Clôture admin sans litige autorisée'; END IF;
END $admin_sans_litige$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,type_litige,statut)
VALUES('9c100000-0000-4000-8000-000000000040','9c100000-0000-4000-8000-000000000030',
 '9c100000-0000-4000-8000-000000000001','9c100000-0000-4000-8000-000000000020',
 'SYSTEME','Arbitrage de fixture clôture anticipée','DESACCORD_MONTANT_FACTURE','REVUE_ADMIN');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"9c100000-0000-4000-8000-000000000010"}',true);
DO $admin_litige$
DECLARE r jsonb;
BEGIN
 r:=public.fn_terminer_mission('9c100000-0000-4000-8000-000000000030');
 IF r->>'success' IS DISTINCT FROM 'true' OR r->>'cloture_anticipee_admin' IS DISTINCT FROM 'true'
   OR r->>'litige_id' IS DISTINCT FROM '9c100000-0000-4000-8000-000000000040' THEN
   RAISE EXCEPTION 'Arbitrage admin valide refusé : %',r; END IF;
END $admin_litige$;
RESET ROLE;
DO $effets_admin$
BEGIN
 IF (SELECT statut FROM public.missions WHERE id='9c100000-0000-4000-8000-000000000030') IS DISTINCT FROM 'TERMINEE'
   OR NOT EXISTS(SELECT 1 FROM public.journaux_audit WHERE id_ressource='9c100000-0000-4000-8000-000000000030'
     AND details->>'evenement'='CLOTURE_ANTICIPEE_APRES_ARBITRAGE'
     AND acteur_id='9c100000-0000-4000-8000-000000000010')
   OR (SELECT count(*) FROM public.notifications WHERE titre='Mission terminée ✅'
     AND destinataire_id='9c100000-0000-4000-8000-000000000001') <> 1 THEN
   RAISE EXCEPTION 'État, audit ou notification après clôture incohérent'; END IF;
END $effets_admin$;
ROLLBACK TO SAVEPOINT cloture_anticipee;
ROLLBACK;
