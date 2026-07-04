-- Relâcher le rate-limit de l'export RGPD : 2/24h était inutilement bloquant
-- (un utilisateur légitime atteignait vite la limite en testant). Passe à 30/h,
-- effectivement invisible pour un usage normal tout en gardant un garde-fou
-- anti-boucle/spam (l'export dump toutes les données = requête lourde).
CREATE OR REPLACE FUNCTION public.fn_rgpd_exporter_rate_limited()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_allowed BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Non authentifié');
    END IF;

    v_allowed := fn_verifier_rate_limit(v_user_id::TEXT, 'rgpd_export', 30, 3600);
    IF NOT v_allowed THEN
        RETURN jsonb_build_object('error', 'Trop d''exports en peu de temps. Réessayez dans quelques minutes.');
    END IF;

    RETURN fn_rgpd_exporter_donnees_soignant();
END;
$function$;

NOTIFY pgrst, 'reload schema';
