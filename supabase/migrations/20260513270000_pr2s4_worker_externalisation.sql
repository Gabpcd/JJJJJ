-- PR 2 Sprint 4 — Worker externalisation_actions + cron + retry
--
-- Étend la table externalisation_actions (créée Sprint 3.5 PR 2) avec :
--   - statut PENDING_AIFE (cas spécifique Chorus Pro en attente scope)
--   - next_retry_at pour backoff exponentiel
--   - cron_lock_at pour éviter les double-process
--   - cron_lock_par pour traçabilité worker
--
-- + RPC fn_externalisations_a_traiter : sélectionne + lock 50 rows pour
--   le worker edge function process-externalisation-actions
-- + cron pg_cron 5 min : appelle l'edge function

-- 1. Étendre statut + ajouter colonnes
ALTER TABLE public.externalisation_actions
  ADD COLUMN IF NOT EXISTS next_retry_at timestamptz,
  ADD COLUMN IF NOT EXISTS cron_lock_at timestamptz,
  ADD COLUMN IF NOT EXISTS cron_lock_par text;

-- Drop ancien CHECK + recréer avec PENDING_AIFE + ERROR (alias FAILED)
ALTER TABLE public.externalisation_actions
  DROP CONSTRAINT IF EXISTS externalisation_actions_statut_check;
ALTER TABLE public.externalisation_actions
  ADD CONSTRAINT externalisation_actions_statut_check
  CHECK (statut IN ('PENDING', 'PROCESSING', 'DONE', 'ERROR', 'PENDING_AIFE', 'CANCELLED'));

COMMENT ON COLUMN public.externalisation_actions.next_retry_at IS
  'Timestamp du prochain retry calculé avec backoff exponentiel '
  '(1 min, 5 min, 30 min selon nb tentatives). Pour PENDING_AIFE '
  'Chorus Pro : NOW() + 24h (re-check quotidien si scopes activés).';

COMMENT ON COLUMN public.externalisation_actions.cron_lock_at IS
  'Timestamp de prise de lock par le worker. Une action LOCKEE depuis '
  'plus de 10 min est considérée orpheline et peut être re-lock.';

-- 2. Index sur statut pour scan rapide (sans condition NOW() pour rester IMMUTABLE)
-- Note Sprint 4.5 PR 1 : NOW() retiré de la WHERE clause car non-IMMUTABLE
-- (erreur PG 42P17: functions in index predicate must be marked IMMUTABLE).
-- L'index couvre les statuts actifs ; le filtre cron_lock_at < NOW() - 10min
-- est appliqué dans la requête fn_externalisations_a_traiter.
CREATE INDEX IF NOT EXISTS idx_ext_actions_pending
  ON public.externalisation_actions(statut, cree_le ASC)
  WHERE statut IN ('PENDING', 'PENDING_AIFE', 'PROCESSING');

