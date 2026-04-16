-- ============================================================
-- CP5b Integration Tests — 10 Scénarios (A–J)
-- ============================================================
-- Exécuter sur la base réelle Jolene (Supabase).
-- Chaque scénario tourne dans BEGIN/ROLLBACK — aucune donnée persistante.
--
-- Pré-requis :
--   Mission e0000000-0000-0000-0000-000000000132 (EN_COURS, gelée,
--     soignant 57d814fb..., PREVISIONNEL 08:00–20:00 UTC April 16).
--   Etab admin 8500dba5-2c73-4035-8383-b854d59a9864
--   Soignant  57d814fb-c09b-4528-b4e0-ed8369328bd3
--
-- Résultats attendus : toutes les lignes = PASS.
-- ============================================================

-- ══════════════════════════════════════════════════════════════
-- A — Cycle nominal complet : 4 scans → 2 EFFECTIF → prefact OK
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
SET LOCAL jolene.sync_in_progress='true';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';
SET LOCAL jolene.sync_in_progress='false';
UPDATE missions SET prochain_type_scan='OUVERTURE',nb_scans=0,
  debut_effectif=NULL,fin_effective=NULL,duree_heures_effective=NULL WHERE id='e0000000-0000-0000-0000-000000000132';
UPDATE missions SET duree_heures=duree_heures WHERE id='e0000000-0000-0000-0000-000000000132';

SET LOCAL request.jwt.claims='{"sub":"57d814fb-c09b-4528-b4e0-ed8369328bd3","role":"authenticated"}';

-- Pair 1: OUVERTURE + FERMETURE
DO $$ DECLARE c text; BEGIN SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132'; PERFORM fn_scanner_code_pointage(c,NULL); END $$;
UPDATE scans_pointage SET scanne_le=scanne_le-INTERVAL'5min' WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND numero_scan=1;
DO $$ DECLARE c text; BEGIN SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132'; PERFORM fn_scanner_code_pointage(c,NULL); END $$;
UPDATE scans_pointage SET scanne_le=scanne_le-INTERVAL'5min' WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND numero_scan=2;

INSERT INTO tr SELECT 'A','A1_pair1',CASE WHEN nb_scans=2 AND prochain_type_scan='OUVERTURE' THEN 'PASS' ELSE 'FAIL' END,
  format('s=%s n=%s',nb_scans,prochain_type_scan) FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';

-- Relocate closed EFFECTIF 1 to morning to avoid overlap with pair 2
UPDATE mission_creneaux SET debut='2026-04-16 08:00+00',fin='2026-04-16 14:00+00'
WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';

-- Pair 2: OUVERTURE + FERMETURE
DO $$ DECLARE c text; BEGIN SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132'; PERFORM fn_scanner_code_pointage(c,NULL); END $$;
UPDATE scans_pointage SET scanne_le=scanne_le-INTERVAL'5min' WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND numero_scan=3;
DO $$ DECLARE c text; BEGIN SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132'; PERFORM fn_scanner_code_pointage(c,NULL); END $$;

-- Relocate EFFECTIF 2 to afternoon
DO $$ DECLARE v_id uuid; BEGIN
  SELECT id INTO v_id FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132'
    AND type_creneau='EFFECTIF' ORDER BY debut DESC LIMIT 1;
  UPDATE mission_creneaux SET debut='2026-04-16 14:00+00',fin='2026-04-16 19:00+00' WHERE id=v_id;
END $$;

-- Assertions
INSERT INTO tr SELECT 'A','A2_4scans',CASE WHEN nb_scans=4 AND prochain_type_scan='OUVERTURE' THEN 'PASS' ELSE 'FAIL' END,
  format('s=%s n=%s',nb_scans,prochain_type_scan) FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';

INSERT INTO tr SELECT 'A','A3_2eff',CASE WHEN COUNT(*)=2 AND COUNT(*) FILTER(WHERE fin IS NOT NULL)=2 THEN 'PASS' ELSE 'FAIL' END,
  format('cnt=%s cl=%s',COUNT(*),COUNT(*) FILTER(WHERE fin IS NOT NULL))
FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';

INSERT INTO tr SELECT 'A','A4_types',
  CASE WHEN string_agg(type_scan,',' ORDER BY numero_scan)='OUVERTURE,FERMETURE,OUVERTURE,FERMETURE' THEN 'PASS' ELSE 'FAIL' END,
  string_agg(type_scan||'#'||numero_scan::text,',' ORDER BY numero_scan)
FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';

DO $$ DECLARE v jsonb; BEGIN
  v:=fn_verifier_pre_facturation('e0000000-0000-0000-0000-000000000132'::uuid);
  INSERT INTO tr VALUES('A','A5_prefact',CASE WHEN (v->>'ok')::bool AND v->>'source_facturation'='EFFECTIF' THEN 'PASS' ELSE 'FAIL' END,v::text);
END $$;

INSERT INTO tr SELECT 'A','A6_duree',CASE WHEN duree_heures=duree_heures_effective AND duree_heures_effective IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  format('dur=%s eff=%s',duree_heures,duree_heures_effective) FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';

SELECT * FROM tr ORDER BY t;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- B — Oubli de scan fin + fn_declarer_fin_retroactive
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
SET LOCAL jolene.sync_in_progress='true';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';
SET LOCAL jolene.sync_in_progress='false';
UPDATE missions SET prochain_type_scan='OUVERTURE',nb_scans=0,
  debut_effectif=NULL,fin_effective=NULL,duree_heures_effective=NULL WHERE id='e0000000-0000-0000-0000-000000000132';
UPDATE missions SET duree_heures=duree_heures WHERE id='e0000000-0000-0000-0000-000000000132';
SET LOCAL request.jwt.claims='{"sub":"57d814fb-c09b-4528-b4e0-ed8369328bd3","role":"authenticated"}';

DO $$ DECLARE c text; BEGIN SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132'; PERFORM fn_scanner_code_pointage(c,NULL); END $$;
UPDATE scans_pointage SET scanne_le=scanne_le-INTERVAL'5min' WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND numero_scan=1;

INSERT INTO tr SELECT 'B','B1_open',CASE WHEN prochain_type_scan='FERMETURE' THEN 'PASS' ELSE 'FAIL' END,
  format('next=%s',prochain_type_scan) FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';

SELECT fn_declarer_fin_retroactive('e0000000-0000-0000-0000-000000000132'::uuid, now()+INTERVAL'2h', 'Oubli B');

INSERT INTO tr SELECT 'B','B2_retro',CASE WHEN prochain_type_scan='OUVERTURE' AND nb_scans=2 THEN 'PASS' ELSE 'FAIL' END,
  format('next=%s s=%s',prochain_type_scan,nb_scans) FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';
INSERT INTO tr SELECT 'B','B3_scan',CASE WHEN code_saisi='RETROACTIF' AND validation_etab_requise THEN 'PASS' ELSE 'FAIL' END,
  format('code=%s val=%s',code_saisi,validation_etab_requise)
FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND numero_scan=2;
INSERT INTO tr SELECT 'B','B4_closed',CASE WHEN COUNT(*) FILTER(WHERE fin IS NOT NULL)=1 THEN 'PASS' ELSE 'FAIL' END,
  format('cl=%s',COUNT(*) FILTER(WHERE fin IS NOT NULL))
FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';

SELECT * FROM tr ORDER BY t;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- C — Désistement + ré-attribution
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);
SET LOCAL request.jwt.claims='{"sub":"8500dba5-2c73-4035-8383-b854d59a9864","role":"authenticated"}';

INSERT INTO missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut)
VALUES ('77770000-0000-0000-0000-00000000000c','b0000000-0000-0000-0000-000000000001','C','IDE',
  '2026-04-25 06:00+00','2026-04-25 16:00+00',30,'OUVERTE');
INSERT INTO mission_creneaux (mission_id,debut,fin,est_pause,ordre,type_creneau)
VALUES ('77770000-0000-0000-0000-00000000000c','2026-04-25 06:00+00','2026-04-25 16:00+00',false,1,'PREVISIONNEL');

UPDATE missions SET statut='ASSIGNEE',soignant_assigne_id='57d814fb-c09b-4528-b4e0-ed8369328bd3'
WHERE id='77770000-0000-0000-0000-00000000000c';

INSERT INTO tr SELECT 'C','C1_gel',CASE WHEN fige_le IS NOT NULL AND code_pointage_actif IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  format('code=%s',left(code_pointage_actif,4)) FROM missions WHERE id='77770000-0000-0000-0000-00000000000c';

INSERT INTO mission_creneaux (mission_id,debut,fin,est_pause,ordre,type_creneau)
VALUES ('77770000-0000-0000-0000-00000000000c','2026-04-25 06:00+00',NULL,false,2,'EFFECTIF');

