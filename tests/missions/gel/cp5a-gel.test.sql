-- ============================================================
-- CP5a — Tests de gel/dégel/protection
-- Exécutés sur Supabase prod 2026-04-16
-- Mission test: e0000000-0000-0000-0000-000000000132 (OUVERTE)
-- Admin: 07dae751-4be3-468d-b8ec-c4b8176a596f
-- Soignant: 57d814fb-c09b-4528-b4e0-ed8369328bd3
-- ============================================================

-- ══════════════════════════════════════════════════════════════
-- Test A: GEL NORMAL (OUVERTE → ASSIGNEE)
-- Expected: 8 _fige populated, fige_le = now()
-- Result: PASS
-- ══════════════════════════════════════════════════════════════
SELECT set_config('request.jwt.claims', '{"sub": "07dae751-4be3-468d-b8ec-c4b8176a596f", "role": "authenticated"}', true);

UPDATE missions
SET statut = 'ASSIGNEE', soignant_assigne_id = '57d814fb-c09b-4528-b4e0-ed8369328bd3'
WHERE id = 'e0000000-0000-0000-0000-000000000132';

-- Verify: taux_horaire_base_fige=38, nuit=25, dim=50, fer=100,
--         h_debut=21:00, h_fin=06:00, commission=15, fige_le NOT NULL

-- ══════════════════════════════════════════════════════════════
-- Test B: DEGEL (ASSIGNEE → OUVERTE)
-- Expected: 8 _fige = NULL, journaux_audit DEGEL_APPLIED
-- Result: PASS
-- ══════════════════════════════════════════════════════════════
UPDATE missions SET statut = 'OUVERTE', soignant_assigne_id = NULL
WHERE id = 'e0000000-0000-0000-0000-000000000132';

-- Verify: all _fige NULL, fige_le NULL
-- Verify: journaux_audit has DEGEL_APPLIED with old_snapshot.taux_horaire_base_fige=38

-- ══════════════════════════════════════════════════════════════
-- Test C: PROTECTION SANS BYPASS
-- Expected: RAISE EXCEPTION check_violation
-- Result: PASS
-- ══════════════════════════════════════════════════════════════
-- (re-gel first)
UPDATE missions SET statut = 'ASSIGNEE', soignant_assigne_id = '57d814fb-c09b-4528-b4e0-ed8369328bd3'
WHERE id = 'e0000000-0000-0000-0000-000000000132';

-- This should RAISE:
-- UPDATE missions SET taux_horaire_base = 999
-- WHERE id = 'e0000000-0000-0000-0000-000000000132';
-- Error: Modification du champ "taux_horaire_base" interdite après assignation

-- ══════════════════════════════════════════════════════════════
-- Test D: PROTECTION AVEC BYPASS ADMIN
-- Expected: UPDATE passes, journaux_audit OVERRIDE_CHAMP_POST_GEL
-- Result: PASS
-- ══════════════════════════════════════════════════════════════
SELECT set_config('jolene.admin_override_gel', 'e0000000-0000-0000-0000-000000000132', true);
SELECT set_config('jolene.admin_override_reason', 'Test CP5a', true);

UPDATE missions SET intitule = 'Test override admin CP5a'
WHERE id = 'e0000000-0000-0000-0000-000000000132';

-- Verify: intitule changed, journaux_audit has OVERRIDE_CHAMP_POST_GEL
--         with fields_modified.intitule.old="Sage-femme — Maternité"

-- ══════════════════════════════════════════════════════════════
-- Test E: RE-GEL APRÈS DÉSISTEMENT
-- Expected: taux_majoration_nuit_fige = new etab value (30), not old (25)
-- Result: PASS
-- ══════════════════════════════════════════════════════════════
-- DEGEL
UPDATE missions SET statut = 'OUVERTE', soignant_assigne_id = NULL
WHERE id = 'e0000000-0000-0000-0000-000000000132';

-- Change etab rate
UPDATE etablissements SET taux_majoration_nuit_pourcent = 30
WHERE id = 'b0000000-0000-0000-0000-000000000013';

-- RE-GEL
UPDATE missions SET statut = 'ASSIGNEE', soignant_assigne_id = '57d814fb-c09b-4528-b4e0-ed8369328bd3'
WHERE id = 'e0000000-0000-0000-0000-000000000132';

-- Verify: taux_majoration_nuit_fige = 30

-- Restore
UPDATE etablissements SET taux_majoration_nuit_pourcent = 25
WHERE id = 'b0000000-0000-0000-0000-000000000013';

-- ══════════════════════════════════════════════════════════════
-- Test F: SYNC CRÉNEAU SUR MISSION GELÉE
-- Expected: _fige unchanged, timing updated
-- Result: PASS
-- ══════════════════════════════════════════════════════════════
INSERT INTO mission_creneaux (mission_id, debut, fin, est_pause, ordre)
VALUES ('e0000000-0000-0000-0000-000000000132', '2026-04-16 20:00+00', '2026-04-16 21:00+00', false, 2);

-- Verify: fin_le=21:00, duree=13h, nb_creneaux=2
--         _fige UNCHANGED (38/15/30)

DELETE FROM mission_creneaux
WHERE mission_id = 'e0000000-0000-0000-0000-000000000132' AND ordre = 2;

-- ══════════════════════════════════════════════════════════════
-- Test G: PROTECTION DES 11 CHAMPS
-- Expected: each of 11 fields raises check_violation
-- Result: PASS (11/11)
-- ══════════════════════════════════════════════════════════════
-- Fields tested:
--  1. taux_horaire_base        PASS
--  2. intitule                 PASS
--  3. profession_requise       PASS
--  4. taux_horaire_base_fige   PASS
--  5. taux_majoration_nuit_fige PASS
--  6. taux_majoration_dimanche_fige PASS
--  7. taux_majoration_ferie_fige PASS
--  8. heure_debut_nuit_fige    PASS
--  9. heure_fin_nuit_fige      PASS
-- 10. taux_commission_fige     PASS
-- 11. fige_le                  PASS

-- ══════════════════════════════════════════════════════════════
-- Bugs discovered during testing:
-- 1. journaux_audit.action CHECK constraint missing DEGEL_APPLIED/OVERRIDE_CHAMP_POST_GEL → fixed
-- 2. journaux_audit.type_acteur CHECK: 'system'→'SYSTEME', 'admin'→'ADMIN_PLATEFORME' → fixed
-- 3. dec_alerte_mission_liberee: niveau_urgence='CRITIQUE' but column is integer → fixed to 3
-- ══════════════════════════════════════════════════════════════
