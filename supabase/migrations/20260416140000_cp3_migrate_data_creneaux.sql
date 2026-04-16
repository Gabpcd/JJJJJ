-- ============================================================
-- Sub-PR 1 / Checkpoint 3
-- Data migration: create 1 créneau per existing mission
-- + reconstruct mission_series from [SERIE_ID:...] tags
-- ============================================================
-- CONTEXT:
-- - 268 missions in prod (213 TERMINEE, 43 ANNULEE, etc.)
-- - 3 missions skipped: span > 24h (all ANNULEE, invalid test data)
-- - 1 série found: SERIE_DEMO_001 (8 missions, etab b0000000...0002)
--
-- LESSON LEARNED: Using jolene.sync_in_progress bypass for UPDATE on
-- missions is NOT SAFE for financial integrity. The bypass disables
-- dec_proteger_mission_soignant, which normally reverts financial
-- recalculations from other triggers. Instead, use DISABLE TRIGGER USER
-- for bulk UPDATEs on missions during migration.
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. Create 1 créneau per mission (excluding 3 with span > 24h)
-- ──────────────────────────────────────────────────────────────
-- INSERT into mission_creneaux triggers trg_sync_creneaux which
-- would UPDATE missions. We set sync bypass to prevent this.
SELECT set_config('jolene.sync_in_progress', 'true', false);

INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre)
SELECT id, debut_le, fin_le, false, 1
FROM missions
WHERE debut_le IS NOT NULL
  AND fin_le IS NOT NULL
  AND EXTRACT(EPOCH FROM (fin_le - debut_le)) <= 86400;
-- Expected: 265 rows

SELECT set_config('jolene.sync_in_progress', 'false', false);

-- ──────────────────────────────────────────────────────────────
-- 2. Update nb_creneaux on migrated missions
-- ──────────────────────────────────────────────────────────────
-- DISABLE TRIGGER USER to prevent financial cascade from
-- 30+ BEFORE UPDATE triggers on missions.
ALTER TABLE missions DISABLE TRIGGER USER;

UPDATE missions SET nb_creneaux = 1
WHERE id IN (SELECT DISTINCT mission_id FROM mission_creneaux);

ALTER TABLE missions ENABLE TRIGGER USER;

-- ──────────────────────────────────────────────────────────────
-- 3. Reconstruct mission_series from [SERIE_ID:...] tags
-- ──────────────────────────────────────────────────────────────
ALTER TABLE missions DISABLE TRIGGER USER;

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

    UPDATE missions SET description = TRIM(REGEXP_REPLACE(description, '\s*\[SERIE_ID:[^\]]+\]\s*', ' ', 'g'))
    WHERE serie_id = v_serie_id;

    RAISE NOTICE 'Serie % : % missions linkées, etab=%', v_tag, v_updated, v_etab_id;
  END LOOP;
END $$;

ALTER TABLE missions ENABLE TRIGGER USER;
