-- PostgreSQL isolé uniquement. Aucun fournisseur appelé. Exemple :
-- PGOPTIONS='-c jolene.isolated_sql_test=on' psql "$LOCAL_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f ce_fichier
-- Les tables réduites portent les colonnes utilisées par la vraie migration.
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR to_regclass('public.factures') IS NOT NULL THEN
    RAISE EXCEPTION 'Base PostgreSQL vide et isolée requise';
  END IF;
END $guard$;
CREATE SCHEMA IF NOT EXISTS private;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE TABLE public.email_queue(id uuid PRIMARY KEY, type text, destinataire_id uuid, data jsonb,
  statut text, envoye boolean DEFAULT false, envoye_le timestamptz, erreur text);
CREATE TABLE public.etablissements(id uuid PRIMARY KEY, supprime_le timestamptz);
CREATE TABLE public.soignants(id uuid PRIMARY KEY, supprime_le timestamptz);
CREATE TABLE public.factures(id uuid PRIMARY KEY, etablissement_id uuid, numero_facture text,
  statut text, montant_ht numeric, montant_tva numeric, montant_ttc numeric, type_document text DEFAULT 'FACTURE',
  date_echeance date, periode_debut date, periode_fin date, mission_id uuid, facture_honoraire_id uuid);
CREATE TABLE public.factures_honoraires(LIKE public.factures INCLUDING ALL,
  soignant_id uuid, pdf_s3_key text, facturx_xml_url text, emise_le timestamptz, verification_echeance_le timestamptz);
CREATE TABLE public.missions(id uuid PRIMARY KEY, etablissement_id uuid, soignant_assigne_id uuid, facture_id uuid);
CREATE TABLE private.email_dispatch_idempotency(idempotency_key text PRIMARY KEY, statut text);
CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,categorie text,definition_md5 text,justification text,recense_le timestamptz);
INSERT INTO public.etablissements VALUES ('69510000-0000-4000-8000-000000000001',NULL);
INSERT INTO public.soignants VALUES ('69510000-0000-4000-8000-000000000002',NULL);
-- Une facture historique ne doit pas devenir un nouvel email au déploiement.
INSERT INTO public.factures(id,etablissement_id,numero_facture,statut,montant_ht,montant_tva,montant_ttc)
VALUES ('69510000-0000-4000-8000-000000000100','69510000-0000-4000-8000-000000000001','HISTORIQUE','EMISE',10,2,12);

\ir ../../supabase/migrations/20261016125521_fiabiliser_emails_factures.sql
-- Le step PG17 fournit le corps exact extrait de la sixième migration.
-- Ne pas inclure son BEGIN/COMMIT : le rollback de ce témoin doit tout annuler.
\if :{?facturation_email_corrective}
\i :facturation_email_corrective
\else
\echo 'Refus : corps correctif email exact non fourni'
\quit 3
\endif

