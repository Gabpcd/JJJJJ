-- Gestion admin des paliers BFA (bonus de fin d'année) : le backend (table
-- paliers_bfa + fn_bfa_info/fn_calculer_bfa_safe/fn_calculer_bfa_tous) était
-- complet mais sans aucune interface admin — toute modification passait par
-- un UPDATE SQL manuel.

-- Liste des paliers + groupes éligibles (une seule RPC pour la page AdminBFA)
CREATE OR REPLACE FUNCTION public.fn_admin_lister_paliers_bfa()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  RETURN jsonb_build_object(
    'paliers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id, 'nom', p.nom, 'missions_min', p.missions_min,
        'missions_max', p.missions_max, 'taux_bfa', p.taux_bfa,
        'ordre', p.ordre, 'est_actif', p.est_actif
      ) ORDER BY p.ordre)
      FROM paliers_bfa p
    ), '[]'::jsonb),
    'groupes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', g.id, 'nom', g.nom, 'bfa_eligible', g.bfa_eligible,
        'bfa_contrat_signe_le', g.bfa_contrat_signe_le,
        'nb_etablissements', (SELECT count(*) FROM etablissements e WHERE e.groupe_sante_id = g.id AND e.supprime_le IS NULL)
      ) ORDER BY g.nom)
      FROM groupes_sante g
    ), '[]'::jsonb)
  );
END;
$fn$;

-- Modification d'un palier (bornes + taux + actif) avec validation de
-- non-chevauchement entre paliers actifs et audit.
CREATE OR REPLACE FUNCTION public.fn_admin_modifier_palier_bfa(
  p_palier_id uuid,
  p_nom text DEFAULT NULL,
  p_missions_min integer DEFAULT NULL,
  p_missions_max integer DEFAULT NULL,
  p_taux_bfa numeric DEFAULT NULL,
  p_est_actif boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_avant record;
  v_min integer;
  v_max integer;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  SELECT * INTO v_avant FROM paliers_bfa WHERE id = p_palier_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Palier introuvable');
  END IF;

  v_min := COALESCE(p_missions_min, v_avant.missions_min);
  v_max := COALESCE(p_missions_max, v_avant.missions_max);

  IF p_taux_bfa IS NOT NULL AND (p_taux_bfa < 0 OR p_taux_bfa > 50) THEN
    RETURN jsonb_build_object('error', 'Le taux BFA doit être entre 0 et 50 %');
  END IF;
  IF v_min < 0 OR (v_max IS NOT NULL AND v_max < v_min) THEN
    RETURN jsonb_build_object('error', 'Bornes invalides (max < min)');
  END IF;
  -- Non-chevauchement avec les autres paliers actifs
  IF COALESCE(p_est_actif, v_avant.est_actif) AND EXISTS (
    SELECT 1 FROM paliers_bfa autre
    WHERE autre.id <> p_palier_id AND autre.est_actif
      AND v_min <= COALESCE(autre.missions_max, 2147483647)
      AND COALESCE(v_max, 2147483647) >= autre.missions_min
  ) THEN
    RETURN jsonb_build_object('error', 'Les bornes chevauchent un autre palier actif');
  END IF;

  UPDATE paliers_bfa SET
    nom = COALESCE(p_nom, nom),
    missions_min = v_min,
    missions_max = CASE WHEN p_missions_max IS NOT NULL THEN p_missions_max ELSE missions_max END,
    taux_bfa = COALESCE(p_taux_bfa, taux_bfa),
    est_actif = COALESCE(p_est_actif, est_actif)
  WHERE id = p_palier_id;

  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (auth.uid(), 'ADMIN', 'TAUX_COMMISSION_MODIFIE', 'palier_bfa', p_palier_id,
    jsonb_build_object(
      'avant', jsonb_build_object('nom', v_avant.nom, 'min', v_avant.missions_min, 'max', v_avant.missions_max, 'taux', v_avant.taux_bfa, 'actif', v_avant.est_actif),
      'apres', jsonb_build_object('nom', COALESCE(p_nom, v_avant.nom), 'min', v_min, 'max', COALESCE(p_missions_max, v_avant.missions_max), 'taux', COALESCE(p_taux_bfa, v_avant.taux_bfa), 'actif', COALESCE(p_est_actif, v_avant.est_actif))
    ));

  RETURN jsonb_build_object('success', true);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_paliers_bfa() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_modifier_palier_bfa(uuid, text, integer, integer, numeric, boolean) TO authenticated;
