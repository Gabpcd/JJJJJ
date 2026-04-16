-- ============================================================
-- Sub-PR 1 / Checkpoint 3
-- Data migration: create 1 créneau per existing mission
-- + reconstruct mission_series from [SERIE_ID:...] tags
-- ============================================================
-- CONTEXT:
-- - 268 missions in prod (213 TERMINEE, 43 ANNULEE, etc.)
-- - 3 missions skipped: span > 24h (all ANNULEE, invalid test data)
-- - 1 série found: SERIE_DEMO_001 (8 missions, etab b0000000...0002)
-- - jolene.sync_in_progress bypass used to avoid trigger cascade
--   during bulk INSERT (sync runs manually at the end)
-- ============================================================

-- Enable sync bypass for bulk migration
SELECT set_config('jolene.sync_in_progress', 'true', false);

-- ──────────────────────────────────────────────────────────────
-- 1. Create 1 créneau per mission (excluding 3 with span > 24h)
-- ──────────────────────────────────────────────────────────────
INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre)
SELECT id, debut_le, fin_le, false, 1
FROM missions
WHERE debut_le IS NOT NULL
  AND fin_le IS NOT NULL
  AND EXTRACT(EPOCH FROM (fin_le - debut_le)) <= 86400;
-- Expected: 265 rows

-- ──────────────────────────────────────────────────────────────
-- 2. Update nb_creneaux on migrated missions
-- ──────────────────────────────────────────────────────────────
UPDATE missions SET nb_creneaux = 1
WHERE id IN (SELECT DISTINCT mission_id FROM mission_creneaux);

-- ──────────────────────────────────────────────────────────────
-- 3. Reconstruct mission_series from [SERIE_ID:...] tags
-- ──────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_tag text;
  v_etab_id uuid;
  v_cree_le timestamptz;
  v_nb integer;
  v_serie_id uuid;
  v_updated integer;
BEGIN
  FOR v_tag, v_etab_id, v_cree_le, v_nb IN
    SELECT
      substring(description FROM '\[SERIE_ID:([^\]]+)\]'),
      MIN(etablissement_id::text)::uuid,
      MIN(cree_le),
      COUNT(*)
    FROM missions
    WHERE description LIKE '%[SERIE_ID:%'
    GROUP BY substring(description FROM '\[SERIE_ID:([^\]]+)\]')
  LOOP
    v_serie_id := gen_random_uuid();

    INSERT INTO mission_series (id, etablissement_id, cree_par, motif, nb_missions_prevues, cree_le)
    VALUES (v_serie_id, v_etab_id, NULL, 'Migration CP3 — série ' || v_tag, v_nb, v_cree_le);

    UPDATE missions SET serie_id = v_serie_id
    WHERE description LIKE '%[SERIE_ID:' || v_tag || ']%';
    GET DIAGNOSTICS v_updated = ROW_COUNT;

    -- Clean the tag from description
    UPDATE missions SET description = TRIM(REGEXP_REPLACE(description, '\s*\[SERIE_ID:[^\]]+\]\s*', ' ', 'g'))
    WHERE serie_id = v_serie_id;

    RAISE NOTICE 'Serie % : % missions linkées, etab=%', v_tag, v_updated, v_etab_id;
  END LOOP;
END $$;

-- ──────────────────────────────────────────────────────────────
-- 4. Disable sync bypass
-- ──────────────────────────────────────────────────────────────
SELECT set_config('jolene.sync_in_progress', 'false', false);
