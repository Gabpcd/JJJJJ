-- AUDIT INFRA J2.3.B.AUDIT — Fix grants service_role sur 62 tables manquantes.
--
-- Contexte : audit infrastructure complète post-bug email-cron 401. 62 tables
-- publiques n'avaient AUCUN grant pour service_role, ce qui causait des
-- silencieux retours vides ou des erreurs `permission denied` étouffées par
-- les `.catch(()=>{})` des edge functions. Tables critiques affectées :
--   - email_queue (cron processait silencieusement 0 rows)
--   - emails_envoyes / sms_envoyes (logging jamais écrit)
--   - bulletins_paie / cotisations_sociales (paie)
--   - candidatures / contrats_mission (onboarding emails J3/J7)
--   - factor_advances / cessions_creance (cession Defacto)
--   - litiges / messages_litige / reclamations (litige escalation)
--   - preferences_notifications (fn_doit_notifier dans send-* fns)
--   - tokens_push (send-push)
--   - chorus_submissions (sync-chorus-status)
--   - stripe_refunds_queue / stripe_transfers (process-stripe-refunds)
--   - et 50+ autres
--
-- Politique : service_role obtient SELECT, INSERT, UPDATE par défaut. DELETE
-- et TRUNCATE restent non-grantés pour préserver l'invariant "service_role
-- ne supprime jamais" (immutable par design, sauf cas explicites comme
-- partages_rib qui a déjà DELETE séparément).

DO $$
DECLARE r record; cnt int := 0;
BEGIN
  FOR r IN
    SELECT t.tablename FROM pg_tables t
    WHERE t.schemaname='public'
      AND t.tablename NOT IN (
        SELECT DISTINCT table_name FROM information_schema.role_table_grants
        WHERE grantee='service_role' AND table_schema='public'
      )
  LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON public.%I TO service_role', r.tablename);
    cnt := cnt + 1;
  END LOOP;
  RAISE NOTICE 'GRANTed SELECT/INSERT/UPDATE on % previously-ungranted tables', cnt;
END $$;

NOTIFY pgrst, 'reload schema';
