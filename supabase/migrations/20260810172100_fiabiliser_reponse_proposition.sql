-- La réponse à une proposition doit rester la seule voie permettant au
-- soignant de faire évoluer PROPOSEE vers ACCEPTEE/REFUSEE/EXPIREE. Le
-- contexte du trigger est posé au plus près de chaque écriture : la
-- finalisation de mission ne peut ainsi ni le perdre ni l'élargir.
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_repondre_proposition(
  p_candidature_id uuid,
  p_accepter boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_candidature record;
  v_result jsonb;
BEGIN
  SELECT c.* INTO v_candidature
    FROM public.candidatures c
   WHERE c.id = p_candidature_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Candidature introuvable'); END IF;
  IF v_candidature.soignant_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;
  IF v_candidature.statut <> 'PROPOSEE' THEN
    RETURN jsonb_build_object('error', 'Cette proposition n’est plus en attente');
  END IF;

  IF v_candidature.cree_le < now() - interval '2 hours' THEN
    PERFORM set_config(
      'jolene.candidature_rpc_mission_id',
      v_candidature.mission_id::text,
      true
    );
    UPDATE public.candidatures
       SET statut = 'EXPIREE', traite_le = now()
     WHERE id = p_candidature_id;
    PERFORM set_config('jolene.candidature_rpc_mission_id', '', true);
    RETURN jsonb_build_object('error', 'Cette proposition a expiré');
  END IF;

  IF NOT p_accepter THEN
    PERFORM set_config(
      'jolene.candidature_rpc_mission_id',
      v_candidature.mission_id::text,
      true
    );
    UPDATE public.candidatures
       SET statut = 'REFUSEE', traite_le = now()
     WHERE id = p_candidature_id;
    PERFORM set_config('jolene.candidature_rpc_mission_id', '', true);
    RETURN jsonb_build_object('success', true, 'message', 'Proposition refusée');
  END IF;

  v_result := public.fn_finaliser_attribution_mission(
    v_candidature.mission_id,
    v_candidature.soignant_id,
    v_candidature.type_contrat_choisi
  );
  IF COALESCE((v_result->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_result;
  END IF;

  -- La finalisation précédente peut exécuter plusieurs triggers. Réarmer le
  -- contexte uniquement maintenant garantit que seules les écritures de la
  -- réponse canonique ci-dessous traversent le garde candidature.
  PERFORM set_config(
    'jolene.candidature_rpc_mission_id',
    v_candidature.mission_id::text,
    true
  );
  UPDATE public.candidatures
     SET statut = 'ACCEPTEE', traite_le = now()
   WHERE id = p_candidature_id;
  UPDATE public.candidatures
     SET statut = 'REFUSEE', motif_refus = 'Mission attribuée', traite_le = now()
   WHERE mission_id = v_candidature.mission_id
     AND id <> p_candidature_id
     AND statut IN ('EN_ATTENTE', 'EN_ATTENTE_VALIDATION_ETAB', 'PROPOSEE');
  PERFORM set_config('jolene.candidature_rpc_mission_id', '', true);

  RETURN v_result || jsonb_build_object('message', 'Proposition acceptée');
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_repondre_proposition(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_repondre_proposition(uuid, boolean)
  TO authenticated, service_role;

INSERT INTO private.security_definer_inventory (
  signature,
  categorie,
  definition_md5,
  justification,
  recense_le
)
SELECT
  'fn_repondre_proposition(uuid,boolean)',
  'RPC_UTILISATEUR_AUTH_INTERNE',
  md5(p.prosrc),
  'RPC authenticated: identité/tenancy interne observée (auth.uid).',
  now()
FROM pg_catalog.pg_proc p
WHERE p.oid = 'public.fn_repondre_proposition(uuid,boolean)'::regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

DO $assert_reponse_proposition$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.fn_repondre_proposition(uuid,boolean)'::regprocedure
  ) INTO v_definition;

  IF position('v_result := public.fn_finaliser_attribution_mission' IN v_definition) = 0
     OR position(
          'PERFORM set_config(' IN substring(
            v_definition FROM position(
              'v_result := public.fn_finaliser_attribution_mission' IN v_definition
            )
          )
        ) = 0
     OR v_definition NOT LIKE
        '%PERFORM set_config(''jolene.candidature_rpc_mission_id'', '''', true)%' THEN
    RAISE EXCEPTION 'Le contexte candidature n''encadre pas la réponse canonique';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.fn_repondre_proposition(uuid,boolean)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM false
     OR has_function_privilege(
       'authenticated',
       'public.fn_repondre_proposition(uuid,boolean)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM true
     OR has_function_privilege(
       'service_role',
       'public.fn_repondre_proposition(uuid,boolean)'::regprocedure,
       'EXECUTE'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'ACL incorrectes pour fn_repondre_proposition';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM private.security_definer_inventory i
    JOIN pg_catalog.pg_proc p
      ON p.oid = 'public.fn_repondre_proposition(uuid,boolean)'::regprocedure
    WHERE i.signature = 'fn_repondre_proposition(uuid,boolean)'
      AND i.definition_md5 = md5(p.prosrc)
  ) THEN
    RAISE EXCEPTION 'Inventaire SECURITY DEFINER non aligné pour fn_repondre_proposition';
  END IF;
END;
$assert_reponse_proposition$;

COMMIT;
