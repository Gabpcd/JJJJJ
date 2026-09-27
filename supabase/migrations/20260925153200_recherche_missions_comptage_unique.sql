-- Définition LIVE staging/production relue le 25/09/2026.
-- Le plan observé recompte le CTE de 500 lignes 500 fois quand les statistiques
-- sous-estiment le catalogue. La fenêtre calcule une seule fois le total filtré,
-- sans modifier colonnes, filtres métier, autorisations ni ordre de présentation.
CREATE OR REPLACE FUNCTION public.fn_missions_publiques_recherche(p_profession text DEFAULT NULL::text, p_ville text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, intitule text, profession_requise text, ville text, code_postal text, debut_le timestamp with time zone, fin_le timestamp with time zone, taux_horaire_base numeric, est_urgente boolean, type_contrat_recherche text, total_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_est_soignant boolean := EXISTS (
    SELECT 1 FROM public.soignants s WHERE s.id = auth.uid() AND s.supprime_le IS NULL
  );
BEGIN
  RETURN QUERY
  WITH filtered AS (
    SELECT m.id AS mid, m.intitule AS mintitule, m.profession_requise::text AS mprof,
      e.adresse_ville::text AS mville, e.adresse_code_postal::text AS mcp,
      m.debut_le AS mdebut, m.fin_le AS mfin, m.taux_horaire_base AS mtaux,
      COALESCE(m.est_urgente, false) AS murgente,
      m.type_contrat_recherche::text AS mcontrat, m.cree_le AS mcree
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND e.supprime_le IS NULL
      AND COALESCE(e.est_compte_test, false) = false
      AND e.statut_verification = 'VERIFIE'
      AND COALESCE(e.peut_publier_missions, false) = true
      AND e.type <> 'PHARMACIE_OFFICINE'
      AND m.intitule NOT LIKE '[%'
      AND (p_profession IS NULL OR btrim(p_profession) = '' OR m.profession_requise::text = btrim(p_profession))
      AND (p_ville IS NULL OR btrim(p_ville) = ''
           OR e.adresse_ville ILIKE '%' || btrim(p_ville) || '%'
           OR e.adresse_code_postal LIKE btrim(p_ville) || '%')
      AND (NOT v_est_soignant OR public.fn_soignant_eligible_mission(v_uid, m.id, false))
      AND (v_uid IS NULL OR NOT public.fn_est_exclu(v_uid, m.etablissement_id))
  )
  SELECT f.mid, f.mintitule, f.mprof, f.mville, f.mcp, f.mdebut, f.mfin,
         f.mtaux, f.murgente, f.mcontrat, count(*) OVER ()
  FROM filtered f
  ORDER BY f.murgente DESC, f.mcree DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_missions_publiques_recherche(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_recherche(text,text) TO anon,authenticated,service_role;
