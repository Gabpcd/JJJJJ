-- Fix permissions for soignants table used during signup flow
GRANT INSERT ON TABLE public.soignants TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.soignants TO service_role;