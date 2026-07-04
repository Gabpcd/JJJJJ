-- Helpers RPC pour les tests E2E Playwright.
-- 
-- Pattern : préfixe `playwright-test-` pour tous les comptes éphémères créés
-- pendant un test. `playwright-soignant@jolene.app` et `playwright-etab@jolene.app`
-- sont les comptes test fixes réutilisables (NE PAS supprimer).

CREATE OR REPLACE FUNCTION public.fn_admin_cleanup_test_accounts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count integer := 0;
  v_user record;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  FOR v_user IN
    SELECT id, email FROM auth.users
    WHERE email LIKE 'playwright-test-%@%'
  LOOP
    DELETE FROM auth.users WHERE id = v_user.id;
    v_deleted_count := v_deleted_count + 1;
  END LOOP;

  RETURN jsonb_build_object('deleted', v_deleted_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_cleanup_test_accounts() TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_reset_test_account(p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  v_user_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  v_email := CASE p_role
    WHEN 'SOIGNANT' THEN 'playwright-soignant@jolene.app'
    WHEN 'ADMIN_ETABLISSEMENT' THEN 'playwright-etab@jolene.app'
    ELSE NULL
  END;

  IF v_email IS NULL THEN
    RETURN jsonb_build_object('error', 'Rôle invalide');
  END IF;

  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Compte test introuvable, exécuter le seed d''abord');
  END IF;

  IF p_role = 'SOIGNANT' THEN
    DELETE FROM public.candidatures WHERE soignant_id = v_user_id;
    DELETE FROM public.notations WHERE evaluateur_id = v_user_id OR evalue_id = v_user_id;
    DELETE FROM public.exclusions WHERE excluant_id = v_user_id;
    DELETE FROM public.notifications WHERE destinataire_id = v_user_id;
    DELETE FROM public.parrainages WHERE filleul_id = v_user_id;
    UPDATE public.soignants SET
      score_fiabilite = 50,
      total_missions_terminees = 0,
      total_missions_annulees = 0,
      heures_cumulees = 0,
      premiere_mission_le = NULL
    WHERE id = v_user_id;
  ELSIF p_role = 'ADMIN_ETABLISSEMENT' THEN
    DELETE FROM public.candidatures WHERE mission_id IN (
      SELECT id FROM public.missions WHERE etablissement_id = v_user_id
    );
    DELETE FROM public.missions WHERE etablissement_id = v_user_id AND statut IN ('OUVERTE', 'BROUILLON');
    DELETE FROM public.notifications WHERE destinataire_id = v_user_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'role', p_role);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_reset_test_account(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
