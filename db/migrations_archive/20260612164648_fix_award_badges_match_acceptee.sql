-- Fix Sprint 13-C — badges PREMIER_MATCH / MATCH_KING_QUEEN inattribuables
--
-- Bug : fn_award_badges_match (migration 20260515140000) ne s'exécutait que
-- quand candidatures.statut passait à 'ASSIGNEE'. Or 'ASSIGNEE' est un statut
-- de MISSION : candidatures_statut_check (migration 20260429300000) n'autorise
-- que EN_ATTENTE / EN_ATTENTE_VALIDATION_ETAB / ACCEPTEE / REFUSEE / ANNULEE /
-- PROPOSEE / EXPIREE. Tout UPDATE vers 'ASSIGNEE' viole la CHECK → la condition
-- du trigger était du code mort et les badges PREMIER_MATCH / MATCH_KING_QUEEN
-- ne pouvaient JAMAIS être attribués en production.
--
-- Fix :
--   1. Le trigger écoute le passage à 'ACCEPTEE' — statut posé par
--      fn_traiter_candidature / fn_repondre_proposition quand l'établissement
--      accepte la candidature (même événement que trg_candidature_acceptee_chat).
--   2. Le count MATCH_KING_QUEEN compte les candidatures ACCEPTEE (même fix).
--   3. Backfill rétroactif : badges attribués aux soignants dont des
--      candidatures ACCEPTEE existantes étaient précédées d'un swipe
--      LIKE/SUPER_LIKE (earned_at = traite_le de l'acceptation, métadonnée
--      backfill=true pour la traçabilité).

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
  -- Match détecté uniquement quand la candidature passe à ACCEPTEE
  IF NEW.statut <> 'ACCEPTEE' OR OLD.statut = 'ACCEPTEE' THEN
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
     AND c.statut = 'ACCEPTEE'
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

COMMENT ON FUNCTION public.fn_award_badges_match() IS
'Sprint 13-C (fixé 12/06/2026) : award PREMIER_MATCH / MATCH_KING_QUEEN quand une candidature précédée d''un swipe LIKE/SUPER_LIKE passe à ACCEPTEE. Écoutait à tort ASSIGNEE (statut de mission, interdit par candidatures_statut_check) → badges inattribuables.';

-- ─── Backfill rétroactif ─────────────────────────────────────────────

-- PREMIER_MATCH : pour chaque soignant ayant ≥1 candidature ACCEPTEE précédée
-- d'un swipe LIKE/SUPER_LIKE. earned_at = date d'acceptation la plus ancienne.
INSERT INTO public.badges_soignant (soignant_id, badge_type, earned_at, metadata)
SELECT DISTINCT ON (c.soignant_id)
       c.soignant_id,
       'PREMIER_MATCH',
       COALESCE(c.traite_le, now()),
       jsonb_build_object('mission_id', c.mission_id, 'backfill', true)
  FROM public.candidatures c
 WHERE c.statut = 'ACCEPTEE'
   AND EXISTS (
     SELECT 1 FROM public.swipes s
      WHERE s.soignant_id = c.soignant_id
        AND s.mission_id = c.mission_id
        AND s.direction IN ('LIKE', 'SUPER_LIKE')
   )
 ORDER BY c.soignant_id, c.traite_le ASC NULLS LAST
ON CONFLICT (soignant_id, badge_type) DO NOTHING;

-- MATCH_KING_QUEEN : soignants à ≥10 candidatures ACCEPTEE via swipe.
INSERT INTO public.badges_soignant (soignant_id, badge_type, metadata)
SELECT m.soignant_id,
       'MATCH_KING_QUEEN',
       jsonb_build_object('total_matches', m.total, 'backfill', true)
  FROM (
    SELECT c.soignant_id, count(*) AS total
      FROM public.candidatures c
     WHERE c.statut = 'ACCEPTEE'
       AND EXISTS (
         SELECT 1 FROM public.swipes s
          WHERE s.soignant_id = c.soignant_id
            AND s.mission_id = c.mission_id
            AND s.direction IN ('LIKE', 'SUPER_LIKE')
       )
     GROUP BY c.soignant_id
    HAVING count(*) >= 10
  ) m
ON CONFLICT (soignant_id, badge_type) DO NOTHING;
