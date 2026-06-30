-- Les missions de test E2E (préfixe « [playwright-test] » / « [pw-test:... » créées
-- en continu par la suite Playwright) apparaissaient dans le FEED PUBLIC de missions
-- (page publique + recherche) → polluaient les captures store ET seraient visibles
-- par de vrais utilisateurs au lancement. On les exclut de la recherche publique :
-- aucune vraie mission ne commence par « [ ». Déjà appliqué en prod via MCP.
--
-- NB : on NE filtre PAS fn_obtenir_missions_swipe — les tests E2E matching seedent des
-- missions [playwright-test] et les vérifient justement via ce RPC (matching-backend.spec).
-- Le swipe est derrière authentification (exposition non publique). L'isolation propre =
-- un projet Supabase de test dédié (backlog).

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