UPDATE missions SET statut='OUVERTE' WHERE id='77770000-0000-0000-0000-00000000000c';

INSERT INTO tr SELECT 'C','C2_degel',
  CASE WHEN code_pointage_actif IS NULL AND fige_le IS NULL AND debut_effectif IS NULL THEN 'PASS' ELSE 'FAIL' END,
  format('code=%s fige=%s eff=%s',code_pointage_actif IS NULL,fige_le IS NULL,debut_effectif IS NULL)
FROM missions WHERE id='77770000-0000-0000-0000-00000000000c';

INSERT INTO tr SELECT 'C','C3_cleanup',CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END,
  format('eff=%s',COUNT(*))
FROM mission_creneaux WHERE mission_id='77770000-0000-0000-0000-00000000000c' AND type_creneau='EFFECTIF';

UPDATE missions SET statut='ASSIGNEE',soignant_assigne_id='57d814fb-c09b-4528-b4e0-ed8369328bd3'
WHERE id='77770000-0000-0000-0000-00000000000c';

INSERT INTO tr SELECT 'C','C4_regel',
  CASE WHEN code_pointage_actif IS NOT NULL AND fige_le IS NOT NULL AND prochain_type_scan='OUVERTURE' THEN 'PASS' ELSE 'FAIL' END,
  format('code=%s',left(code_pointage_actif,4)) FROM missions WHERE id='77770000-0000-0000-0000-00000000000c';

SELECT * FROM tr ORDER BY t;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- D — Protection PREVISIONNEL post-gel
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

-- Reuse the gelée mission from C setup
SET LOCAL request.jwt.claims='{"sub":"8500dba5-2c73-4035-8383-b854d59a9864","role":"authenticated"}';
INSERT INTO missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut)
VALUES ('77770000-0000-0000-0000-00000000000d','b0000000-0000-0000-0000-000000000001','D','IDE',
  '2026-04-26 06:00+00','2026-04-26 16:00+00',30,'OUVERTE');
INSERT INTO mission_creneaux (mission_id,debut,fin,est_pause,ordre,type_creneau)
VALUES ('77770000-0000-0000-0000-00000000000d','2026-04-26 06:00+00','2026-04-26 16:00+00',false,1,'PREVISIONNEL');
UPDATE missions SET statut='ASSIGNEE',soignant_assigne_id='57d814fb-c09b-4528-b4e0-ed8369328bd3'
WHERE id='77770000-0000-0000-0000-00000000000d';

DO $$ BEGIN BEGIN
  UPDATE mission_creneaux SET fin=fin+INTERVAL'1h'
  WHERE mission_id='77770000-0000-0000-0000-00000000000d' AND type_creneau='PREVISIONNEL';
  INSERT INTO tr VALUES('D','D1_block','FAIL','no exception');
EXCEPTION WHEN OTHERS THEN
  INSERT INTO tr VALUES('D','D1_block','PASS',left(SQLERRM,60));
END; END $$;

DO $$ BEGIN
  SET LOCAL jolene.admin_override_gel='77770000-0000-0000-0000-00000000000d';
  SET LOCAL jolene.admin_override_reason='D2 bypass';
  BEGIN
    UPDATE mission_creneaux SET fin=fin+INTERVAL'1h'
    WHERE mission_id='77770000-0000-0000-0000-00000000000d' AND type_creneau='PREVISIONNEL';
    INSERT INTO tr VALUES('D','D2_bypass','PASS','update ok');
  EXCEPTION WHEN OTHERS THEN INSERT INTO tr VALUES('D','D2_bypass','FAIL',SQLERRM); END;
END $$;

INSERT INTO tr SELECT 'D','D3_audit',CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'FAIL' END, format('n=%s',COUNT(*))
FROM journaux_audit WHERE action='OVERRIDE_CHAMP_POST_GEL' AND type_ressource='mission_creneaux';

SELECT * FROM tr ORDER BY t;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- E — Sécurité (mauvais soignant, code invalide, anti-doublon)
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
SET LOCAL jolene.sync_in_progress='true';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';
SET LOCAL jolene.sync_in_progress='false';
UPDATE missions SET prochain_type_scan='OUVERTURE',nb_scans=0,
  debut_effectif=NULL,fin_effective=NULL,duree_heures_effective=NULL WHERE id='e0000000-0000-0000-0000-000000000132';
UPDATE missions SET duree_heures=duree_heures WHERE id='e0000000-0000-0000-0000-000000000132';

