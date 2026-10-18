-- Deux transactions PostgreSQL réelles. Ce fichier refuse toute base applicative.
\set ON_ERROR_STOP on
DO $scope$ BEGIN
 IF current_database()<>'avoirs_imputation_concurrence' OR current_user<>'postgres'
   OR current_setting('jolene.isolated_sql_test',true) IS DISTINCT FROM 'on'
   OR current_setting('server_version_num')::integer/10000<>17 THEN
   RAISE EXCEPTION 'AVOIRS_CONCURRENCE_CI_EPHEMERE_SEULEMENT'; END IF;
END $scope$;
CREATE EXTENSION dblink;
BEGIN;
INSERT INTO public.etablissements(id,nom,email_contact)
VALUES('a0181000-0000-4000-8000-000000000001','Concurrence','concurrence@example.invalid');
INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,mode_paiement) VALUES
 ('a0181000-0000-4000-8000-000000000010','a0181000-0000-4000-8000-000000000001','CONC-ORIGINE','FACTURE','EMISE',20,4,24,'STRIPE'),
 ('a0181000-0000-4000-8000-000000000020','a0181000-0000-4000-8000-000000000001','CONC-A','FACTURE','BROUILLON',6,1,7,'STRIPE'),
 ('a0181000-0000-4000-8000-000000000021','a0181000-0000-4000-8000-000000000001','CONC-B','FACTURE','BROUILLON',6,1,7,'STRIPE');
INSERT INTO public.missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES
 ('a0181000-0000-4000-8000-000000000011','a0181000-0000-4000-8000-000000000001','SALARIE','a0181000-0000-4000-8000-000000000010'),
 ('a0181000-0000-4000-8000-000000000022','a0181000-0000-4000-8000-000000000001','SALARIE','a0181000-0000-4000-8000-000000000020'),
 ('a0181000-0000-4000-8000-000000000023','a0181000-0000-4000-8000-000000000001','SALARIE','a0181000-0000-4000-8000-000000000021');
INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,facture_precedente_id) VALUES
 ('a0181000-0000-4000-8000-000000000012','a0181000-0000-4000-8000-000000000001','CONC-AVOIR','AVOIR','EMISE',8,2,10,'a0181000-0000-4000-8000-000000000010');
SELECT private.fn_inscrire_avoir_commission('a0181000-0000-4000-8000-000000000012','a0181000-0000-4000-8000-000000000011','LITIGE_SALARIE');
COMMIT;

-- Mot de passe public du service postgres:17 éphémère validate-pr, pas un secret.
SELECT dblink_connect('avoir_a','host=127.0.0.1 port=5432 dbname=avoirs_imputation_concurrence user=postgres password=fixture-ci-ephemere');
SELECT dblink_connect('avoir_b','host=127.0.0.1 port=5432 dbname=avoirs_imputation_concurrence user=postgres password=fixture-ci-ephemere');
SELECT dblink_exec('avoir_a','BEGIN; SET LOCAL statement_timeout=''20s'';');
SELECT dblink_exec('avoir_b','BEGIN; SET LOCAL statement_timeout=''20s'';');
SELECT dblink_send_query('avoir_a',$a$SELECT private.fn_emettre_facture_mensuelle_avec_avoirs('a0181000-0000-4000-8000-000000000020')$a$);
CREATE TEMP TABLE resultat_a AS SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
SELECT dblink_send_query('avoir_b',$b$SELECT private.fn_emettre_facture_mensuelle_avec_avoirs('a0181000-0000-4000-8000-000000000021')$b$);
SELECT pg_sleep(0.2);
DO $attente$ BEGIN
 IF dblink_is_busy('avoir_b')<>1 THEN RAISE EXCEPTION 'AVOIR_SECOND_ECRIVAIN_NON_SERIALISE'; END IF;
