-- Fix 1: presences INSERT — soignant can only clock in for their assigned missions
DROP POLICY IF EXISTS pol_pres_insert ON public.presences;
CREATE POLICY pol_pres_insert ON public.presences
FOR INSERT TO authenticated
WITH CHECK (
  est_admin()
  OR (
    soignant_id = auth.uid()
    AND mission_id IN (
      SELECT id FROM missions
      WHERE soignant_assigne_id = auth.uid()
        AND statut IN ('ASSIGNEE', 'EN_COURS')
    )
  )
);

-- Fix 2: evaluations INSERT — evaluateur must be participant of the mission (soignant or etab)
DROP POLICY IF EXISTS pol_eval_insert ON public.evaluations;
CREATE POLICY pol_eval_insert ON public.evaluations
FOR INSERT TO authenticated
WITH CHECK (
  evaluateur_id = auth.uid()
  AND mission_id IN (
    SELECT id FROM missions
    WHERE soignant_assigne_id = auth.uid()
       OR etablissement_id = mon_etablissement_id()
  )
  AND (SELECT statut FROM missions WHERE id = mission_id) = 'TERMINEE'
);

-- Fix 3: litiges INSERT — mission must belong to the initiator
DROP POLICY IF EXISTS pol_litige_insert ON public.litiges;
CREATE POLICY pol_litige_insert ON public.litiges
FOR INSERT TO authenticated
WITH CHECK (
  (
    initie_par = 'SOIGNANT'
    AND soignant_id = auth.uid()
    AND mission_id IN (
      SELECT id FROM missions WHERE soignant_assigne_id = auth.uid()
    )
  )
  OR (
    initie_par = 'ETABLISSEMENT'
    AND etablissement_id = mon_etablissement_id()
    AND mission_id IN (
      SELECT id FROM missions WHERE etablissement_id = mon_etablissement_id()
    )
  )
);

-- Fix 4: contrats INSERT — soignant can only create for their own assigned missions
DROP POLICY IF EXISTS pol_contrat_insert ON public.contrats_mission;
CREATE POLICY pol_contrat_insert ON public.contrats_mission
FOR INSERT TO authenticated
WITH CHECK (
  est_admin()
  OR (
    est_admin_etablissement()
    AND etablissement_id = mon_etablissement_id()
  )
  OR (
    soignant_id = auth.uid()
    AND mission_id IN (
      SELECT id FROM missions WHERE soignant_assigne_id = auth.uid()
    )
  )
);