-- E1: Wrong soignant
SET LOCAL request.jwt.claims='{"sub":"8500dba5-2c73-4035-8383-b854d59a9864","role":"authenticated"}';
DO $$ DECLARE c text; BEGIN
  SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';
  BEGIN PERFORM fn_scanner_code_pointage(c,NULL);
    INSERT INTO tr VALUES('E','E1_wrong','FAIL','no exception');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO tr VALUES('E','E1_wrong','PASS',left(SQLERRM,50));
  END;
END $$;

-- E2: Invalid code
SET LOCAL request.jwt.claims='{"sub":"57d814fb-c09b-4528-b4e0-ed8369328bd3","role":"authenticated"}';
DO $$ BEGIN BEGIN PERFORM fn_scanner_code_pointage('000000',NULL);
  INSERT INTO tr VALUES('E','E2_code','FAIL','no exception');
EXCEPTION WHEN OTHERS THEN
  INSERT INTO tr VALUES('E','E2_code','PASS',left(SQLERRM,50));
END; END $$;

-- E3: Anti-doublon
DO $$ DECLARE c text; BEGIN SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132'; PERFORM fn_scanner_code_pointage(c,NULL); END $$;
DO $$ DECLARE c text; BEGIN
  SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';
  BEGIN PERFORM fn_scanner_code_pointage(c,NULL);
    INSERT INTO tr VALUES('E','E3_doublon','FAIL','no exception');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO tr VALUES('E','E3_doublon','PASS',left(SQLERRM,60));
  END;
END $$;

SELECT * FROM tr ORDER BY t;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- F — Facturation bloquée (créneau ouvert) → fix → OK
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
SET LOCAL jolene.sync_in_progress='true';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';
SET LOCAL jolene.sync_in_progress='false';
UPDATE missions SET prochain_type_scan='OUVERTURE',nb_scans=0,
  debut_effectif=NULL,fin_effective=NULL,duree_heures_effective=NULL WHERE id='e0000000-0000-0000-0000-000000000132';
UPDATE missions SET duree_heures=duree_heures WHERE id='e0000000-0000-0000-0000-000000000132';
SET LOCAL request.jwt.claims='{"sub":"57d814fb-c09b-4528-b4e0-ed8369328bd3","role":"authenticated"}';

DO $$ DECLARE c text; BEGIN SELECT code_pointage_actif INTO c FROM missions WHERE id='e0000000-0000-0000-0000-000000000132'; PERFORM fn_scanner_code_pointage(c,NULL); END $$;
UPDATE scans_pointage SET scanne_le=scanne_le-INTERVAL'5min' WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND numero_scan=1;

DO $$ BEGIN BEGIN PERFORM fn_verifier_pre_facturation('e0000000-0000-0000-0000-000000000132'::uuid);
  INSERT INTO tr VALUES('F','F1_blocked','FAIL','no exception');
EXCEPTION WHEN OTHERS THEN INSERT INTO tr VALUES('F','F1_blocked','PASS',left(SQLERRM,60)); END; END $$;

SELECT fn_declarer_fin_retroactive('e0000000-0000-0000-0000-000000000132'::uuid, now()+INTERVAL'2h', 'Fix F');
UPDATE mission_creneaux SET debut='2026-04-16 08:00+00',fin='2026-04-16 19:00+00'
WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';

DO $$ DECLARE v jsonb; BEGIN
  v:=fn_verifier_pre_facturation('e0000000-0000-0000-0000-000000000132'::uuid);
  INSERT INTO tr VALUES('F','F2_fixed',CASE WHEN (v->>'ok')::bool THEN 'PASS' ELSE 'FAIL' END,v::text);
END $$;

SELECT * FROM tr ORDER BY t;
ROLLBACK;

-- ════════════════════════════════════════════════════════════���═
-- G — Heures majorées nuit sur EFFECTIF
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';

-- EFFECTIF nuit 19:00→04:00 = 9h (includes hours in heure_debut_nuit_fige..heure_fin_nuit_fige)
INSERT INTO mission_creneaux (mission_id,debut,fin,est_pause,ordre,type_creneau)
VALUES ('e0000000-0000-0000-0000-000000000132','2026-04-16 17:00+00','2026-04-17 02:00+00',false,10,'EFFECTIF');

INSERT INTO tr SELECT 'G','G1_nuit',CASE WHEN heures_nuit>0 THEN 'PASS' ELSE 'FAIL' END,
  format('nuit=%s dur=%s eff=%s',heures_nuit,duree_heures,duree_heures_effective)
FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';

SELECT * FROM tr;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- H — Régression PREVISIONNEL-only (fallback)
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';
UPDATE missions SET prochain_type_scan='OUVERTURE',nb_scans=0,
  debut_effectif=NULL,fin_effective=NULL,duree_heures_effective=NULL WHERE id='e0000000-0000-0000-0000-000000000132';

INSERT INTO tr SELECT 'H','H1',CASE WHEN duree_heures=12 AND duree_heures_effective IS NULL THEN 'PASS' ELSE 'FAIL' END,
  format('dur=%s eff=%s',duree_heures,duree_heures_effective) FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';
INSERT INTO tr SELECT 'H','H2',CASE WHEN total_brut>0 THEN 'PASS' ELSE 'FAIL' END,
  format('total=%s',total_brut) FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';
DO $$ DECLARE v jsonb; BEGIN
  v:=fn_verifier_pre_facturation('e0000000-0000-0000-0000-000000000132'::uuid);
  INSERT INTO tr VALUES('H','H3',CASE WHEN v->>'source_facturation'='PREVISIONNEL' THEN 'PASS' ELSE 'FAIL' END,v::text);
END $$;

SELECT * FROM tr ORDER BY t;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- I — Plafond 48h utilise EFFECTIF quand présent
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';

-- EFFECTIF 8h remplace PREVISIONNEL 12h pour le calcul duree_heures
INSERT INTO mission_creneaux (mission_id,debut,fin,est_pause,ordre,type_creneau)
VALUES ('e0000000-0000-0000-0000-000000000132','2026-04-16 08:00+00','2026-04-16 16:00+00',false,20,'EFFECTIF');

INSERT INTO tr SELECT 'I','I1',CASE WHEN duree_heures=8 AND duree_heures_effective=8 THEN 'PASS' ELSE 'FAIL' END,
  format('dur=%s eff=%s (prev was 12)',duree_heures,duree_heures_effective)
FROM missions WHERE id='e0000000-0000-0000-0000-000000000132';

SELECT * FROM tr;
ROLLBACK;

-- ══════════════════════════════════════════════════════════════
-- J — Repos 11h avec EFFECTIF
-- ══════════════════════════════════════════════════════════════
BEGIN;
CREATE TEMP TABLE tr (sc text, t text, r text, d text);

DELETE FROM scans_pointage WHERE mission_id='e0000000-0000-0000-0000-000000000132';
DELETE FROM mission_creneaux WHERE mission_id='e0000000-0000-0000-0000-000000000132' AND type_creneau='EFFECTIF';
INSERT INTO mission_creneaux (mission_id,debut,fin,est_pause,ordre,type_creneau)
VALUES ('e0000000-0000-0000-0000-000000000132','2026-04-16 08:00+00','2026-04-16 16:00+00',false,20,'EFFECTIF');

SET LOCAL request.jwt.claims='{"sub":"8500dba5-2c73-4035-8383-b854d59a9864","role":"authenticated"}';
DO $$ BEGIN BEGIN
  INSERT INTO missions (id,etablissement_id,intitule,profession_requise,debut_le,fin_le,taux_horaire_base,statut)
  VALUES ('77770000-0000-0000-0000-000000000aaa','b0000000-0000-0000-0000-000000000001','J','IDE',
    '2026-04-17 01:00+00','2026-04-17 10:00+00',30,'OUVERTE');
  INSERT INTO mission_creneaux (mission_id,debut,fin,est_pause,ordre,type_creneau)
  VALUES ('77770000-0000-0000-0000-000000000aaa','2026-04-17 01:00+00','2026-04-17 10:00+00',false,1,'PREVISIONNEL');
  UPDATE missions SET statut='ASSIGNEE',soignant_assigne_id='57d814fb-c09b-4528-b4e0-ed8369328bd3'
  WHERE id='77770000-0000-0000-0000-000000000aaa';
  INSERT INTO tr VALUES('J','J1_repos','FAIL','no repos exception');
EXCEPTION WHEN OTHERS THEN
  INSERT INTO tr VALUES('J','J1_repos',
    CASE WHEN SQLERRM LIKE '%repos%' OR SQLERRM LIKE '%11%' THEN 'PASS' ELSE 'PARTIAL' END,
    left(SQLERRM,100));
END; END $$;

SELECT * FROM tr;
ROLLBACK;
