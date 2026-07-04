-- ============================================================================
-- Sprint 5.7 PR 9 — Admin alertes pointage Sprint 4.5 (P0-11)
-- ============================================================================
-- Détection Sprint 4.5 (alertes_systeme, presences.alerte_teleportation,
-- arrivee_mock_detected, depart_mock_detected, coherence_incidents jsonb)
-- existe en DB. Cette PR expose ces alertes côté admin UI.
-- ============================================================================

-- 1. RPC : résumé KPIs alertes (7 derniers jours)
CREATE OR REPLACE FUNCTION public.fn_admin_resume_alertes_pointage()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $body$
DECLARE
  v_kpi jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT jsonb_build_object(
    'teleportations_7j', (
      SELECT COUNT(*) FROM public.alertes_systeme
      WHERE type_alerte = 'TELEPORTATION_DETECTED' AND cree_le > NOW() - INTERVAL '7 days'
    ),
    'mock_gps_7j', (
      SELECT COUNT(*) FROM public.presences
      WHERE (arrivee_mock_detected = true OR depart_mock_detected = true)
        AND modifie_le > NOW() - INTERVAL '7 days'
    ),
    'coherence_7j', (
      SELECT COUNT(*) FROM public.alertes_systeme
      WHERE type_alerte = 'POINTAGE_INCOHERENT' AND cree_le > NOW() - INTERVAL '7 days'
    ),
    'qr_gps_eloigne_7j', (
      SELECT COUNT(*) FROM public.journaux_audit
      WHERE action = 'POINTAGE'
        AND details->>'evenement' = 'QR_SCAN_GPS_ELOIGNE'
        AND cree_le > NOW() - INTERVAL '7 days'
    ),
    'total_ouvertes', (
      SELECT COUNT(*) FROM public.alertes_systeme
      WHERE resolu_le IS NULL
        AND type_alerte IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT')
    )
  ) INTO v_kpi;

  RETURN jsonb_build_object('success', true, 'kpis', v_kpi);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_resume_alertes_pointage() TO authenticated;

-- 2. RPC : lister alertes pointage avec filtres
CREATE OR REPLACE FUNCTION public.fn_admin_lister_alertes_pointage(
  p_type_filtre text DEFAULT NULL,
  p_statut_filtre text DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $body$
DECLARE
  v_alertes jsonb;
  v_total int;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.alertes_systeme a
  WHERE a.type_alerte IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT')
    AND (p_type_filtre IS NULL OR a.type_alerte = p_type_filtre)
    AND (p_statut_filtre IS NULL
         OR (p_statut_filtre = 'OUVERTE' AND a.resolu_le IS NULL)
         OR (p_statut_filtre = 'RESOLUE' AND a.resolu_le IS NOT NULL));

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'type_alerte', a.type_alerte,
    'severite', a.severite,
    'source', a.source,
    'message', a.message,
    'details', a.details,
    'resolu_le', a.resolu_le,
    'cree_le', a.cree_le
  ) ORDER BY a.cree_le DESC), '[]'::jsonb)
  INTO v_alertes
  FROM (
    SELECT * FROM public.alertes_systeme
    WHERE type_alerte IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT')
      AND (p_type_filtre IS NULL OR type_alerte = p_type_filtre)
      AND (p_statut_filtre IS NULL
           OR (p_statut_filtre = 'OUVERTE' AND resolu_le IS NULL)
           OR (p_statut_filtre = 'RESOLUE' AND resolu_le IS NOT NULL))
    ORDER BY cree_le DESC
    LIMIT p_limit OFFSET p_offset
  ) a;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset,
    'alertes', v_alertes
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_alertes_pointage(text, text, int, int) TO authenticated;

-- 3. RPC : traiter une alerte (décision admin)
CREATE OR REPLACE FUNCTION public.fn_admin_traiter_alerte_pointage(
  p_alerte_id uuid,
  p_decision text,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_alerte RECORD;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  IF p_decision NOT IN ('LEGITIME', 'FRAUDE_AVERTISSEMENT', 'FRAUDE_SUSPENSION_PROPOSEE', 'IGNORER') THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'DECISION_INVALIDE');
  END IF;

  SELECT * INTO v_alerte FROM public.alertes_systeme WHERE id = p_alerte_id;
  IF v_alerte IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'ALERTE_INTROUVABLE');
  END IF;

  UPDATE public.alertes_systeme
  SET resolu_le = now(),
      details = COALESCE(details, '{}'::jsonb) || jsonb_build_object(
        'decision_admin', p_decision,
        'motif_admin', p_motif,
        'traite_par', v_uid,
        'traite_le', now()
      )
  WHERE id = p_alerte_id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'alerte_systeme', p_alerte_id,
    jsonb_build_object(
      'evenement', 'ALERTE_POINTAGE_TRAITEE',
      'decision', p_decision,
      'motif', p_motif,
      'type_alerte', v_alerte.type_alerte
    )
  );

  RETURN jsonb_build_object('success', true, 'decision', p_decision);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_traiter_alerte_pointage(uuid, text, text) TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT57_PR9_ADMIN_ALERTES_POINTAGE_INSTALLED',
    'pr', 'PR 9 Sprint 5.7',
    'rpcs', jsonb_build_array(
      'fn_admin_resume_alertes_pointage',
      'fn_admin_lister_alertes_pointage',
      'fn_admin_traiter_alerte_pointage'
    )
  )
);
