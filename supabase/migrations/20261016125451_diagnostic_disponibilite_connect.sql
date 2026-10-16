BEGIN;

-- Diagnostic de lecture seulement : aucun droit d'ouverture n'est exposé.
CREATE OR REPLACE FUNCTION public.fn_diagnostic_disponibilite_connect()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object('protocol', 'CONNECT_PRETRANSFER_V1', 'enabled',
    EXISTS (SELECT 1 FROM private.stripe_connect_release_gate
      WHERE protocol = 'CONNECT_PRETRANSFER_V1' AND enabled IS TRUE));
END;
$function$;
ALTER FUNCTION public.fn_diagnostic_disponibilite_connect() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_diagnostic_disponibilite_connect() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_diagnostic_disponibilite_connect() TO service_role;

INSERT INTO private.security_definer_inventory(signature, categorie, definition_md5, justification, recense_le)
SELECT 'fn_diagnostic_disponibilite_connect()', 'SERVICE_ONLY_REVOQUE', md5(prosrc),
  'Diagnostic interne en lecture du verrou Connect ; aucun accès client et aucune ouverture.', now()
FROM pg_proc WHERE oid = 'public.fn_diagnostic_disponibilite_connect()'::regprocedure
ON CONFLICT (signature) DO UPDATE SET definition_md5 = EXCLUDED.definition_md5,
  categorie = EXCLUDED.categorie, justification = EXCLUDED.justification, recense_le = EXCLUDED.recense_le;

COMMIT;
