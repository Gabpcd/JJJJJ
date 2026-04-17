-- ============================================================
-- Tests CP-LITIGES-2 — Triggers et RPCs fondamentales
-- ============================================================
-- Prérequis : migrations CP-LITIGES-1 (20260417130000) + CP-LITIGES-2
-- (20260417130100) appliquées.
-- Usage :
--   psql "$DB_URL" -f tests/litiges/cp2-triggers-rpcs.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-2 Triggers et RPCs =='

-- ──────────────────────────────────────────────────────────────
-- T1 : fn_ajouter_jours_ouvres (comportemental)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T1 : fn_ajouter_jours_ouvres'

-- T1.1 : vendredi + 1 jour ouvré = lundi (2026-04-17 vendredi → 2026-04-20 lundi)
SELECT
  CASE WHEN public.fn_ajouter_jours_ouvres('2026-04-17 10:00:00+02'::timestamptz, 1)::date
            = '2026-04-20'::date
       THEN '[1.1] OK — vendredi + 1 ouvré = lundi'
       ELSE '[1.1] FAIL — résultat : ' || public.fn_ajouter_jours_ouvres('2026-04-17 10:00:00+02'::timestamptz, 1)::text
  END;

-- T1.2 : lundi + 5 ouvrés = lundi suivant (2026-04-20 → 2026-04-27)
SELECT
  CASE WHEN public.fn_ajouter_jours_ouvres('2026-04-20 10:00:00+02'::timestamptz, 5)::date
            = '2026-04-27'::date
       THEN '[1.2] OK — lundi + 5 ouvrés = lundi+1semaine'
       ELSE '[1.2] FAIL — résultat : ' || public.fn_ajouter_jours_ouvres('2026-04-20 10:00:00+02'::timestamptz, 5)::text
  END;

-- T1.3 : 0 jour = même date
SELECT
  CASE WHEN public.fn_ajouter_jours_ouvres('2026-04-17 10:00:00+02'::timestamptz, 0)::date
            = '2026-04-17'::date
       THEN '[1.3] OK — 0 jour = même date'
       ELSE '[1.3] FAIL' END;

-- T1.4 : négatif — lundi - 1 ouvré = vendredi (2026-04-20 → 2026-04-17)
SELECT
  CASE WHEN public.fn_ajouter_jours_ouvres('2026-04-20 10:00:00+02'::timestamptz, -1)::date
            = '2026-04-17'::date
       THEN '[1.4] OK — lundi - 1 ouvré = vendredi'
       ELSE '[1.4] FAIL' END;

-- T1.5 : jour férié skippé — ex. 1er mai 2026 (vendredi férié) → mercredi + 2 ouvrés saute le 1er mai
-- 29/04/2026 (mer) + 2 ouvrés = normalement 01/05 (ven férié) skip → 04/05 (lun)
-- Note : ce test dépend de la présence du 2026-05-01 dans jours_feries_fr
DO $$
DECLARE
  v_is_feried BOOLEAN;
  v_result DATE;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.jours_feries_fr WHERE date_ferie = '2026-05-01'::date)
    INTO v_is_feried;
  IF NOT v_is_feried THEN
    RAISE NOTICE '[1.5] SKIP — 1er mai 2026 absent de jours_feries_fr';
    RETURN;
  END IF;
  v_result := public.fn_ajouter_jours_ouvres('2026-04-29 10:00:00+02'::timestamptz, 2)::date;
  IF v_result = '2026-05-04'::date THEN
    RAISE NOTICE '[1.5] OK — mercredi + 2 ouvrés saute 1er mai férié → lundi';
  ELSE
    RAISE NOTICE '[1.5] FAIL — résultat : %', v_result;
  END IF;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- T2 : trigger mapping catégorie (metadata + comportemental léger)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T2 : trg_litige_mapping_categorie'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[2.1] OK — trigger trg_litige_mapping_categorie présent'
       ELSE '[2.1] FAIL' END
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'litiges'
  AND t.tgname = 'trg_litige_mapping_categorie'
  AND NOT t.tgisinternal;

