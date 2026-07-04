
DROP FUNCTION IF EXISTS public.fn_mes_exclusions_recues();

CREATE OR REPLACE FUNCTION public.fn_mes_exclusions_recues()
RETURNS TABLE(
  id uuid,
  exclu_par uuid,
  motif text,
  cree_le timestamptz,
  nom_etablissement text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id,
    e.exclu_par,
    e.motif,
    e.cree_le,
    et.nom AS nom_etablissement
  FROM exclusions e
  LEFT JOIN etablissements et ON et.id = e.exclu_par
  WHERE e.exclu_id = auth.uid()
  ORDER BY e.cree_le DESC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mes_exclusions_recues() TO authenticated;
