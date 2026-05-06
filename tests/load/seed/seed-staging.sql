-- Seed staging pour les tests de charge k6.
--
-- Crée 500 missions TERMINEE rattachées au compte test étab fixe
-- (playwright-etab@jolene.app) pour le scenario F (cron weekly invoicing).
--
-- IDEMPOTENT : le DELETE WHERE intitule LIKE '[loadtest]%' purge avant insert.
--
-- À déclencher via le workflow `deploy-supabase-staging.yml` avec input
-- `seed_load_test_data=true`, ou en exécution directe SQL Editor staging.

DO $$
DECLARE
  v_etab_id uuid;
  v_soignant_id uuid;
  v_mission_id uuid;
  v_mission_count integer := 500;
  v_now timestamptz := NOW();
  i integer;
BEGIN
  -- Récupérer l'id du compte test étab fixe (seedé via 20260503050000)
  SELECT id INTO v_etab_id
  FROM auth.users
  WHERE email = 'playwright-etab@jolene.app'
  LIMIT 1;

  IF v_etab_id IS NULL THEN
    RAISE EXCEPTION 'Compte playwright-etab@jolene.app non seedé. Appliquer la migration 20260503050000 d''abord.';
  END IF;

  -- Récupérer un soignant test pour assignation
  SELECT id INTO v_soignant_id
  FROM auth.users
  WHERE email = 'playwright-soignant@jolene.app'
  LIMIT 1;

  IF v_soignant_id IS NULL THEN
    RAISE EXCEPTION 'Compte playwright-soignant@jolene.app non seedé.';
  END IF;

  -- Cleanup : purge les anciennes missions [loadtest]
  DELETE FROM public.factures_honoraires
  WHERE mission_id IN (
    SELECT id FROM public.missions WHERE intitule LIKE '[loadtest]%'
  );
  DELETE FROM public.candidatures
  WHERE mission_id IN (
    SELECT id FROM public.missions WHERE intitule LIKE '[loadtest]%'
  );
  DELETE FROM public.missions WHERE intitule LIKE '[loadtest]%';

  -- Seed : 500 missions TERMINEE prêtes à être facturées
  FOR i IN 1..v_mission_count LOOP
    INSERT INTO public.missions (
      etablissement_id,
      soignant_assigne_id,
      intitule,
      description,
      profession_requise,
      service,
      debut_le,
      fin_le,
      taux_horaire_base,
      statut,
      mode_attribution,
      created_at,
      updated_at
    ) VALUES (
      v_etab_id,
      v_soignant_id,
      '[loadtest] Mission #' || i,
      'Mission seedée pour test charge cron weekly-invoicing',
      'IDE',
      'Test',
      v_now - INTERVAL '14 days' + (i || ' minutes')::interval,
      v_now - INTERVAL '14 days' + (i || ' minutes')::interval + INTERVAL '8 hours',
      30.0,
      'TERMINEE',
      'CANDIDATURE',
      v_now - INTERVAL '14 days',
      v_now - INTERVAL '7 days'
    );
  END LOOP;

  RAISE NOTICE 'Seed terminé : % missions [loadtest] TERMINEE créées.', v_mission_count;
END $$;

-- Vérification
SELECT
  COUNT(*) AS total_missions_loadtest,
  COUNT(*) FILTER (WHERE statut = 'TERMINEE') AS terminees
FROM public.missions
WHERE intitule LIKE '[loadtest]%';
