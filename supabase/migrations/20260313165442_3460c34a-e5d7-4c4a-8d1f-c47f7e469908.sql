
-- F14: Sécuriser tokens_push — séparer les policies pour garantir WITH CHECK sur INSERT/UPDATE
DROP POLICY IF EXISTS pol_token_all ON public.tokens_push;

-- SELECT: uniquement ses propres tokens
CREATE POLICY pol_token_select ON public.tokens_push
  FOR SELECT TO authenticated
  USING (utilisateur_id = auth.uid());

-- INSERT: forcer utilisateur_id = auth.uid()
CREATE POLICY pol_token_insert ON public.tokens_push
  FOR INSERT TO authenticated
  WITH CHECK (utilisateur_id = auth.uid());

-- UPDATE: uniquement ses propres tokens, sans changer utilisateur_id
CREATE POLICY pol_token_update ON public.tokens_push
  FOR UPDATE TO authenticated
  USING (utilisateur_id = auth.uid())
  WITH CHECK (utilisateur_id = auth.uid());

-- DELETE: uniquement ses propres tokens
CREATE POLICY pol_token_delete ON public.tokens_push
  FOR DELETE TO authenticated
  USING (utilisateur_id = auth.uid());
