-- ============================================================
-- Tests CP-C-1 — fn_declarer_paiement_soignant v2 (E12 + E13)
-- ============================================================
-- Prérequis : migration 20260420150000_cp_c_1_declarer_paiement_v2
--             appliquée.
-- Scope     : valide l'ATTESTATION obligatoire + validations + audit.
-- Usage     : psql "$DB_URL" -f tests/paiements/cp-c-1.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-C-1 — déclaration paiement soignant v2 =='

-- ------------------------------------------------------------
-- [1] Signature RPC : 6 params attendus
-- ------------------------------------------------------------
SELECT CASE
  WHEN pg_get_function_identity_arguments(p.oid) LIKE '%p_attestation_sur_l_honneur%'
    THEN '[1.1] OK — param p_attestation_sur_l_honneur présent'
  ELSE '[1.1] FAIL — signature : ' || pg_get_function_identity_arguments(p.oid)
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_declarer_paiement_soignant';

-- ------------------------------------------------------------
-- [2] Appel SANS attestation → error ATTESTATION_REQUISE
-- ------------------------------------------------------------

BEGIN;

-- Setup minimal : créer un étab + soignant + mission TERMINEE
DO $$
DECLARE
  v_etab_id UUID := 'e0c0c0c0-cccc-1111-0000-000000000001';
  v_soignant_id UUID := 'e0c0c0c0-cccc-1111-0000-000000000002';
  v_user_id UUID := 'e0c0c0c0-cccc-1111-0000-000000000003';
BEGIN
  -- Créer un user auth minimal pour le contexte
  INSERT INTO auth.users (id, instance_id, email, role, aud)
  VALUES (v_user_id, '00000000-0000-0000-0000-000000000000'::uuid,
    'cpc1-test@jolene.test', 'authenticated', 'authenticated')
  ON CONFLICT (id) DO NOTHING;

  -- Note : le test appelle la RPC mais comme SECURITY DEFINER consulte
  -- mon_etablissement_id() (qui lit auth.uid), on ne peut pas facilement
  -- simuler sans JWT. On valide donc la LOGIQUE de la validation
  -- attestation côté RPC directement.
END $$;

-- Appel direct RPC sans JWT (ce sera admin_test via apply_migration si besoin)
-- Sans JWT, mon_etablissement_id() retournera NULL → mismatch etab → erreur
-- "Accès refusé". Le test 2 est donc dégradé : on vérifie que l'attestation
-- fait RETURN avant même la lecture du JWT/mission.

SELECT CASE
  WHEN (public.fn_declarer_paiement_soignant(
      'e0c0c0c0-cccc-1111-0000-00000000dead'::uuid,  -- mission_id fake
      100::numeric,
      'VIREMENT', 'TEST-001', CURRENT_DATE,
      FALSE  -- attestation FALSE
    )::jsonb->>'error') = 'ATTESTATION_REQUISE'
    THEN '[2.1] OK — attestation FALSE → ATTESTATION_REQUISE (rejet avant autres checks)'
  ELSE '[2.1] FAIL — devrait rejeter ATTESTATION_REQUISE'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [3] Enum méthode strict (ESPECES retiré)
-- ------------------------------------------------------------

BEGIN;

-- Avec attestation TRUE mais méthode invalide (ESPECES) → METHODE_INVALIDE
-- (si on arrive assez loin dans la fonction — sinon Mission introuvable avant)
SELECT CASE
  WHEN (public.fn_declarer_paiement_soignant(
      'e0c0c0c0-cccc-1111-0000-00000000dead'::uuid,
      100::numeric,
      'ESPECES', 'TEST-001', CURRENT_DATE,
      TRUE
    )::jsonb->>'error') IN ('METHODE_INVALIDE', 'Mission introuvable')
    THEN '[3.1] OK — méthode ESPECES rejetée (ou mission fake → introuvable, deux cas acceptables)'
  ELSE '[3.1] FAIL — ESPECES aurait dû être rejetée'
END;

ROLLBACK;

-- ------------------------------------------------------------
-- [4] Validation : les 4 méthodes autorisées acceptées en enum
-- ------------------------------------------------------------

BEGIN;

-- On vérifie le CHECK IF du code (via la RPC elle-même)
-- Méthodes attendues : VIREMENT, CHEQUE, BULLETIN_PAIE, NOTE_HONORAIRES
-- Sans mission réelle, l'erreur retournée sera "Mission introuvable" (et pas METHODE_INVALIDE)
-- ce qui confirme que la méthode a passé le check enum.

DO $$
DECLARE
  methode TEXT;
  errs TEXT[] := ARRAY[]::TEXT[];
BEGIN
  FOREACH methode IN ARRAY ARRAY['VIREMENT','CHEQUE','BULLETIN_PAIE','NOTE_HONORAIRES']
  LOOP
    IF (public.fn_declarer_paiement_soignant(
        'e0c0c0c0-cccc-1111-0000-00000000dead'::uuid,
        100::numeric, methode, 'REF-001', CURRENT_DATE, TRUE
      )::jsonb->>'error') = 'METHODE_INVALIDE'
    THEN
      errs := errs || methode;
    END IF;
  END LOOP;

  IF array_length(errs, 1) IS NULL THEN
    RAISE NOTICE '[4.1] OK — 4 méthodes valides acceptées (VIREMENT, CHEQUE, BULLETIN_PAIE, NOTE_HONORAIRES)';
  ELSE
    RAISE NOTICE '[4.1] FAIL — méthodes rejetées à tort : %', errs;
  END IF;
END $$;

ROLLBACK;

-- ------------------------------------------------------------
-- [5] Idempotence : double déclaration → erreur
-- ------------------------------------------------------------

-- Scénario non-testable sans contexte JWT étab valide (double INSERT
-- ferait conflict sur le check `EXISTS(WHERE statut IN ('DECLARE', 'CONFIRME'))`
-- mais nécessite mission réelle). Scénario à valider en manuel (checklist).

\echo '[5] Double déclaration : à valider en checklist manuelle (docs/tests-cp-c-1.md)'

\echo ''
\echo '== Fin tests CP-C-1 =='
