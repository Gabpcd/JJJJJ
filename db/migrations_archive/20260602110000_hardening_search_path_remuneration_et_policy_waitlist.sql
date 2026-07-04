-- Hardening advisors Supabase (les 2 seuls warnings réellement actionnables).
-- Advisor 0011 (function_search_path_mutable) : fn_calculer_remuneration_mission
-- n'avait pas de search_path figé. Elle n'utilise que public (fn_est_jour_ferie +
-- tables etablissements/soignants) + pg_catalog implicite → SET search_path TO 'public'.
DO $mig$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('public.fn_calculer_remuneration_mission(timestamp with time zone, timestamp with time zone, numeric, uuid, uuid)'::regprocedure);
  v_new := replace(v_def, E' STABLE\nAS $function$', E' STABLE\n SET search_path TO ''public''\nAS $function$');
  IF v_new = v_def THEN RAISE EXCEPTION 'search_path: pattern STABLE non trouvé'; END IF;
  EXECUTE v_new;
END $mig$;

-- Advisor 0024 (rls_policy_always_true) : la policy INSERT de prevoyance_liste_attente
-- était en WITH CHECK (true). On l'aligne sur les policies SELECT/UPDATE déjà scopées
-- (soignant_id = auth.uid()). NULL reste autorisé pour les inscriptions email anonymes
-- depuis la landing (RPC fn_inscrire_liste_attente_prevoyance, SECURITY DEFINER, non
-- impactée). Empêche désormais l'insertion d'une ligne attribuée à un soignant tiers.
ALTER POLICY pol_prev_la_insert ON public.prevoyance_liste_attente
  WITH CHECK (soignant_id IS NULL OR soignant_id = auth.uid());
