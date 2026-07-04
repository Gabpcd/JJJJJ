-- 1. Fix liste_attente_premium: restrict INSERT to own data
DROP POLICY IF EXISTS pol_liste_insert ON public.liste_attente_premium;
CREATE POLICY pol_liste_insert ON public.liste_attente_premium
  FOR INSERT TO authenticated
  WITH CHECK (
    utilisateur_id = auth.uid()
  );

-- 2. Fix parrainages: validate parrain_id matches a real soignant with the given code
DROP POLICY IF EXISTS pol_parr_insert ON public.parrainages;
CREATE POLICY pol_parr_insert ON public.parrainages
  FOR INSERT TO authenticated
  WITH CHECK (
    filleul_id = auth.uid()
    AND parrain_id <> auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.soignants s
      WHERE s.id = parrainages.parrain_id
        AND s.code_parrainage = parrainages.code_parrainage
    )
  );

-- 3. Fix tokens_calendrier: allow soignants to revoke their own token
CREATE POLICY pol_cal_token_delete ON public.tokens_calendrier
  FOR DELETE TO authenticated
  USING (soignant_id = auth.uid());