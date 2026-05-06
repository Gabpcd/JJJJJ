-- ============================================================
-- CP8b — T11 : Escalade auto salarié 5 j.o. (résilient aux fériés)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX T18 + FIX T19.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t11-escalade-salarie-ferie.test.sql
--
-- Scénario : mission avec type_contrat_applique='SALARIE' (FIX T19 lit
-- ce champ en priorité), litige créé il y a 8 jours calendaires (> 5
-- jours ouvrés même avec un férié dans la fenêtre) → escalade attendue
-- avec motif "salarié (5 jours ouvrés)".
--
-- Note : fn_ajouter_jours_ouvres gère intrinsèquement public.jours_feries_fr,
-- donc on n'a pas besoin de forcer un férié — 8j calendaires garantissent
-- le dépassement de 5 j.o. dans tous les cas.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T11 — Escalade auto salarié 5 j.o. =='

BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_litige_id UUID := gen_random_uuid();
  v_litige RECORD;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'CP8B_TEST_T11_Etab', '12345678900089', 'HOPITAL_PUBLIC', '11 rue', 'Paris', '75011', 'cp8b-t11@test.local');

  INSERT INTO public.soignants (id, nom, prenom, email, profession, est_salarie_etablissement)
    VALUES (v_soignant_id, 'CP8B_TEST_T11_Nom', 'Karim', 'cp8b-t11-' || v_soignant_id || '@test.local', 'IDE', TRUE);

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise, debut_le, fin_le,
    duree_heures, taux_horaire_base, statut, soignant_assigne_id, type_contrat_applique
  ) VALUES (
    v_mission_id, v_etab_id, 'CP8B_TEST_T11_Mission', 'IDE',
    NOW() - INTERVAL '12 days', NOW() - INTERVAL '11 days 16 hours',
    8, 25, 'TERMINEE', v_soignant_id, 'SALARIE'
  );

  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '11 days', 8);

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, cree_le, est_informatif
  ) VALUES (
    v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'SOIGNANT',
    'Litige salarié créé il y a 8 jours calendaires sans réponse de l''établissement.',
    'OUVERT', 'DESACCORD_HEURES_POINTAGE', NOW() - INTERVAL '8 days', FALSE
  );

  PERFORM public.fn_litiges_escalader_auto();

  SELECT statut, escalade_auto_le, escalade_auto_motif
    INTO v_litige
    FROM public.litiges WHERE id = v_litige_id;

  IF v_litige.statut <> 'EN_MEDIATION' THEN
    RAISE NOTICE '[T11] FAIL — statut=% (attendu EN_MEDIATION)', v_litige.statut;
  ELSIF v_litige.escalade_auto_le IS NULL THEN
    RAISE NOTICE '[T11] FAIL — escalade_auto_le NULL';
  ELSIF v_litige.escalade_auto_motif NOT LIKE '%salarié%'
     AND v_litige.escalade_auto_motif NOT LIKE '%jours ouvrés%' THEN
    RAISE NOTICE '[T11] FAIL — motif=% (attendu mention salarié ou jours ouvrés)', v_litige.escalade_auto_motif;
  ELSE
    RAISE NOTICE '[T11] PASS — litige escaladé EN_MEDIATION (motif=%, le=%)',
      v_litige.escalade_auto_motif, v_litige.escalade_auto_le;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T11] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T11 =='
