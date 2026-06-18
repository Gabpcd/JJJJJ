-- BUG : migration 20260615120000 a créé l'overload 7-args (filtres email/tel)
-- SANS GRANT EXECUTE TO authenticated → "permission denied for function" pour
-- l'admin (rôle authenticated). De plus, l'ancien overload 5-args coexiste et
-- crée un risque d'ambiguïté PostgREST. On supprime le 5-args (le 7-args le
-- couvre intégralement, params en plus = DEFAULT false) et on grant le 7-args.

DROP FUNCTION IF EXISTS public.fn_admin_chercher_prospects(text, text, text, boolean, integer);
DROP FUNCTION IF EXISTS public.fn_admin_chercher_prospects_soignants(text, text, text, boolean, integer);

GRANT EXECUTE ON FUNCTION public.fn_admin_chercher_prospects(text, text, text, boolean, integer, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_chercher_prospects_soignants(text, text, text, boolean, integer, boolean, boolean) TO authenticated;
