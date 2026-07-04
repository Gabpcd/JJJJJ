-- BUG : fn_calculer_score_etab référence public.notations (inexistante, renommée
-- en evaluations). Aussi les colonnes cible_id/cible_type/masquee_par_admin →
-- evalue_id/type_evaluateur/visible. Fix : renommer table + colonnes.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('public.fn_calculer_score_etab(uuid)'::regprocedure);
  v_new := replace(v_def, 'FROM public.notations', 'FROM public.evaluations');
  v_new := replace(v_new, 'cible_id = p_etablissement_id', 'evalue_id = p_etablissement_id');
  v_new := replace(v_new, 'cible_type = ''ETABLISSEMENT''', 'type_evaluateur = ''SOIGNANT''');
  v_new := replace(v_new, 'masquee_par_admin IS NOT TRUE', 'visible IS NOT FALSE');
  IF v_new = v_def THEN RAISE EXCEPTION 'aucun remplacement effectué'; END IF;
  EXECUTE v_new;
END $mig$;
