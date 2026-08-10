-- Retour arrière explicite des changements introduits par les PR #935 et #936.
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_top_soignants(
  p_profession text DEFAULT NULL,
  p_limit integer DEFAULT 20
)
RETURNS TABLE(
  id uuid,
  prenom text,
  nom text,
  profession text,
  note_moyenne numeric,
  nb_evaluations integer,
  score_fiabilite integer,
  total_missions_terminees integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.id, s.prenom, s.nom, s.profession::TEXT, s.note_moyenne, s.nb_evaluations,
           ROUND(COALESCE(s.score_fiabilite, 0))::integer AS score_fiabilite,
           s.total_missions_terminees
    FROM soignants s
    WHERE s.supprime_le IS NULL
    AND s.est_compte_test = false
    AND fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND (p_profession IS NULL OR s.profession::TEXT = p_profession)
    ORDER BY s.note_moyenne DESC NULLS LAST, s.score_fiabilite DESC, s.total_missions_terminees DESC
    LIMIT p_limit;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_dans_fenetre_retractation(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.fn_dans_fenetre_retractation(uuid)
  TO authenticated, service_role;

INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
)
VALUES
  (
    'fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)'::regprocedure)),
    'RPC établissement/admin : sépare total net dû et montant versé et refuse les paiements partiels ou les surpaiements.',
    now()
  ),
  (
    'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)'::regprocedure)),
    'Compatibilité libéral uniquement ; les salaires exigent désormais le total dû explicite via v2.',
    now()
  ),
  (
    'fn_paiements_etablissement()',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_paiements_etablissement()'::regprocedure)),
    'Lecture financière bornée par permission, enrichie du total dû et du reliquat.',
    now()
  ),
  (
    'fn_obligations_financieres()',
    'MIXTE_TENANT_ADMIN',
    md5(pg_get_functiondef('public.fn_obligations_financieres()'::regprocedure)),
    'Lecture des obligations financières bornée au tenant et enrichie du total dû et du reliquat.',
    now()
  ),
  (
    'fn_diagnostic_coherence_financiere()',
    'ADMIN_EST_ADMIN_VALIDE',
    md5(pg_get_functiondef('public.fn_diagnostic_coherence_financiere()'::regprocedure)),
    'Diagnostic admin : compare le brut de base au taux x heures et les factures hebdomadaires à leur période exacte.',
    now()
  ),
  (
    'fn_marquer_messages_lus(uuid)',
    'MIXTE_TENANT_ADMIN',
    'f51bcb1f94bfe5b19cebeb53d8b84711',
    'RPC mixte: branche tenant (auth.uid) et élévation admin (est_admin() explicitement conservées.',
    now()
  ),
  (
    'fn_top_soignants(text,integer)',
    'RPC_UTILISATEUR_AUTH_INTERNE',
    'e400f441004b009d497b1dfdbe8483ff',
    'RPC authenticated: identité/tenancy interne observée (fn_documents_ok_pour_mission).',
    now()
  ),
  (
    'fn_dans_fenetre_retractation(uuid)',
    'RPC_UTILISATEUR_AUTH_INTERNE',
    '5248dd60f1d0a37b8ee919c9f512e9e8',
    'RPC authenticated de lecture/référentiel ou wrapper vers une RPC canonique; ACL et appelants recensés.',
    now()
  )
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_rollback_classement_security_inventory$
DECLARE
  v_definition text;
  v_bad text;
BEGIN
  SELECT pg_get_functiondef(
    'public.fn_top_soignants(text,integer)'::regprocedure
  ) INTO v_definition;

  IF v_definition NOT LIKE '%LIMIT p_limit;%'
     OR v_definition LIKE '%v_limit integer%' THEN
    RAISE EXCEPTION 'Le rollback de fn_top_soignants n''est pas effectif';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM true
     OR has_function_privilege(
       'service_role',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Le rollback des droits de fn_dans_fenetre_retractation n''est pas effectif';
  END IF;

  WITH expected(signature, categorie, definition_md5, justification) AS (
    VALUES
      (
        'fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)',
        'MIXTE_TENANT_ADMIN',
        md5(pg_get_functiondef('public.fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)'::regprocedure)),
        'RPC établissement/admin : sépare total net dû et montant versé et refuse les paiements partiels ou les surpaiements.'
      ),
      (
        'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)',
        'MIXTE_TENANT_ADMIN',
        md5(pg_get_functiondef('public.fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)'::regprocedure)),
        'Compatibilité libéral uniquement ; les salaires exigent désormais le total dû explicite via v2.'
      ),
      (
        'fn_paiements_etablissement()',
        'MIXTE_TENANT_ADMIN',
        md5(pg_get_functiondef('public.fn_paiements_etablissement()'::regprocedure)),
        'Lecture financière bornée par permission, enrichie du total dû et du reliquat.'
      ),
      (
        'fn_obligations_financieres()',
        'MIXTE_TENANT_ADMIN',
        md5(pg_get_functiondef('public.fn_obligations_financieres()'::regprocedure)),
        'Lecture des obligations financières bornée au tenant et enrichie du total dû et du reliquat.'
      ),
      (
        'fn_diagnostic_coherence_financiere()',
        'ADMIN_EST_ADMIN_VALIDE',
        md5(pg_get_functiondef('public.fn_diagnostic_coherence_financiere()'::regprocedure)),
        'Diagnostic admin : compare le brut de base au taux x heures et les factures hebdomadaires à leur période exacte.'
      ),
      (
        'fn_marquer_messages_lus(uuid)',
        'MIXTE_TENANT_ADMIN',
        'f51bcb1f94bfe5b19cebeb53d8b84711',
        'RPC mixte: branche tenant (auth.uid) et élévation admin (est_admin() explicitement conservées.'
      ),
      (
        'fn_top_soignants(text,integer)',
        'RPC_UTILISATEUR_AUTH_INTERNE',
        'e400f441004b009d497b1dfdbe8483ff',
        'RPC authenticated: identité/tenancy interne observée (fn_documents_ok_pour_mission).'
      ),
      (
        'fn_dans_fenetre_retractation(uuid)',
        'RPC_UTILISATEUR_AUTH_INTERNE',
        '5248dd60f1d0a37b8ee919c9f512e9e8',
        'RPC authenticated de lecture/référentiel ou wrapper vers une RPC canonique; ACL et appelants recensés.'
      )
  )
  SELECT string_agg(e.signature, ', ' ORDER BY e.signature)
  INTO v_bad
  FROM expected e
  LEFT JOIN private.security_definer_inventory i ON i.signature = e.signature
  WHERE i.signature IS NULL
     OR i.categorie IS DISTINCT FROM e.categorie
     OR i.definition_md5 IS DISTINCT FROM e.definition_md5
     OR i.justification IS DISTINCT FROM e.justification;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Rollback incomplet de l''inventaire SECURITY DEFINER : %', v_bad;
  END IF;
END;
$assert_rollback_classement_security_inventory$;

COMMIT;
