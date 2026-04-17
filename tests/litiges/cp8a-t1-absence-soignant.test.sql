-- ============================================================
-- CP8a — T1 : Auto-création litige ABSENCE_SOIGNANT (Cas A)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t1-absence-soignant.test.sql
--
-- Scénario : présence validée par étab il y a > 48h, soignant marqué
-- absent (heures_reelles=0, motif_litige renseigné), aucun litige pré-
-- existant → fn_auto_creation_litiges_presence() doit créer un litige
-- type=ABSENCE_SOIGNANT, statut=OUVERT.
--
-- Tout le setup (étab, soignant, mission, présence, litige) est
-- ROLLBACK en fin de script : pas de pollution base.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8a T1 — Absence soignant (auto-création litige) =='

BEGIN;

DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_litige      RECORD;
  v_result      JSONB;
BEGIN
  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact
  ) VALUES (
    v_etab_id, 'CP8A_TEST_T1_Etab', '12345678900099', 'HOPITAL_PUBLIC',
    '1 rue test', 'Paris', '75001', 'cp8a-t1@test.local'
  );

  INSERT INTO public.soignants (
    id, nom, prenom, email, profession
  ) VALUES (
    v_soignant_id, 'CP8A_TEST_T1_Nom', 'Alice',
    'cp8a-t1-' || v_soignant_id || '@test.local', 'IDE'
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id
  ) VALUES (
    v_mission_id, v_etab_id, 'CP8A_TEST_T1_Mission', 'IDE',
    NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days 16 hours',
    8, 25, 'TERMINEE', v_soignant_id
  );

  INSERT INTO public.presences (
    id, mission_id, soignant_id,
    valide_par_etablissement, valide_le,
    heures_reelles, motif_litige
  ) VALUES (
    v_presence_id, v_mission_id, v_soignant_id,
    TRUE, NOW() - INTERVAL '49 hours',
    0, 'Soignant absent, pas de justificatif reçu'
  );

  v_result := public.fn_auto_creation_litiges_presence();

  SELECT * INTO v_litige
    FROM public.litiges
   WHERE mission_id = v_mission_id
     AND type_litige = 'ABSENCE_SOIGNANT';

  IF NOT FOUND THEN
    RAISE NOTICE '[T1] FAIL — aucun litige créé (result=%)', v_result;
  ELSIF v_litige.statut <> 'OUVERT' THEN
    RAISE NOTICE '[T1] FAIL — statut=% au lieu de OUVERT', v_litige.statut;
  ELSIF v_litige.initie_par NOT IN ('ETABLISSEMENT', 'SYSTEME') THEN
    RAISE NOTICE '[T1] FAIL — initie_par=% (attendu ETABLISSEMENT ou SYSTEME)',
      v_litige.initie_par;
  ELSE
    RAISE NOTICE '[T1] PASS — litige % créé (type=ABSENCE_SOIGNANT, statut=%, initie_par=%)',
      v_litige.id, v_litige.statut, v_litige.initie_par;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T1] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;

ROLLBACK;

\echo ''
\echo '== Fin CP8a T1 =='