-- Vérifie les mappings via pattern matching sur la fonction source
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%ABSENCE_SOIGNANT%PRESENCE%'
        AND pg_get_functiondef(p.oid) LIKE '%DESACCORD_MONTANT_FACTURE%FINANCIER%'
        AND pg_get_functiondef(p.oid) LIKE '%SECURITE_DANGER%CONDITIONS%'
        AND pg_get_functiondef(p.oid) LIKE '%COMPORTEMENT_SOIGNANT%COMPORTEMENT%'
       THEN '[2.2] OK — 4 mappings clés présents dans la source'
       ELSE '[2.2] FAIL — mapping incomplet' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_trg_litige_mapping_categorie';

-- ──────────────────────────────────────────────────────────────
-- T3 : trigger gel/dégel facture (metadata)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T3 : trg_litige_gel_degel_facture'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[3.1] OK — trigger trg_litige_gel_degel_facture présent'
       ELSE '[3.1] FAIL' END
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'litiges'
  AND t.tgname = 'trg_litige_gel_degel_facture'
  AND NOT t.tgisinternal;

-- Vérifie présence des 2 branches (gel + dégel) dans la source
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%EN_ATTENTE_LITIGE%'
        AND pg_get_functiondef(p.oid) LIKE '%LITIGE_RESOLU_CONFIRME%'
        AND pg_get_functiondef(p.oid) LIKE '%est_informatif%'
        AND pg_get_functiondef(p.oid) LIKE '%PAYEE%'
       THEN '[3.2] OK — gel + dégel + garde-fous présents'
       ELSE '[3.2] FAIL — logique incomplète' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_trg_litige_gel_degel_facture';

-- ──────────────────────────────────────────────────────────────
-- T4 : fn_fenetre_contestation_ouverte (comportemental)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T4 : fn_fenetre_contestation_ouverte'

-- T4.1 : SECURITE_DANGER → toujours ouvert (UUID bidons OK car return précoce)
SELECT
  CASE WHEN public.fn_fenetre_contestation_ouverte(
              'SECURITE_DANGER'::public.type_litige,
              '00000000-0000-0000-0000-000000000000'::uuid,
              NULL)
       THEN '[4.1] OK — SECURITE_DANGER toujours ouvert'
       ELSE '[4.1] FAIL' END;

-- T4.2 : NON_PAIEMENT → toujours ouvert
SELECT
  CASE WHEN public.fn_fenetre_contestation_ouverte(
              'NON_PAIEMENT'::public.type_litige,
              '00000000-0000-0000-0000-000000000000'::uuid,
              NULL)
       THEN '[4.2] OK — NON_PAIEMENT toujours ouvert'
       ELSE '[4.2] FAIL' END;

-- T4.3 : AUTRE → toujours ouvert
SELECT
  CASE WHEN public.fn_fenetre_contestation_ouverte(
              'AUTRE'::public.type_litige,
              '00000000-0000-0000-0000-000000000000'::uuid,
              NULL)
       THEN '[4.3] OK — AUTRE toujours ouvert'
       ELSE '[4.3] FAIL' END;

-- T4.4 : DESACCORD_MONTANT_FACTURE sans facture_id → TRUE (ouvert par défaut)
SELECT
  CASE WHEN public.fn_fenetre_contestation_ouverte(
              'DESACCORD_MONTANT_FACTURE'::public.type_litige,
              '00000000-0000-0000-0000-000000000000'::uuid,
              NULL)
       THEN '[4.4] OK — DESACCORD_MONTANT_FACTURE sans facture_id = ouvert'
       ELSE '[4.4] FAIL' END;

-- T4.5 : COMPORTEMENT sur mission introuvable → TRUE (fallback)
SELECT
  CASE WHEN public.fn_fenetre_contestation_ouverte(
              'COMPORTEMENT_SOIGNANT'::public.type_litige,
              '00000000-0000-0000-0000-000000000000'::uuid,
              NULL)
       THEN '[4.5] OK — COMPORTEMENT sur mission introuvable = ouvert (fallback)'
       ELSE '[4.5] FAIL' END;

