-- RECRÉATION de fn_admin_planning_global, supprimée À TORT dans le cleanup
-- 20260608120000. Elle y avait été classée « superseded » avec fn_planning_soignant
-- et fn_planning_etablissement — mais celles-ci le sont réellement (PlanningHebdomadaire
-- lit la table missions en direct), tandis que le PLANNING GLOBAL ADMIN n'a jamais eu
-- d'UI : c'était une feature non construite, pas du code mort. On la rétablit pour la
-- brancher côté admin (cf. PR vue planning admin).
--
-- Vue admin : toutes les missions sur une fenêtre de dates, avec établissement, ville,
-- soignant assigné (si présent), statut, profession, urgence. Triées par début.
CREATE OR REPLACE FUNCTION public.fn_admin_planning_global(p_debut date, p_fin date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'debut', p_debut,
    'fin', p_fin,
    'missions', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id,
        'intitule', m.intitule,
        'statut', m.statut,
        'profession_requise', m.profession_requise,
        'service', m.service,
        'debut_le', m.debut_le,
        'fin_le', m.fin_le,
        'est_urgente', m.est_urgente,
        'etablissement_nom', e.nom,
        'etablissement_ville', e.adresse_ville,
        'soignant_nom', CASE WHEN s.id IS NOT NULL THEN s.prenom || ' ' || s.nom ELSE NULL END
      ) ORDER BY m.debut_le), '[]'::jsonb)
      FROM missions m
      LEFT JOIN etablissements e ON e.id = m.etablissement_id
      LEFT JOIN soignants s ON s.id = m.soignant_assigne_id
      WHERE m.debut_le >= p_debut::timestamptz
        AND m.debut_le < (p_fin::timestamptz + interval '1 day')
    )
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_planning_global(date, date) TO authenticated;
