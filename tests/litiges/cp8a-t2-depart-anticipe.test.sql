-- ============================================================
-- CP8a — T2 : Auto-création litige DEPART_ANTICIPE (Cas B partiel)
-- ============================================================
-- Prérequis : migrations CP-LITIGES 1 → 7b appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp8a-t2-depart-anticipe.test.sql
--
-- Scénario : mission 8h prévues, présence validée par étab il y a 48h,
-- heures_reelles=4 (moitié effectuée) → fn_auto_creation_litiges_presence()
-- doit créer un litige type=DEPART_ANTICIPE, statut=OUVERT.
--
-- Tout en BEGIN/ROLLBACK : pas de pollution base.
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== CP8a T2 — Départ anticipé (auto-création litige) =='

BEGIN;

DO $$
DECLARE
  v_etab_id     UUID := gen_random_uuid();
  v_soignant_id UUID := gen_random_uuid();
  v_mission_id  UUID := gen_random_uuid();
  v_presence_id UUID := gen_random_uuid();
  v_litige      RECORD;
  v_result      JSONB;
BEGIN
  INSERT INTO public.etablissements (
    id, nom, siret, type, adresse_rue, adresse_ville, adresse_code_postal, email_contact
  ) VALUES (
    v_etab_id, 'CP8A_TEST_T2_Etab', '12345678900098', 'HOPITAL_PUBLIC',
    '2 rue test', 'Paris', '75002', 'cp8a-t2@test.local'
  );

  INSERT INTO public.soignants (
    id, nom, prenom, email, profession
  ) VALUES (
    v_soignant_id, 'CP8A_TEST_T2_Nom', 'Bob',
    'cp8a-t2-' || v_soignant_id || '@test.local', 'IDE'
  );

  INSERT INTO public.missions (
    id, etablissement_id, intitule, profession_requise,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    statut, soignant_assigne_id
  ) VALUES (
    v_mission_id, v_etab_id, 'CP8A_TEST_T2_Mission', 'IDE',
    NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days 16 hours',
    8, 25, 'TERMINEE', v_soignant_id
  );

  INSERT INTO public.presences (
    id, mission_id, soignant_id,
    valide_par_etablissement, valide_le,
    heures_reelles, motif_litige, depart_anticipe_min
  ) VALUES (
    v_presence_id, v_mission_id, v_soignant_id,
    TRUE, NOW() - INTERVAL '49 hours',
    4, 'Soignant est parti en milieu de garde sans prévenir', 240
  );

  v_result := public.fn_auto_creation_litiges_presence();

  SELECT * INTO v_litige
    FROM public.litiges
   WHERE mission_id = v_mission_id
     AND type_litige = 'DEPART_ANTICIPE';

  IF NOT FOUND THEN
    RAISE NOTICE '[T2] FAIL — aucun litige DEPART_ANTICIPE créé (result=%)', v_result;
  ELSIF v_litige.statut <> 'OUVERT' THEN
    RAISE NOTICE '[T2] FAIL — statut=% au lieu de OUVERT', v_litige.statut;
  ELSE
    RAISE NOTICE '[T2] PASS — litige % créé (type=DEPART_ANTICIPE, statut=%, initie_par=%)',
      v_litige.id, v_litige.statut, v_litige.initie_par;
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[T2] FAIL — exception: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END $$;

ROLLBACK;

\echo ''
\echo '== Fin CP8a T2 =='