END $attente$;
SELECT dblink_exec('avoir_a','COMMIT');
CREATE TEMP TABLE resultat_b AS SELECT * FROM dblink_get_result('avoir_b') AS r(resultat jsonb);
SELECT * FROM dblink_get_result('avoir_b') AS r(resultat jsonb);
SELECT dblink_exec('avoir_b','COMMIT');
DO $resultats$ BEGIN
 IF (SELECT (resultat->>'montant_avoirs_imputes')::numeric FROM resultat_a) IS DISTINCT FROM 7
   OR (SELECT (resultat->>'montant_avoirs_imputes')::numeric FROM resultat_b) IS DISTINCT FROM 3
   OR (SELECT (resultat->>'montant_a_payer')::numeric FROM resultat_b) IS DISTINCT FROM 4
   OR (SELECT sum(montant_cents) FROM private.avoirs_commission_mouvements) IS DISTINCT FROM 1000
   OR (SELECT count(*) FROM private.avoirs_commission_mouvements)<>2 THEN
   RAISE EXCEPTION 'AVOIR_CONCURRENCE_DOUBLE_CONSOMMATION'; END IF;
END $resultats$;
-- L'allocation est non commitée quand le remboursement arrive. La garde doit
-- refuser avec 40001, sans attendre en tenant la ligne de l'origine, puis le
-- rejeu après COMMIT doit signaler la nouvelle cible sans modifier son net.
BEGIN;
INSERT INTO public.etablissements(id,nom,email_contact) VALUES
 ('a0182000-0000-4000-8000-000000000001','Allocation avant signalement','avant@example.invalid'),
 ('a0183000-0000-4000-8000-000000000001','Signalement avant allocation','apres@example.invalid');
INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,mode_paiement) VALUES
 ('a0182000-0000-4000-8000-000000000010','a0182000-0000-4000-8000-000000000001','SIGNAL-ORIGINE-A','FACTURE','EMISE',20,4,24,'STRIPE'),
 ('a0182000-0000-4000-8000-000000000020','a0182000-0000-4000-8000-000000000001','SIGNAL-CIBLE-A','FACTURE','BROUILLON',6,1,7,'STRIPE'),
 ('a0183000-0000-4000-8000-000000000010','a0183000-0000-4000-8000-000000000001','SIGNAL-ORIGINE-B','FACTURE','EMISE',20,4,24,'STRIPE'),
 ('a0183000-0000-4000-8000-000000000020','a0183000-0000-4000-8000-000000000001','SIGNAL-CIBLE-B','FACTURE','BROUILLON',6,1,7,'STRIPE');
INSERT INTO public.missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES
 ('a0182000-0000-4000-8000-000000000011','a0182000-0000-4000-8000-000000000001','SALARIE','a0182000-0000-4000-8000-000000000010'),
 ('a0182000-0000-4000-8000-000000000022','a0182000-0000-4000-8000-000000000001','SALARIE','a0182000-0000-4000-8000-000000000020'),
 ('a0183000-0000-4000-8000-000000000011','a0183000-0000-4000-8000-000000000001','SALARIE','a0183000-0000-4000-8000-000000000010'),
 ('a0183000-0000-4000-8000-000000000022','a0183000-0000-4000-8000-000000000001','SALARIE','a0183000-0000-4000-8000-000000000020');
INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,facture_precedente_id) VALUES
 ('a0182000-0000-4000-8000-000000000012','a0182000-0000-4000-8000-000000000001','SIGNAL-AVOIR-A','AVOIR','EMISE',8,2,10,'a0182000-0000-4000-8000-000000000010'),
 ('a0183000-0000-4000-8000-000000000012','a0183000-0000-4000-8000-000000000001','SIGNAL-AVOIR-B','AVOIR','EMISE',8,2,10,'a0183000-0000-4000-8000-000000000010');
