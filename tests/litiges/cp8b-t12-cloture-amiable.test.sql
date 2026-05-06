-- ============================================================
-- CP8b — T12 : Clôture amiable (2 parties d'accord) → RESOLU
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8b-t12-cloture-amiable.test.sql
--
-- Scénario : litige OUVERT, le soignant et l'étab marquent leur accord
-- successivement via fn_cloturer_litige_mutuel(UUID). Au 2e appel,
-- statut passe automatiquement à RESOLU.
--
-- Note : auth.users minimal requis pour étab (mon_etablissement_id()).
-- Gap connu : fn_cloturer_litige_mutuel ne call PAS fn_ecrire_audit.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8b T12 — Clôture amiable (accord mutuel) =='

BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_etab_user_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_litige_id UUID := gen_random_uuid();
  v_r1 JSONB;
  v_r2 JSONB;
  v_litige RECORD;
BEGIN
  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'CP8B_T12_Etab', '12345678900088', 'HOPITAL_PUBLIC', '12 rue', 'Paris', '75012', 'cp8b-t12@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'CP8B_T12', 'Léa', 'cp8b-t12-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'CP8B_T12_M', 'IDE', NOW()-INTERVAL '3 days', NOW()-INTERVAL '2 days 16h', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW()-INTERVAL '2 days', 8);

  INSERT INTO public.litiges (id, mission_id, soignant_id, etablissement_id, initie_par, motif, statut, type_litige)
    VALUES (v_litige_id, v_mission_id, v_soignant_id, v_etab_id, 'SOIGNANT',
            'Contestation des heures pointées, soumise à accord mutuel.', 'OUVERT', 'DESACCORD_HEURES_POINTAGE');

  -- Auth.users minimal pour simuler un user étab
  INSERT INTO auth.users (id, email, raw_app_meta_data, role, aud, instance_id)
    VALUES (v_etab_user_id, 'cp8b-t12-etab@test.local',
            jsonb_build_object('role', 'ADMIN_ETABLISSEMENT', 'etablissement_id', v_etab_id),
            'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'::uuid)
    ON CONFLICT (id) DO NOTHING;

  -- Étape 1 : soignant marque son accord
  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);
  v_r1 := public.fn_cloturer_litige_mutuel(v_litige_id);

  IF v_r1 ? 'error' THEN
    RAISE NOTICE '[T12] FAIL — step1 soignant error: %', v_r1->>'error'; RETURN;
  END IF;

  SELECT accord_soignant, accord_etablissement, statut INTO v_litige
    FROM public.litiges WHERE id = v_litige_id;

  IF v_litige.accord_soignant IS NOT TRUE THEN
    RAISE NOTICE '[T12] FAIL — accord_soignant=% après step1', v_litige.accord_soignant; RETURN;
  END IF;
  IF v_litige.statut <> 'OUVERT' THEN
    RAISE NOTICE '[T12] FAIL — statut=% après step1 (attendu OUVERT)', v_litige.statut; RETURN;
  END IF;

  -- Étape 2 : étab marque son accord → RESOLU
  PERFORM set_config('request.jwt.claim.sub', v_etab_user_id::text, true);
  v_r2 := public.fn_cloturer_litige_mutuel(v_litige_id);

  IF v_r2 ? 'error' THEN
    RAISE NOTICE '[T12] FAIL — step2 étab error: %', v_r2->>'error'; RETURN;
  END IF;

  SELECT statut, accord_soignant, accord_etablissement, resolution, resolu_le INTO v_litige
    FROM public.litiges WHERE id = v_litige_id;

  IF v_litige.statut <> 'RESOLU' THEN
    RAISE NOTICE '[T12] FAIL — statut=% (attendu RESOLU)', v_litige.statut;
  ELSIF v_litige.accord_etablissement IS NOT TRUE THEN
    RAISE NOTICE '[T12] FAIL — accord_etablissement=% (attendu TRUE)', v_litige.accord_etablissement;
  ELSIF v_litige.resolu_le IS NULL THEN
    RAISE NOTICE '[T12] FAIL — resolu_le NULL';
  ELSE
    RAISE NOTICE '[T12] PASS — RESOLU accord mutuel (resolution=%, le=%)',
      v_litige.resolution, v_litige.resolu_le;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T12] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8b T12 =='
