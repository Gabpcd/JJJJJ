-- ============================================================
-- Tests CP-LITIGES-7a FIX 10 — AT TIME ZONE Europe/Paris
-- ============================================================
-- Prérequis : 20260417130709_fix10_timezone_europe_paris.sql appliquée.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix10.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 10 =='

-- [1] prosrc de fn_ajouter_jours_ouvres contient AT TIME ZONE 'Europe/Paris'
SELECT CASE
  WHEN prosrc ILIKE '%AT TIME ZONE%Europe/Paris%'
    THEN '[10.1] OK — AT TIME ZONE Europe/Paris présent dans prosrc'
  ELSE '[10.1] FAIL — absent'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_ajouter_jours_ouvres';

-- [2] Régression : vendredi 10h Paris + 1 ouvré = lundi 10h Paris
-- (cas nominal déjà couvert par cp2, revalidé ici)
SELECT CASE
  WHEN public.fn_ajouter_jours_ouvres('2026-04-17 10:00:00+02'::timestamptz, 1)
       AT TIME ZONE 'Europe/Paris'
     = '2026-04-20 10:00:00'::timestamp
    THEN '[10.2] OK — vendredi 10h Paris + 1 ouvré = lundi 10h Paris'
  ELSE '[10.2] FAIL — résultat : '
     || public.fn_ajouter_jours_ouvres('2026-04-17 10:00:00+02'::timestamptz, 1)::text
END;

-- [3] Cas TZ-bug : lundi 01h Paris + 5 ouvrés saute le 1er mai (vendredi
-- férié Paris) et retourne lundi 2026-05-04 01h Paris, pas mardi 05/05.
-- Sans le fix, DOW/DATE évalués en UTC voyaient '2026-04-30' jeudi UTC et
-- ne skippaient pas le 1er mai.
DO $$
DECLARE
  v_result_utc TIMESTAMPTZ;
  v_result_paris TIMESTAMP;
  v_is_feried_1_mai BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.jours_feries_fr WHERE date_ferie = '2026-05-01')
    INTO v_is_feried_1_mai;
  IF NOT v_is_feried_1_mai THEN
    RAISE NOTICE '[10.3] SKIP — 2026-05-01 absent de jours_feries_fr';
    RETURN;
  END IF;
  v_result_utc := public.fn_ajouter_jours_ouvres('2026-04-27 01:00:00+02'::timestamptz, 5);
  v_result_paris := v_result_utc AT TIME ZONE 'Europe/Paris';
  IF v_result_paris = '2026-05-04 01:00:00'::timestamp THEN
    RAISE NOTICE '[10.3] OK — lundi 01h Paris + 5 ouvrés saute 1er mai férié → lundi 04/05 01h Paris';
  ELSE
    RAISE NOTICE '[10.3] FAIL — résultat Paris : % (attendu 2026-05-04 01:00)', v_result_paris;
  END IF;
END $$;

-- [4] Régression négatif : lundi - 1 ouvré = vendredi (cas cp2 T1.4)
SELECT CASE
  WHEN public.fn_ajouter_jours_ouvres('2026-04-20 10:00:00+02'::timestamptz, -1)
       AT TIME ZONE 'Europe/Paris'
     = '2026-04-17 10:00:00'::timestamp
    THEN '[10.4] OK — lundi 10h Paris - 1 ouvré = vendredi 10h Paris'
  ELSE '[10.4] FAIL'
END;

-- [5] Cas DST (passage heure d'hiver, dim 2026-10-25 à 03h→02h Paris) :
-- vendredi 24/10 10h Paris + 1 ouvré = lundi 27/10 10h Paris (pas 09h).
-- Test que l'heure wall-clock Paris est préservée à travers DST.
SELECT CASE
  WHEN (public.fn_ajouter_jours_ouvres('2026-10-23 10:00:00+02'::timestamptz, 1)
        AT TIME ZONE 'Europe/Paris')::time
     = '10:00:00'::time
    THEN '[10.5] OK — wall-clock Paris 10h préservée à travers DST oct 2026'
  ELSE '[10.5] FAIL — heure wall-clock = '
     || (public.fn_ajouter_jours_ouvres('2026-10-23 10:00:00+02'::timestamptz, 1)
         AT TIME ZONE 'Europe/Paris')::time::text
END;
