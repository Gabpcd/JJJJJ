-- ============================================================================
-- Sprint 5.7 PR 5 — RPC pour lister missions à évaluer côté étab (P0-8)
-- ============================================================================
-- L'infrastructure backend Sprint 3.5 (table notations_missions, RPCs
-- fn_creer_notation_mission, fn_compter_missions_sans_notation) existe déjà.
-- Cette PR ajoute la RPC `fn_lister_missions_a_noter_etab()` qui retourne
-- les missions terminées assignées sans notation ETAB_VERS_SOIGNANT.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_noter_etab()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'intitule', m.intitule,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'soignant_id', m.soignant_assigne_id,
    'soignant_prenom', s.prenom,
    'soignant_nom', s.nom,
    'soignant_profession', s.profession,
    'duree_heures', m.duree_heures,
    'taux_horaire_base', m.taux_horaire_base,
    'jours_depuis_fin', EXTRACT(DAY FROM NOW() - m.fin_le)::int
  ) ORDER BY m.fin_le DESC), '[]'::jsonb)
  INTO v_missions
  FROM public.missions m
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  WHERE m.etablissement_id = v_etab_id
    AND m.statut = 'TERMINEE'
    AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.notations_missions nm
      WHERE nm.mission_id = m.id
        AND nm.sens = 'ETAB_VERS_SOIGNANT'
        AND nm.notateur_id = v_uid
    )
    AND m.fin_le > NOW() - INTERVAL '60 days';

  RETURN jsonb_build_object('success', true, 'missions', v_missions);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_lister_missions_a_noter_etab() TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT57_PR5_EVALUATION_REVERSE_ETAB_INSTALLED',
    'pr', 'PR 5 Sprint 5.7',
    'rpc', 'fn_lister_missions_a_noter_etab',
    'description', 'Liste missions TERMINEE assignées sans notation ETAB_VERS_SOIGNANT'
  )
);
