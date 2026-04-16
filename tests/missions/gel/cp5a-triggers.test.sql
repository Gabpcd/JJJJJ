-- ============================================================
-- CP5a Step 4 — Tests refonte 4 triggers
-- Exécutés sur Supabase prod 2026-04-16
-- ============================================================

-- ══════════════════════════════════════════════════════════════
-- Test 4a-night: créneau 21:00-03:00 Paris (full night)
-- Result: PASS — heures_nuit = 6.00
-- ══════════════════════════════════════════════════════════════
-- Créneau: 19:00 UTC → 01:00+1 UTC = 21:00-03:00 Paris
-- Night window 21:00-06:00: all 6h are night
-- heures_nuit = 6.00 ✓

-- ══════════════════════════════════════════════════════════════
-- Test 4a-dimanche: créneau dimanche 8h-14h Paris
-- Result: PASS — heures_dimanche = 6.00, heures_nuit = 0
-- ══════════════════════════════════════════════════════════════
-- April 19 2026 is Sunday. 06:00-12:00 UTC = 08:00-14:00 Paris
-- heures_dimanche = 6.00 ✓
-- heures_nuit = 0.00 (daytime) ✓

-- ══════════════════════════════════════════════════════════════
-- Test 4a-pause: créneau avec pause au milieu
-- Result: PASS — duree=10h (pause 2h exclue), night=1h
-- ══════════════════════════════════════════════════════════════
-- Work 08:00-12:00 UTC (4h) + Pause 12:00-14:00 UTC (2h) + Work 14:00-20:00 UTC (6h)
-- duree_heures = 10.00 (pause excluded) ✓
-- heures_nuit = 1.00 (21:00-22:00 Paris from afternoon shift) ✓
-- nb_creneaux = 3 ✓

-- ══════════════════════════════════════════════════════════════
-- Test 4b: dec_refuser_chevauchement_soignant
-- Result: N/A — NO CODE CHANGE (D1: span-based, validated)
-- ══════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════
-- Test 4c: dec_verifier_plafond_48h — sanity check
-- Result: PASS — mission 0132 (12h) assigned without 48h block
-- ══════════════════════════════════════════════════════════════
-- Soignant has ~21h this week (12h + 9h). Well under 48h.
-- Assignment succeeds. Trigger uses créneaux now.

-- ══════════════════════════════════════════════════════════════
-- Test 4d: dec_verifier_repos_11h — block on 25min gap
-- Result: PASS — blocked with "0.4 heures au lieu de 11h"
-- ══════════════════════════════════════════════════════════════
-- Mission 0133 (19:00 fin) → next mission at 19:25 → gap 25min < 11h
-- RAISE: "Repos insuffisant après mission : 0.4 heures" ✓
-- Uses créneaux (MAX fin WHERE NOT est_pause) for actual work end ✓

-- ══════════════════════════════════════════════════════════════
-- Bugs fixed during testing:
-- 1. RAISE format: %.1f → ROUND(v_ecart, 1) (PL/pgSQL doesn't support printf)
-- 2. conformite_travail columns: type_violation/details → type_controle/resultat/details_violation
-- 3. Phase 2 sync needs admin JWT context for protectors to allow heures recalculation
-- ══════════════════════════════════════════════════════════════
