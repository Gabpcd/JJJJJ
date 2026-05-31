-- BUG : fn_enregistrer_swipe incrémentait super_swipes_quota.count à 6 puis
-- vérifiait « > 5 » pour décrémenter et renvoyer une erreur propre. Mais la
-- contrainte CHECK (count <= 5) rejette l'incrément à 6 AVANT → le 6e super-like
-- renvoyait une erreur de contrainte brute au lieu de {ok:false, quota_atteint}.
-- Fix : vérifier le quota AVANT d'incrémenter (la contrainte reste garde-fou).
CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(p_mission_id uuid, p_direction text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_direction swipe_direction;
  v_quota_count integer;
  v_swipe_id uuid;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'SUPER_LIKE') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;

  v_direction := p_direction::swipe_direction;

  IF v_direction = 'SUPER_LIKE' THEN
    -- vérifier le quota AVANT d'incrémenter (évite de violer CHECK count<=5)
    SELECT count INTO v_quota_count
      FROM public.super_swipes_quota
     WHERE soignant_id = v_soignant_id AND date = current_date;

    IF COALESCE(v_quota_count, 0) >= 5 THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'quota_super_like_atteint',
        'quota_max', 5,
        'reset_le', (current_date + interval '1 day')::date
      );
    END IF;

    INSERT INTO public.super_swipes_quota (soignant_id, date, count)
      VALUES (v_soignant_id, current_date, 1)
      ON CONFLICT (soignant_id, date)
        DO UPDATE SET count = super_swipes_quota.count + 1
      RETURNING count INTO v_quota_count;
  END IF;

  INSERT INTO public.swipes (soignant_id, mission_id, direction)
    VALUES (v_soignant_id, p_mission_id, v_direction)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING
    RETURNING id INTO v_swipe_id;

  IF v_swipe_id IS NULL THEN
    IF v_direction = 'SUPER_LIKE' THEN
      UPDATE public.super_swipes_quota
         SET count = count - 1
       WHERE soignant_id = v_soignant_id AND date = current_date;
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'swipe_id', v_swipe_id,
    'direction', p_direction,
    'quota_restant', CASE WHEN v_direction = 'SUPER_LIKE' THEN 5 - v_quota_count ELSE NULL END
  );
END;
$function$;
