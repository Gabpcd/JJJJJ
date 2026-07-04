-- FIX bug latent (audit de cohérence CHECK ↔ code) : fn_admin_moderer_evaluation
-- insère dans journaux_audit l'action 'MODERATION_EVALUATION', absente de
-- journaux_audit_action_check → la fonction échoue dès qu'un admin modère une
-- évaluation (chemin rarement exercé, d'où le caractère latent). Même classe que
-- VALIDATION_ETABLISSEMENT (Sprint 4 audit). La convention existe déjà
-- ('MODERATION_DOCUMENT' est whitelistée) : on ajoute le pendant 'MODERATION_EVALUATION'.
DO $fix$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
  FROM pg_constraint WHERE conname='journaux_audit_action_check';

  IF position('MODERATION_EVALUATION' IN v_def) = 0 THEN
    ALTER TABLE public.journaux_audit DROP CONSTRAINT journaux_audit_action_check;
    -- Insère la nouvelle valeur juste avant la fermeture du tableau ('::text]' est unique).
    EXECUTE 'ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check ' ||
            replace(v_def, '::text]', ', ''MODERATION_EVALUATION''::text]');
  END IF;
END $fix$;
