-- ============================================================
-- CP8a — T1 : Auto-création litige ABSENCE_SOIGNANT (Cas A)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t1-absence-soignant.test.sql
--
-- Scénario : présence validée par étab il y a plus de
-- delai_contestation_pointage_h (72 h depuis D12 ; âge DÉRIVÉ du paramètre
-- lu, jamais en dur), soignant marqué absent (heures_reelles=0, motif_litige
-- renseigné), aucun litige préexistant → fn_auto_creation_litiges_presence()
-- doit créer un litige type=ABSENCE_SOIGNANT, statut=OUVERT.
--
-- Cas limite T1-limite (D12, migration 20261118145614) : paramètre à 72 et
-- présence validée il y a 60 h → aucun litige auto-créé, fenêtre de
-- contestation DESACCORD_HEURES_POINTAGE encore ouverte (à 48, ce cas
-- créerait un litige et la fenêtre serait fermée). Le volet cron n'est
-- probant que sur une mission réelle : en prélancement,
-- trg_forcer_compte_test_prelaunch force est_compte_test et le cron ignore la
-- mission (message NON PROBANT, comme T1).
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
  -- Âge de validation DÉRIVÉ du paramètre lu (CLAUDE.md « État dérivé », D12) :
  -- une heure au-delà de la fenêtre delai_contestation_pointage_h.
  v_delai_h     INT := (SELECT pl.valeur::int FROM public.parametres_litiges pl
                         WHERE pl.cle = 'delai_contestation_pointage_h');
  v_valide_le   TIMESTAMPTZ;
  v_reelle      BOOLEAN;
BEGIN
  IF v_delai_h IS NULL THEN
    RAISE NOTICE '[T1] FAIL — paramètre delai_contestation_pointage_h absent';
    RETURN;
  END IF;
  v_valide_le := NOW() - make_interval(hours => v_delai_h + 1);

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
    v_valide_le - INTERVAL '23 hours', v_valide_le - INTERVAL '15 hours',
    8, 25, 'TERMINEE', v_soignant_id
  );

  INSERT INTO public.presences (
    id, mission_id, soignant_id,
    valide_par_etablissement, valide_le,
    heures_reelles, motif_litige
  ) VALUES (
    v_presence_id, v_mission_id, v_soignant_id,
    TRUE, v_valide_le,
    0, 'Soignant absent, pas de justificatif reçu'
  );

  v_reelle := private.fn_mission_est_reelle(v_mission_id);
  v_result := public.fn_auto_creation_litiges_presence();

  SELECT * INTO v_litige
    FROM public.litiges
   WHERE mission_id = v_mission_id
     AND type_litige = 'ABSENCE_SOIGNANT';

  IF NOT FOUND AND NOT v_reelle THEN
    RAISE NOTICE '[T1] NON PROBANT — mission dérivée test (trg_forcer_compte_test_prelaunch force est_compte_test) : fn_auto_creation_litiges_presence l''ignore (private.fn_mission_est_reelle)';
  ELSIF NOT FOUND THEN
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

-- Cas limite (D12) : paramètre à 72, présence validée il y a 60 h.
DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_delai       TEXT := (SELECT pl.valeur FROM public.parametres_litiges pl
                          WHERE pl.cle = 'delai_contestation_pointage_h');
  v_nb          INT;
  v_ouverte     BOOLEAN;
  v_reelle      BOOLEAN;
BEGIN
  IF v_delai IS DISTINCT FROM '72' THEN
    RAISE NOTICE '[T1-limite] FAIL — delai_contestation_pointage_h=% (attendu 72, migration 20261118145614)', v_delai;
    RETURN;
  END IF;

  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact
  ) VALUES (
    v_etab_id, 'CP8A_TEST_T1L_Etab', '12345678900089', 'HOPITAL_PUBLIC',
    '1 bis rue test', 'Paris', '75001', 'cp8a-t1l@test.local'
  );

  INSERT INTO public.soignants (
    id, nom, prenom, email, profession
  ) VALUES (
    v_soignant_id, 'CP8A_TEST_T1L_Nom', 'Alix',
    'cp8a-t1l-' || v_soignant_id || '@test.local', 'IDE'
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id
  ) VALUES (
    v_mission_id, v_etab_id, 'CP8A_TEST_T1L_Mission', 'IDE',
    NOW() - INTERVAL '83 hours', NOW() - INTERVAL '75 hours',
    8, 25, 'TERMINEE', v_soignant_id
  );

  INSERT INTO public.presences (
    id, mission_id, soignant_id,
    valide_par_etablissement, valide_le,
    heures_reelles, motif_litige
  ) VALUES (
    v_presence_id, v_mission_id, v_soignant_id,
    TRUE, NOW() - INTERVAL '60 hours',
    0, 'Soignant absent, pas de justificatif reçu'
  );

  v_reelle := private.fn_mission_est_reelle(v_mission_id);
  PERFORM public.fn_auto_creation_litiges_presence();

  SELECT COUNT(*) INTO v_nb FROM public.litiges WHERE mission_id = v_mission_id;
  v_ouverte := public.fn_fenetre_contestation_ouverte(
    'DESACCORD_HEURES_POINTAGE'::public.type_litige, v_mission_id, NULL);

  IF v_ouverte IS NOT TRUE THEN
    RAISE NOTICE '[T1-limite] FAIL — fenêtre de contestation fermée à 60 h (attendu ouverte avec 72 h)';
  ELSE
    RAISE NOTICE '[T1-limite] PASS (fenêtre) — 60 h : contestation DESACCORD_HEURES_POINTAGE ouverte';
  END IF;

  IF NOT v_reelle THEN
    RAISE NOTICE '[T1-limite] NON PROBANT — mission dérivée test (trg_forcer_compte_test_prelaunch force est_compte_test) : fn_auto_creation_litiges_presence l''ignore (private.fn_mission_est_reelle)';
  ELSIF v_nb <> 0 THEN
    RAISE NOTICE '[T1-limite] FAIL — % litige(s) auto-créé(s) à 60 h (attendu 0 avec 72 h)', v_nb;
  ELSE
    RAISE NOTICE '[T1-limite] PASS (cron) — 60 h : aucun litige auto-créé';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T1-limite] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;

ROLLBACK;

\echo ''
\echo '== Fin CP8a T1 =='
