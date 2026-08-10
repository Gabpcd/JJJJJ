-- Aligne le classement affiché et l'inventaire SECURITY DEFINER sur les
-- conventions réellement contrôlées par le drift quotidien.
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
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.prenom,
    s.nom,
    s.profession::text,
    s.note_moyenne,
    s.nb_evaluations,
    ROUND(COALESCE(s.score_fiabilite, 0))::integer,
    s.total_missions_terminees
  FROM public.soignants s
  WHERE s.supprime_le IS NULL
    AND s.est_compte_test = false
    AND public.fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND (p_profession IS NULL OR s.profession::text = p_profession)
  ORDER BY
    s.note_moyenne DESC NULLS LAST,
    s.score_fiabilite DESC,
    s.total_missions_terminees DESC
  LIMIT v_limit;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_dans_fenetre_retractation(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_dans_fenetre_retractation(uuid)
  TO service_role;

-- L'inventaire et le contrôle de drift doivent tous deux empreinter pg_proc.prosrc.
-- On recapture les six fonctions signalées, la RPC de classement modifiée et
-- le helper de test dont l'ACL vient d'être resserrée.
WITH reviewed(signature, procedure_oid, categorie, justification) AS (
  VALUES
    (
      'fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)',
      'public.fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)'::regprocedure,
      'MIXTE_TENANT_ADMIN',
      'RPC établissement/admin : sépare total net dû et montant versé et refuse les paiements partiels ou les surpaiements.'
    ),
    (
      'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)',
      'public.fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)'::regprocedure,
      'MIXTE_TENANT_ADMIN',
      'Compatibilité libéral uniquement ; les salaires exigent le total dû explicite via v2.'
    ),
    (
      'fn_diagnostic_coherence_financiere()',
      'public.fn_diagnostic_coherence_financiere()'::regprocedure,
      'ADMIN_EST_ADMIN_VALIDE',
      'Diagnostic admin : contrôle la cohérence des montants et des périodes financières.'
    ),
    (
      'fn_marquer_messages_lus(uuid)',
      'public.fn_marquer_messages_lus(uuid)'::regprocedure,
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'Messagerie authentifiée : marque uniquement les messages d’une conversation autorisée.'
    ),
    (
      'fn_obligations_financieres()',
      'public.fn_obligations_financieres()'::regprocedure,
      'MIXTE_TENANT_ADMIN',
      'Lecture des obligations financières bornée au tenant, avec total dû et reliquat.'
    ),
    (
      'fn_paiements_etablissement()',
      'public.fn_paiements_etablissement()'::regprocedure,
      'MIXTE_TENANT_ADMIN',
      'Lecture financière bornée par permission, avec total dû et reliquat.'
    ),
    (
      'fn_top_soignants(text,integer)',
      'public.fn_top_soignants(text,integer)'::regprocedure,
      'RPC_UTILISATEUR_AUTH_INTERNE',
      'Classement authentifié : renvoie prénom et nom et borne toute réponse à cinquante soignants.'
    ),
    (
      'fn_dans_fenetre_retractation(uuid)',
      'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
      'SERVICE_ONLY_REVOQUE',
      'Helper réservé aux tests transactionnels exécutés avec service_role ; aucun appel produit authentifié.'
    )
)
INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
)
SELECT
  r.signature,
  r.categorie,
  pg_catalog.md5(p.prosrc),
  r.justification,
  pg_catalog.now()
FROM reviewed r
JOIN pg_catalog.pg_proc p ON p.oid = r.procedure_oid
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_classement_and_security_inventory$
DECLARE
  v_bad text;
  v_count integer;
BEGIN
  IF pg_catalog.has_function_privilege(
       'anon',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     )
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     )
     OR NOT pg_catalog.has_function_privilege(
       'service_role',
       'public.fn_dans_fenetre_retractation(uuid)'::regprocedure,
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'fn_dans_fenetre_retractation doit être réservée à service_role';
  END IF;

  IF pg_catalog.pg_get_functiondef(
       'public.fn_top_soignants(text,integer)'::regprocedure
     ) NOT LIKE '%LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50)%' THEN
    RAISE EXCEPTION 'fn_top_soignants ne borne pas p_limit entre 1 et 50';
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_count
  FROM private.security_definer_inventory i
  WHERE i.signature = ANY (ARRAY[
    'fn_declarer_paiement_soignant_v2(uuid,numeric,numeric,text,text,date,boolean)',
    'fn_declarer_paiement_soignant(uuid,numeric,text,text,date,boolean)',
    'fn_diagnostic_coherence_financiere()',
    'fn_marquer_messages_lus(uuid)',
    'fn_obligations_financieres()',
    'fn_paiements_etablissement()',
    'fn_top_soignants(text,integer)',
    'fn_dans_fenetre_retractation(uuid)'
  ]);
  IF v_count <> 8 THEN
    RAISE EXCEPTION 'Inventaire ciblé incomplet : %/8', v_count;
  END IF;

  SELECT pg_catalog.string_agg(i.signature, ', ' ORDER BY i.signature)
  INTO v_bad
  FROM private.security_definer_inventory i
  JOIN pg_catalog.pg_proc p
    ON p.oid::regprocedure::text = i.signature
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND pg_catalog.md5(p.prosrc) <> i.definition_md5;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Empreintes SECURITY DEFINER non alignées : %', v_bad;
  END IF;
END;
$assert_classement_and_security_inventory$;

COMMIT;
