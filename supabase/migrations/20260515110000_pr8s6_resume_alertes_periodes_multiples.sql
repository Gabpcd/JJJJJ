-- ============================================================================
-- Sprint 6 PR 8 — Résumé alertes pointage périodes multiples (P1-10)
-- ============================================================================
-- Étend fn_admin_resume_alertes_pointage avec compteurs 24h / 7j / 30j
-- pour widget dashboard admin (cf. Sprint 5.7 PR 9 + PR 10 bandeau).
-- ============================================================================

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
    -- Périodes : 24h / 7j / 30j pour chaque type d'alerte
    'teleportations_24h', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'TELEPORTATION_DETECTED' AND cree_le > NOW() - INTERVAL '24 hours'),
    'teleportations_7j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'TELEPORTATION_DETECTED' AND cree_le > NOW() - INTERVAL '7 days'),
    'teleportations_30j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'TELEPORTATION_DETECTED' AND cree_le > NOW() - INTERVAL '30 days'),

    'mock_gps_24h', (SELECT COUNT(*) FROM public.presences
        WHERE (arrivee_mock_detected = true OR depart_mock_detected = true)
          AND modifie_le > NOW() - INTERVAL '24 hours'),
    'mock_gps_7j', (SELECT COUNT(*) FROM public.presences
        WHERE (arrivee_mock_detected = true OR depart_mock_detected = true)
          AND modifie_le > NOW() - INTERVAL '7 days'),
    'mock_gps_30j', (SELECT COUNT(*) FROM public.presences
        WHERE (arrivee_mock_detected = true OR depart_mock_detected = true)
          AND modifie_le > NOW() - INTERVAL '30 days'),

    'coherence_24h', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'POINTAGE_INCOHERENT' AND cree_le > NOW() - INTERVAL '24 hours'),
    'coherence_7j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'POINTAGE_INCOHERENT' AND cree_le > NOW() - INTERVAL '7 days'),
    'coherence_30j', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE type_alerte = 'POINTAGE_INCOHERENT' AND cree_le > NOW() - INTERVAL '30 days'),

    'qr_gps_eloigne_24h', (SELECT COUNT(*) FROM public.journaux_audit
        WHERE action = 'POINTAGE' AND details->>'evenement' = 'QR_SCAN_GPS_ELOIGNE'
          AND cree_le > NOW() - INTERVAL '24 hours'),
    'qr_gps_eloigne_7j', (SELECT COUNT(*) FROM public.journaux_audit
        WHERE action = 'POINTAGE' AND details->>'evenement' = 'QR_SCAN_GPS_ELOIGNE'
          AND cree_le > NOW() - INTERVAL '7 days'),
    'qr_gps_eloigne_30j', (SELECT COUNT(*) FROM public.journaux_audit
        WHERE action = 'POINTAGE' AND details->>'evenement' = 'QR_SCAN_GPS_ELOIGNE'
          AND cree_le > NOW() - INTERVAL '30 days'),

    'total_ouvertes', (SELECT COUNT(*) FROM public.alertes_systeme
        WHERE resolu_le IS NULL
          AND type_alerte IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT'))
  ) INTO v_kpi;

  RETURN jsonb_build_object('success', true, 'kpis', v_kpi);
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_admin_resume_alertes_pointage() TO authenticated;

INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT6_PR8_RESUME_ALERTES_PERIODES_INSTALLED',
    'pr', 'PR 8 Sprint 6',
    'rpc', 'fn_admin_resume_alertes_pointage',
    'note', 'KPIs étendus 24h/7j/30j pour widget dashboard'
  )
);
