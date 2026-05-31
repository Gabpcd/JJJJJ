-- Ajouter MODERATION_DOCUMENT + COHERENCE_IDENTITE_VERIFIEE à journaux_audit_action_check
DO $mig$
DECLARE v_def text; v_expr text; v_additions text; v_new_expr text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint WHERE conname='journaux_audit_action_check';
  v_expr := substring(v_def from 7);
  v_additions := ', ''MODERATION_DOCUMENT''::text, ''COHERENCE_IDENTITE_VERIFIEE''::text';
  v_new_expr := regexp_replace(v_expr, '\]\)\)\)\s*$', v_additions || '])))');
  EXECUTE 'ALTER TABLE public.journaux_audit DROP CONSTRAINT journaux_audit_action_check';
  EXECUTE 'ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK ' || v_new_expr;
END $mig$;
