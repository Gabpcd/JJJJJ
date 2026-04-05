-- Grant EXECUTE on fn_user_id_pour_etablissement to authenticated role
-- This function is SECURITY DEFINER so it safely queries auth.users
-- but the authenticated role needs permission to call it via RPC
GRANT EXECUTE ON FUNCTION public.fn_user_id_pour_etablissement(uuid) TO authenticated;
