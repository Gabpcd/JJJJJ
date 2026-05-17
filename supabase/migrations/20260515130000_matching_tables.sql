-- Sprint 13-A PR 1 — Tables matching swipe Hinge-style
--
-- Crée 3 tables : matching_scores, swipes, super_swipes_quota
-- + RLS strict (chaque soignant ne voit que ses propres données)
-- + index pour requêtes scoring + listing missions à swiper.
--
-- Modèle :
-- - matching_scores : cache score calculé soignant×mission (pré-calcul cron horaire)
-- - swipes : historique des actions soignant (LIKE/DISLIKE/SUPER_LIKE)
-- - super_swipes_quota : compteur quotidien super-likes (limite 5/jour anti-spam)

CREATE TABLE IF NOT EXISTS public.matching_scores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
  mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  score_global integer NOT NULL CHECK (score_global >= 0 AND score_global <= 100),
  breakdown jsonb NOT NULL DEFAULT '{}'::jsonb,
  calcule_le timestamptz NOT NULL DEFAULT now(),
  UNIQUE (soignant_id, mission_id)
);

CREATE INDEX IF NOT EXISTS idx_matching_scores_soignant_score
  ON public.matching_scores (soignant_id, score_global DESC);
CREATE INDEX IF NOT EXISTS idx_matching_scores_mission
  ON public.matching_scores (mission_id);
CREATE INDEX IF NOT EXISTS idx_matching_scores_calcule_le
  ON public.matching_scores (calcule_le);

CREATE TYPE swipe_direction AS ENUM ('LIKE', 'DISLIKE', 'SUPER_LIKE');

CREATE TABLE IF NOT EXISTS public.swipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
  mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  direction swipe_direction NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (soignant_id, mission_id)
);

CREATE INDEX IF NOT EXISTS idx_swipes_soignant_created
  ON public.swipes (soignant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_swipes_mission_direction
  ON public.swipes (mission_id, direction);

CREATE TABLE IF NOT EXISTS public.super_swipes_quota (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
  date date NOT NULL DEFAULT current_date,
  count integer NOT NULL DEFAULT 0 CHECK (count >= 0 AND count <= 5),
  UNIQUE (soignant_id, date)
);

CREATE INDEX IF NOT EXISTS idx_super_swipes_quota_soignant_date
  ON public.super_swipes_quota (soignant_id, date);

-- RLS strict : chaque soignant ne voit que ses propres données.
-- Convention Jolene : soignants.id = auth.uid() directement (cf. pol_soig_select).
ALTER TABLE public.matching_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.super_swipes_quota ENABLE ROW LEVEL SECURITY;

-- matching_scores : SELECT own + service_role full access (cron + RPC)
CREATE POLICY matching_scores_select_own ON public.matching_scores
  FOR SELECT USING (soignant_id = auth.uid());

CREATE POLICY matching_scores_service_role ON public.matching_scores
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- swipes : SELECT/INSERT own, pas d'UPDATE/DELETE (historique immuable)
CREATE POLICY swipes_select_own ON public.swipes
  FOR SELECT USING (soignant_id = auth.uid());

CREATE POLICY swipes_insert_own ON public.swipes
  FOR INSERT WITH CHECK (soignant_id = auth.uid());

CREATE POLICY swipes_service_role ON public.swipes
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- super_swipes_quota : SELECT own, INSERT/UPDATE via RPC SECURITY DEFINER uniquement
CREATE POLICY super_swipes_quota_select_own ON public.super_swipes_quota
  FOR SELECT USING (soignant_id = auth.uid());

CREATE POLICY super_swipes_quota_service_role ON public.super_swipes_quota
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public.matching_scores IS 'Sprint 13-A : cache scores matching soignant×mission, recalculé cron horaire pour soignants actifs.';
COMMENT ON TABLE public.swipes IS 'Sprint 13-A : historique swipes soignant (LIKE/DISLIKE/SUPER_LIKE) immuable. UNIQUE (soignant_id, mission_id).';
COMMENT ON TABLE public.super_swipes_quota IS 'Sprint 13-A : compteur super-likes quotidien par soignant (limite 5/jour anti-spam).';
