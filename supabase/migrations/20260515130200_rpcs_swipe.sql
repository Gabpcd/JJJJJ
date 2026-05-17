-- Sprint 13-A PR 3 — RPCs swipe + cron pré-calcul matching_scores
--
-- 1. fn_obtenir_missions_swipe(p_limit) : missions ouvertes triées par score DESC,
--    excluant celles déjà swipées par le soignant authentifié.
-- 2. fn_enregistrer_swipe(p_mission_id, p_direction) : INSERT swipe + validation
--    quota super-likes 5/jour si SUPER_LIKE.
-- 3. fn_recalculer_scores_soignants_actifs() : cron job pour pré-calculer
--    matching_scores des soignants ayant une activité récente (24h).

-- ─── 1. fn_obtenir_missions_swipe ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_missions jsonb;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required');
  END IF;

  SELECT COALESCE(jsonb_agg(payload ORDER BY (payload->>'score')::int DESC), '[]'::jsonb)
    INTO v_missions
    FROM (
      SELECT jsonb_build_object(
        'mission_id', m.id,
        'intitule', m.intitule,
        'profession_requise', m.profession_requise,
        'etablissement_id', m.etablissement_id,
        'etablissement_nom', e.nom,
        'etablissement_ville', e.adresse_ville,
        'etablissement_score', e.score_qualite,
        'taux_horaire_base', m.taux_horaire_base,
        'duree_heures', m.duree_heures,
        'debut_le', m.debut_le,
        'fin_le', m.fin_le,
        'est_urgente', m.est_urgente,
        'service', m.service,
        'score', COALESCE(ms.score_global, 0),
        'breakdown', COALESCE(ms.breakdown, '{}'::jsonb)
      ) AS payload
        FROM public.missions m
        JOIN public.etablissements e ON e.id = m.etablissement_id
        LEFT JOIN public.matching_scores ms
          ON ms.mission_id = m.id AND ms.soignant_id = v_soignant_id
       WHERE m.statut = 'OUVERTE'
         AND m.id NOT IN (
           SELECT s.mission_id FROM public.swipes s WHERE s.soignant_id = v_soignant_id
         )
       ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
       LIMIT p_limit
    ) t;

  RETURN jsonb_build_object('missions', v_missions);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_missions_swipe(integer)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_obtenir_missions_swipe(integer) IS
'Sprint 13-A : retourne missions OUVERTES non-swipées triées par score matching DESC. Inclut breakdown pour transparence UI.';

-- ─── 2. fn_enregistrer_swipe ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(
  p_mission_id uuid,
  p_direction text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
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

  -- Validation quota super-likes 5/jour
  IF v_direction = 'SUPER_LIKE' THEN
    INSERT INTO public.super_swipes_quota (soignant_id, date, count)
      VALUES (v_soignant_id, current_date, 1)
      ON CONFLICT (soignant_id, date)
        DO UPDATE SET count = super_swipes_quota.count + 1
      RETURNING count INTO v_quota_count;

    IF v_quota_count > 5 THEN
      -- Rollback : décrémenter pour ne pas consommer le quota
      UPDATE public.super_swipes_quota
         SET count = count - 1
       WHERE soignant_id = v_soignant_id AND date = current_date;
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'quota_super_like_atteint',
        'quota_max', 5,
        'reset_le', (current_date + interval '1 day')::date
      );
    END IF;
  END IF;

  -- INSERT swipe (ON CONFLICT DO NOTHING : pas de re-swipe)
  INSERT INTO public.swipes (soignant_id, mission_id, direction)
    VALUES (v_soignant_id, p_mission_id, v_direction)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING
    RETURNING id INTO v_swipe_id;

  IF v_swipe_id IS NULL THEN
    -- Si re-swipe détecté + SUPER_LIKE, on doit rollback le quota
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
$body$;

GRANT EXECUTE ON FUNCTION public.fn_enregistrer_swipe(uuid, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_enregistrer_swipe(uuid, text) IS
'Sprint 13-A : enregistre swipe LIKE/DISLIKE/SUPER_LIKE. Valide quota super-likes 5/jour. Idempotent via UNIQUE.';

-- ─── 3. fn_recalculer_scores_soignants_actifs (cron) ─────────────────

CREATE OR REPLACE FUNCTION public.fn_recalculer_scores_soignants_actifs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_soignant record;
  v_mission record;
  v_result jsonb;
  v_count integer := 0;
  v_start timestamptz := clock_timestamp();
BEGIN
  -- Soignants actifs : ont swipé ou ont eu activité auth récente (24h)
  FOR v_soignant IN
    SELECT DISTINCT s.id
      FROM public.soignants s
      LEFT JOIN public.swipes sw ON sw.soignant_id = s.id
        AND sw.created_at > now() - interval '24 hours'
     WHERE sw.id IS NOT NULL
        OR EXISTS (
          SELECT 1 FROM auth.users u
           WHERE u.id = s.id AND u.last_sign_in_at > now() - interval '24 hours'
        )
     LIMIT 200
  LOOP
    FOR v_mission IN
      SELECT m.id
        FROM public.missions m
       WHERE m.statut = 'OUVERTE'
         AND m.id NOT IN (
           SELECT mission_id FROM public.swipes WHERE soignant_id = v_soignant.id
         )
       LIMIT 50
    LOOP
      v_result := public.fn_calculer_score_matching(v_soignant.id, v_mission.id);

      INSERT INTO public.matching_scores (soignant_id, mission_id, score_global, breakdown)
        VALUES (
          v_soignant.id,
          v_mission.id,
          (v_result->>'score')::integer,
          v_result->'breakdown'
        )
        ON CONFLICT (soignant_id, mission_id)
          DO UPDATE SET
            score_global = EXCLUDED.score_global,
            breakdown = EXCLUDED.breakdown,
            calcule_le = now();

      v_count := v_count + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'scores_calcules', v_count,
    'duree_ms', extract(epoch from (clock_timestamp() - v_start)) * 1000
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_recalculer_scores_soignants_actifs() TO service_role;

COMMENT ON FUNCTION public.fn_recalculer_scores_soignants_actifs() IS
'Sprint 13-A : cron pré-calcul matching_scores pour soignants actifs (last_sign_in_at < 24h OU swipe récent). Limite 200 soignants × 50 missions par run.';

-- ─── 4. Schedule pg_cron (horaire) ───────────────────────────────────

-- Best-effort : crée le job seulement si pg_cron est dispo + RPC fn_lire_secret_cron.
DO $$
DECLARE
  v_secret text;
BEGIN
  -- Vérifie extension pg_cron
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron non installé, skip schedule';
    RETURN;
  END IF;

  -- Récupère secret cron pour appel HTTP (alternative : appel SQL direct)
  -- Ici on passe par appel SQL direct (plus simple, pas de net.http_post)
  PERFORM cron.schedule(
    'matching_scores_recalcul_hourly',
    '0 * * * *',
    $cron$
      SELECT public.fn_recalculer_scores_soignants_actifs();
    $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Schedule pg_cron skipped (peut être déjà créé) : %', SQLERRM;
END $$;
