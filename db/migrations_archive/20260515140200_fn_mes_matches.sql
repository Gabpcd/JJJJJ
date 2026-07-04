-- Sprint 13-C PR 5 — RPC fn_mes_matches
--
-- Liste les candidatures du soignant authentifié qui sont issues d'un swipe
-- LIKE/SUPER_LIKE et qui sont passées à ASSIGNEE (matches). Inclut stats
-- engagement : nb swipes / nb matches / taux match.

CREATE OR REPLACE FUNCTION public.fn_mes_matches()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_matches jsonb;
  v_total_swipes integer;
  v_total_likes integer;
  v_total_matches integer;
  v_taux_match numeric;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('error', 'auth_required');
  END IF;

  -- Stats engagement
  SELECT count(*) INTO v_total_swipes FROM public.swipes WHERE soignant_id = v_soignant_id;
  SELECT count(*) INTO v_total_likes FROM public.swipes
   WHERE soignant_id = v_soignant_id AND direction IN ('LIKE', 'SUPER_LIKE');

  -- Liste des matches (candidatures ASSIGNEE issues d'un swipe LIKE/SUPER_LIKE)
  SELECT COALESCE(jsonb_agg(payload ORDER BY (payload->>'updated_at') DESC), '[]'::jsonb)
    INTO v_matches
    FROM (
      SELECT jsonb_build_object(
        'candidature_id', c.id,
        'mission_id', m.id,
        'mission_intitule', m.intitule,
        'mission_debut_le', m.debut_le,
        'mission_fin_le', m.fin_le,
        'mission_taux_horaire_base', m.taux_horaire_base,
        'mission_statut', m.statut,
        'etablissement_id', m.etablissement_id,
        'etablissement_nom', e.nom,
        'etablissement_ville', e.adresse_ville,
        'swipe_direction', s.direction,
        'candidature_statut', c.statut,
        'updated_at', GREATEST(COALESCE(c.acceptee_a, c.traite_le, c.cree_le), s.created_at)
      ) AS payload
        FROM public.candidatures c
        JOIN public.missions m ON m.id = c.mission_id
        JOIN public.etablissements e ON e.id = m.etablissement_id
        JOIN public.swipes s ON s.soignant_id = c.soignant_id AND s.mission_id = c.mission_id
       WHERE c.soignant_id = v_soignant_id
         AND s.direction IN ('LIKE', 'SUPER_LIKE')
         AND c.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    ) t;

  v_total_matches := COALESCE(jsonb_array_length(v_matches), 0);
  v_taux_match := CASE
    WHEN v_total_likes > 0 THEN round((v_total_matches::numeric / v_total_likes) * 100, 1)
    ELSE 0
  END;

  RETURN jsonb_build_object(
    'matches', v_matches,
    'stats', jsonb_build_object(
      'total_swipes', v_total_swipes,
      'total_likes', v_total_likes,
      'total_matches', v_total_matches,
      'taux_match', v_taux_match
    )
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_mes_matches() TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_mes_matches() IS
'Sprint 13-C : liste candidatures ASSIGNEE/EN_COURS/TERMINEE issues d''un swipe LIKE/SUPER_LIKE + stats engagement (nb swipes, nb likes, nb matches, taux match %).';
