-- BUG : fn_trg_parrainage_commission_encaissee insérait externalisation_actions.source_id
-- avec v_parrainage.id::text alors que la colonne source_id est de type uuid →
-- 42804 → l'enqueue de la prime de parrainage (50€ parrain + 50€ filleul) échouait
-- au seuil de 100€ de commission → aucune prime jamais versée. Fix : id uuid sans cast.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('public.fn_trg_parrainage_commission_encaissee()'::regprocedure);
  v_new := replace(v_def, '''parrainage_soignant'', v_parrainage.id::text)', '''parrainage_soignant'', v_parrainage.id)');
  IF v_new = v_def THEN RAISE EXCEPTION 'pattern non trouvé'; END IF;
  EXECUTE v_new;
END $mig$;
