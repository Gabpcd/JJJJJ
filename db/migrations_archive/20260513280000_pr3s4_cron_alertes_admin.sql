-- PR 3 Sprint 4 — Cron alertes admin (réclamations PENDING > 14j)
--
-- Cron quotidien à 09:00 : si réclamations score en statut PENDING
-- depuis > 14 jours → email + push admin avec liste détaillée.
-- Évite l'oubli admin sur réclamations en attente trop longues.

-- 1. RPC qui compile la liste des réclamations en retard
CREATE OR REPLACE FUNCTION public.fn_alerte_reclamations_pending_old()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
  v_liste jsonb;
  v_admin_ids uuid[];
BEGIN
  -- Sélection : réclamations PENDING depuis > 14 jours
  SELECT COUNT(*),
         jsonb_agg(jsonb_build_object(
           'id', id,
           'evenement_type', evenement_type,
           'contesteur_id', contesteur_id,
           'motif_categorie', motif_categorie,
           'texte_libre', LEFT(texte_libre, 100),
           'cree_le', cree_le,
           'jours_attente', EXTRACT(EPOCH FROM (NOW() - cree_le)) / 86400
         ) ORDER BY cree_le ASC)
  INTO v_count, v_liste
  FROM public.reclamations_score
  WHERE statut = 'PENDING' AND cree_le < NOW() - INTERVAL '14 days';

  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', true, 'count', 0, 'message', 'Aucune réclamation > 14j');
  END IF;

  -- Récupérer les admins plateforme
  v_admin_ids := ARRAY(SELECT id FROM public.fn_list_admin_user_ids());

  -- Envoyer email + push à chaque admin via externalisation_actions
  IF array_length(v_admin_ids, 1) > 0 THEN
    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    SELECT 'EMAIL_NOTIF',
           jsonb_build_object(
             'destinataire_id', uid,
             'type', 'ALERTE_RECLAMATIONS_PENDING',
             'data', jsonb_build_object(
               'count', v_count,
               'liste', v_liste,
               'lien_admin', 'https://app.jolene.app/admin/reclamations-score'
             )
           ),
           'CRON_ALERTE_ADMIN',
           NULL
    FROM unnest(v_admin_ids) AS uid;

    INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
    SELECT 'PUSH_NOTIF',
           jsonb_build_object(
             'destinataire_id', uid,
             'type_evenement', 'ALERTE_ADMIN',
             'titre', '⚠️ ' || v_count || ' réclamation' || CASE WHEN v_count > 1 THEN 's' ELSE '' END || ' en attente > 14j',
             'corps', 'Examen requis. Lien direct dans la console admin.',
             'lien', '/admin/reclamations-score'
           ),
           'CRON_ALERTE_ADMIN',
           NULL
    FROM unnest(v_admin_ids) AS uid;
  END IF;

  -- Audit
  INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (
    '00000000-0000-0000-0000-000000000000', 'SYSTEME',
    'SYSTEM', 'cron', NULL,
    jsonb_build_object(
      'evenement', 'CRON_ALERTE_RECLAMATIONS_PENDING_OLD',
      'count', v_count,
      'admins_notifies', array_length(v_admin_ids, 1),
      'exec_le', NOW()
    )
  );

  RETURN jsonb_build_object('success', true, 'count', v_count, 'admins_notifies', array_length(v_admin_ids, 1));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_alerte_reclamations_pending_old() TO service_role;

-- 2. Cron quotidien à 09:00 UTC
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_alert_reclamations_pending')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_alert_reclamations_pending');

    PERFORM cron.schedule(
      'jolene_alert_reclamations_pending',
      '0 9 * * *',  -- quotidien à 09:00 UTC
      'SELECT public.fn_alerte_reclamations_pending_old()'
    );
  END IF;
END $body$;

-- 3. Audit installation
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT4_PR3_CRON_ALERTES_INSTALLED',
    'pr', 'PR 3 Sprint 4',
    'rpc', 'fn_alerte_reclamations_pending_old',
    'cron', 'jolene_alert_reclamations_pending (0 9 * * *)'
  )
);