-- ──────────────────────────────────────────────────────────────
-- T5 : fn_admin_creer_litige_force (metadata + non-admin rejeté)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T5 : fn_admin_creer_litige_force'

SELECT
  CASE WHEN COUNT(*) = 1 THEN '[5.1] OK — fonction présente'
       ELSE '[5.1] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_admin_creer_litige_force';

-- En contexte psql (auth.uid() NULL), la RPC doit rejeter
DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := public.fn_admin_creer_litige_force(
    '00000000-0000-0000-0000-000000000000'::uuid,
    'AUTRE'::public.type_litige,
    'Test motif long minimum 10',
    'Test raison bypass long minimum 10'
  );
  IF v_result ? 'error' AND v_result->>'error' LIKE '%Admin%' THEN
    RAISE NOTICE '[5.2] OK — non-admin rejeté (error: %)', v_result->>'error';
  ELSE
    RAISE NOTICE '[5.2] FAIL — résultat inattendu : %', v_result;
  END IF;
END;
$$;

-- T5.3 : audit RGPD référencé dans la source
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%fn_ecrire_audit%'
        AND pg_get_functiondef(p.oid) LIKE '%LITIGE_FORCE_CREATION%'
       THEN '[5.3] OK — audit RGPD appelé avec action LITIGE_FORCE_CREATION'
       ELSE '[5.3] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_admin_creer_litige_force';

-- ──────────────────────────────────────────────────────────────
-- T6 : fn_ouvrir_litige_rate_limited — 2 signatures coexistent
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T6 : fn_ouvrir_litige_rate_limited surcharge'

SELECT
  CASE WHEN COUNT(*) = 2 THEN '[6.1] OK — 2 signatures (ancienne + nouvelle)'
       ELSE '[6.1] FAIL — ' || COUNT(*) || ' signatures trouvées' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'fn_ouvrir_litige_rate_limited';

-- Vérifie nouvelle signature 3-arg existe (avec type_litige)
SELECT
  CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
         JOIN pg_namespace n ON p.pronamespace = n.oid
         WHERE n.nspname = 'public'
           AND p.proname = 'fn_ouvrir_litige_rate_limited'
           AND pg_get_function_identity_arguments(p.oid) LIKE '%type_litige%'
       )
       THEN '[6.2] OK — signature 3-arg (type_litige) présente'
       ELSE '[6.2] FAIL — signature 3-arg absente' END;

-- Vérifie wrapper 2-arg contient RAISE WARNING DEPRECATED
SELECT
  CASE WHEN pg_get_functiondef(p.oid) LIKE '%DEPRECATED%'
       THEN '[6.3] OK — wrapper 2-arg marqué DEPRECATED'
       ELSE '[6.3] FAIL' END
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'fn_ouvrir_litige_rate_limited'
  AND pg_get_function_identity_arguments(p.oid) = 'p_mission_id uuid, p_motif text';

-- ──────────────────────────────────────────────────────────────
-- T7 : GRANTS (authenticated + service_role)
-- ──────────────────────────────────────────────────────────────
\echo ''
\echo '-- T7 : GRANTs sur les nouvelles RPCs'

SELECT
  CASE WHEN COUNT(*) >= 8 THEN '[7] OK — grants sur nouvelles RPCs OK (' || COUNT(*) || ' privilèges)'
       ELSE '[7] FAIL — ' || COUNT(*) || ' privilèges (attendu >= 8 : 4 RPCs × 2 roles)' END
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'fn_ajouter_jours_ouvres',
    'fn_fenetre_contestation_ouverte',
    'fn_admin_creer_litige_force'
  )
  AND privilege_type = 'EXECUTE'
  AND grantee IN ('authenticated', 'service_role');

\echo ''
\echo '== FIN CP-LITIGES-2 =='
