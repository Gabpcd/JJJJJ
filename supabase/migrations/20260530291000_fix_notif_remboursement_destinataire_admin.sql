-- BUG : fn_trg_notif_admin_remboursement_manuel insérait type_destinataire =
-- 'ADMIN_PLATEFORME', valeur rejetée par notifications_type_destinataire_check
-- (SOIGNANT/ETABLISSEMENT/ADMIN). En plus de bloquer l'INSERT (23514), la
-- convention de l'app filtre les notifs admin sur type_destinataire='ADMIN' :
-- une valeur 'ADMIN_PLATEFORME' aurait été invisible côté UI admin.
-- Fix : utiliser 'ADMIN'. (v_admin_id provient de fn_list_admin_user_ids(),
-- aucun filtre de rôle inline n'est impacté par ce remplacement.)
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.fn_trg_notif_admin_remboursement_manuel()'::regprocedure) INTO v_def;
  v_new := replace(v_def, '''ADMIN_PLATEFORME''', '''ADMIN''');
  IF v_new = v_def THEN RAISE EXCEPTION 'no replacement'; END IF;
  EXECUTE v_new;
END $mig$;
