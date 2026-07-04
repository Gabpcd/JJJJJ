-- Grant anon role access to the public schema and the public search RPC
GRANT USAGE ON SCHEMA public TO anon;
GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_recherche(text, text) TO anon;
