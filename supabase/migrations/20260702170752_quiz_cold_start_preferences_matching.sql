-- 7d-4 (Lot 7 v2 A1) — cold start : le mini-quiz d'onboarding amorce les
-- préférences horaires apprises AVANT le premier swipe. Le quiz n'écrase
-- JAMAIS des préférences déjà apprises (nb_signaux > 0) : les signaux réels
-- priment toujours sur le déclaratif.
CREATE OR REPLACE FUNCTION public.fn_initialiser_preferences_matching(
  p_pref_nuit numeric,
  p_pref_jour numeric,
  p_pref_weekend numeric,
  p_pref_semaine numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;
  IF p_pref_nuit NOT BETWEEN 0 AND 1 OR p_pref_jour NOT BETWEEN 0 AND 1
     OR p_pref_weekend NOT BETWEEN 0 AND 1 OR p_pref_semaine NOT BETWEEN 0 AND 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Préférences hors bornes [0,1]');
  END IF;

  INSERT INTO public.matching_preferences_soignant
    (soignant_id, pref_nuit, pref_jour, pref_weekend, pref_semaine, nb_signaux, maj_le)
  VALUES (v_uid, p_pref_nuit, p_pref_jour, p_pref_weekend, p_pref_semaine, 0, now())
  ON CONFLICT (soignant_id) DO UPDATE SET
    pref_nuit = EXCLUDED.pref_nuit,
    pref_jour = EXCLUDED.pref_jour,
    pref_weekend = EXCLUDED.pref_weekend,
    pref_semaine = EXCLUDED.pref_semaine,
    maj_le = now()
  WHERE matching_preferences_soignant.nb_signaux = 0;

  RETURN jsonb_build_object('success', true);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_initialiser_preferences_matching(numeric, numeric, numeric, numeric) TO authenticated;
