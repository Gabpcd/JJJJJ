-- Grant service_role full access to documents_soignants (needed by verify-document edge function)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents_soignants TO service_role;

-- Also grant on related tables the edge function may need
GRANT SELECT ON public.documents_requis_par_profession TO service_role;