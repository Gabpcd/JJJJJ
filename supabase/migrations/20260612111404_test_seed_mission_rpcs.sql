-- Helpers de seed E2E réservés au service_role : insèrent/modifient des missions
-- de test en passant les GUC internes (app.internal_operation +
-- jolene.creer_mission_context) qui désactivent proprement les garde-fous métier
-- (anti-seed financier, onboarding représentant légal, validation transitions).
-- Les comptes test (playwright-etab) ne sont volontairement PAS onboardés, donc
-- l'insert/update direct depuis les tests était rejeté par le trigger stack.
-- Réservé service_role : aucun client (anon/authenticated) ne peut les appeler.

CREATE OR REPLACE FUNCTION public.fn_test_seed_mission(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
  v_cols text;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'fn_test_seed_mission réservé au service_role (seed E2E uniquement)';
  END IF;
  PERFORM set_config('app.internal_operation', 'true', true);
  PERFORM set_config('jolene.creer_mission_context', 'true', true);
  v_cols := (SELECT string_agg(quote_ident(key), ',') FROM jsonb_object_keys(p_data) AS key);
  EXECUTE format(
    'INSERT INTO public.missions (%s) SELECT %s FROM jsonb_populate_record(NULL::public.missions, $1) RETURNING id',
    v_cols, v_cols
  ) USING p_data INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_test_update_mission(p_mission_id uuid, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_set text;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'fn_test_update_mission réservé au service_role (seed E2E uniquement)';
  END IF;
  PERFORM set_config('app.internal_operation', 'true', true);
  PERFORM set_config('jolene.creer_mission_context', 'true', true);
  v_set := (SELECT string_agg(format('%I = r.%I', key, key), ',') FROM jsonb_object_keys(p_data) AS key);
  EXECUTE format(
    'UPDATE public.missions m SET %s FROM jsonb_populate_record(NULL::public.missions, $1) r WHERE m.id = $2',
    v_set
  ) USING p_data, p_mission_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_test_seed_mission(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_test_update_mission(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_test_seed_mission(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_test_update_mission(uuid, jsonb) TO service_role;