SELECT private.fn_inscrire_avoir_commission('a0182000-0000-4000-8000-000000000012','a0182000-0000-4000-8000-000000000011','LITIGE_SALARIE');
SELECT private.fn_inscrire_avoir_commission('a0183000-0000-4000-8000-000000000012','a0183000-0000-4000-8000-000000000011','LITIGE_SALARIE');
COMMIT;
SELECT dblink_exec('avoir_a','BEGIN; SET LOCAL statement_timeout=''20s'';');
SELECT dblink_exec('avoir_b','BEGIN; SET LOCAL statement_timeout=''20s''; SET LOCAL request.jwt.claim.role=''service_role'';');
SELECT dblink_send_query('avoir_a',$a$SELECT private.fn_emettre_facture_mensuelle_avec_avoirs('a0182000-0000-4000-8000-000000000020')$a$);
SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
SELECT dblink_exec('avoir_b',$b$DO $refus$
 BEGIN
  UPDATE public.factures SET rapprochement_paiement_requis=true WHERE id='a0182000-0000-4000-8000-000000000010';
  RAISE EXCEPTION 'SIGNAL_CONCURRENT_DOIT_REJOUER';
 EXCEPTION WHEN serialization_failure THEN
  IF SQLERRM<>'AVOIR_RAPPROCHEMENT_CONCURRENT_REESSAYER' THEN RAISE; END IF;
 END $refus$;$b$);
SELECT dblink_exec('avoir_a','COMMIT');
SELECT dblink_exec('avoir_b',$b$UPDATE public.factures SET rapprochement_paiement_requis=true WHERE id='a0182000-0000-4000-8000-000000000010'; COMMIT;$b$);
DO $rejeu$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id='a0182000-0000-4000-8000-000000000020'
   AND rapprochement_paiement_requis AND statut='PAYEE' AND mode_paiement='AVOIR'
   AND montant_avoirs_imputes=7 AND montant_a_payer=0 AND stripe_payment_intent_id IS NULL)
   OR (SELECT count(*) FROM private.avoirs_commission_mouvements WHERE facture_id='a0182000-0000-4000-8000-000000000020')<>1 THEN
   RAISE EXCEPTION 'SIGNAL_REJOUE_PERD_ALLOCATION_OU_PREUVE'; END IF;
END $rejeu$;

-- Ordre inverse : B signale d'abord et détient E ; A attend, puis relit le flag
-- commité et émet au TTC, sans consommer cet avoir.
SELECT dblink_exec('avoir_b','BEGIN; SET LOCAL statement_timeout=''20s''; SET LOCAL request.jwt.claim.role=''service_role'';');
SELECT dblink_exec('avoir_b',$b$UPDATE public.factures SET rapprochement_paiement_requis=true WHERE id='a0183000-0000-4000-8000-000000000010'$b$);
SELECT dblink_exec('avoir_a','BEGIN; SET LOCAL statement_timeout=''20s'';');
SELECT dblink_send_query('avoir_a',$a$SELECT private.fn_emettre_facture_mensuelle_avec_avoirs('a0183000-0000-4000-8000-000000000020')$a$);
SELECT pg_sleep(0.2);
DO $attente_signal$ BEGIN
 IF dblink_is_busy('avoir_a')<>1 THEN RAISE EXCEPTION 'ALLOCATION_IGNORE_VERROU_SIGNAL'; END IF;
END $attente_signal$;
SELECT dblink_exec('avoir_b','COMMIT');
SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
SELECT dblink_exec('avoir_a','COMMIT');
DO $signal_premier$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.factures WHERE id='a0183000-0000-4000-8000-000000000020'
   AND statut='EMISE' AND montant_avoirs_imputes=0 AND montant_a_payer=7)
   OR EXISTS(SELECT 1 FROM private.avoirs_commission_mouvements WHERE facture_id='a0183000-0000-4000-8000-000000000020') THEN
   RAISE EXCEPTION 'ALLOCATION_ORIGINE_SIGNALEE_CONSOMMEE'; END IF;
END $signal_premier$;

