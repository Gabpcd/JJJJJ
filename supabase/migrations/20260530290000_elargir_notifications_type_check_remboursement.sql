-- Types de notifications liés aux remboursements d'avoir absents de la
-- contrainte (jamais émis jusqu'ici car la résolution litige avec AVOIR ne
-- s'exécutait pas — bug record-NULL) :
--   REMBOURSEMENT_MANUEL_A_FAIRE (trigger admin fn_trg_notif_admin_remboursement_manuel)
--   REMBOURSEMENT_CONFIRME       (edge process-externalisation-actions, confirmation SWAN/manuel au soignant)
DO $mig$
DECLARE v_def text; v_expr text; v_additions text; v_new_expr text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint WHERE conname='notifications_type_check';
  v_expr := substring(v_def from 7);
  v_additions := (
    SELECT string_agg(format(', %L::text', a), '')
    FROM unnest(ARRAY['REMBOURSEMENT_MANUEL_A_FAIRE','REMBOURSEMENT_CONFIRME']) AS a
  );
  v_new_expr := regexp_replace(v_expr, '\]\)\)\)\s*$', v_additions || '])))');
  EXECUTE 'ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check';
  EXECUTE 'ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ' || v_new_expr;
END $mig$;
