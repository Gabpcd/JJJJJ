-- Fix missing table grants for service_role on etablissements
GRANT ALL ON TABLE public.etablissements TO service_role;
GRANT ALL ON TABLE public.etablissements TO authenticated;
GRANT SELECT ON TABLE public.etablissements TO anon;
