-- BUG 1 : fn_rgpd_exporter_rate_limited appelle fn_rgpd_exporter_donnees_soignant()
-- sans argument. Fix : passer v_user_id (= auth.uid()).
-- BUG 2 : fn_supprimer_mon_compte référence 'favoris' (inexistante, renommée en
-- favoris_soignant_etab) + compare signataire_soignant_id (text) = v_uid (uuid)
-- sans cast → suppression de compte RGPD cassée. Fix : renommer + cast ::text.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  -- Fix 1 : rate_limited
  v_def := pg_get_functiondef('public.fn_rgpd_exporter_rate_limited()'::regprocedure);
  v_new := replace(v_def, 'fn_rgpd_exporter_donnees_soignant()', 'fn_rgpd_exporter_donnees_soignant(v_user_id)');
  IF v_new = v_def THEN RAISE EXCEPTION 'pattern 1 non trouvé'; END IF;
  EXECUTE v_new;

  -- Fix 2a : favoris table
  v_def := pg_get_functiondef('public.fn_supprimer_mon_compte()'::regprocedure);
  v_new := replace(v_def, 'FROM favoris WHERE', 'FROM favoris_soignant_etab WHERE');
  IF v_new = v_def THEN NULL; END IF; -- peut être déjà corrigé par apply_migration antérieure
  -- Fix 2b : signatures_yousign cast
  v_new := COALESCE(v_new, v_def);
  v_new := replace(v_new, 'WHERE signataire_soignant_id = v_uid', 'WHERE signataire_soignant_id = v_uid::text');
  IF v_new <> v_def THEN EXECUTE v_new; END IF;
END $mig$;
