-- BUG : fn_confirmer_remboursement_avoir passe l'avoir au statut 'REMBOURSE'
-- (remboursement confirmé), valeur absente de factures_honoraires_statut_check
-- -> la confirmation de remboursement d'avoir échouait (23514). Jamais atteint
-- jusqu'ici car la résolution litige -> AVOIR ne s'exécutait pas (bug record-NULL).
-- 'REMBOURSE' est le statut métier correct pour un avoir dont le virement est fait.
DO $mig$
DECLARE v_def text; v_expr text; v_new_expr text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint WHERE conname='factures_honoraires_statut_check';
  v_expr := substring(v_def from 7);
  v_new_expr := regexp_replace(v_expr, '\]\)\)\)\s*$', ', ''REMBOURSE''::text])))');
  IF v_new_expr = v_expr THEN RAISE EXCEPTION 'regex no match: %', right(v_expr,40); END IF;
  EXECUTE 'ALTER TABLE public.factures_honoraires DROP CONSTRAINT factures_honoraires_statut_check';
  EXECUTE 'ALTER TABLE public.factures_honoraires ADD CONSTRAINT factures_honoraires_statut_check CHECK ' || v_new_expr;
END $mig$;
