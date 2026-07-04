-- BUG : fn_verifier_coherence_identite insère priorite='HAUTE' (texte) dans
-- file_revue_manuelle.priorite (integer) → crash à chaque incohérence identité.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('public.fn_verifier_coherence_identite(uuid)'::regprocedure);
  v_new := replace(v_def, '''EN_ATTENTE'', ''HAUTE'')', '''EN_ATTENTE'', 4)');
  IF v_new = v_def THEN RAISE EXCEPTION 'pattern non trouvé'; END IF;
  EXECUTE v_new;
END $mig$;
