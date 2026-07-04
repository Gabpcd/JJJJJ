-- FIX: CRITICAL - Prevent soignants from inflating referral bonuses
DROP POLICY IF EXISTS pol_parr_insert ON public.parrainages;
CREATE POLICY pol_parr_insert ON public.parrainages
  FOR INSERT TO authenticated
  WITH CHECK (
    (filleul_id = auth.uid())
    AND (parrain_id <> auth.uid())
    AND (bonus_heures_filleul = 50)
    AND (bonus_heures_parrain = 50)
    AND (statut = 'EN_ATTENTE')
    AND (valide_le IS NULL)
    AND (EXISTS (
      SELECT 1 FROM soignants s
      WHERE s.id = parrainages.parrain_id
        AND s.code_parrainage = parrainages.code_parrainage
    ))
  );

-- FIX: WARN - Block parraine_par self-assignment on soignant insert
-- First check current policy
DO $$
DECLARE
  v_check text;
BEGIN
  SELECT with_check INTO v_check FROM pg_policies WHERE tablename = 'soignants' AND policyname = 'pol_soig_insert';
  IF v_check IS NOT NULL AND v_check NOT LIKE '%parraine_par IS NULL%' THEN
    EXECUTE 'DROP POLICY IF EXISTS pol_soig_insert ON public.soignants';
    EXECUTE format('CREATE POLICY pol_soig_insert ON public.soignants FOR INSERT TO authenticated WITH CHECK (%s AND (parraine_par IS NULL))', v_check);
  END IF;
END;
$$;

-- FIX: WARN - Restrict audit log inserts to service role via RPC only
DROP POLICY IF EXISTS pol_audit_insert ON public.journaux_audit;
CREATE POLICY pol_audit_insert ON public.journaux_audit
  FOR INSERT TO authenticated
  WITH CHECK (false);
-- All audit writes now go through fn_ecrire_audit_safe (SECURITY DEFINER)