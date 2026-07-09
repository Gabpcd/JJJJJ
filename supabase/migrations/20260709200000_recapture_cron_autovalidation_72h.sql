-- Lot 13 — Recapture de la planification d'auto-validation des présences 72h
-- (règle 9.0 : le cron tournait en PROD hors repo — dérive repo↔prod).
--
-- État prod constaté le 09/07/2026 :
--   jobid 26 « jolene_valider_presences_72h »  (15 */6 * * *) → fn_valider_presences_72h_auto()  ← CONSERVÉ
--   jobid  8 « auto-valider-presences-72h »    (0 6 * * *)    → fn_auto_valider_presences_72h()  ← DOUBLON (wrapper, quotidien)
-- Les deux appellent la même logique idempotente ; le doublon est retiré, la
-- planification 6h est recapturée sous son nom pour que les rebuilds
-- (et le registre schema_migrations) la portent. C'est CE cron qui déclenche la
-- libération escrow « auto-72h » promise par la CGU §4.6.
--
-- Garde pg_cron : les BRANCHES Supabase n'ont pas l'extension (relation
-- cron.job absente) — la migration s'y rejoue en no-op propre.

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron absent (branche preview) — planification 72h sautée.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-valider-presences-72h') THEN
    PERFORM cron.unschedule('auto-valider-presences-72h');
  END IF;

  -- cron.schedule remplace le job existant du même nom (idempotent).
  PERFORM cron.schedule(
    'jolene_valider_presences_72h',
    '15 */6 * * *',
    'SELECT public.fn_valider_presences_72h_auto()'
  );
END $do$;