-- 3. RPC pour sélectionner + lock un batch (utilisée par le worker)
CREATE OR REPLACE FUNCTION public.fn_externalisations_a_traiter(p_limit int DEFAULT 50, p_worker_id text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actions jsonb;
  v_count int;
  v_worker text := COALESCE(p_worker_id, 'worker_' || substring(md5(random()::text), 1, 8));
BEGIN
  -- Sélectionne + lock atomiquement via UPDATE ... RETURNING
  WITH selectionnees AS (
    SELECT id FROM public.externalisation_actions
    WHERE (
      -- Actions PENDING jamais traitées
      (statut = 'PENDING' AND (next_retry_at IS NULL OR next_retry_at < NOW()))
      OR
      -- Actions PENDING_AIFE prêtes au re-check
      (statut = 'PENDING_AIFE' AND next_retry_at IS NOT NULL AND next_retry_at < NOW())
      OR
      -- Actions PROCESSING orphelines depuis > 10 min
      (statut = 'PROCESSING' AND cron_lock_at < NOW() - INTERVAL '10 minutes')
    )
    ORDER BY cree_le ASC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.externalisation_actions a
  SET statut = 'PROCESSING',
      cron_lock_at = NOW(),
      cron_lock_par = v_worker
  FROM selectionnees s
  WHERE a.id = s.id
  RETURNING a.id, a.type_action, a.payload, a.source, a.source_id, a.tentatives;

  SELECT jsonb_agg(jsonb_build_object(
    'id', id, 'type_action', type_action, 'payload', payload,
    'source', source, 'source_id', source_id, 'tentatives', tentatives
  )), COUNT(*)
  INTO v_actions, v_count
  FROM public.externalisation_actions
  WHERE cron_lock_par = v_worker AND statut = 'PROCESSING'
    AND cron_lock_at > NOW() - INTERVAL '5 seconds';

  RETURN jsonb_build_object(
    'success', true,
    'worker_id', v_worker,
    'count', COALESCE(v_count, 0),
    'actions', COALESCE(v_actions, '[]'::jsonb)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_externalisations_a_traiter(int, text) TO service_role;

-- 4. RPC marquer succès
CREATE OR REPLACE FUNCTION public.fn_externalisation_succes(p_id uuid, p_resultat jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.externalisation_actions SET
    statut = 'DONE',
    traite_le = NOW(),
    resultat = COALESCE(p_resultat, '{}'::jsonb),
    derniere_erreur = NULL,
    cron_lock_at = NULL,
    cron_lock_par = NULL
  WHERE id = p_id;
  RETURN jsonb_build_object('success', true);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_externalisation_succes(uuid, jsonb) TO service_role;

-- 5. RPC marquer échec + recalculer backoff
CREATE OR REPLACE FUNCTION public.fn_externalisation_echec(
  p_id uuid,
  p_erreur text,
  p_special_statut text DEFAULT NULL  -- 'PENDING_AIFE' pour Chorus
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_action RECORD;
  v_new_tentatives int;
  v_new_statut text;
  v_next_retry timestamptz;
BEGIN
  SELECT tentatives, type_action INTO v_action FROM public.externalisation_actions WHERE id = p_id;

  -- Cas spécial : Chorus Pro en attente scope AIFE → re-check 24h
  IF p_special_statut = 'PENDING_AIFE' THEN
    v_new_statut := 'PENDING_AIFE';
    v_next_retry := NOW() + INTERVAL '24 hours';
    v_new_tentatives := v_action.tentatives; -- ne pas incrémenter
  ELSE
    v_new_tentatives := COALESCE(v_action.tentatives, 0) + 1;
    -- Backoff exponentiel : 1 min, 5 min, 30 min, puis FAILED
    IF v_new_tentatives >= 3 THEN
      v_new_statut := 'ERROR';
      v_next_retry := NULL;
    ELSIF v_new_tentatives = 1 THEN
      v_new_statut := 'PENDING';
      v_next_retry := NOW() + INTERVAL '1 minute';
    ELSIF v_new_tentatives = 2 THEN
      v_new_statut := 'PENDING';
      v_next_retry := NOW() + INTERVAL '5 minutes';
    ELSE
      v_new_statut := 'PENDING';
      v_next_retry := NOW() + INTERVAL '30 minutes';
    END IF;
  END IF;

  UPDATE public.externalisation_actions SET
    statut = v_new_statut,
    tentatives = v_new_tentatives,
    derniere_tentative_le = NOW(),
    derniere_erreur = LEFT(p_erreur, 1000),
    next_retry_at = v_next_retry,
    cron_lock_at = NULL,
    cron_lock_par = NULL,
    traite_le = CASE WHEN v_new_statut = 'ERROR' THEN NOW() ELSE traite_le END
  WHERE id = p_id;

  -- Si FAILED, notif admin
  IF v_new_statut = 'ERROR' THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (
      '00000000-0000-0000-0000-000000000000', 'SYSTEME',
      'SYSTEM', 'externalisation_action', p_id,
      jsonb_build_object('evenement', 'EXTERNALISATION_ECHEC_DEFINITIF',
                          'type_action', v_action.type_action,
                          'tentatives', v_new_tentatives,
                          'derniere_erreur', LEFT(p_erreur, 200))
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'statut', v_new_statut, 'tentatives', v_new_tentatives);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_externalisation_echec(uuid, text, text) TO service_role;

-- 6. RPC admin : relancer une action FAILED ou annuler PENDING
CREATE OR REPLACE FUNCTION public.fn_admin_externalisation_retry(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;
  UPDATE public.externalisation_actions SET
    statut = 'PENDING',
    tentatives = 0,
    next_retry_at = NOW(),
    cron_lock_at = NULL,
    cron_lock_par = NULL
  WHERE id = p_id AND statut IN ('ERROR', 'PENDING_AIFE');
  RETURN jsonb_build_object('success', true);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_admin_externalisation_retry(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_externalisation_cancel(p_id uuid, p_motif text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;
  UPDATE public.externalisation_actions SET
    statut = 'CANCELLED',
    traite_le = NOW(),
    derniere_erreur = 'Annulée par admin : ' || COALESCE(p_motif, '')
  WHERE id = p_id AND statut IN ('PENDING', 'PENDING_AIFE', 'ERROR');
  RETURN jsonb_build_object('success', true);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_admin_externalisation_cancel(uuid, text) TO authenticated;

-- 7. RPC admin : lister actions avec filtres
CREATE OR REPLACE FUNCTION public.fn_admin_lister_externalisations(
  p_statut text DEFAULT NULL,
  p_type_action text DEFAULT NULL,
  p_limit int DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'type_action', type_action, 'statut', statut,
    'source', source, 'source_id', source_id,
    'tentatives', tentatives, 'derniere_erreur', derniere_erreur,
    'next_retry_at', next_retry_at,
    'cree_le', cree_le, 'traite_le', traite_le,
    'payload', payload, 'resultat', resultat
  ) ORDER BY cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT * FROM public.externalisation_actions
    WHERE (p_statut IS NULL OR statut = p_statut)
      AND (p_type_action IS NULL OR type_action = p_type_action)
    ORDER BY cree_le DESC
    LIMIT p_limit
  ) t;
  RETURN jsonb_build_object('success', true, 'actions', v_result);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.fn_admin_lister_externalisations(text, text, int) TO authenticated;

-- 8. Schedule pg_cron toutes les 5 min — appel HTTP edge function worker
DO $body$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('jolene_process_externalisations')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jolene_process_externalisations');

    PERFORM cron.schedule(
      'jolene_process_externalisations',
      '*/5 * * * *',  -- toutes les 5 min
      'SELECT net.http_post(
        url := ''https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/process-externalisation-actions'',
        headers := jsonb_build_object(
          ''Content-Type'', ''application/json'',
          ''Authorization'', ''Bearer '' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = ''service_role_key'' LIMIT 1)
        ),
        body := ''{}''::jsonb
      )'
    );
  END IF;
END $body$;

-- 9. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'SPRINT4_PR2_WORKER_EXTERNALISATION_INSTALLED',
    'pr', 'PR 2 Sprint 4',
    'rpcs', ARRAY['fn_externalisations_a_traiter', 'fn_externalisation_succes',
                   'fn_externalisation_echec', 'fn_admin_externalisation_retry',
                   'fn_admin_externalisation_cancel', 'fn_admin_lister_externalisations'],
    'cron', 'jolene_process_externalisations (*/5 min)',
    'note', 'Edge function process-externalisation-actions à déployer en parallèle'
  )
);
