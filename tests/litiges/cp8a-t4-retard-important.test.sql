-- ============================================================
-- CP8a — T4 : Retard important signalé par soignant (manuel)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t4-retard-important.test.sql
--
-- Scénario : présence validée il y a 2h (fenêtre 48h ouverte),
-- retard_min=45 → le soignant signale un RETARD_IMPORTANT via
-- fn_ouvrir_litige_rate_limited.
--
-- Note : la RPC détermine initie_par via soignant_assigne_id = auth.uid()
-- (→ SOIGNANT) ou mon_etablissement_id() (→ ETABLISSEMENT). Simuler un
-- user étab nécessiterait un INSERT auth.users + user_roles + link
-- mon_etablissement_id(), complexité disproportionnée pour ce test.
-- On simplifie : le soignant ouvre le litige RETARD_IMPORTANT.
-- Le test vérifie le type_litige, pas l'acteur (initie_par=SOIGNANT).
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8a T4 — Retard important (manuel, soignant) =='

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
    v_etab_id, 'CP8A_TEST_T4_Etab', '12345678900096', 'HOPITAL_PUBLIC',
    '4 rue test', 'Paris', '75004', 'cp8a-t4@test.local'
  );

  INSERT INTO public.soignants (
    id, nom, prenom, email, profession
  ) VALUES (
    v_soignant_id, 'CP8A_TEST_T4_Nom', 'David',
    'cp8a-t4-' || v_soignant_id || '@test.local', 'IDE'
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id
  ) VALUES (
    v_mission_id, v_etab_id, 'CP8A_TEST_T4_Mission', 'IDE',
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '16 hours',
    8, 25, 'TERMINEE', v_soignant_id
  );

  INSERT INTO public.presences (
    id, mission_id, soignant_id,
    valide_par_etablissement, valide_le,
    heures_reelles, retard_min
  ) VALUES (
    v_presence_id, v_mission_id, v_soignant_id,
    TRUE, NOW() - INTERVAL '2 hours',
    7.25, 45
  );

  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);

  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id,
    'RETARD_IMPORTANT'::public.type_litige,
    'Retard de 45 min constaté à la prise de poste, non signalé au préalable.'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[T4] FAIL — RPC error: %', v_result->>'error';
  ELSE
    SELECT * INTO v_litige FROM public.litiges
     WHERE id = (v_result->>'litige_id')::UUID;

    IF NOT FOUND THEN
      RAISE NOTICE '[T4] FAIL — litige_id retourné mais introuvable';
    ELSIF v_litige.type_litige <> 'RETARD_IMPORTANT' OR v_litige.statut <> 'OUVERT' THEN
      RAISE NOTICE '[T4] FAIL — type=% statut=%', v_litige.type_litige, v_litige.statut;
    ELSE
      RAISE NOTICE '[T4] PASS — litige % (RETARD_IMPORTANT, OUVERT, initie_par=%)',
        v_litige.id, v_litige.initie_par;
    END IF;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T4] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;

ROLLBACK;

\echo ''
\echo '== Fin CP8a T4 =='
