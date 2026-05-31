-- SWEEP antipattern Postgres `RECORD IS NOT NULL` : sur un RECORD issu de
-- SELECT * INTO, `v_rec IS NOT NULL` n'est vrai que si TOUTES les colonnes sont
-- non-nulles → quasi toujours faux (colonnes nullables) → la branche « ligne
-- trouvée » est silencieusement ignorée. 12 fonctions affectées (parrainage,
-- BFA, pauses, contestation paiement, code secours, scan QR, cohérence identité,
-- expiration docs, résolution litige legacy, annulation mission). Fix : tester
-- une colonne-clé (`.id`, ou `.type_document` quand l'id n'est pas sélectionné).
DO $mig$
DECLARE r RECORD; v_def text; v_new text;
BEGIN
  FOR r IN
    SELECT p.oid, x.var, x.keycol
    FROM (VALUES
      ('dec_verifier_docs_jusqua_fin','v_doc_expire','type_document'),
      ('fn_admin_resoudre_litige','v_mission','id'),
      ('fn_admin_resoudre_litige','v_presence','id'),
      ('fn_annuler_mission_etab','v_contrat','id'),
      ('fn_bfa_info','v_prochain','id'),
      ('fn_calculer_bfa','v_palier','id'),
      ('fn_litige_preuves_agregees','v_presence','id'),
      ('fn_pointer_debut_pause','v_pause_en_cours','id'),
      ('fn_repondre_contestation_paiement','v_litige','id'),
      ('fn_trg_valider_parrainage_soignant_premiere_mission','v_parrainage','id'),
      ('fn_valider_code_secours','v_presence','id'),
      ('fn_valider_scan_qr','v_presence','id'),
      ('fn_verifier_coherence_identite','v_doc_identite','id')
    ) AS x(fname,var,keycol)
    JOIN pg_proc p ON p.proname=x.fname AND p.pronamespace='public'::regnamespace
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := regexp_replace(v_def, '\m'||r.var||'\s+IS NOT NULL', r.var||'.'||r.keycol||' IS NOT NULL', 'g');
    IF v_new <> v_def THEN EXECUTE v_new; END IF;
  END LOOP;
END $mig$;
