BEGIN;
DO $test$
DECLARE result jsonb;
BEGIN
  IF has_function_privilege('anon','public.fn_diagnostic_disponibilite_connect()','execute')
    OR has_function_privilege('authenticated','public.fn_diagnostic_disponibilite_connect()','execute')
    OR NOT has_function_privilege('service_role','public.fn_diagnostic_disponibilite_connect()','execute') THEN
    RAISE EXCEPTION 'Droits diagnostic incorrects';
  END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.fn_diagnostic_disponibilite_connect();
    RAISE EXCEPTION 'Diagnostic accessible client';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  result:=public.fn_diagnostic_disponibilite_connect();
  IF result->>'protocol' IS DISTINCT FROM 'CONNECT_PRETRANSFER_V1'
    OR (result->>'enabled')::boolean IS DISTINCT FROM EXISTS(SELECT 1 FROM private.stripe_connect_release_gate WHERE protocol='CONNECT_PRETRANSFER_V1' AND enabled IS TRUE) THEN
    RAISE EXCEPTION 'Diagnostic différent du verrou réel';
  END IF;
END;
$test$;
ROLLBACK;
