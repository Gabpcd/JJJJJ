-- ============================================================
-- CP8b — T8 : SECURITE_DANGER à 4 mois → litige normal
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX T18.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t8-securite-danger.test.sql
--
-- Scénario : SECURITE_DANGER fait partie des types "fenêtre toujours
-- ouverte" (cf. fn_fenetre_contestation_ouverte, branche
-- 'SECURITE_DANGER', 'NON_PAIEMENT', 'AUTRE' → RETURN TRUE). Même 4 mois
-- après la presence validée, le litige doit être créé normalement, NON
-- informatif (est_informatif=FALSE), statut OUVERT.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T8 — SECURITE_DANGER à 4 mois (fenêtre toujours ouverte) =='

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
    VALUES (v_etab_id, 'CP8B_TEST_T8_Etab', '12345678900092', 'HOPITAL_PUBLIC', '8 rue', 'Paris', '75008', 'cp8b-t8@test.local');

  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'CP8B_TEST_T8_Nom', 'Hugo', 'cp8b-t8-' || v_soignant_id || '@test.local', 'IDE');

  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'CP8B_TEST_T8_Mission', 'IDE',
            NOW() - INTERVAL '121 days', NOW() - INTERVAL '120 days 16 hours',
            8, 25, 'TERMINEE', v_soignant_id);

  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '120 days', 8);

  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);

  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id,
    'SECURITE_DANGER'::public.type_litige,
    'Signalement tardif d''une situation de danger constatée pendant la mission (4 mois ago).'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[T8] FAIL — RPC error: %', v_result->>'error';
    RETURN;
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = (v_result->>'litige_id')::UUID;

  IF NOT FOUND THEN
    RAISE NOTICE '[T8] FAIL — litige_id retourné mais introuvable';
  ELSIF v_litige.type_litige <> 'SECURITE_DANGER' THEN
    RAISE NOTICE '[T8] FAIL — type=% (attendu SECURITE_DANGER)', v_litige.type_litige;
  ELSIF v_litige.statut <> 'OUVERT' THEN
    RAISE NOTICE '[T8] FAIL — statut=% (attendu OUVERT)', v_litige.statut;
  ELSIF v_litige.est_informatif IS NOT FALSE THEN
    RAISE NOTICE '[T8] FAIL — est_informatif=% (attendu FALSE, fenêtre toujours ouverte)', v_litige.est_informatif;
  ELSIF v_litige.initie_par <> 'SOIGNANT' THEN
    RAISE NOTICE '[T8] FAIL — initie_par=% (attendu SOIGNANT)', v_litige.initie_par;
  ELSE
    RAISE NOTICE '[T8] PASS — SECURITE_DANGER % OUVERT, est_informatif=FALSE après 4 mois', v_litige.id;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T8] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T8 =='
