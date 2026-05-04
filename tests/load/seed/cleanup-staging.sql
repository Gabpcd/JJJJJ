-- Cleanup staging post tests de charge.
--
-- Supprime :
-- - Toutes les missions/candidatures/factures [loadtest]
-- - Les comptes auth créés par les scénarios A et D (loadtest-*)
-- - Préserve les comptes test fixes (playwright-soignant, playwright-etab)
--
-- À exécuter via SQL Editor staging ou via le workflow deploy-staging avec
-- un input dédié si besoin (non implémenté par défaut).

DO $$
DECLARE
  v_user record;
  v_count_users integer := 0;
  v_count_missions integer := 0;
BEGIN
  -- 1. Cleanup factures + candidatures + missions [loadtest]
  DELETE FROM public.factures_honoraires
  WHERE mission_id IN (
    SELECT id FROM public.missions WHERE intitule LIKE '[loadtest]%'
  );

  DELETE FROM public.candidatures
  WHERE mission_id IN (
    SELECT id FROM public.missions WHERE intitule LIKE '[loadtest]%'
  );

  DELETE FROM public.missions WHERE intitule LIKE '[loadtest]%';
  GET DIAGNOSTICS v_count_missions = ROW_COUNT;

  -- 2. Cleanup comptes auth.users loadtest-*
  --    Les FK ON DELETE CASCADE depuis profiles → soignants/etablissements
  --    propagent la suppression.
  FOR v_user IN
    SELECT id, email FROM auth.users
    WHERE email LIKE 'loadtest-%@jolene.app'
       OR email LIKE 'loadtest-soignant-%@jolene.app'
  LOOP
    DELETE FROM auth.users WHERE id = v_user.id;
    v_count_users := v_count_users + 1;
  END LOOP;

  RAISE NOTICE 'Cleanup terminé : % missions [loadtest], % comptes auth supprimés.',
    v_count_missions, v_count_users;
END $$;
