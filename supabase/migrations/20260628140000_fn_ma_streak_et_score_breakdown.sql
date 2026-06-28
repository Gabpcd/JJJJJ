-- Raccords frontend↔backend cassés (diff de contrat) : 2 RPC appelées par le
-- front mais absentes en prod.
--   - fn_ma_streak : lu par DashboardSoignant + SwipeMissions (le streak quotidien
--     s'écrivait via fn_update_streak_on_swipe mais rien ne le lisait → invisible).
--     Reset effectif si dernier jour d'activité < hier.
--   - fn_soignant_score_breakdown : lu par PopoverScoreSoignant (sinon « détail
--     indisponible » en permanence). Renvoie {success, composantes:[{cle,label,poids,valeur}]}.

CREATE OR REPLACE FUNCTION public.fn_ma_streak()
 RETURNS TABLE(streak_count integer, max_streak integer, last_activity_date date)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT
    CASE WHEN s.last_activity_date >= current_date - 1 THEN s.streak_count ELSE 0 END,
    COALESCE(s.max_streak, 0),
    s.last_activity_date
  FROM public.streaks_soignant s
  WHERE s.soignant_id = auth.uid();
$function$;
GRANT EXECUTE ON FUNCTION public.fn_ma_streak() TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_soignant_score_breakdown(p_soignant_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_b public.scoring_breakdown;
BEGIN
  SELECT * INTO v_b FROM public.scoring_breakdown
   WHERE soignant_id = p_soignant_id ORDER BY cree_le DESC LIMIT 1;
  IF v_b.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'composantes', '[]'::jsonb);
  END IF;
  RETURN jsonb_build_object(
    'success', true, 'score_total', v_b.score_total, 'niveau', v_b.niveau,
    'composantes', jsonb_build_array(
      jsonb_build_object('cle','notation_etab','label','Notations reçues','poids',35,'valeur', v_b.notation_etab_soignant_pct),
      jsonb_build_object('cle','presentisme','label','Présentéisme','poids',20,'valeur', v_b.presentisme_pct),
      jsonb_build_object('cle','ponctualite','label','Ponctualité','poids',15,'valeur', v_b.ponctualite_pct),
      jsonb_build_object('cle','reactivite','label','Réactivité','poids',10,'valeur', v_b.reactivite_pct),
      jsonb_build_object('cle','anciennete','label','Ancienneté / volume','poids',10,'valeur', v_b.anciennete_volume_pct),
      jsonb_build_object('cle','notation_soignant_etab','label','Notes données aux établissements','poids',10,'valeur', v_b.notation_soignant_etab_pct)
    ));
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_soignant_score_breakdown(uuid) TO authenticated;
