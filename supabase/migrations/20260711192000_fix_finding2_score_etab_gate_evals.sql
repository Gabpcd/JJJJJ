-- Finding #2 (audit A4) — l'affichage du score qualité établissement dépendait de
-- la PRÉSENCE de `etablissements.score_qualite` (un baseline par défaut = 50),
-- jamais du COMPTE d'évaluations publiées. Conséquence : un établissement sans
-- aucune évaluation réelle (ex. données de seed avec score_qualite=50) affichait
-- « 50/100 » au lieu de « Nouveau » via `fn_score_etab_public` →
-- `BadgeScoreEtabPublic`.
--
-- Règle : un score ne s'affiche QUE si l'établissement a au moins 3 évaluations
-- SOIGNANT_VERS_ETAB **publiées** (double-aveugle, `publie_le IS NOT NULL`) — sinon
-- score_qualite/niveau = NULL (le badge rend « Nouveau »). Le compte est renvoyé
-- pour que le front puisse asserter la règle. Redéfinition depuis la déf LIVE
-- (règle 9.0), seul le gate est ajouté.
CREATE OR REPLACE FUNCTION public.fn_score_etab_public(p_etab_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_a_eu_mission BOOLEAN := false;
  v_nb_evals INT := 0;
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;
  SELECT EXISTS (SELECT 1 FROM missions WHERE etablissement_id = p_etab_id AND soignant_assigne_id = v_uid)
  INTO v_a_eu_mission;
  IF NOT v_a_eu_mission AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  -- Gate Finding #2 : compte d'évaluations SOIGNANT_VERS_ETAB PUBLIÉES.
  SELECT COUNT(*) INTO v_nb_evals
  FROM notations_missions
  WHERE note_id = p_etab_id AND sens = 'SOIGNANT_VERS_ETAB'
    AND masque = false AND publie_le IS NOT NULL;

  SELECT jsonb_build_object(
    'etablissement_id', e.id, 'nom', e.nom,
    'nb_evaluations_publiees', v_nb_evals,
    -- score/niveau masqués tant que < 3 évaluations publiées (→ badge « Nouveau »)
    'score_qualite', CASE WHEN v_nb_evals >= 3 THEN e.score_qualite ELSE NULL END,
    'niveau', CASE WHEN v_nb_evals >= 3 THEN e.niveau ELSE NULL END
  ) INTO v_result FROM etablissements e WHERE e.id = p_etab_id;
  RETURN COALESCE(v_result, '{}'::jsonb);
END;
$function$;