DO $proof$
DECLARE email uuid; r jsonb; cle text; corps jsonb; n integer; signature text;
BEGIN
  IF EXISTS(SELECT FROM public.email_queue) THEN RAISE EXCEPTION 'Backfill interdit'; END IF;
  FOREACH signature IN ARRAY ARRAY['public.fn_reserver_email_facturation(uuid)',
    'public.fn_acquitter_email_facturation(uuid,uuid,text,text)','public.fn_reprendre_emails_facturation()'] LOOP
    IF has_function_privilege('anon',signature,'execute') OR has_function_privilege('authenticated',signature,'execute')
      OR NOT has_function_privilege('service_role',signature,'execute') THEN RAISE EXCEPTION 'RPC exposée : %',signature; END IF;
  END LOOP;
  IF has_table_privilege('service_role','private.facturation_email_livraisons','INSERT')
    OR has_table_privilege('authenticated','private.facturation_email_livraisons','SELECT')
    OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.facturation_email_livraisons'::regclass)
  THEN RAISE EXCEPTION 'Reçus non protégés'; END IF;

  INSERT INTO public.factures VALUES ('69510000-0000-4000-8000-000000000101','69510000-0000-4000-8000-000000000001',
    'C-101','EMISE',15,3,18,'FACTURE','2026-11-30','2026-10-01','2026-10-16');
  SELECT email_id,idempotency_key,l.corps INTO email,cle,corps FROM private.facturation_email_livraisons l
    WHERE document_id='69510000-0000-4000-8000-000000000101';
  IF email IS NULL OR (SELECT count(*) FROM public.email_queue)<>1
    OR corps#>>'{data,date_echeance}' <> '30/11/2026'
    OR corps#>>'{data,montant_ttc}' <> '18.00' THEN RAISE EXCEPTION 'Commission non mise en file correctement'; END IF;
  UPDATE public.factures SET statut='EMISE' WHERE id='69510000-0000-4000-8000-000000000101';
  IF (SELECT count(*) FROM public.email_queue)<>1 THEN RAISE EXCEPTION 'Doublon émission'; END IF;
  -- NULL n'est pas une émission (factures.statut est nullable en production).
  INSERT INTO public.factures VALUES ('69510000-0000-4000-8000-000000000106','69510000-0000-4000-8000-000000000001',
    'C-106',NULL,15,3,18,'FACTURE',NULL,'2026-10-01','2026-10-16');
  IF EXISTS(SELECT FROM private.facturation_email_livraisons WHERE document_id='69510000-0000-4000-8000-000000000106')
    OR (SELECT count(*) FROM public.email_queue)<>1 THEN RAISE EXCEPTION 'Statut NULL présenté comme émission'; END IF;
  -- Une émission dont le statut est devenu indéterminé ne peut être livrée.
  INSERT INTO public.factures VALUES ('69510000-0000-4000-8000-000000000107','69510000-0000-4000-8000-000000000001',
    'C-107','EMISE',15,3,18,'FACTURE',NULL,'2026-10-01','2026-10-16');
  UPDATE public.factures SET statut=NULL WHERE id='69510000-0000-4000-8000-000000000107';
  IF public.fn_reserver_email_facturation((SELECT email_id FROM private.facturation_email_livraisons
      WHERE document_id='69510000-0000-4000-8000-000000000107'))->>'statut' IS DISTINCT FROM 'ANNULE'
    THEN RAISE EXCEPTION 'Statut devenu NULL livré'; END IF;
  -- Retirer seulement cette fixture de diagnostic pour conserver les compteurs
  -- historiques de ce témoin, sous le ROLLBACK global de la base isolée.
  DELETE FROM public.email_queue WHERE id IN (SELECT email_id FROM private.facturation_email_livraisons
    WHERE document_id='69510000-0000-4000-8000-000000000107');
  -- Déploiement mixte : l'ancien cron refuse le nouveau type sans appeler
  -- le fournisseur, avant toute réservation du nouveau worker.
  UPDATE public.email_queue SET statut='ERREUR',erreur='Type non supporté ancien cron' WHERE id=email;
  PERFORM public.fn_reprendre_emails_facturation();
  IF (SELECT statut FROM public.email_queue WHERE id=email)<>'EN_ATTENTE'
    OR (SELECT premiere_tentative_le FROM private.facturation_email_livraisons WHERE email_id=email) IS NOT NULL
    THEN RAISE EXCEPTION 'Première livraison bloquée par déploiement mixte'; END IF;
  r := public.fn_reserver_email_facturation(email);
  IF r->>'statut'<>'RESERVE' OR r->'corps' IS DISTINCT FROM corps OR r->>'idempotency_key'<>cle
    THEN RAISE EXCEPTION 'Réservation invalide'; END IF;
  IF public.fn_reserver_email_facturation(email)->>'statut'<>'ATTENDRE' THEN RAISE EXCEPTION 'Bail concurrent absent'; END IF;
  PERFORM public.fn_acquitter_email_facturation(email,(r->>'reservation')::uuid,'ERREUR','503 fictif');
  IF (SELECT statut FROM public.email_queue WHERE id=email)<>'ERREUR' THEN RAISE EXCEPTION 'Erreur masquée'; END IF;
  PERFORM public.fn_reprendre_emails_facturation();
  IF (SELECT statut FROM public.email_queue WHERE id=email)<>'ERREUR' THEN RAISE EXCEPTION 'Backoff ignoré'; END IF;
  FOR n IN 2..5 LOOP
    UPDATE private.facturation_email_livraisons SET prochaine_tentative_le=now()-interval '1 second' WHERE email_id=email;
    PERFORM public.fn_reprendre_emails_facturation();
    r := public.fn_reserver_email_facturation(email);
    IF r->>'statut'<>'RESERVE' OR r->'corps' IS DISTINCT FROM corps OR r->>'idempotency_key'<>cle
      THEN RAISE EXCEPTION 'Reprise modifie identité ou payload'; END IF;
    PERFORM public.fn_acquitter_email_facturation(email,(r->>'reservation')::uuid,'ERREUR','503 fictif');
  END LOOP;
  UPDATE private.facturation_email_livraisons SET prochaine_tentative_le=now()-interval '1 second' WHERE email_id=email;
  PERFORM public.fn_reprendre_emails_facturation();
  IF (SELECT statut FROM public.email_queue WHERE id=email)<>'ERREUR'
    OR (SELECT tentatives FROM private.facturation_email_livraisons WHERE email_id=email)<>5
    THEN RAISE EXCEPTION 'Nombre de reprises non borné'; END IF;

  INSERT INTO public.factures_honoraires(id,etablissement_id,soignant_id,numero_facture,statut,montant_ht,montant_tva,montant_ttc,
    date_echeance,periode_debut,periode_fin)
  VALUES ('69510000-0000-4000-8000-000000000201','69510000-0000-4000-8000-000000000001',
    '69510000-0000-4000-8000-000000000002','FH-201','EN_GENERATION',100,0,100,'2026-11-25','2026-10-01','2026-10-16');
  IF (SELECT count(*) FROM public.email_queue)<>1 THEN RAISE EXCEPTION 'Document intermédiaire envoyé'; END IF;
  UPDATE public.factures_honoraires SET statut='EMISE',pdf_s3_key='fictif.pdf',facturx_xml_url='fictif.xml',
    emise_le=now(),verification_echeance_le='2026-10-18T08:00:00Z' WHERE id='69510000-0000-4000-8000-000000000201';
  IF (SELECT count(*) FROM private.facturation_email_livraisons WHERE famille='HONORAIRES')<>2
    THEN RAISE EXCEPTION 'Deux copies honoraires attendues'; END IF;
  IF EXISTS (SELECT FROM private.facturation_email_livraisons l WHERE l.famille='HONORAIRES'
    AND (l.corps#>>'{data,date_echeance}' IS DISTINCT FROM '25/11/2026'
      OR l.corps#>>'{data,verification_echeance}' IS DISTINCT FROM '18/10/2026 à 10:00'))
    THEN RAISE EXCEPTION 'Échéances honoraires incorrectes'; END IF;
  SELECT email_id,idempotency_key INTO email,cle FROM private.facturation_email_livraisons
    WHERE famille='HONORAIRES' AND destinataire_id='69510000-0000-4000-8000-000000000001';
  IF cle<>'facture-emise-etablissement:69510000-0000-4000-8000-000000000201'
    THEN RAISE EXCEPTION 'Clé de déploiement compatible perdue'; END IF;
  -- Succès transport dont l'acquittement a été perdu : aucune deuxième émission.
  r := public.fn_reserver_email_facturation(email);
  INSERT INTO private.email_dispatch_idempotency VALUES(cle,'ENVOYE');
  UPDATE private.facturation_email_livraisons SET prochaine_tentative_le=now()-interval '1 second' WHERE email_id=email;
  -- L'appel écrit la queue : l'observer dans une instruction suivante évite
  -- qu'une sous-requête de la même expression soit évaluée avant cet effet.
  r := public.fn_reserver_email_facturation(email);
  IF r->>'statut' IS DISTINCT FROM 'DEJA_ENVOYE'
    OR (SELECT statut FROM public.email_queue WHERE id=email) IS DISTINCT FROM 'ENVOYE'
    OR (SELECT envoye AND envoye_le IS NOT NULL FROM public.email_queue WHERE id=email) IS DISTINCT FROM true
    THEN RAISE EXCEPTION 'Copie déjà envoyée répétée'; END IF;
  -- Un document annulé entre émission et livraison n'est plus expédié.
  UPDATE public.factures_honoraires SET statut='ANNULEE' WHERE id='69510000-0000-4000-8000-000000000201';
  SELECT email_id INTO email FROM private.facturation_email_livraisons WHERE famille='HONORAIRES'
    AND destinataire_id='69510000-0000-4000-8000-000000000002';
  IF public.fn_reserver_email_facturation(email)->>'statut'<>'ANNULE' THEN RAISE EXCEPTION 'Document annulé envoyé'; END IF;

  -- La limite de 20 heures s'applique également à un transport indéterminé.
  INSERT INTO public.factures VALUES ('69510000-0000-4000-8000-000000000102','69510000-0000-4000-8000-000000000001',
    'C-102','EMISE',15,3,18,'FACTURE','2026-11-30','2026-10-01','2026-10-16');
  SELECT email_id INTO email FROM private.facturation_email_livraisons WHERE document_id='69510000-0000-4000-8000-000000000102';
  UPDATE private.facturation_email_livraisons SET premiere_tentative_le=now()-interval '21 hours' WHERE email_id=email;
  IF public.fn_reserver_email_facturation(email)->>'statut'<>'ERREUR' THEN RAISE EXCEPTION 'Fenêtre idempotence dépassée'; END IF;

  INSERT INTO public.factures VALUES ('69510000-0000-4000-8000-000000000104','69510000-0000-4000-8000-000000000001',
    'AC-104','EMISE',15,3,18,'AVOIR',NULL,'2026-10-01','2026-10-16');
  IF EXISTS(SELECT FROM private.facturation_email_livraisons WHERE document_id='69510000-0000-4000-8000-000000000104')
    THEN RAISE EXCEPTION 'Notification avoir commission existante doublée'; END IF;
  INSERT INTO public.factures_honoraires(id,etablissement_id,soignant_id,numero_facture,statut,montant_ht,montant_tva,montant_ttc,
    type_document,periode_debut,periode_fin,pdf_s3_key,facturx_xml_url,emise_le)
  VALUES ('69510000-0000-4000-8000-000000000202','69510000-0000-4000-8000-000000000001',
    '69510000-0000-4000-8000-000000000002','AH-202','EMISE',100,0,100,'AVOIR','2026-10-01','2026-10-16','avoir.pdf','avoir.xml',now());
  IF (SELECT count(*) FROM private.facturation_email_livraisons WHERE document_id='69510000-0000-4000-8000-000000000202')<>1
    OR EXISTS(SELECT FROM private.facturation_email_livraisons WHERE document_id='69510000-0000-4000-8000-000000000202'
      AND destinataire_id='69510000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'AVOIR_EMIS soignant doublé'; END IF;
END $proof$;

-- Les nouvelles copies portent les sources canoniques, distinctes du seul
-- destinataire. La classification TEST/fournisseur relève du vrai transport.
DO $sources$
DECLARE corps jsonb;
BEGIN
  INSERT INTO public.missions VALUES ('69510000-0000-4000-8000-000000000301',
    '69510000-0000-4000-8000-000000000001','69510000-0000-4000-8000-000000000002',NULL);
  INSERT INTO public.factures_honoraires(id,etablissement_id,soignant_id,mission_id,numero_facture,statut,montant_ht,montant_tva,montant_ttc)
  VALUES ('69510000-0000-4000-8000-000000000203','69510000-0000-4000-8000-000000000001',
    '69510000-0000-4000-8000-000000000002','69510000-0000-4000-8000-000000000301','FH-203','EN_GENERATION',100,0,100);
  INSERT INTO public.factures(id,etablissement_id,mission_id,facture_honoraire_id,numero_facture,statut,montant_ht,montant_tva,montant_ttc)
  VALUES ('69510000-0000-4000-8000-000000000111','69510000-0000-4000-8000-000000000001',
    '69510000-0000-4000-8000-000000000301','69510000-0000-4000-8000-000000000203','C-111','EMISE',15,3,18);
  SELECT l.corps INTO corps FROM private.facturation_email_livraisons l WHERE document_id='69510000-0000-4000-8000-000000000111';
  IF corps#>>'{data,mission_id}' IS DISTINCT FROM '69510000-0000-4000-8000-000000000301'
    OR corps#>>'{data,etablissement_id}' IS DISTINCT FROM '69510000-0000-4000-8000-000000000001'
    OR corps#>>'{data,soignant_id}' IS DISTINCT FROM '69510000-0000-4000-8000-000000000002'
    THEN RAISE EXCEPTION 'Sources commission individuelle absentes ou fabriquées'; END IF;
  UPDATE public.factures_honoraires SET statut='EMISE',pdf_s3_key='source.pdf',facturx_xml_url='source.xml',emise_le=now()
    WHERE id='69510000-0000-4000-8000-000000000203';
  IF EXISTS(SELECT 1 FROM private.facturation_email_livraisons l WHERE document_id='69510000-0000-4000-8000-000000000203'
    AND (l.corps#>>'{data,mission_id}' IS DISTINCT FROM '69510000-0000-4000-8000-000000000301'
      OR l.corps#>>'{data,etablissement_id}' IS DISTINCT FROM '69510000-0000-4000-8000-000000000001'
      OR l.corps#>>'{data,soignant_id}' IS DISTINCT FROM '69510000-0000-4000-8000-000000000002'))
    THEN RAISE EXCEPTION 'Sources copies honoraires incorrectes'; END IF;
  -- Au moment de l'INSERT d'une commission groupée, ses liens missions sont
  -- encore absents : aucun soignant arbitraire n'est placé dans le reçu.
  INSERT INTO public.factures(id,etablissement_id,numero_facture,statut,montant_ht,montant_tva,montant_ttc)
  VALUES ('69510000-0000-4000-8000-000000000112','69510000-0000-4000-8000-000000000001','C-112','EMISE',30,6,36);
  UPDATE public.missions SET facture_id='69510000-0000-4000-8000-000000000112' WHERE id='69510000-0000-4000-8000-000000000301';
  SELECT l.corps INTO corps FROM private.facturation_email_livraisons l WHERE document_id='69510000-0000-4000-8000-000000000112';
  IF corps#>>'{data,etablissement_id}' IS DISTINCT FROM '69510000-0000-4000-8000-000000000001'
    OR corps#>>'{data,mission_id}' IS NOT NULL OR corps#>>'{data,soignant_id}' IS NOT NULL
    THEN RAISE EXCEPTION 'Source groupée déduite d’une mission arbitraire'; END IF;
END $sources$;

-- L'échec de file doit annuler aussi l'émission et son reçu, pas perdre la copie.
CREATE FUNCTION pg_temp.refuser_facture_email() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN RAISE EXCEPTION 'File indisponible fictive'; END $fn$;
CREATE TRIGGER recette_refus_facture_email BEFORE INSERT ON public.email_queue
FOR EACH ROW EXECUTE FUNCTION pg_temp.refuser_facture_email();
DO $atomicite$ BEGIN
  BEGIN
    INSERT INTO public.factures VALUES ('69510000-0000-4000-8000-000000000103','69510000-0000-4000-8000-000000000001',
      'C-103','EMISE',15,3,18,'FACTURE','2026-11-30','2026-10-01','2026-10-16');
    RAISE EXCEPTION 'Échec attendu absent';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'File indisponible fictive' THEN RAISE; END IF; END;
  IF EXISTS(SELECT FROM public.factures WHERE id='69510000-0000-4000-8000-000000000103')
    OR EXISTS(SELECT FROM private.facturation_email_livraisons WHERE document_id='69510000-0000-4000-8000-000000000103')
    THEN RAISE EXCEPTION 'Émission ou reçu orphelin'; END IF;
END $atomicite$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
