-- ============================================================
-- CP8b — T10 : Escalade auto libéral 72h → EN_MEDIATION
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX T18.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t10-escalade-liberal.test.sql
--
-- Scénario : litige libéral (soignant.est_salarie_etablissement=FALSE)
-- créé il y a 80h, sans réponse → fn_litiges_escalader_auto() doit
-- l'escalader (statut OUVERT → EN_MEDIATION + escalade_auto_le +
-- escalade_auto_motif renseigné).
--
-- Note : la RPC détecte libéral/salarié via soignants.est_salarie_etablissement,
-- pas via mission.type_contrat_applique. fn_litiges_escalader_auto() est
-- SECURITY DEFINER → pas besoin d'auth.uid().
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T10 — Escalade auto libéral 72h =='

BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_litige_id UUID := gen_random_uuid();
  v_result JSONB;
  v_litige RECORD;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'CP8B_TEST_T10_Etab', '12345678900090', 'HOPITAL_PUBLIC', '10 rue', 'Paris', '75010', 'cp8b-t10@test.local');

  INSERT INTO public.soignants (id, nom, prenom, email, profession, est_salarie_etablissement)
    VALUES (v_soignant_id, 'CP8B_TEST_T10_Nom', 'Julie', 'cp8b-t10-' || v_soignant_id || '@test.local', 'IDE', FALSE);

  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'CP8B_TEST_T10_Mission', 'IDE',
            NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days 16 hours',
            8, 25, 'TERMINEE', v_soignant_id);

  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '4 days', 8);

  INSERT INTO public.litiges (
    id, mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, cree_le, est_informatif
  ) VALUES (
    v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'SOIGNANT',
    'Litige libéral créé il y a 80h sans réponse de l''établissement.',
    'OUVERT', 'DESACCORD_HEURES_POINTAGE', NOW() - INTERVAL '80 hours', FALSE
  );

  v_result := public.fn_litiges_escalader_auto();

  SELECT statut, escalade_auto_le, escalade_auto_motif
    INTO v_litige
    FROM public.litiges WHERE id = v_litige_id;

  IF v_litige.statut <> 'EN_MEDIATION' THEN
    RAISE NOTICE '[T10] FAIL — statut=% (attendu EN_MEDIATION), escalades=%',
      v_litige.statut, v_result->>'escalades';
  ELSIF v_litige.escalade_auto_le IS NULL THEN
    RAISE NOTICE '[T10] FAIL — escalade_auto_le NULL';
  ELSIF v_litige.escalade_auto_motif IS NULL OR length(trim(v_litige.escalade_auto_motif)) = 0 THEN
    RAISE NOTICE '[T10] FAIL — escalade_auto_motif vide';
  ELSE
    RAISE NOTICE '[T10] PASS — litige escaladé EN_MEDIATION (motif=%, le=%)',
      v_litige.escalade_auto_motif, v_litige.escalade_auto_le;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T10] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T10 =='
