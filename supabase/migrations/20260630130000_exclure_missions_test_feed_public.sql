-- Les missions de test E2E (préfixe « [playwright-test] » / « [pw-test:... » créées
-- en continu par la suite Playwright) apparaissaient dans le feed public de missions
-- ET dans le swipe → polluaient les captures store ET seraient visibles par de vrais
-- utilisateurs au lancement. On les exclut des deux RPC : aucune vraie mission ne
-- commence par « [ ». Déjà appliqué en prod via MCP.

CREATE OR REPLACE FUNCTION public.fn_missions_publiques_recherche(p_profession text DEFAULT NULL::text, p_ville text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, intitule text, profession_requise text, ville text, code_postal text, debut_le timestamp with time zone, fin_le timestamp with time zone, taux_horaire_base numeric, est_urgente boolean, type_contrat_recherche text, total_count bigint)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant_id UUID;
    v_type_exercice TEXT;
BEGIN
    v_soignant_id := auth.uid();
    SELECT s.type_exercice INTO v_type_exercice FROM soignants s WHERE s.id = v_soignant_id;
    RETURN QUERY
    WITH filtered AS (
        SELECT m.id AS mid, m.intitule AS mintitule, m.profession_requise::TEXT AS mprof,
            e.adresse_ville::TEXT AS mville, e.adresse_code_postal::TEXT AS mcp,
            m.debut_le AS mdebut, m.fin_le AS mfin, m.taux_horaire_base AS mtaux,
            COALESCE(m.est_urgente, FALSE) AS murgente, m.type_contrat_recherche::TEXT AS mcontrat, m.cree_le AS mcree
        FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.statut = 'OUVERTE' AND m.debut_le > NOW() AND e.supprime_le IS NULL
          AND m.intitule NOT LIKE '[%'  -- exclut les missions de test E2E
          AND (p_profession IS NULL OR BTRIM(p_profession) = '' OR m.profession_requise::TEXT = BTRIM(p_profession))
          AND (p_ville IS NULL OR BTRIM(p_ville) = '' OR e.adresse_ville ILIKE '%' || BTRIM(p_ville) || '%' OR e.adresse_code_postal LIKE BTRIM(p_ville) || '%')
          AND (v_soignant_id IS NULL OR NOT fn_est_exclu(v_soignant_id, m.etablissement_id))
          AND (m.type_contrat_recherche = 'TOUS' OR v_type_exercice IS NULL OR v_type_exercice = 'MIXTE'
              OR (m.type_contrat_recherche = 'SALARIE' AND v_type_exercice IN ('SALARIE', 'MIXTE'))
              OR (m.type_contrat_recherche = 'LIBERAL' AND v_type_exercice IN ('LIBERAL', 'MIXTE')))
    ), counted AS (SELECT COUNT(*)::BIGINT AS cnt FROM filtered)
    SELECT f.mid, f.mintitule, f.mprof, f.mville, f.mcp, f.mdebut, f.mfin, f.mtaux, f.murgente, f.mcontrat, c.cnt
    FROM filtered f CROSS JOIN counted c
    ORDER BY f.murgente DESC, f.mcree DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_soignant_id uuid := auth.uid(); v_missions jsonb;
BEGIN
  IF v_soignant_id IS NULL THEN RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required'); END IF;
  SELECT COALESCE(jsonb_agg(payload ORDER BY (payload->>'score')::int DESC), '[]'::jsonb) INTO v_missions
  FROM (
    SELECT jsonb_build_object(
      'mission_id', m.id, 'intitule', m.intitule, 'profession_requise', m.profession_requise,
      'etablissement_id', m.etablissement_id, 'etablissement_nom', e.nom, 'etablissement_ville', e.adresse_ville,
      'etablissement_score', e.score_qualite, 'taux_horaire_base', m.taux_horaire_base, 'duree_heures', m.duree_heures,
      'debut_le', m.debut_le, 'fin_le', m.fin_le, 'est_urgente', m.est_urgente, 'service', m.service,
      'type_contrat_applique', m.type_contrat_applique, 'total_brut', m.total_brut, 'net_a_payer', m.net_a_payer,
      'net_estime', m.net_estime, 'montant_ifm', COALESCE(m.montant_ifm, 0), 'montant_icp', COALESCE(m.montant_icp, 0),
      'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0), 'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
      'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0), 'score', COALESCE(ms.score_global, 0),
      'breakdown', COALESCE(ms.breakdown, '{}'::jsonb)
    ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_soignant_id
     WHERE m.statut = 'OUVERTE'
       AND m.intitule NOT LIKE '[%'  -- exclut les missions de test E2E
       AND m.id NOT IN (SELECT s.mission_id FROM public.swipes s WHERE s.soignant_id = v_soignant_id)
     ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
     LIMIT p_limit
  ) t;
  RETURN jsonb_build_object('missions', v_missions);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_missions_swipe(integer) TO authenticated, service_role;
