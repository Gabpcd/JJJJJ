-- Régularisation drift DB↔repo (Session D) : fn_rechercher_utilisateurs existait
-- en prod (déployée via MCP) sans fichier migration. CREATE OR REPLACE à
-- l'identique de la définition prod — no-op en prod, source de vérité au repo.
CREATE OR REPLACE FUNCTION public.fn_rechercher_utilisateurs(p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN '[]'::JSONB; END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', u.id,
            'type', CASE
                WHEN s.id IS NOT NULL THEN 'soignant'
                WHEN e.id IS NOT NULL THEN 'etablissement'
                ELSE 'inconnu'
            END,
            'nom', COALESCE(s.nom, e.nom, ''),
            'prenom', COALESCE(s.prenom, ''),
            'email', u.email,
            'profession', s.profession,
            'avatar_url', COALESCE(s.avatar_url, e.logo_url)
        )), '[]'::JSONB)
        FROM auth.users u
        LEFT JOIN soignants s ON s.id = u.id
        LEFT JOIN etablissements e ON e.id = u.id
        WHERE (
            LOWER(u.email) LIKE LOWER(p_query) || '%'
            OR LOWER(s.prenom || ' ' || s.nom) LIKE '%' || LOWER(p_query) || '%'
            OR LOWER(e.nom) LIKE '%' || LOWER(p_query) || '%'
        )
        LIMIT 10
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_rechercher_utilisateurs(text) TO authenticated;
