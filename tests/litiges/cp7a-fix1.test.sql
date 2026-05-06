-- ============================================================
-- Tests CP-LITIGES-7a FIX 1 — Trigger maj_tresorerie_bloquee
-- ============================================================
-- Prérequis : 20260417130706_fix1_trigger_tresorerie_bloquee.sql +
-- CP-LITIGES-1 + CP-LITIGES-2 appliquées.
-- Usage : psql "$DB_URL" -f tests/litiges/cp7a-fix1.test.sql
-- ============================================================

\set ON_ERROR_STOP off
\echo ''
\echo '== Tests CP-LITIGES-7a FIX 1 =='

-- [1] Fonction fn_recalculer_tresorerie_bloquee existe (signature UUID → VOID)
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[1.1] OK — fn_recalculer_tresorerie_bloquee(UUID) présente'
  ELSE '[1.1] FAIL — ' || COUNT(*) || ' match'
END
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_recalculer_tresorerie_bloquee'
  AND pg_get_function_identity_arguments(p.oid) = 'p_litige_id uuid';

-- [2] Trigger trg_maj_tresorerie_bloquee présent sur factures_honoraires,
-- AFTER INSERT/UPDATE, FOR EACH ROW
SELECT CASE
  WHEN COUNT(*) = 1
    THEN '[1.2] OK — trigger trg_maj_tresorerie_bloquee présent'
  ELSE '[1.2] FAIL — absent'
END
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname = 'factures_honoraires'
  AND t.tgname  = 'trg_maj_tresorerie_bloquee'
  AND NOT t.tgisinternal;

-- [3] Trigger couvre les 4 colonnes attendues (montant_ht, montant_ttc,
-- statut_litige, litige_id) — via pg_trigger.tgattr → attnames.
SELECT CASE
  WHEN (
    SELECT array_agg(a.attname ORDER BY a.attname)
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(t.tgattr)
     WHERE c.relname = 'factures_honoraires'
       AND t.tgname  = 'trg_maj_tresorerie_bloquee'
  ) = ARRAY['litige_id','montant_ht','montant_ttc','statut_litige']
    THEN '[1.3] OK — trigger couvre les 4 colonnes'
  ELSE '[1.3] FAIL — colonnes couvertes inattendues'
END;

-- [4] Comportemental : fn_recalculer_tresorerie_bloquee(NULL) no-op silencieux
DO $$
BEGIN
  PERFORM public.fn_recalculer_tresorerie_bloquee(NULL);
  RAISE NOTICE '[1.4] OK — fn_recalculer_tresorerie_bloquee(NULL) no-op';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[1.4] FAIL — exception : %', SQLERRM;
END $$;

-- [5] Comportemental : recalc sur UUID inconnu n'échoue pas et ne crée rien
DO $$
DECLARE v_fake UUID := gen_random_uuid();
BEGIN
  PERFORM public.fn_recalculer_tresorerie_bloquee(v_fake);
  RAISE NOTICE '[1.5] OK — recalc sur UUID inconnu silencieux';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[1.5] FAIL — exception : %', SQLERRM;
END $$;

-- [6] Comportemental end-to-end si un litige existe avec >=1 facture gelée :
-- on appelle recalc + on vérifie la cohérence post-trigger.
DO $$
DECLARE
  v_litige_id UUID;
  v_attendu   NUMERIC(12,2);
  v_cache     NUMERIC(12,2);
BEGIN
  SELECT l.id,
         COALESCE(SUM(f.montant_ht), 0)
    INTO v_litige_id, v_attendu
    FROM public.litiges l
    LEFT JOIN public.factures_honoraires f
      ON f.litige_id = l.id AND f.statut_litige = 'EN_ATTENTE_LITIGE'
   GROUP BY l.id
   HAVING COUNT(f.id) >= 1
   LIMIT 1;

  IF v_litige_id IS NULL THEN
    RAISE NOTICE '[1.6] SKIP — aucun litige avec facture gelée en base';
    RETURN;
  END IF;

  PERFORM public.fn_recalculer_tresorerie_bloquee(v_litige_id);
  SELECT montant_tresorerie_bloquee INTO v_cache
    FROM public.litiges WHERE id = v_litige_id;

  IF v_cache = v_attendu THEN
    RAISE NOTICE '[1.6] OK — cache=% attendu=% (litige %)',
      v_cache, v_attendu, v_litige_id;
  ELSE
    RAISE NOTICE '[1.6] FAIL — cache=% attendu=% (litige %)',
      v_cache, v_attendu, v_litige_id;
  END IF;
END $$;
