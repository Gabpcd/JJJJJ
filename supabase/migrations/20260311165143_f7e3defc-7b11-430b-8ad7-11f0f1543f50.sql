ALTER TABLE public.soignants
ADD COLUMN types_contrat_acceptes TEXT DEFAULT NULL;

COMMENT ON COLUMN public.soignants.types_contrat_acceptes IS 'JSON array de types de contrat acceptés par le soignant, ex: ["CDDU","LIBERAL"]. NULL = utilise type_contrat seul.';