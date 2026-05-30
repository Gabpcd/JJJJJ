-- Légal : le parcours 3200h doit compter les heures RÉELLEMENT travaillées
-- (pointage arrivée/départ, nettes de pauses), pas les heures prévues du planning.
--
-- presences.heures_reelles est déjà calculée automatiquement au pointage départ
-- (trigger trg_calculer_duree → dec_calculer_duree_presence :
--  heures_reelles = (départ - arrivée - pauses) / 60).
-- On somme ces heures réelles par mission terminée. Repli sur les heures prévues
-- (duree_heures_effective / duree_heures) uniquement si aucun pointage exploitable
-- (ex. missions historiques sans pointage).

CREATE OR REPLACE FUNCTION public.fn_compteur_heures_soignant(p_soignant_id uuid)
RETURNS TABLE(heures_jolene integer, heures_externes_validees integer, heures_externes_en_attente integer, heures_totales integer, eligible_free_transition boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_heures_jolene INTEGER := 0;
  v_heures_ext_val INTEGER := 0;
  v_heures_ext_att INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;
  IF auth.uid() != p_soignant_id AND NOT est_admin() THEN
    RAISE EXCEPTION 'Accès non autorisé';
  END IF;

  -- Heures Jolene = somme par mission terminée des heures RÉELLEMENT pointées
  -- (presences.heures_reelles), avec repli sur les heures prévues si la mission
  -- n'a aucun pointage exploitable.
  SELECT COALESCE(SUM(
    COALESCE(
      (SELECT SUM(pr.heures_reelles)
         FROM public.presences pr
        WHERE pr.mission_id = m.id
          AND pr.heures_reelles IS NOT NULL),
      m.duree_heures_effective,
      m.duree_heures
    )
  )::INTEGER, 0)
  INTO v_heures_jolene
  FROM public.missions m
  WHERE m.soignant_assigne_id = p_soignant_id AND m.statut = 'TERMINEE';

  SELECT COALESCE(SUM(heures_declarees)::INTEGER, 0)
  INTO v_heures_ext_val
  FROM public.heures_externes_soignants
  WHERE soignant_id = p_soignant_id AND statut_validation = 'VALIDE';

  SELECT COALESCE(SUM(heures_declarees)::INTEGER, 0)
  INTO v_heures_ext_att
  FROM public.heures_externes_soignants
  WHERE soignant_id = p_soignant_id AND statut_validation = 'EN_ATTENTE';

  RETURN QUERY SELECT v_heures_jolene, v_heures_ext_val, v_heures_ext_att,
    v_heures_jolene + v_heures_ext_val, v_heures_jolene >= 3200;
END;
$function$;

NOTIFY pgrst, 'reload schema';
