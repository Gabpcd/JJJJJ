-- ============================================================
-- CP8b — T13 : Double litige concurrent sur même mission
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b + FIX T18/T19/T20.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t13-double-litige.test.sql
--
-- Scénario : soignant ouvre SECURITE_DANGER, puis étab ouvre
-- ABSENCE_SOIGNANT sur la même mission. L'index unique partiel
-- est sur (mission_id, type_litige) → 2 types différents coexistent.
--
-- Note : auth.users minimal pour user étab (mon_etablissement_id()).
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T13 — Double litige concurrent (types différents) =='

BEGIN;
DO $$
DECLARE
  v_e UUID := gen_random_uuid(); v_s UUID := gen_random_uuid();
  v_eu UUID := gen_random_uuid(); v_m UUID := gen_random_uuid();
  v_p UUID := gen_random_uuid();
  v_r1 JSONB; v_r2 JSONB;
  v_nb INT;
  v_l1 RECORD; v_l2 RECORD;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_e, 'CP8B_T13_Etab', '12345678900087', 'HOPITAL_PUBLIC', '13 rue', 'Paris', '75013', 'cp8b-t13@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_s, 'CP8B_T13', 'Marc', 'cp8b-t13-' || v_s || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_m, v_e, 'CP8B_T13_M', 'IDE', NOW()-INTERVAL '1 day', NOW()-INTERVAL '16 hours', 8, 25, 'TERMINEE', v_s);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_p, v_m, v_s, TRUE, NOW()-INTERVAL '2 hours', 0);

  INSERT INTO auth.users (id, email, raw_app_meta_data, role, aud, instance_id)
    VALUES (v_eu, 'cp8b-t13-etab@test.local',
            jsonb_build_object('role', 'ADMIN_ETABLISSEMENT', 'etablissement_id', v_e),
            'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid)
    ON CONFLICT (id) DO NOTHING;

  -- Étape 1 : soignant ouvre SECURITE_DANGER
  PERFORM set_config('request.jwt.claim.sub', v_s::text, true);
  v_r1 := public.fn_ouvrir_litige_rate_limited(
    v_m, 'SECURITE_DANGER'::public.type_litige,
    'Soignant signale un danger constaté pendant la mission (fenêtre toujours ouverte).'
  );
  IF v_r1 ? 'error' THEN
    RAISE NOTICE '[T13] FAIL — step1 error: %', v_r1->>'error'; RETURN;
  END IF;

  -- Étape 2 : étab ouvre ABSENCE_SOIGNANT sur la même mission
  PERFORM set_config('request.jwt.claim.sub', v_eu::text, true);
  v_r2 := public.fn_ouvrir_litige_rate_limited(
    v_m, 'ABSENCE_SOIGNANT'::public.type_litige,
    'Étab constate l''absence du soignant sur le créneau prévu (type distinct du 1er litige).'
  );
  IF v_r2 ? 'error' THEN
    RAISE NOTICE '[T13] FAIL — step2 error: %', v_r2->>'error'; RETURN;
  END IF;

  -- Étape 3 : 2 litiges coexistent
  SELECT COUNT(*) INTO v_nb FROM public.litiges WHERE mission_id = v_m;
  IF v_nb <> 2 THEN
    RAISE NOTICE '[T13] FAIL — COUNT(litiges)=% (attendu 2)', v_nb; RETURN;
  END IF;

  SELECT * INTO v_l1 FROM public.litiges WHERE id = (v_r1->>'litige_id')::UUID;
  SELECT * INTO v_l2 FROM public.litiges WHERE id = (v_r2->>'litige_id')::UUID;

  IF v_l1.type_litige <> 'SECURITE_DANGER' OR v_l1.statut <> 'OUVERT' OR v_l1.initie_par <> 'SOIGNANT' THEN
    RAISE NOTICE '[T13] FAIL — litige1 type=% statut=% initie=%', v_l1.type_litige, v_l1.statut, v_l1.initie_par;
  ELSIF v_l2.type_litige <> 'ABSENCE_SOIGNANT' OR v_l2.statut <> 'OUVERT' OR v_l2.initie_par <> 'ETABLISSEMENT' THEN
    RAISE NOTICE '[T13] FAIL — litige2 type=% statut=% initie=%', v_l2.type_litige, v_l2.statut, v_l2.initie_par;
  ELSE
    RAISE NOTICE '[T13] PASS — 2 litiges coexistent (SECURITE_DANGER/SOIGNANT + ABSENCE_SOIGNANT/ETABLISSEMENT)';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T13] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T13 =='
