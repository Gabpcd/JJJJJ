-- ============================================================
-- CP8a — T3 : Désaccord heures pointage (flow manuel)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t3-desaccord-heures.test.sql
--
-- Scénario : présence récemment validée (valide_le = NOW()-2h, donc
-- fenêtre 48h ouverte), heures_reelles=8 mais le soignant conteste →
-- appel manuel fn_ouvrir_litige_rate_limited(mission_id,
-- 'DESACCORD_HEURES_POINTAGE', motif) en contexte soignant → un litige
-- de ce type est créé, statut=OUVERT, initie_par=SOIGNANT.
--
-- Cas C non auto-détectable (schéma presences mono-colonne) : ce test
-- couvre la voie manuelle, qui reste la seule disponible.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8a T3 — Désaccord heures pointage (manuel) =='

BEGIN;

DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_result      JSONB;
  v_litige      RECORD;
BEGIN
  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact
  ) VALUES (
    v_etab_id, 'CP8A_TEST_T3_Etab', '12345678900097', 'HOPITAL_PUBLIC',
    '3 rue test', 'Paris', '75003', 'cp8a-t3@test.local'
  );

  INSERT INTO public.soignants (
    id, nom, prenom, email, profession
  ) VALUES (
    v_soignant_id, 'CP8A_TEST_T3_Nom', 'Claire',
    'cp8a-t3-' || v_soignant_id || '@test.local', 'IDE'
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id
  ) VALUES (
    v_mission_id, v_etab_id, 'CP8A_TEST_T3_Mission', 'IDE',
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '16 hours',
    8, 25, 'TERMINEE', v_soignant_id
  );

  INSERT INTO public.presences (
    id, mission_id, soignant_id,
    valide_par_etablissement, valide_le,
    heures_reelles, motif_litige
  ) VALUES (
    v_presence_id, v_mission_id, v_soignant_id,
    TRUE, NOW() - INTERVAL '2 hours',
    8, NULL
  );

  -- Simule auth.uid() = soignant (fn_ouvrir_litige_rate_limited détecte
  -- alors initie_par='SOIGNANT' via soignant_assigne_id = v_user_id).
  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);

  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id,
    'DESACCORD_HEURES_POINTAGE'::public.type_litige,
    'Soignant conteste : 10 h effectuées mais présence validée à 8 h.'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[T3] FAIL — RPC a retourné error: %', v_result->>'error';
  ELSE
    SELECT * INTO v_litige FROM public.litiges
     WHERE id = (v_result->>'litige_id')::UUID;

    IF NOT FOUND THEN
      RAISE NOTICE '[T3] FAIL — litige_id retourné mais introuvable (result=%)', v_result;
    ELSIF v_litige.type_litige <> 'DESACCORD_HEURES_POINTAGE'
       OR v_litige.statut      <> 'OUVERT'
       OR v_litige.initie_par  <> 'SOIGNANT'
    THEN
      RAISE NOTICE '[T3] FAIL — type=% statut=% initie_par=%',
        v_litige.type_litige, v_litige.statut, v_litige.initie_par;
    ELSE
      RAISE NOTICE '[T3] PASS — litige % (DESACCORD_HEURES_POINTAGE, OUVERT, SOIGNANT)',
        v_litige.id;
    END IF;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T3] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;

ROLLBACK;

\echo ''
\echo '== Fin CP8a T3 =='
