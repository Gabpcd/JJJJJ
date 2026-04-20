-- ============================================================
-- CP8a — T7 : Hors fenêtre 48h + bypass admin
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b appliquées + 1 admin.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t7-hors-fenetre-bypass.test.sql
--
-- Scénario : presence validée il y a 5j (>48h) → fenêtre F1 fermée.
-- 1) Soignant tente fn_ouvrir_litige_rate_limited('DESACCORD_HEURES_POINTAGE')
--    → error "Fenêtre de contestation fermée..." (JSONB, pas exception).
-- 2) Admin bypass via fn_admin_creer_litige_force → litige créé,
--    est_informatif=TRUE, initie_par='ADMIN'.
--
-- Note : DESACCORD_MONTANT_FACTURE non utilisé ici (fn_ouvrir_litige passe
-- facture_id=NULL → fenêtre toujours ouverte). DESACCORD_HEURES_POINTAGE
-- utilise la fenêtre F1 (48h post-validation presence) → testable.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8a T7 — Hors fenêtre 48h + bypass admin =='

BEGIN;
DO $$
DECLARE
  v_etab_id UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_admin_id UUID;
  v_result JSONB;
  v_litige RECORD;
BEGIN
  SELECT user_id INTO v_admin_id FROM public.user_roles
   WHERE role = 'ADMIN_PLATEFORME' LIMIT 1;
  IF v_admin_id IS NULL THEN
    RAISE NOTICE '[T7] SKIP — aucun admin ADMIN_PLATEFORME disponible'; RETURN;
  END IF;

  INSERT INTO public.etablissements (id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact)
    VALUES (v_etab_id, 'CP8A_TEST_T7_Etab', '12345678900093', 'HOPITAL_PUBLIC', '7 rue', 'Paris', '75007', 'cp8a-t7@test.local');
  INSERT INTO public.soignants (id, nom, prenom, email, profession)
    VALUES (v_soignant_id, 'CP8A_TEST_T7_Nom', 'Gaël', 'cp8a-t7-' || v_soignant_id || '@test.local', 'IDE');
  INSERT INTO public.missions (id, etablissement_id, intitule, profession_requise, debut_le, fin_le, duree_heures, taux_horaire_base, statut, soignant_assigne_id)
    VALUES (v_mission_id, v_etab_id, 'CP8A_TEST_T7_Mission', 'IDE', NOW() - INTERVAL '6 days', NOW() - INTERVAL '5 days 16 hours', 8, 25, 'TERMINEE', v_soignant_id);
  INSERT INTO public.presences (id, mission_id, soignant_id, valide_par_etablissement, valide_le, heures_reelles)
    VALUES (v_presence_id, v_mission_id, v_soignant_id, TRUE, NOW() - INTERVAL '5 days', 8);

  -- Étape 1 : soignant hors fenêtre → refus attendu
  PERFORM set_config('request.jwt.claim.sub', v_soignant_id::text, true);
  v_result := public.fn_ouvrir_litige_rate_limited(
    v_mission_id, 'DESACCORD_HEURES_POINTAGE'::public.type_litige,
    'Soignant conteste les heures pointées (tentative hors fenêtre).'
  );

  IF NOT (v_result ? 'error') THEN
    RAISE NOTICE '[T7] FAIL — soignant hors fenêtre devrait être refusé, got success=%', v_result;
    RETURN;
  END IF;

  IF (v_result->>'error') NOT LIKE '%Fenêtre%' AND (v_result->>'error') NOT LIKE '%fenêtre%' THEN
    RAISE NOTICE '[T7] FAIL — error inattendue: %', v_result->>'error';
    RETURN;
  END IF;

  RAISE NOTICE '[T7] step1 OK — soignant refusé: %', v_result->>'error';

  -- Étape 2 : admin bypass → litige créé, est_informatif=TRUE
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  v_result := public.fn_admin_creer_litige_force(
    v_mission_id, 'DESACCORD_HEURES_POINTAGE'::public.type_litige,
    'Contestation tardive des heures — signalée par le soignant au support.',
    'Contestation reçue hors fenêtre, justifiée par circonstances exceptionnelles documentées.'
  );

  IF v_result ? 'error' THEN
    RAISE NOTICE '[T7] FAIL — admin bypass error: %', v_result->>'error';
    RETURN;
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = (v_result->>'litige_id')::UUID;

  IF NOT FOUND THEN
    RAISE NOTICE '[T7] FAIL — litige_id retourné mais introuvable';
  ELSIF v_litige.initie_par <> 'ADMIN' THEN
    RAISE NOTICE '[T7] FAIL — initie_par=% (attendu ADMIN)', v_litige.initie_par;
  ELSIF v_litige.est_informatif IS NOT TRUE THEN
    RAISE NOTICE '[T7] FAIL — est_informatif=% (attendu TRUE)', v_litige.est_informatif;
  ELSIF v_litige.statut <> 'OUVERT' THEN
    RAISE NOTICE '[T7] FAIL — statut=% (attendu OUVERT)', v_litige.statut;
  ELSE
    RAISE NOTICE '[T7] PASS — bypass admin OK: litige % (OUVERT, ADMIN, est_informatif=TRUE)', v_litige.id;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T7] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;
ROLLBACK;

\echo ''
\echo '== Fin CP8a T7 =='
