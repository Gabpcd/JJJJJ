-- ============================================================
-- FIX BONUS — tests fn_auto_creation_litiges_presence étendue
-- ============================================================
-- Prérequis : migration 20260417130719_fix_bonus_auto_creation_cas_b_c.
-- Usage : psql "$DB_URL" -f tests/litiges/fix-bonus-auto-creation-b-c.test.sql
--
-- Couverture (3 scénarios isolés, tous en BEGIN/ROLLBACK) :
--   S1 — Cas A  : heures_reelles=0        → ABSENCE_SOIGNANT
--   S2 — Cas B  : heures_reelles=4 /8h    → DEPART_ANTICIPE
--   S3 — Anti-boucle : 2e appel sur même présence → pas de 2e litige
-- Cas C (DESACCORD_HEURES_POINTAGE) non auto-détectable avec le schéma
-- presences actuel — reste manuel, pas de test E2E ici.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== FIX bonus — auto-création Cas A/B + anti-boucle =='

-- ─────────────────────────────────────────────────────────────
-- S1 — Cas A : ABSENCE_SOIGNANT
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_litige      RECORD;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'FIXB_TEST_S1_Etab', '11111111100001', 'HOPITAL_PUBLIC', '1 rue', 'Paris', '75001', 's1@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'FIXB_S1', 'A', 'fixb-s1-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'FIXB_S1_Mission', 'IDE', NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles, motif_litige)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '49 hours', 0, 'Soignant absent');

  PERFORM public.fn_auto_creation_litiges_presence();

  SELECT * INTO v_litige FROM public.litiges
   WHERE mission_id = v_mission_id AND type_litige = 'ABSENCE_SOIGNANT';

  IF NOT FOUND THEN
    RAISE NOTICE '[S1] FAIL — aucun litige ABSENCE_SOIGNANT créé';
  ELSIF v_litige.statut <> 'OUVERT' OR v_litige.initie_par <> 'SYSTEME' THEN
    RAISE NOTICE '[S1] FAIL — statut=% initie_par=%', v_litige.statut, v_litige.initie_par;
  ELSE
    RAISE NOTICE '[S1] PASS — ABSENCE_SOIGNANT OUVERT initie_par=SYSTEME';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S1] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S2 — Cas B : DEPART_ANTICIPE (4h sur 8h prévues)
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_litige      RECORD;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'FIXB_TEST_S2_Etab', '11111111100002', 'HOPITAL_PUBLIC', '2 rue', 'Paris', '75002', 's2@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'FIXB_S2', 'B', 'fixb-s2-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'FIXB_S2_Mission', 'IDE', NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles, motif_litige, depart_anticipe_min)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '49 hours', 4, 'Départ anticipé constaté', 240);

  PERFORM public.fn_auto_creation_litiges_presence();

  SELECT * INTO v_litige FROM public.litiges
   WHERE mission_id = v_mission_id AND type_litige = 'DEPART_ANTICIPE';

  IF NOT FOUND THEN
    RAISE NOTICE '[S2] FAIL — aucun litige DEPART_ANTICIPE créé';
  ELSIF v_litige.statut <> 'OUVERT' OR v_litige.initie_par <> 'SYSTEME' THEN
    RAISE NOTICE '[S2] FAIL — statut=% initie_par=%', v_litige.statut, v_litige.initie_par;
  ELSE
    RAISE NOTICE '[S2] PASS — DEPART_ANTICIPE OUVERT initie_par=SYSTEME';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S2] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

-- ─────────────────────────────────────────────────────────────
-- S3 — Anti-boucle : 2e appel sur même présence = 0 nouveau litige
-- ─────────────────────────────────────────────────────────────
BEGIN;
DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_nb_avant INT;
  v_nb_apres INT;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'FIXB_TEST_S3_Etab', '11111111100003', 'HOPITAL_PUBLIC', '3 rue', 'Paris', '75003', 's3@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'FIXB_S3', 'C', 'fixb-s3-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'FIXB_S3_Mission', 'IDE', NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles, motif_litige)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '49 hours', 0, 'Soignant absent');

  PERFORM public.fn_auto_creation_litiges_presence();
  SELECT COUNT(*) INTO v_nb_avant FROM public.litiges WHERE mission_id = v_mission_id;

  PERFORM public.fn_auto_creation_litiges_presence();
  SELECT COUNT(*) INTO v_nb_apres FROM public.litiges WHERE mission_id = v_mission_id;

  IF v_nb_avant = 1 AND v_nb_apres = 1 THEN
    RAISE NOTICE '[S3] PASS — anti-boucle OK (1 litige après 2 appels)';
  ELSE
    RAISE NOTICE '[S3] FAIL — avant=% après=% (attendu 1/1)', v_nb_avant, v_nb_apres;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[S3] FAIL — exception: %', SQLERRM;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin tests FIX bonus =='
