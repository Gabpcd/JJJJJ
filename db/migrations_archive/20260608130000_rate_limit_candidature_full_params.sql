-- Anti-spam candidature (série A). Le front appelait fn_postuler_mission EN DIRECT,
-- sans throttle → un client malveillant pouvait mass-candidater (spam établissements,
-- bruit dans le matching, mini-DoS). Le wrapper fn_postuler_mission_rate_limited
-- existait mais (a) n'était câblé nulle part et (b) ne forwardait que p_mission_id
-- (il aurait perdu p_message + p_choix_contrat).
--
-- On recrée le wrapper pour forwarder les 3 paramètres réels de fn_postuler_mission,
-- puis le front bascule dessus (cf. PR). On supprime d'abord l'ancienne surcharge à
-- 1 argument pour éviter toute ambiguïté de résolution d'overload.
DROP FUNCTION IF EXISTS public.fn_postuler_mission_rate_limited(uuid);

CREATE OR REPLACE FUNCTION public.fn_postuler_mission_rate_limited(
  p_mission_id uuid,
  p_message text DEFAULT NULL,
  p_choix_contrat text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  -- 20 candidatures / heure / utilisateur (même seuil que l'ancien wrapper).
  IF NOT fn_verifier_rate_limit(v_user_id::text, 'candidature', 20, 3600) THEN
    RETURN jsonb_build_object('error', 'Trop de candidatures en peu de temps. Réessayez plus tard.');
  END IF;
  RETURN fn_postuler_mission(p_mission_id, p_message, p_choix_contrat);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_postuler_mission_rate_limited(uuid, text, text) TO authenticated;
