-- Monitoring iter5 — Tableau de bord santé production
-- 1) Table alertes_systeme : aggregateur d'alertes monitoring
-- 2) RPC fn_check_crons_health : check crons + détecte échecs/retards
-- 3) RPC fn_check_stripe_webhook_health : ratio erreurs stripe_webhook_events
-- 4) RPC fn_admin_health_check : vue globale santé pour page /admin/status
-- 5) RPC fn_emettre_alerte_monitoring : helper pour enregistrer alerte

CREATE TABLE IF NOT EXISTS public.alertes_systeme (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type_alerte TEXT NOT NULL,
  severite TEXT NOT NULL CHECK (severite IN ('INFO','WARNING','CRITICAL')),
  source TEXT NOT NULL,
  message TEXT NOT NULL,
  details JSONB DEFAULT '{}'::jsonb,
  resolu_le TIMESTAMPTZ,
  email_envoye_le TIMESTAMPTZ,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alertes_systeme_non_resolues
  ON public.alertes_systeme(severite, cree_le DESC) WHERE resolu_le IS NULL;
CREATE INDEX IF NOT EXISTS idx_alertes_systeme_type_recent
  ON public.alertes_systeme(type_alerte, source, cree_le DESC);

ALTER TABLE public.alertes_systeme ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_alertes_admin ON public.alertes_systeme;
CREATE POLICY pol_alertes_admin ON public.alertes_systeme FOR ALL
  USING (est_admin()) WITH CHECK (est_admin());

GRANT SELECT, INSERT, UPDATE ON public.alertes_systeme TO service_role;

CREATE OR REPLACE FUNCTION public.fn_emettre_alerte_monitoring(
  p_type TEXT, p_severite TEXT, p_source TEXT, p_message TEXT, p_details JSONB DEFAULT '{}'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_id UUID; v_existing UUID;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  SELECT id INTO v_existing FROM alertes_systeme
  WHERE type_alerte = p_type AND source = p_source AND resolu_le IS NULL
    AND cree_le > NOW() - INTERVAL '1 hour'
  LIMIT 1;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;

  INSERT INTO alertes_systeme (type_alerte, severite, source, message, details)
  VALUES (p_type, p_severite, p_source, p_message, p_details)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_emettre_alerte_monitoring(TEXT, TEXT, TEXT, TEXT, JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_check_crons_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_results jsonb := '[]'::jsonb;
  v_cron RECORD;
  v_dernier_run TIMESTAMPTZ;
  v_dernier_statut TEXT;
  v_dernier_msg TEXT;
  v_intervalle_attendu INTERVAL;
  v_retard BOOLEAN;
  v_alertes_emises INT := 0;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  FOR v_cron IN SELECT jobid, jobname, schedule FROM cron.job WHERE active = true LOOP
    SELECT end_time, status, return_message INTO v_dernier_run, v_dernier_statut, v_dernier_msg
    FROM cron.job_run_details WHERE jobid = v_cron.jobid ORDER BY end_time DESC LIMIT 1;

    v_intervalle_attendu := CASE
      WHEN v_cron.schedule LIKE '*/5%' THEN INTERVAL '15 minutes'
      WHEN v_cron.schedule LIKE '*/10%' THEN INTERVAL '30 minutes'
      WHEN v_cron.schedule LIKE '*/15%' THEN INTERVAL '45 minutes'
      WHEN v_cron.schedule LIKE '0 * * * *' THEN INTERVAL '90 minutes'
      WHEN v_cron.schedule LIKE '15 * * * *' THEN INTERVAL '90 minutes'
      WHEN v_cron.schedule LIKE '0 % * * *' THEN INTERVAL '26 hours'
      WHEN v_cron.schedule LIKE '0 % % * *' THEN INTERVAL '32 days'
      WHEN v_cron.schedule LIKE '0 % * * 0' THEN INTERVAL '8 days'
      ELSE INTERVAL '40 days'
    END;

    v_retard := v_dernier_run IS NULL OR v_dernier_run < NOW() - v_intervalle_attendu;

    IF v_dernier_statut = 'failed' THEN
      PERFORM fn_emettre_alerte_monitoring(
        'CRON_FAILED', 'CRITICAL', v_cron.jobname,
        format('Cron "%s" a échoué : %s', v_cron.jobname, COALESCE(SUBSTRING(v_dernier_msg, 1, 200), '?')),
        jsonb_build_object('jobid', v_cron.jobid, 'schedule', v_cron.schedule, 'dernier_run', v_dernier_run)
      );
      v_alertes_emises := v_alertes_emises + 1;
    ELSIF v_retard AND v_cron.jobname NOT IN ('calculer-bfa-annuel') THEN
      PERFORM fn_emettre_alerte_monitoring(
        'CRON_RETARD', 'WARNING', v_cron.jobname,
        format('Cron "%s" en retard (dernier run : %s)', v_cron.jobname, COALESCE(v_dernier_run::text, 'jamais')),
        jsonb_build_object('jobid', v_cron.jobid, 'schedule', v_cron.schedule, 'dernier_run', v_dernier_run)
      );
      v_alertes_emises := v_alertes_emises + 1;
    END IF;

    v_results := v_results || jsonb_build_object(
      'jobid', v_cron.jobid, 'jobname', v_cron.jobname, 'schedule', v_cron.schedule,
      'dernier_run', v_dernier_run, 'dernier_statut', v_dernier_statut,
      'retard', v_retard, 'echec', v_dernier_statut = 'failed'
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'crons', v_results, 'alertes_emises', v_alertes_emises);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_check_crons_health() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_check_stripe_webhook_health()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_total_24h INT; v_avec_erreur INT; v_non_traites_24h INT; v_taux_erreur NUMERIC;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT COUNT(*) INTO v_total_24h FROM stripe_webhook_events WHERE recu_le > NOW() - INTERVAL '24 hours';
  SELECT COUNT(*) INTO v_avec_erreur FROM stripe_webhook_events WHERE recu_le > NOW() - INTERVAL '24 hours' AND erreur IS NOT NULL;
  SELECT COUNT(*) INTO v_non_traites_24h FROM stripe_webhook_events
    WHERE recu_le > NOW() - INTERVAL '24 hours' AND traite_le IS NULL;

  v_taux_erreur := CASE WHEN v_total_24h > 0 THEN ROUND(v_avec_erreur * 100.0 / v_total_24h, 1) ELSE 0 END;

  IF v_total_24h > 0 AND v_taux_erreur > 5 THEN
    PERFORM fn_emettre_alerte_monitoring(
      'WEBHOOK_ERROR_RATE', 'WARNING', 'stripe-webhook',
      format('Taux erreur webhook Stripe %s%% sur 24h (%s/%s)', v_taux_erreur, v_avec_erreur, v_total_24h),
      jsonb_build_object('total', v_total_24h, 'avec_erreur', v_avec_erreur, 'non_traites', v_non_traites_24h)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'total_24h', v_total_24h, 'avec_erreur', v_avec_erreur, 'non_traites', v_non_traites_24h, 'taux_erreur_pct', v_taux_erreur);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_check_stripe_webhook_health() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_health_check()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
  v_crons_health jsonb;
  v_stripe_health jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès admin uniquement');
  END IF;

  SELECT public.fn_check_crons_health() INTO v_crons_health;
  SELECT public.fn_check_stripe_webhook_health() INTO v_stripe_health;

  v_result := jsonb_build_object(
    'timestamp', NOW(),
    'database', jsonb_build_object('connected', true, 'version', current_setting('server_version')),
    'crons', v_crons_health,
    'stripe_webhooks', v_stripe_health,
    'alertes_actives', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'type', type_alerte, 'severite', severite,
        'source', source, 'message', message, 'cree_le', cree_le
      ) ORDER BY cree_le DESC), '[]'::jsonb)
      FROM alertes_systeme WHERE resolu_le IS NULL
    ),
    'stats_temps_reel', jsonb_build_object(
      'soignants_actifs_7j', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL AND derniere_activite_le > NOW() - INTERVAL '7 days'),
      'missions_ouvertes', (SELECT COUNT(*) FROM missions WHERE statut = 'OUVERTE'),
      'missions_assignees', (SELECT COUNT(*) FROM missions WHERE statut = 'ASSIGNEE'),
      'missions_en_cours', (SELECT COUNT(*) FROM missions WHERE statut = 'EN_COURS'),
      'candidatures_pending', (SELECT COUNT(*) FROM candidatures WHERE statut = 'EN_ATTENTE'),
      'litiges_ouverts', (SELECT COUNT(*) FROM litiges WHERE statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS','REVUE_ADMIN'))
    ),
    'logs_recents', jsonb_build_object(
      'audit_24h', (SELECT COUNT(*) FROM journaux_audit WHERE cree_le > NOW() - INTERVAL '24 hours'),
      'emails_24h', (SELECT COUNT(*) FROM emails_envoyes WHERE cree_le > NOW() - INTERVAL '24 hours'),
      'sms_24h', (SELECT COUNT(*) FROM sms_envoyes WHERE cree_le > NOW() - INTERVAL '24 hours'),
      'notifications_24h', (SELECT COUNT(*) FROM notifications WHERE cree_le > NOW() - INTERVAL '24 hours')
    )
  );
  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_admin_health_check() TO authenticated;

-- Cron méta-monitoring : toutes les heures
SELECT cron.schedule(
  'monitoring-health-check-hourly',
  '30 * * * *',
  $cron$
    SELECT public.fn_check_crons_health();
    SELECT public.fn_check_stripe_webhook_health();
  $cron$
);

NOTIFY pgrst, 'reload schema';
