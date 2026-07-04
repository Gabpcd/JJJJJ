-- ============================================================
-- CP-C-5 D.1 — RPCs admin Chorus Pro
-- ============================================================
-- A. fn_admin_chorus_stats() : KPIs dashboard admin
-- B. fn_admin_chorus_submission_reset(p_facture_honoraire_id) :
--    reset idempotence pour permettre resubmit via frontend
-- ============================================================

-- A. Stats dashboard admin
CREATE OR REPLACE FUNCTION public.fn_admin_chorus_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_par_statut JSONB;
BEGIN
  IF NOT est_admin() THEN RETURN '{"error":"Acces refuse"}'::JSONB; END IF;

  SELECT jsonb_object_agg(status, nb)
  INTO v_par_statut
  FROM (
    SELECT status, COUNT(*) AS nb FROM public.chorus_submissions GROUP BY status
  ) t;

  RETURN jsonb_build_object(
    'total_submissions', (SELECT COUNT(*) FROM public.chorus_submissions),
    'par_statut', COALESCE(v_par_statut, '{}'::JSONB),
    'erreurs_7j', (SELECT COUNT(*) FROM public.chorus_submissions WHERE status='error' AND created_at > NOW() - INTERVAL '7 days'),
    'derniere_sync', (SELECT MAX(last_checked_at) FROM public.chorus_submissions),
    'etabs_configures_actifs', (SELECT COUNT(*) FROM public.chorus_pro_config WHERE actif=TRUE),
    'etabs_secteur_public_total', (SELECT COUNT(*) FROM public.etablissements WHERE est_secteur_public=TRUE AND supprime_le IS NULL)
  );
END;
$function$;

-- B. Reset idempotence pour permettre resubmit
-- Appelée par l'admin avant de re-invoquer submit-to-chorus côté frontend.
CREATE OR REPLACE FUNCTION public.fn_admin_chorus_submission_reset(p_facture_honoraire_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_existing_sub_id UUID;
BEGIN
  IF NOT est_admin() THEN RETURN '{"error":"Acces refuse"}'::JSONB; END IF;

  SELECT chorus_submission_id INTO v_existing_sub_id
  FROM public.factures_honoraires WHERE id = p_facture_honoraire_id;

  IF v_existing_sub_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Facture sans chorus_submission_id — rien à reset');
  END IF;

  -- Marquer ancienne submission comme erreur (garde l'historique, permet nouveau submit)
  UPDATE public.chorus_submissions
  SET status = 'error',
      error_message = COALESCE(error_message || ' | ', '') || 'Resubmit admin initie le ' || NOW()::TEXT
  WHERE id = v_existing_sub_id
  AND status NOT IN ('error', 'rejected');

  -- Reset factures_honoraires pour bypasser idempotence dans submit-to-chorus
  UPDATE public.factures_honoraires
  SET chorus_submission_id = NULL,
      chorus_submission_status = NULL
  WHERE id = p_facture_honoraire_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'ancienne_submission_id', v_existing_sub_id,
    'message', 'Facture reset — admin peut maintenant invoquer submit-to-chorus'
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_admin_chorus_stats() IS 'CP-C-5 D.1 KPIs admin dashboard Chorus Pro';
COMMENT ON FUNCTION public.fn_admin_chorus_submission_reset(UUID) IS 'CP-C-5 D.1 reset idempotence pour permettre resubmit d une facture Chorus Pro';
