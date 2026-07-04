-- BUG : fn_admin_resoudre_litige testait l'existence d'enregistrements via
-- `v_facture IS NOT NULL` / `v_litige IS NOT NULL`. Sur un RECORD, `IS NOT NULL`
-- n'est vrai que si TOUS les champs sont non-nuls — or une facture (date_paiement,
-- pdf_s3_key, ...) et un litige (resolu_par, presence_id, ...) ont toujours des
-- colonnes nullables. Résultat : ces expressions étaient TOUJOURS fausses.
--   • v_facture : les branches financières (RECALCUL / ANNULER_REEMETTRE / AVOIR)
--     et le calcul heures/taux étaient systématiquement ignorés → le litige était
--     marqué résolu sans qu'AUCUN ajustement de facture/avoir ne soit appliqué.
--   • v_litige  : les notifications de résolution (soignant + établissement, et
--     l'email d'avoir) n'étaient jamais envoyées.
-- Fix : tester `.id IS [NOT] NULL` comme test d'existence correct. Patch
-- dynamique pour ne rien changer d'autre au corps de la fonction.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p
  WHERE p.pronamespace='public'::regnamespace
    AND p.proname='fn_admin_resoudre_litige'
    AND pg_get_function_identity_arguments(p.oid) LIKE '%p_action_financiere%';

  v_new := replace(v_def, 'v_facture IS NOT NULL', 'v_facture.id IS NOT NULL');
  v_new := replace(v_new, 'v_facture IS NULL', 'v_facture.id IS NULL');
  v_new := replace(v_new, 'v_litige IS NOT NULL', 'v_litige.id IS NOT NULL');

  IF v_new = v_def THEN
    RAISE EXCEPTION 'Aucun remplacement effectué — abandon';
  END IF;
  EXECUTE v_new;
END $mig$;
