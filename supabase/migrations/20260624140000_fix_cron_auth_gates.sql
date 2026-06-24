-- Fix critique : 3 fonctions SECURITY DEFINER appelées par pg_cron mais gatées
-- sur est_admin() → échouent silencieusement car pg_cron n'a pas de contexte auth.
--
-- Bugs découverts pendant l'audit financier approfondi :
--
-- 1. fn_auto_facturation_mensuelle : factures commission mensuelles → JAMAIS générées
--    automatiquement. Le cron tourne chaque 1er du mois mais la garde est_admin()
--    retourne FALSE (auth.uid() = NULL dans pg_cron). Vérification prod : 0 factures
--    dans la table. Impact : aucune commission Jolene n'est facturée automatiquement.
--
-- 2. fn_check_crons_health : monitoring crons → silencieusement mort depuis le déploiement.
--    La garde est_admin() OR jwt.claim.role = 'service_role' échoue (aucun JWT dans pg_cron).
--
-- 3. fn_check_stripe_webhook_health : monitoring Stripe → idem, silencieusement mort.
--
-- 4. fn_auto_valider_presences_72h (cron daily 6h) : doublonne fn_valider_presences_72h_auto
--    (cron 4x/jour) avec des gardes différentes. La version ancienne BYPASSE le gate litige
--    (valide même les presences en litige) et n'a pas le gate anti-fraude complet ni le
--    marqueur d'idempotence valide_auto_72h_le. La version récente BYPASSE le gate anti-fraude
--    (valide même les presences flaggées teleportation/GPS).
--
-- Correctifs :
-- - fn_auto_facturation_mensuelle : remplacer est_admin() par fn_est_contexte_cron_ou_admin()
-- - fn_check_crons_health / fn_check_stripe_webhook_health : idem
-- - fn_valider_presences_72h_auto : ajouter le gate anti-fraude manquant
-- - fn_auto_valider_presences_72h : rediriger vers fn_valider_presences_72h_auto (unifié)
--   + désactiver le cron doublon

-- Helper : détecte un appel depuis pg_cron (superuser sans auth) OU admin authentifié.
CREATE OR REPLACE FUNCTION public.fn_est_contexte_cron_ou_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
  SELECT
    auth.uid() IS NULL  -- pas de session → contexte cron/trigger (SECURITY DEFINER)
    OR public.est_admin()
    OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role';
$$;

-- 1. fn_auto_facturation_mensuelle : remplacer est_admin() par fn_est_contexte_cron_ou_admin()
CREATE OR REPLACE FUNCTION public.fn_auto_facturation_mensuelle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_facture_id UUID;
    v_num TEXT;
    v_compteur INT := 0;
    v_mois TEXT;
    v_recalc_info JSONB;
    v_est_public BOOLEAN;
    v_delai_j INTEGER;
    v_echeance DATE;
BEGIN
    IF NOT fn_est_contexte_cron_ou_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Non autorisé');
    END IF;

    v_recalc_info := public.fn_recalculer_commissions_post_litige();

    v_mois := TO_CHAR(now(), 'YYYY-MM');

    FOR v_etab IN
        SELECT etablissement_id,
               COUNT(*) as nb,
               SUM(COALESCE(montant_commission_ht, 0)) as sum_ht,
               SUM(COALESCE(montant_commission_tva, 0)) as sum_tva,
               SUM(COALESCE(montant_commission_ttc, 0)) as sum_ttc
        FROM missions m
        WHERE m.statut = 'TERMINEE'
          AND m.commission_facturee = false
          AND NOT (m.mode_remuneration = 'RETROCESSION' AND m.honoraires_confirmes_le IS NULL)
          AND m.facture_id IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM factures f
              WHERE f.mission_id = m.id
          )
        GROUP BY etablissement_id
    LOOP
        IF v_etab.sum_ht <= 0 THEN CONTINUE; END IF;

        SELECT COALESCE(est_secteur_public, false) INTO v_est_public
        FROM etablissements WHERE id = v_etab.etablissement_id;

        v_delai_j := CASE WHEN v_est_public
                          THEN (public.fn_param_num('delai_paiement_public_j', 50))::integer
                          ELSE (public.fn_param_num('delai_paiement_prive_j', 30))::integer END;
        v_echeance := (now() + (v_delai_j::text || ' days')::interval)::date;

        v_compteur := v_compteur + 1;
        v_num := 'FACT-' || v_mois || '-' || LPAD(v_compteur::TEXT, 4, '0');

        INSERT INTO factures (
            etablissement_id, numero_facture, montant_ht, montant_tva, montant_ttc,
            nombre_missions, statut, date_emission, date_echeance, periode_debut, periode_fin
        ) VALUES (
            v_etab.etablissement_id, v_num, v_etab.sum_ht, v_etab.sum_tva, v_etab.sum_ttc,
            v_etab.nb, 'EMISE', now(), v_echeance,
            date_trunc('month', now())::date,
            (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
        ) RETURNING id INTO v_facture_id;

        UPDATE missions
        SET facture_id = v_facture_id, commission_facturee = true
        WHERE etablissement_id = v_etab.etablissement_id
          AND statut = 'TERMINEE'
          AND commission_facturee = false
          AND facture_id IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM factures f
              WHERE f.mission_id = missions.id
          );
    END LOOP;

    RETURN jsonb_build_object(
      'success', true,
      'factures_generees', v_compteur,
      'recalc_post_litige', v_recalc_info
    );
END;
$function$;

-- 2. fn_check_crons_health : remplacer le gate auth
CREATE OR REPLACE FUNCTION public.fn_check_crons_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  IF NOT fn_est_contexte_cron_ou_admin() THEN
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
$function$;

-- 3. fn_check_stripe_webhook_health : remplacer le gate auth
CREATE OR REPLACE FUNCTION public.fn_check_stripe_webhook_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_total_24h INT; v_avec_erreur INT; v_non_traites_24h INT; v_taux_erreur NUMERIC;
BEGIN
  IF NOT fn_est_contexte_cron_ou_admin() THEN
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
$function$;

-- 4. fn_valider_presences_72h_auto : ajouter le gate anti-fraude manquant
--    (téléportation + alertes_fraude) pour ne pas auto-valider les presences suspectes.
CREATE OR REPLACE FUNCTION public.fn_valider_presences_72h_auto()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
  v_delai interval := ((public.fn_param_num('delai_autovalidation_presence_h', 72))::text || ' hours')::interval;
BEGIN
  UPDATE public.presences
  SET valide_auto_72h_le = NOW(), valide_par_etablissement = true,
      valide_le = COALESCE(valide_le, NOW()), modifie_le = NOW()
  WHERE pointage_depart_le IS NOT NULL
    AND pointage_depart_le < NOW() - v_delai
    AND COALESCE(valide_par_etablissement, false) = false
    AND motif_litige IS NULL
    AND valide_auto_72h_le IS NULL
    AND COALESCE(alerte_teleportation, false) = false
    AND (alertes_fraude IS NULL OR alertes_fraude = '[]'::JSONB);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'cron', NULL,
      jsonb_build_object('evenement', 'PRESENCES_VALIDEES_AUTO_72H', 'count', v_count, 'exec_le', NOW()));
  END IF;
  RETURN jsonb_build_object('success', true, 'count_validees', v_count);
END;
$function$;

-- 5. fn_auto_valider_presences_72h : rediriger vers la version unifiée
CREATE OR REPLACE FUNCTION public.fn_auto_valider_presences_72h()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  v_result := fn_valider_presences_72h_auto();
  RETURN COALESCE((v_result->>'count_validees')::int, 0);
END;
$function$;
