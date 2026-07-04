-- BUG : les deux INSERT de fn_admin_resoudre_litige (réémission ANNULER_REEMETTRE
-- et AVOIR) omettaient periode_debut/periode_fin (NOT NULL) → la résolution de
-- litige avec ajustement financier échouait (23502). On hérite la période de la
-- facture d'origine (même mission). Patch dynamique ciblé sur les 2 blocs INSERT.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.fn_admin_resoudre_litige(uuid,text,text,numeric,numeric,text)'::regprocedure) INTO v_def;
  v_new := v_def;

  -- INSERT ANNULER_REEMETTRE : colonnes
  v_new := replace(v_new,
    E'      statut, mandat_version, type_document, facture_precedente_id,\n      statut_litige, litige_id, pdf_a_regenerer\n    ) VALUES (',
    E'      statut, mandat_version, type_document, facture_precedente_id,\n      statut_litige, litige_id, pdf_a_regenerer,\n      periode_debut, periode_fin, numero_semaine_iso, annee_iso\n    ) VALUES (');
  -- INSERT ANNULER_REEMETTRE : valeurs
  v_new := replace(v_new,
    E'      ''LITIGE_RESOLU_AJUSTE'', p_litige_id, TRUE\n    )\n    RETURNING id INTO v_nouvelle_facture_id;',
    E'      ''LITIGE_RESOLU_AJUSTE'', p_litige_id, TRUE,\n      COALESCE(v_facture.periode_debut, CURRENT_DATE),\n      COALESCE(v_facture.periode_fin, v_facture.periode_debut, CURRENT_DATE),\n      v_facture.numero_semaine_iso, v_facture.annee_iso\n    )\n    RETURNING id INTO v_nouvelle_facture_id;');

  -- INSERT AVOIR : colonnes
  v_new := replace(v_new,
    E'        statut, mandat_version, type_document, facture_precedente_id,\n        statut_litige, litige_id, mode_remboursement, pdf_a_regenerer\n      ) VALUES (',
    E'        statut, mandat_version, type_document, facture_precedente_id,\n        statut_litige, litige_id, mode_remboursement, pdf_a_regenerer,\n        periode_debut, periode_fin, numero_semaine_iso, annee_iso\n      ) VALUES (');
  -- INSERT AVOIR : valeurs
  v_new := replace(v_new,
    E'        ''LITIGE_RESOLU_AJUSTE'', p_litige_id, v_mode_remboursement, TRUE\n      )\n      RETURNING id INTO v_avoir_id;',
    E'        ''LITIGE_RESOLU_AJUSTE'', p_litige_id, v_mode_remboursement, TRUE,\n        COALESCE(v_facture.periode_debut, CURRENT_DATE),\n        COALESCE(v_facture.periode_fin, v_facture.periode_debut, CURRENT_DATE),\n        v_facture.numero_semaine_iso, v_facture.annee_iso\n      )\n      RETURNING id INTO v_avoir_id;');

  IF v_new = v_def THEN
    RAISE EXCEPTION 'Aucun remplacement effectué — vérifier les fragments';
  END IF;
  EXECUTE v_new;
END $mig$;
