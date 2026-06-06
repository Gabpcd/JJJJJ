-- AUDIT performance (Supabase advisors) — auth_rls_initplan (76 policies).
-- Les politiques RLS qui appellent auth.uid()/auth.role()/auth.jwt()/auth.email()
-- "nus" ré-évaluent la fonction POUR CHAQUE LIGNE. La recommandation officielle
-- Supabase est de wrapper l'appel dans un sous-select : `(select auth.uid())`,
-- évalué une seule fois par requête (InitPlan). Transformation sémantiquement neutre.
--
-- Rewrite générique idempotent : déballe d'abord toute forme `(select auth.x() [AS alias])`
-- puis ré-emballe uniformément. Vérifié en dry-run : 76 policies modifiées, 0 appel nu
-- restant. Ne touche QUE les policies ayant un appel nu (les déjà-wrappées sont ignorées).
DO $mig$
DECLARE
  r RECORD;
  v_qual text; v_check text; v_sql text;
  v_unwrap text := '\(\s*[Ss][Ee][Ll][Ee][Cc][Tt]\s+(auth\.(uid|role|jwt|email)\(\))(\s+[Aa][Ss]\s+\w+)?\s*\)';
  v_bare   text := '(auth\.(uid|role|jwt|email)\(\))';
BEGIN
  FOR r IN SELECT tablename, policyname, qual, with_check FROM pg_policies WHERE schemaname='public'
  LOOP
    IF (regexp_replace(COALESCE(r.qual,''), v_unwrap, '', 'g') ~ v_bare)
       OR (regexp_replace(COALESCE(r.with_check,''), v_unwrap, '', 'g') ~ v_bare) THEN
      v_qual := CASE WHEN r.qual IS NOT NULL THEN
        regexp_replace(regexp_replace(r.qual, v_unwrap, '\1', 'g'), v_bare, '(SELECT \1)', 'g') END;
      v_check := CASE WHEN r.with_check IS NOT NULL THEN
        regexp_replace(regexp_replace(r.with_check, v_unwrap, '\1', 'g'), v_bare, '(SELECT \1)', 'g') END;
      v_sql := 'ALTER POLICY ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
      IF v_qual IS NOT NULL THEN v_sql := v_sql || ' USING (' || v_qual || ')'; END IF;
      IF v_check IS NOT NULL THEN v_sql := v_sql || ' WITH CHECK (' || v_check || ')'; END IF;
      EXECUTE v_sql;
    END IF;
  END LOOP;
END $mig$;
