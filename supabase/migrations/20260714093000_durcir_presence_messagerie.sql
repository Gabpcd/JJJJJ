-- Rend les indicateurs de saisie et de présence réellement utilisables par
-- Realtime, sans réouvrir les mutations directes ni exposer la présence à
-- tous les comptes authentifiés.

ALTER TABLE public.typing_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.presence_status ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.typing_status, public.presence_status
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.typing_status, public.presence_status
  TO authenticated;

-- Les mutations passent exclusivement par les RPC bornées ci-dessous.
DROP POLICY IF EXISTS pol_typing_status_upsert ON public.typing_status;
DROP POLICY IF EXISTS pol_typing_status_delete ON public.typing_status;
DROP POLICY IF EXISTS pol_presence_status_insert ON public.presence_status;
DROP POLICY IF EXISTS pol_presence_status_update ON public.presence_status;

DROP POLICY IF EXISTS pol_typing_status_select ON public.typing_status;
CREATE POLICY pol_typing_status_select
  ON public.typing_status
  FOR SELECT
  TO authenticated
  USING (
    public.fn_conversation_accessible(conversation_id)
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = typing_status.conversation_id
        AND c.archived_at IS NULL
        AND (SELECT auth.uid()) IN (
          c.participant_1_id,
          c.participant_2_id
        )
    )
  );

DROP POLICY IF EXISTS pol_presence_status_select ON public.presence_status;
CREATE POLICY pol_presence_status_select
  ON public.presence_status
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE presence_status.user_id IN (
        c.participant_1_id,
        c.participant_2_id
      )
        AND (SELECT auth.uid()) IN (
          c.participant_1_id,
          c.participant_2_id
        )
        AND c.archived_at IS NULL
        AND public.fn_conversation_accessible(c.id)
    )
  );

CREATE OR REPLACE FUNCTION public.fn_typing_start(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'NON_AUTHENTIFIE' USING ERRCODE = '28000';
  END IF;

  IF public.fn_conversation_accessible(p_conversation_id) IS NOT TRUE
     OR NOT EXISTS (
       SELECT 1
       FROM public.conversations c
       WHERE c.id = p_conversation_id
         AND c.archived_at IS NULL
         AND v_uid IN (c.participant_1_id, c.participant_2_id)
     ) THEN
    RAISE EXCEPTION 'NON_AUTORISE' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.typing_status (
    conversation_id,
    user_id,
    started_at
  ) VALUES (
    p_conversation_id,
    v_uid,
    clock_timestamp()
  )
  ON CONFLICT (conversation_id, user_id) DO UPDATE
  SET started_at = excluded.started_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_typing_stop(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RETURN;
  END IF;

  DELETE FROM public.typing_status
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_update_presence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR public.fn_compte_auth_actif() IS NOT TRUE THEN
    RAISE EXCEPTION 'NON_AUTHENTIFIE' USING ERRCODE = '28000';
  END IF;

  INSERT INTO public.presence_status (
    user_id,
    last_seen_at,
    status,
    maj_le
  ) VALUES (
    v_uid,
    clock_timestamp(),
    'ONLINE',
    clock_timestamp()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET last_seen_at = excluded.last_seen_at,
      status = 'ONLINE',
      maj_le = excluded.maj_le;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_typing_start(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.fn_typing_stop(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.fn_update_presence()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_typing_start(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_typing_stop(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_update_presence()
  TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_messagerie_cleanup_periodique()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_typing_supprimes integer;
  v_away_marques integer;
  v_offline_marques integer;
BEGIN
  WITH suppressions AS (
    DELETE FROM public.typing_status
    WHERE started_at < clock_timestamp() - interval '5 seconds'
    RETURNING 1
  )
  SELECT count(*) INTO v_typing_supprimes FROM suppressions;

  WITH mises_a_jour AS (
    UPDATE public.presence_status
    SET status = 'AWAY',
        maj_le = clock_timestamp()
    WHERE status = 'ONLINE'
      AND last_seen_at < clock_timestamp() - interval '1 minute'
      AND last_seen_at >= clock_timestamp() - interval '15 minutes'
    RETURNING 1
  )
  SELECT count(*) INTO v_away_marques FROM mises_a_jour;

  WITH mises_a_jour AS (
    UPDATE public.presence_status
    SET status = 'OFFLINE',
        maj_le = clock_timestamp()
    WHERE status IN ('ONLINE', 'AWAY')
      AND last_seen_at < clock_timestamp() - interval '15 minutes'
    RETURNING 1
  )
  SELECT count(*) INTO v_offline_marques FROM mises_a_jour;

  RETURN jsonb_build_object(
    'typing_supprimes', v_typing_supprimes,
    'away_marques', v_away_marques,
    'offline_marques', v_offline_marques,
    'execute_le', clock_timestamp()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_messagerie_cleanup_periodique()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_messagerie_cleanup_periodique()
  TO service_role;

-- Le dump de schéma ne conserve pas l'appartenance aux publications. Cette
-- étape répare donc aussi une base fraîche, tout en restant exécutable dans le
-- Postgres minimal des tests qui ne crée pas supabase_realtime.
DO $publication$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication
    WHERE pubname = 'supabase_realtime'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'typing_status'
    ) THEN
      EXECUTE
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_status';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'presence_status'
    ) THEN
      EXECUTE
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.presence_status';
    END IF;
  ELSE
    RAISE NOTICE
      'Publication supabase_realtime absente de cet environnement';
  END IF;
END;
$publication$;

-- Sans ce cron, un heartbeat historique resterait ONLINE indéfiniment.
DO $cron$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron'
  ) THEN
    -- Le SQL dynamique évite toute résolution de cron.job à la préparation
    -- sur les bases de test où l'extension et son schéma sont absents.
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'cron' AND c.relname = 'job'
    ) THEN
      RAISE NOTICE 'Table cron.job absente malgré pg_cron';
    ELSIF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_extension
      WHERE extname = 'pg_cron'
    ) THEN
      NULL;
    ELSE
      EXECUTE $schedule$
        SELECT cron.schedule(
          'messagerie-cleanup',
          '* * * * *',
          'SELECT public.fn_messagerie_cleanup_periodique();'
        )
        WHERE NOT EXISTS (
          SELECT 1 FROM cron.job WHERE jobname = 'messagerie-cleanup'
        )
      $schedule$;
    END IF;
  END IF;
END;
$cron$;

COMMENT ON TABLE public.presence_status IS
  'Présence visible uniquement par le compte concerné et ses interlocuteurs encore autorisés; heartbeat client toutes les 30 secondes.';
COMMENT ON TABLE public.typing_status IS
  'Indicateur de saisie éphémère visible uniquement dans une conversation encore autorisée; TTL applicatif 6 s, nettoyage serveur 5 s.';

NOTIFY pgrst, 'reload schema';
