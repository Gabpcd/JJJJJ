-- Sprint 13-C PR 1 — Badges engagement soignant
--
-- Table badges_soignant + triggers d'award automatique sur événements clés.
--
-- Badges seedés :
-- - PREMIER_SWIPE : 1er INSERT dans swipes
-- - EXPLORATEUR : 50 swipes cumulés
-- - TOP_SWIPER : 200 swipes cumulés
-- - PREMIER_SUPER_LIKE : 1er INSERT swipes direction='SUPER_LIKE'
-- - PREMIER_MATCH : 1ère candidature acceptée issue d'un swipe (LIKE/SUPER_LIKE)
-- - MATCH_KING_QUEEN : 10 candidatures acceptées via swipe

CREATE TABLE IF NOT EXISTS public.badges_soignant (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
  badge_type text NOT NULL,
  earned_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (soignant_id, badge_type)
);

CREATE INDEX IF NOT EXISTS idx_badges_soignant_id
  ON public.badges_soignant (soignant_id, earned_at DESC);

ALTER TABLE public.badges_soignant ENABLE ROW LEVEL SECURITY;

CREATE POLICY badges_soignant_select_own ON public.badges_soignant
  FOR SELECT USING (soignant_id = auth.uid());

CREATE POLICY badges_soignant_service_role ON public.badges_soignant
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public.badges_soignant IS
'Sprint 13-C : badges engagement soignant (PREMIER_SWIPE, EXPLORATEUR, TOP_SWIPER, PREMIER_SUPER_LIKE, PREMIER_MATCH, MATCH_KING_QUEEN). UNIQUE (soignant_id, badge_type) anti-doublon. Award automatique via triggers.';

-- ─── Trigger award sur swipes (INSERT) ───────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_award_badges_swipe()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_total_swipes integer;
BEGIN
  -- Compte total swipes pour ce soignant (incluant celui qu'on vient d'insérer)
  SELECT count(*) INTO v_total_swipes
    FROM public.swipes
   WHERE soignant_id = NEW.soignant_id;

  -- PREMIER_SWIPE
  IF v_total_swipes = 1 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'PREMIER_SWIPE')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  -- EXPLORATEUR (50 swipes)
  IF v_total_swipes = 50 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'EXPLORATEUR')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  -- TOP_SWIPER (200 swipes)
  IF v_total_swipes = 200 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'TOP_SWIPER')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  -- PREMIER_SUPER_LIKE : sur premier swipe direction SUPER_LIKE
  IF NEW.direction = 'SUPER_LIKE' THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type)
      VALUES (NEW.soignant_id, 'PREMIER_SUPER_LIKE')
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_award_badges_swipe ON public.swipes;
CREATE TRIGGER trg_award_badges_swipe
  AFTER INSERT ON public.swipes
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_award_badges_swipe();

-- ─── Trigger award sur candidatures (UPDATE → ASSIGNEE) ──────────────
-- Match = candidature acceptée par étab. Soignant gagne PREMIER_MATCH (1er)
-- ou MATCH_KING_QUEEN (10 cumulés) si la candidature a été précédée d'un
-- swipe LIKE ou SUPER_LIKE pour la mission.

CREATE OR REPLACE FUNCTION public.fn_award_badges_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_had_swipe boolean;
  v_total_matches_via_swipe integer;
BEGIN
  -- Match détecté uniquement quand candidature passe à ASSIGNEE
  IF NEW.statut <> 'ASSIGNEE' OR OLD.statut = 'ASSIGNEE' THEN
    RETURN NEW;
  END IF;

  -- Vérifier qu'un swipe LIKE/SUPER_LIKE existe pour cette mission + soignant
  SELECT EXISTS (
    SELECT 1 FROM public.swipes
     WHERE soignant_id = NEW.soignant_id
       AND mission_id = NEW.mission_id
       AND direction IN ('LIKE', 'SUPER_LIKE')
  ) INTO v_had_swipe;

  IF NOT v_had_swipe THEN
    RETURN NEW;
  END IF;

  -- PREMIER_MATCH (idempotent via UNIQUE)
  INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
    VALUES (NEW.soignant_id, 'PREMIER_MATCH', jsonb_build_object('mission_id', NEW.mission_id))
    ON CONFLICT (soignant_id, badge_type) DO NOTHING;

  -- Compter total matches via swipe pour MATCH_KING_QUEEN
  SELECT count(*) INTO v_total_matches_via_swipe
    FROM public.candidatures c
   WHERE c.soignant_id = NEW.soignant_id
     AND c.statut = 'ASSIGNEE'
     AND EXISTS (
       SELECT 1 FROM public.swipes s
        WHERE s.soignant_id = c.soignant_id
          AND s.mission_id = c.mission_id
          AND s.direction IN ('LIKE', 'SUPER_LIKE')
     );

  IF v_total_matches_via_swipe >= 10 THEN
    INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
      VALUES (
        NEW.soignant_id,
        'MATCH_KING_QUEEN',
        jsonb_build_object('total_matches', v_total_matches_via_swipe)
      )
      ON CONFLICT (soignant_id, badge_type) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$body$;

DROP TRIGGER IF EXISTS trg_award_badges_match ON public.candidatures;
CREATE TRIGGER trg_award_badges_match
  AFTER UPDATE ON public.candidatures
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_award_badges_match();

-- ─── RPC fn_mes_badges (lecture) ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_mes_badges()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_badges jsonb;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('badges', '[]'::jsonb, 'error', 'auth_required');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'badge_type', badge_type,
      'earned_at', earned_at,
      'metadata', metadata
    ) ORDER BY earned_at DESC
  ), '[]'::jsonb)
    INTO v_badges
    FROM public.badges_soignant
   WHERE soignant_id = v_soignant_id;

  RETURN jsonb_build_object('badges', v_badges);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_mes_badges() TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_mes_badges() IS
'Sprint 13-C : liste les badges engagement gagnés par le soignant authentifié.';
