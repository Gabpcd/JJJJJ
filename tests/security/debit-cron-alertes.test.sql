-- Aucun transport : assertions scheduler/lot sous transaction annulée.
BEGIN;
SET LOCAL statement_timeout='90s';
-- Le bootstrap staging retire les jobs avant db push, puis réconcilie après.
-- Vérifier la primitive canonique avec le job absent, puis à la répétition.
DO $bootstrap$
DECLARE resultat jsonb; identifiant bigint;
BEGIN
 FOR identifiant IN SELECT jobid FROM cron.job WHERE jobname IN('litige-escalation-cron','email-cron-hourly-immediate','email-cron-daily','process-stripe-refunds-15min','escrow-debit-echeance','escrow-release','jolene_process_externalisations','weekly-invoicing-cron','jolene-monitor-crons-edge-critiques') LOOP
  PERFORM cron.unschedule(identifiant);
 END LOOP;
 resultat:=private.fn_reconcilier_crons_edge_critiques_inactifs();
 IF resultat->>'success' IS DISTINCT FROM 'true' OR resultat->>'jobs_actifs' IS DISTINCT FROM '0'
 THEN RAISE EXCEPTION 'Réconciliation sans job impossible ou active : %',resultat; END IF;
 resultat:=private.fn_reconcilier_crons_edge_critiques_inactifs();
 IF resultat->>'success' IS DISTINCT FROM 'true' OR (SELECT count(*) FROM cron.job WHERE jobname='email-cron-hourly-immediate' AND schedule='* * * * *' AND active=false)<>1
 THEN RAISE EXCEPTION 'Réconciliation rétablit cadence horaire, doublon ou activation'; END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobname IN('litige-escalation-cron','email-cron-hourly-immediate','email-cron-daily','process-stripe-refunds-15min','escrow-debit-echeance','escrow-release','jolene_process_externalisations','weekly-invoicing-cron','jolene-monitor-crons-edge-critiques') AND active=false)<>9
 THEN RAISE EXCEPTION 'Les neuf jobs doivent rester inactifs avant les sondes'; END IF;
 IF has_function_privilege('authenticated','private.fn_reconcilier_crons_edge_critiques_inactifs()','execute') OR has_function_privilege('anon','private.fn_reconcilier_crons_edge_critiques_inactifs()','execute')
 THEN RAISE EXCEPTION 'Réconciliation de crons exposée aux clients'; END IF;
END $bootstrap$;
SET LOCAL session_replication_role=replica;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES('69400000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','debit-alertes@example.invalid','authenticated','authenticated','{}',now());
UPDATE public.filtres_sauvegardes SET alerte_active=false WHERE alerte_active;
INSERT INTO public.filtres_sauvegardes(id,utilisateur_id,nom,audience,filtres,alerte_active,frequence_alerte,dernier_check_le)
SELECT ('69400000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'69400000-0000-4000-8000-000000000001',
 'Débit recette '||n,'SOIGNANT_RECHERCHE_MISSIONS','{"inconnu":true}',true,'IMMEDIATE',now()-interval '2 hours'
FROM generate_series(101,101+least(500,greatest(1,public.fn_param_num('alertes_filtres_lot',100)::integer))) n;
SET LOCAL session_replication_role=origin;
DO $preuve$
DECLARE max_lot integer:=least(500,greatest(1,public.fn_param_num('alertes_filtres_lot',100)::integer)); n integer; q bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='email-cron-hourly-immediate' AND schedule='* * * * *' AND active=false)
 THEN RAISE EXCEPTION 'Drain non minutely ou activé avant les sondes'; END IF;
 SELECT count(*) INTO q FROM public.email_queue;
 PERFORM public.fn_evaluer_alertes_filtres(NULL);
 SELECT count(*) INTO n FROM public.filtres_sauvegardes WHERE utilisateur_id='69400000-0000-4000-8000-000000000001' AND dernier_check_le=now();
 IF n<>max_lot THEN RAISE EXCEPTION 'Lot attendu %, observé %',max_lot,n; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.filtres_sauvegardes WHERE utilisateur_id='69400000-0000-4000-8000-000000000001' AND dernier_check_le<now()-interval '1 hour')
 THEN RAISE EXCEPTION 'Lot a consommé une recherche de trop'; END IF;
 PERFORM public.fn_evaluer_alertes_filtres(NULL);
 SELECT count(*) INTO n FROM public.filtres_sauvegardes WHERE utilisateur_id='69400000-0000-4000-8000-000000000001' AND dernier_check_le=now();
 IF n<>max_lot+1 THEN RAISE EXCEPTION 'Recherche restante non reprise au lot suivant'; END IF;
 PERFORM public.fn_evaluer_alertes_filtres(NULL);
 IF (SELECT count(*) FROM public.email_queue)<>q THEN RAISE EXCEPTION 'Aucun résultat ne doit générer un envoi'; END IF;
 IF to_regclass('public.idx_email_queue_attente_date_id') IS NULL OR to_regclass('public.idx_filtres_sauvegardes_alertes_echeance') IS NULL
 THEN RAISE EXCEPTION 'Index de drainage absent'; END IF;
END $preuve$;
ROLLBACK;
