-- Fix 4 bugs admin remontés par Gabrielle
-- Date : 2026-05-03
--
-- Root causes identifiées :
-- B.1 fn_admin_cohort_economics 404 : cache PostgREST stale
-- B.2 fn_admin_chorus_stats 403 : GRANT EXECUTE TO authenticated manquant
-- B.3 factor_advances 403 : GRANT SELECT TO authenticated manquant (RLS filtre)
-- Bonus : 3 autres RPCs admin sans GRANT EXECUTE découvertes
-- Bonus : alertes_systeme update direct depuis frontend → RPC dédiée
--
-- Note : toutes les RPCs concernées ont déjà un check est_admin() interne
-- (security definer + check role), donc accorder EXECUTE à authenticated
-- est sûr — la fonction renverra { error: 'Accès refusé' } si non-admin.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════
-- B.2 : Fix RPCs admin sans GRANT EXECUTE
-- ═══════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.fn_admin_chorus_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_chorus_submission_reset(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_incoherences_identite() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_invocations_purge() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- B.3 : Fix factor_advances GRANT SELECT
-- La RLS policy "Admin gère factor_advances" (est_admin()) + "Soignant lit
-- ses avances" (auth.uid() = soignant_id) filtrent correctement les lignes.
-- Le GRANT manque juste pour passer la barrière privilege.
-- ═══════════════════════════════════════════════════════════════════════
GRANT SELECT ON TABLE public.factor_advances TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- Bonus : RPC dédiée pour résoudre alertes (au lieu d'UPDATE direct frontend)
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_admin_resoudre_alerte(p_alerte_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  UPDATE public.alertes_systeme
  SET resolu_le = now(), resolu_par = auth.uid()
  WHERE id = p_alerte_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Alerte introuvable');
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_resoudre_alerte(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- B.1 : Forcer rechargement schema PostgREST (résout 404 fn_admin_cohort_economics)
-- ═══════════════════════════════════════════════════════════════════════
NOTIFY pgrst, 'reload schema';

COMMIT;
