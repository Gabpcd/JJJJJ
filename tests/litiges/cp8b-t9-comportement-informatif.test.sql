-- ============================================================
-- CP8b — T9 : COMPORTEMENT à 7 mois → est_informatif=TRUE
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX T18.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t9-comportement-informatif.test.sql
--
-- Scénario : pour COMPORTEMENT_*/CONDITIONS_*, fn_fenetre_contestation_ouverte
-- vérifie mission.fin_le + delai_comportement_mois (6 mois). Au-delà, la
-- fenêtre est fermée. fn_ouvrir_litige_rate_limited autorise quand même
-- la création du litige avec est_informatif=TRUE pour ces 3 types
-- (COMPORTEMENT_SOIGNANT, COMPORTEMENT_ETABLISSEMENT,
-- CONDITIONS_MISSION_NON_RESPECTEES).
--
-- Note : la fenêtre est calculée sur mission.fin_le, pas sur
-- presence.valide_le → on positionne fin_le à 7 mois ago.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T9 — COMPORTEMENT à 7 mois (informatif) =='

BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_result JSONB;
  v_litige RECORD;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'CP8B_TEST_T9_Etab', '12345678900091', 'HOPITAL_PUBLIC', '9 rue', 'Paris', '75009', 'cp8b-t9@test.local');

  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'CP8B_TEST_T9_Nom', 'Inès', 'cp8b-t9-' || v_soignant_id || '@test.local', 'IDE');

  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'CP8B_TEST_T9_Mission', 'IDE',
            NOW() - INTERVAL '211 days', NOW() - INTERVAL '210 days 16 hours',
            8, 25, 'TERMINEE', v_soignant_id);

  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '210 days', 8);

  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);

  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id,
    'COMPORTEMENT_ETABLISSEMENT'::public.type_litige,
    'Signalement tardif d''un comportement inapproprié de l''établissement (mission terminée 7 mois ago).'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[T9] FAIL — RPC error: %', v_result->>'error';
    RETURN;
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = (v_result->>'litige_id')::UUID;

  IF NOT FOUND THEN
    RAISE NOTICE '[T9] FAIL — litige_id retourné mais introuvable';
  ELSIF v_litige.type_litige <> 'COMPORTEMENT_ETABLISSEMENT' THEN
    RAISE NOTICE '[T9] FAIL — type=% (attendu COMPORTEMENT_ETABLISSEMENT)', v_litige.type_litige;
  ELSIF v_litige.statut <> 'OUVERT' THEN
    RAISE NOTICE '[T9] FAIL — statut=% (attendu OUVERT)', v_litige.statut;
  ELSIF v_litige.est_informatif IS NOT TRUE THEN
    RAISE NOTICE '[T9] FAIL — est_informatif=% (attendu TRUE, fenêtre 6 mois dépassée)', v_litige.est_informatif;
  ELSE
    RAISE NOTICE '[T9] PASS — COMPORTEMENT_ETABLISSEMENT % OUVERT, est_informatif=TRUE après 7 mois', v_litige.id;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T9] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T9 =='
