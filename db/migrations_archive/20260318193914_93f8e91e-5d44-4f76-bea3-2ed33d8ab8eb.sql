CREATE OR REPLACE FUNCTION public.fn_get_my_role()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
    v_role TEXT;
    v_etab_id TEXT;
    v_uid UUID;
BEGIN
    v_uid := auth.uid();

    SELECT 
        raw_app_meta_data ->> 'role',
        raw_app_meta_data ->> 'etablissement_id'
    INTO v_role, v_etab_id
    FROM auth.users
    WHERE id = v_uid;

    -- Fallback: if role is ADMIN_ETABLISSEMENT or ETABLISSEMENT but no explicit etablissement_id, use auth.uid()
    IF v_etab_id IS NULL AND v_role IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT') THEN
        v_etab_id := v_uid::TEXT;
    END IF;

    RETURN jsonb_build_object(
        'user_id', v_uid,
        'role', COALESCE(v_role, 'INCONNU'),
        'etablissement_id', v_etab_id
    );
END;
$function$;