-- Producteur réel, seules ses dépendances de numérotation et de notification
-- sont minimales. La mission/delta ne doit être traitée qu'une fois entre deux
-- appels cron/admin : B ignore la ligne détenue par A, puis le rejeu constate
-- commission_a_recalculer=false. Aucun helper d'émission n'est simulé.
ALTER TABLE public.missions ADD COLUMN taux_commission numeric, ADD COLUMN commission_a_recalculer boolean DEFAULT false;
ALTER TABLE public.factures_honoraires ADD COLUMN montant_signe numeric, ADD COLUMN statut_litige text, ADD COLUMN litige_id uuid;
CREATE SEQUENCE public.fixture_numeros_avoirs;
CREATE FUNCTION public.next_avoir_commission_number(uuid) RETURNS text LANGUAGE sql AS $numero$
 SELECT 'CONC-RECALCUL-'||nextval('public.fixture_numeros_avoirs')::text;
$numero$;
CREATE FUNCTION public.fn_litige_push_notification(uuid,text,text,text,text,uuid,jsonb) RETURNS void LANGUAGE sql AS $notif$
 INSERT INTO public.notifications(destinataire_id,type_destinataire,type,titre,corps,id_ressource)
 VALUES($1,$2,$3,$4,$5,$6);
$notif$;
INSERT INTO public.etablissements(id,nom,email_contact) VALUES
 ('a0184000-0000-4000-8000-000000000001','Recalcul concurrent','recalcul@example.invalid');
INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,mode_paiement) VALUES
 ('a0184000-0000-4000-8000-000000000010','a0184000-0000-4000-8000-000000000001','RECALCUL-ORIGINE','FACTURE','EMISE',20,4,24,'STRIPE');
INSERT INTO public.missions(id,etablissement_id,type_contrat_applique,facture_id,commission_facturee,
 taux_commission,montant_commission_ht,montant_commission_tva,montant_commission_ttc,commission_a_recalculer) VALUES
 ('a0184000-0000-4000-8000-000000000011','a0184000-0000-4000-8000-000000000001','SALARIE',
  'a0184000-0000-4000-8000-000000000010',true,15,20,4,24,true);
SELECT dblink_exec('avoir_a','BEGIN; SET LOCAL statement_timeout=''20s'';');
SELECT dblink_exec('avoir_b','BEGIN; SET LOCAL statement_timeout=''20s'';');
SELECT dblink_send_query('avoir_a',$a$SELECT public.fn_recalculer_commissions_post_litige()$a$);
CREATE TEMP TABLE recalcul_a AS SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
SELECT * FROM dblink_get_result('avoir_a') AS r(resultat jsonb);
CREATE TEMP TABLE recalcul_b AS SELECT * FROM dblink('avoir_b',$b$SELECT public.fn_recalculer_commissions_post_litige()$b$) AS r(resultat jsonb);
SELECT dblink_exec('avoir_a','COMMIT');
CREATE TEMP TABLE recalcul_rejeu AS SELECT * FROM dblink('avoir_b',$b$SELECT public.fn_recalculer_commissions_post_litige()$b$) AS r(resultat jsonb);
SELECT dblink_exec('avoir_b','COMMIT');
DO $producteur$ BEGIN
 IF (SELECT (resultat->>'avoirs_commission_emis')::integer FROM recalcul_a) IS DISTINCT FROM 1
   OR (SELECT (resultat->>'avoirs_commission_emis')::integer FROM recalcul_b) IS DISTINCT FROM 0
   OR (SELECT (resultat->>'avoirs_commission_emis')::integer FROM recalcul_rejeu) IS DISTINCT FROM 0
   OR (SELECT count(*) FROM public.factures WHERE facture_precedente_id='a0184000-0000-4000-8000-000000000010' AND type_document='AVOIR')<>1
   OR (SELECT sum(montant_cents) FROM private.avoirs_commission_sources WHERE facture_origine_id='a0184000-0000-4000-8000-000000000010') IS DISTINCT FROM 2400
   OR (SELECT count(*) FROM public.notifications WHERE destinataire_id='a0184000-0000-4000-8000-000000000001')<>1 THEN
   RAISE EXCEPTION 'RECALCUL_CONCURRENT_DOUBLE_AVOIR'; END IF;
END $producteur$;
SELECT dblink_disconnect('avoir_a');
SELECT dblink_disconnect('avoir_b');
