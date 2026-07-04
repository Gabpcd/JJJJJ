-- Sprint 13-C PR 2 — Streaks quotidien soignant
--
-- Table streaks_soignant : compteur jours consécutifs où le soignant
-- effectue au moins 1 swipe. Reset si jour manqué (>24h sans activité).
--
-- Mécaniques :
-- - 1 swipe par jour = +1 streak
-- - Swipes additionnels même jour = pas d'incrément (1/jour max)
-- - Lendemain sans swipe = reset à 0
-- - Badges streak : 30_DAYS_STREAK, 100_DAYS_STREAK

CREATE TABLE IF NOT EXISTS public.streaks_soignant (
  soignant_id uuid PRIMARY KEY REFERENCES public.soignants(id) ON DELETE CASCADE,
  streak_count integer NOT NULL DEFAULT 0 CHECK (streak_count >= 0),
  last_activity_date date NOT NULL DEFAULT current_date,
  max_streak integer NOT NULL DEFAULT 0 CHECK (max_streak >= 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_streaks_soignant_last_activity
  ON public.streaks_soignant (last_activity_date);

ALTER TABLE public.streaks_soignant ENABLE ROW LEVEL SECURITY;

CREATE POLICY streaks_soignant_select_own ON public.streaks_soignant
  FOR SELECT USING (soignant_id = auth.uid());

CREATE POLICY streaks_soignant_service_role ON public.streaks_soignant
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public.streaks_soignant IS
'Sprint 13-C : compteur jours consécutifs où soignant swipe au moins 1 fois. Reset si jour manqué.';

-- ─── Trigger update streak sur swipe (INSERT) ────────────────────────

CREATE OR REPLACE FUNCTION public.fn_update_streak_on_swipe()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_last_date date;
  v_today date := current_date;
  v_new_streak integer;
  v_max_streak integer;
BEGIN
  SELECT last_activity_date, streak_count, max_streak
    INTO v_last_date, v_new_streak, v_max_streak
    FROM public.streaks_soignant
   WHERE soignant_id = NEW.soignant_id;

  IF v_last_date IS NULL THEN
    -- Premier swipe : init streak = 1
    INSERT INTO public.streaks_soignant (soignant_id, streak_count, last_activity_date, max_streak, updated_at)
      VALUES (NEW.soignant_id, 1, v_today, 1, now())
      ON CONFLICT (soignant_id) DO NOTHING;
    -- Award badge si premier jour (>= 1 streak, déjà couvert par PREMIER_SWIPE)
    RETURN NEW;
  END IF;

  IF v_last_date = v_today THEN
    -- Déjà swipé aujourd'hui : pas d'incrément
    RETURN NEW;
  END IF;

  IF v_last_date = v_today - interval '1 day' THEN
    -- Continuité : +1
    v_new_streak := v_new_streak + 1;
  ELSE
    -- Rupture (>1 jour) : reset à 1 (le swipe du jour démarre nouvelle streak)
    v_new_streak := 1;
  END IF;

  IF v_new_streak > v_max_streak THEN
    v_max_streak := v_new_streak;
  END IF;

  UPDATE public.streaks_soignant
     SET streak_count = v_new_streak,
         last_activity_date = v_today,
         max_streak = v_max_streak,
         updated_at = now()
   WHERE soignant_id = NEW.soignant_id;

  -- Award badges streak (réutilise table badges_soignant Sprint 13-C PR 1)
  IF v_new_streak = 30 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
      VALUES (NEW.soignant_id, '30_DAYS_STREAK', jsonb_build_object('streak', 30))
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  IF v_new_streak = 100 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
      VALUES (NEW.soignant_id, '100_DAYS_STREAK', jsonb_build_object('streak', 100))
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_update_streak_on_swipe ON public.swipes;
CREATE TRIGGER trg_update_streak_on_swipe
  AFTER INSERT ON public.swipes
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_update_streak_on_swipe();

-- ─── RPC fn_ma_streak (lecture) ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_ma_streak()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_streak record;
  v_actif boolean;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('error', 'auth_required');
  END IF;

  SELECT streak_count, last_activity_date, max_streak
    INTO v_streak
    FROM public.streaks_soignant
   WHERE soignant_id = v_soignant_id;

  IF v_streak.streak_count IS NULL THEN
    RETURN jsonb_build_object(
      'streak_count', 0,
      'max_streak', 0,
      'last_activity_date', NULL,
      'actif_aujourdhui', false
    );
  END IF;

  v_actif := (v_streak.last_activity_date = current_date);

  RETURN jsonb_build_object(
    'streak_count', v_streak.streak_count,
    'max_streak', v_streak.max_streak,
    'last_activity_date', v_streak.last_activity_date,
    'actif_aujourdhui', v_actif,
    'risque_perte', NOT v_actif AND v_streak.last_activity_date = current_date - interval '1 day'
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_ma_streak() TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_ma_streak() IS
'Sprint 13-C : retourne streak actuel + max + actif aujourdhui + risque_perte (hier mais pas aujourdhui).';
