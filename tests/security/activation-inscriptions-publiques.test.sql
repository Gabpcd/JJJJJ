-- Staging/local uniquement. Aucune activation ni donnée persistée, aucun transport.
BEGIN;
SET LOCAL statement_timeout='90s';
-- auth.users n’a aucun trigger INSERT LIVE ; aucun privilège de superuser
-- ni désactivation globale de trigger n’est nécessaire pour ces comptes.
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,raw_user_meta_data,email_confirmed_at)
SELECT ('69550000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000',
 CASE WHEN n=5 THEN 'playwright-test-inscription-activation@jolene.app'
      WHEN n=10 THEN 'playwright-test-inscription-activation@example.invalid'
      ELSE 'inscription-activation-'||n||'@example.invalid' END,
 'authenticated','authenticated',CASE WHEN n=3 THEN '{"est_compte_test":true}'::jsonb
      WHEN n=9 THEN '{"is_test_playwright":true}'::jsonb
      WHEN n=11 THEN '{"est_compte_test":"true","is_test_playwright":"true"}'::jsonb ELSE '{}'::jsonb END,
 CASE WHEN n=4 THEN '{"est_compte_test":true,"is_test_playwright":true}'::jsonb ELSE '{}'::jsonb END,now()
FROM generate_series(1,11) n;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
UPDATE public.parametres_systeme SET valeur=0 WHERE cle='inscriptions_publiques_actives';
UPDATE public.parametres_systeme SET valeur=1 WHERE cle='activation_inscriptions_publiques_planifiee';

-- Insertions réelles des deux profils avec les triggers actifs, comme les Edge.
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice)
VALUES('69550000-0000-4000-8000-000000000001','Recette','Activation','inscription-activation-1@example.invalid','IDE','SALARIE');
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
VALUES('69550000-0000-4000-8000-000000000001','Recette activation','69550000000001','EHPAD','1 rue Recette','Paris','75001','inscription-activation-1@example.invalid');

DO $test$
DECLARE r jsonb;
BEGIN
 IF NOT (SELECT est_compte_test FROM public.soignants WHERE id='69550000-0000-4000-8000-000000000001')
 OR NOT (SELECT est_compte_test FROM public.etablissements WHERE id='69550000-0000-4000-8000-000000000001')
 THEN RAISE EXCEPTION 'Flag fermé : un nouveau profil est réel'; END IF;
 BEGIN
  PERFORM private.fn_activer_inscriptions_publiques_planifiees('mejpriaetwgtcstbgfid','EDGE_PROBES_OK');
  RAISE EXCEPTION 'Activation admise avec la référence staging';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM private.fn_activer_inscriptions_publiques_planifiees('flripxtsyegjshnhzjkz','');
  RAISE EXCEPTION 'Activation sans confirmation admise';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- La ref de production est un contrat explicite de l’appel CI. Le test
 -- exerce la fonction sous rollback, jamais une requête vers la production.
 r:=private.fn_activer_inscriptions_publiques_planifiees('flripxtsyegjshnhzjkz','EDGE_PROBES_OK');
 IF r <> '{"success":true,"active":true,"activation_effectuee":true,"planifiee":false}'::jsonb
 THEN RAISE EXCEPTION 'Première activation non atomique : %',r; END IF;
 r:=private.fn_activer_inscriptions_publiques_planifiees('flripxtsyegjshnhzjkz','EDGE_PROBES_OK');
 IF r->>'activation_effectuee'<>'false' OR r->>'active'<>'true'
 THEN RAISE EXCEPTION 'Deuxième activation non idempotente : %',r; END IF;
END;
$test$;

INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice,est_compte_test)
SELECT ('69550000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Recette','Activation',
 'inscription-activation-'||n||'@example.invalid','IDE','SALARIE',n=6
FROM generate_series(2,11) n WHERE n NOT IN (7,8);
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test)
SELECT ('69550000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Recette activation','695500000000'||lpad(n::text,2,'0'),
 'EHPAD','1 rue Recette','Paris','75001','contact-public@example.invalid',n=6
FROM generate_series(2,11) n WHERE n NOT IN (7,8);

-- Sans champ est_compte_test, exactement le contrat des Edge d’inscription.
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice)
VALUES('69550000-0000-4000-8000-000000000008','Recette','Activation','inscription-activation-8@example.invalid','IDE','SALARIE');
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
VALUES('69550000-0000-4000-8000-000000000008','Recette activation','69550000000008','EHPAD','1 rue Recette','Paris','75001','inscription-activation-8@example.invalid');

DO $test$
DECLARE n integer; attendu boolean; s boolean; e boolean;
BEGIN
 FOR n IN SELECT generate_series(1,11) EXCEPT SELECT 7 LOOP
  attendu:=n IN (1,3,5,6,9);
  SELECT est_compte_test INTO s FROM public.soignants WHERE id=('69550000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
  SELECT est_compte_test INTO e FROM public.etablissements WHERE id=('69550000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
  IF s IS DISTINCT FROM attendu OR e IS DISTINCT FROM attendu THEN RAISE EXCEPTION 'Cohorte du cas % incorrecte : %/% attendu %',n,s,e,attendu; END IF;
 END LOOP;
 IF (SELECT est_compte_test FROM public.soignants WHERE id='69550000-0000-4000-8000-000000000008')
 OR (SELECT est_compte_test FROM public.etablissements WHERE id='69550000-0000-4000-8000-000000000008')
 THEN RAISE EXCEPTION 'Inscription publique avec défaut encore classée test'; END IF;
 IF private.fn_comptes_meme_cohorte_test('69550000-0000-4000-8000-000000000001','69550000-0000-4000-8000-000000000002')
 OR NOT private.fn_comptes_meme_cohorte_test('69550000-0000-4000-8000-000000000002','69550000-0000-4000-8000-000000000004')
 OR NOT private.fn_comptes_meme_cohorte_test('69550000-0000-4000-8000-000000000003','69550000-0000-4000-8000-000000000005')
 THEN RAISE EXCEPTION 'Séparation des cohortes altérée'; END IF;
END;
$test$;

-- Même un upsert serveur ou le kill-switch ne modifie pas les cohortes acquises.
UPDATE public.soignants SET est_compte_test=NOT est_compte_test WHERE id::text LIKE '69550000-%';
UPDATE public.etablissements SET est_compte_test=NOT est_compte_test WHERE id::text LIKE '69550000-%';
UPDATE public.parametres_systeme SET valeur=0 WHERE cle='inscriptions_publiques_actives';
DO $test$
DECLARE r jsonb;
BEGIN
 r:=private.fn_activer_inscriptions_publiques_planifiees('flripxtsyegjshnhzjkz','EDGE_PROBES_OK');
 IF r <> '{"success":true,"active":false,"activation_effectuee":false,"planifiee":false}'::jsonb
 THEN RAISE EXCEPTION 'Un redéploiement réactive le kill-switch : %',r; END IF;
 IF (SELECT est_compte_test FROM public.soignants WHERE id='69550000-0000-4000-8000-000000000002') IS DISTINCT FROM false
 OR (SELECT est_compte_test FROM public.etablissements WHERE id='69550000-0000-4000-8000-000000000002') IS DISTINCT FROM false
 OR (SELECT est_compte_test FROM public.soignants WHERE id='69550000-0000-4000-8000-000000000001') IS DISTINCT FROM true
 OR (SELECT est_compte_test FROM public.etablissements WHERE id='69550000-0000-4000-8000-000000000001') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'La cohorte du stock a changé'; END IF;
END;
$test$;
INSERT INTO public.soignants(id,prenom,nom,email,profession,type_exercice)
VALUES('69550000-0000-4000-8000-000000000007','Recette','Activation','inscription-activation-7@example.invalid','IDE','SALARIE');
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact)
VALUES('69550000-0000-4000-8000-000000000007','Recette activation','69550000000007','EHPAD','1 rue Recette','Paris','75001','inscription-activation-7@example.invalid');

-- Test direct du trigger sous rôle client sur une table temporaire dédiée.
-- On ne donne aucun droit supplémentaire sur les tables applicatives.
CREATE TEMP TABLE inscription_cohorte_probe(id uuid,est_compte_test boolean DEFAULT false);
CREATE TRIGGER cohorte_probe BEFORE INSERT OR UPDATE OF est_compte_test ON inscription_cohorte_probe
FOR EACH ROW EXECUTE FUNCTION private.fn_forcer_compte_test_prelaunch();
GRANT SELECT,INSERT,UPDATE ON inscription_cohorte_probe TO authenticated;
UPDATE public.parametres_systeme SET valeur=1 WHERE cle='inscriptions_publiques_actives';
SELECT set_config('request.jwt.claims','{"sub":"69550000-0000-4000-8000-000000000002","role":"authenticated"}',true);
SET LOCAL ROLE authenticated;
INSERT INTO pg_temp.inscription_cohorte_probe(id,est_compte_test) VALUES('69550000-0000-4000-8000-000000000002',true);
DO $test$
DECLARE n integer;
BEGIN
 IF (SELECT est_compte_test FROM pg_temp.inscription_cohorte_probe) THEN RAISE EXCEPTION 'Marqueur fourni par le client accepté'; END IF;
 BEGIN
  UPDATE pg_temp.inscription_cohorte_probe SET est_compte_test=true;
  RAISE EXCEPTION 'Client autorisé à changer de cohorte';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM private.fn_activer_inscriptions_publiques_planifiees('flripxtsyegjshnhzjkz','EDGE_PROBES_OK');
  RAISE EXCEPTION 'Activation ouverte au client';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE public.parametres_systeme SET valeur=0 WHERE cle='inscriptions_publiques_actives';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>0 THEN RAISE EXCEPTION 'Paramètre modifiable par un compte ordinaire'; END IF;
END;
$test$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{}',true);
DO $test$
DECLARE n integer;
BEGIN
 IF NOT (SELECT est_compte_test FROM public.soignants WHERE id='69550000-0000-4000-8000-000000000007')
 OR NOT (SELECT est_compte_test FROM public.etablissements WHERE id='69550000-0000-4000-8000-000000000007')
 THEN RAISE EXCEPTION 'Kill-switch ignoré pour les nouvelles inscriptions'; END IF;
 SELECT count(*) INTO n FROM pg_trigger
 WHERE tgrelid IN ('public.soignants'::regclass,'public.etablissements'::regclass)
 AND tgfoid='private.fn_forcer_compte_test_prelaunch()'::regprocedure AND tgenabled='O';
 IF n<>2 THEN RAISE EXCEPTION 'Trigger de cohorte non actif sur les deux profils'; END IF;
 IF has_function_privilege('authenticated','private.fn_activer_inscriptions_publiques_planifiees(text,text)','EXECUTE')
 OR has_function_privilege('anon','private.fn_activer_inscriptions_publiques_planifiees(text,text)','EXECUTE')
 OR NOT has_function_privilege('service_role','private.fn_activer_inscriptions_publiques_planifiees(text,text)','EXECUTE')
 OR has_function_privilege('authenticated','private.fn_forcer_compte_test_prelaunch()','EXECUTE')
 OR has_function_privilege('anon','private.fn_forcer_compte_test_prelaunch()','EXECUTE')
 OR has_column_privilege('authenticated','public.soignants','est_compte_test','UPDATE')
 OR has_column_privilege('authenticated','public.etablissements','est_compte_test','UPDATE')
 THEN RAISE EXCEPTION 'Droits client de cohorte ouverts'; END IF;
 IF (SELECT column_default FROM information_schema.columns WHERE table_schema='public' AND table_name='soignants' AND column_name='est_compte_test') IS DISTINCT FROM 'false'
 OR (SELECT column_default FROM information_schema.columns WHERE table_schema='public' AND table_name='etablissements' AND column_name='est_compte_test') IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'Défaut des profils incompatible avec les Edge d’inscription'; END IF;
END;
$test$;
ROLLBACK;
