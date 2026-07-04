-- notifications_type_check rejetait des types émis par des fonctions en place :
--   LITIGE_RESOLU_AJUSTE, AVOIR_EMIS (fn_admin_resoudre_litige),
--   COMMISSION_AJUSTEE (recalcul commission post-litige),
--   LITIGE_ESCALADE_ADMIN, LITIGE_MEDIATION_PRIORITAIRE (crons litiges),
--   LITIGE_RAPPEL_J1/J3/J5 (cron rappels litiges).
-- Ces notifications n'avaient jamais été émises jusque-là (masquées par le bug
-- record-NULL de fn_admin_resoudre_litige + crons jamais déclenchés en prod) ;
-- une fois ce bug corrigé elles butaient sur 23514. On aligne la contrainte.
DO $mig$
DECLARE
  v_def text; v_expr text; v_additions text; v_new_expr text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint WHERE conname='notifications_type_check';
  v_expr := substring(v_def from 7);
  v_additions := (
    SELECT string_agg(format(', %L::text', a), '')
    FROM unnest(ARRAY[
      'LITIGE_RESOLU_AJUSTE','AVOIR_EMIS','COMMISSION_AJUSTEE',
      'LITIGE_ESCALADE_ADMIN','LITIGE_MEDIATION_PRIORITAIRE',
      'LITIGE_RAPPEL_J1','LITIGE_RAPPEL_J3','LITIGE_RAPPEL_J5'
    ]) AS a
  );
  v_new_expr := regexp_replace(v_expr, '\]\)\)\)\s*$', v_additions || '])))');
  EXECUTE 'ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check';
  EXECUTE 'ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ' || v_new_expr;
END $mig$;
