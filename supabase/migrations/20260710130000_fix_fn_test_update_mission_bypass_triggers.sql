-- Recapture hotfix prod (10/07/2026) : fn_test_update_mission était un NO-OP
-- silencieux — dec_proteger_mission_soignant (BEFORE UPDATE missions) re-force
-- debut_le/fin_le/soignant_assigne_id/statut depuis OLD pour tout caller non
-- admin, sans respecter app.internal_operation ni le contexte service_role.
-- Les specs E2E qui backdatent une mission (presences-autovalidation,
-- empêchement impérieux) croyaient déplacer la mission : l'UPDATE entier était
-- annulé et l'INSERT presences échouait ensuite en « Pointage trop tôt ».
--
-- Fix : le helper bypasse TOUS les triggers pendant son UPDATE (replica mode,
-- SET LOCAL, restauré aussitôt) — conforme à son contrat documenté « bypass
-- protections », sans risque : réservé au service_role (seed E2E uniquement).
-- Validé sur branche recette : debut passé + assignation appliqués, INSERT
-- presences backdatée accepté (triggers presences actifs).
CREATE OR REPLACE FUNCTION public.fn_test_update_mission(p_mission_id uuid, p_data jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $_$
DECLARE
  v_set text;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'fn_test_update_mission réservé au service_role (seed E2E uniquement)';
  END IF;
  PERFORM set_config('app.internal_operation', 'true', true);
  PERFORM set_config('jolene.creer_mission_context', 'true', true);
  v_set := (SELECT string_agg(format('%I = r.%I', key, key), ',') FROM jsonb_object_keys(p_data) AS key);
  EXECUTE 'SET LOCAL session_replication_role = replica';
  EXECUTE format(
    'UPDATE public.missions m SET %s FROM jsonb_populate_record(NULL::public.missions, $1) r WHERE m.id = $2',
    v_set
  ) USING p_data, p_mission_id;
  EXECUTE 'SET LOCAL session_replication_role = origin';
END;
$_$;
