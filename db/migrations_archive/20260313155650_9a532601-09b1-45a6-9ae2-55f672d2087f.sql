
-- ============================================================
-- F1: Fix exclusions RLS bypass in mission SELECT policy
-- Problem: soignants can't see exclusion rows where exclu_id = auth.uid()
-- because pol_exclusion_select only allows exclu_par = auth.uid().
-- Solution: SECURITY DEFINER functions to check exclusions.
-- ============================================================

-- Function: returns true if current user is excluded by given establishment
CREATE OR REPLACE FUNCTION public.fn_est_exclu_par_etablissement(p_etablissement_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM exclusions
    WHERE (exclu_id = auth.uid() AND exclu_par = p_etablissement_id)
       OR (exclu_par = auth.uid() AND exclu_id = p_etablissement_id)
  )
$$;

-- Replace the mission SELECT policy with one using the SECURITY DEFINER function
DROP POLICY IF EXISTS pol_mission_select ON public.missions;

CREATE POLICY pol_mission_select ON public.missions
FOR SELECT TO authenticated
USING (
  est_admin()
  OR (etablissement_id = mon_etablissement_id())
  OR (soignant_assigne_id = auth.uid())
  OR (
    est_soignant()
    AND statut = 'OUVERTE'::statut_mission
    AND NOT fn_est_exclu_par_etablissement(etablissement_id)
  )
);

GRANT EXECUTE ON FUNCTION public.fn_est_exclu_par_etablissement(uuid) TO authenticated;

-- ============================================================
-- F2: Fix evaluation INSERT policy - constrain evalue_id
-- Problem: evaluateur can set evalue_id to anyone
-- Solution: evalue_id must be the counterparty of the mission
-- ============================================================

DROP POLICY IF EXISTS pol_eval_insert ON public.evaluations;

CREATE POLICY pol_eval_insert ON public.evaluations
FOR INSERT TO authenticated
WITH CHECK (
  (evaluateur_id = auth.uid())
  AND (
    mission_id IN (
      SELECT m.id FROM missions m
      WHERE (m.soignant_assigne_id = auth.uid() AND evalue_id = m.etablissement_id)
         OR (m.etablissement_id = mon_etablissement_id() AND evalue_id = m.soignant_assigne_id)
    )
  )
  AND (
    (SELECT m.statut FROM missions m WHERE m.id = evaluations.mission_id) = 'TERMINEE'::statut_mission
  )
);
