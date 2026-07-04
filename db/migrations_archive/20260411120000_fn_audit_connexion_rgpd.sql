-- fn_audit_connexion : capture automatique IP + User-Agent pour conformité RGPD.
--
-- Avant : la fonction n'insérait que (acteur_id, type_acteur, action, type_ressource, id_ressource).
-- Les colonnes `ip_acteur`, `navigateur_acteur`, `details` de `journaux_audit` restaient NULL.
--
-- Après : la fonction extrait automatiquement l'IP et le User-Agent depuis les en-têtes HTTP
-- exposés par PostgREST via `current_setting('request.headers')`. Aucun changement côté frontend.

CREATE OR REPLACE FUNCTION public.fn_audit_connexion(p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_ip inet;
    v_user_agent text;
    v_headers jsonb;
BEGIN
    IF p_action NOT IN ('CONNEXION', 'DECONNEXION') THEN
        RETURN '{"error":"Action non autorisée"}'::JSONB;
    END IF;

    -- Capture automatique de l'IP et du User-Agent depuis les headers HTTP
    -- (PostgREST expose request.headers à PostgreSQL)
    BEGIN
        v_headers := current_setting('request.headers', true)::jsonb;
        -- X-Forwarded-For peut contenir une chaine "ip1, ip2, ip3" -> on prend la 1ere (client réel)
        v_ip := NULLIF(trim(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1)), '')::inet;
        v_user_agent := NULLIF(v_headers->>'user-agent', '');
    EXCEPTION WHEN OTHERS THEN
        v_ip := NULL;
        v_user_agent := NULL;
    END;

    INSERT INTO journaux_audit (
        acteur_id, type_acteur, action, type_ressource, id_ressource,
        ip_acteur, navigateur_acteur, details
    )
    VALUES (
        COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID),
        COALESCE(mon_role(), 'SOIGNANT'),
        p_action,
        'session',
        COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID),
        v_ip,
        v_user_agent,
        jsonb_build_object(
            'horodatage', now(),
            'method', 'email_password'
        )
    );

    RETURN '{"success":true}'::JSONB;
EXCEPTION WHEN OTHERS THEN
    -- Silencieux — l'audit de connexion ne doit jamais bloquer l'utilisateur
    RETURN '{"success":false}'::JSONB;
END;
$function$;
