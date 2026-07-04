-- Helper function: resolve etablissement_id to the user_id that manages it
CREATE OR REPLACE FUNCTION public.fn_user_id_pour_etablissement(p_etablissement_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT id FROM auth.users
  WHERE (raw_app_meta_data ->> 'etablissement_id')::uuid = p_etablissement_id
  LIMIT 1;
$$;