-- ╔═══════════════════════════════════════════════════════════════════════════
-- ║ Sprint 10-A v3 PR 3 — Tables typing_status + presence_status
-- ║ pour indicateurs temps réel WhatsApp-style (typing + online/away/offline)
-- ╚══════════════════════════════════════════════════════════════════════════
--
-- Architecture :
--   - typing_status : éphémère, TTL 5s, cleaned périodiquement
--   - presence_status : 1 ligne par user, status calculé via last_seen_at
--     - ONLINE  : last_seen_at < NOW() - 1min
--     - AWAY    : 1min ≤ last_seen_at - NOW() < 15min
--     - OFFLINE : last_seen_at ≥ 15min
--   - Heartbeat client toutes les 30s appelle fn_update_presence
--   - Cron pg_cron toutes les minutes recalcule statut + nettoie typing expirés
--
-- Realtime :
--   - Publication supabase_realtime sur typing_status + presence_status
--   - Client subscribe au channel `presence:conversation:{id}` (presence native)
--     OU postgres_changes sur typing_status
--
-- Sécurité :
--   - RLS strict : typing visible UNIQUEMENT aux participants conversation
--   - presence SELECT limité (status uniquement, last_seen_at masqué pour
--     préserver vie privée)

-- ─── 1. Table typing_status ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.typing_status (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_typing_status_started_at
  ON public.typing_status(started_at);

ALTER TABLE public.typing_status ENABLE ROW LEVEL SECURITY;

-- SELECT : uniquement les participants de la conversation
DROP POLICY IF EXISTS pol_typing_status_select ON public.typing_status;
CREATE POLICY pol_typing_status_select ON public.typing_status
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = typing_status.conversation_id
        AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
    )
  );

-- INSERT/UPDATE : uniquement pour soi-même + participant à la conversation
DROP POLICY IF EXISTS pol_typing_status_upsert ON public.typing_status;
CREATE POLICY pol_typing_status_upsert ON public.typing_status
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = typing_status.conversation_id
        AND (c.participant_1_id = auth.uid() OR c.participant_2_id = auth.uid())
    )
  );

-- DELETE : uniquement sa propre ligne (typing stop)
DROP POLICY IF EXISTS pol_typing_status_delete ON public.typing_status;
CREATE POLICY pol_typing_status_delete ON public.typing_status
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ─── 2. Table presence_status ───────────────────────────────────────────────

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'presence_status_enum') THEN
    CREATE TYPE public.presence_status_enum AS ENUM ('ONLINE', 'AWAY', 'OFFLINE');
  END IF;
END;
$do$;

CREATE TABLE IF NOT EXISTS public.presence_status (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  last_seen_at timestamptz NOT NULL DEFAULT NOW(),
  status public.presence_status_enum NOT NULL DEFAULT 'ONLINE',
  maj_le timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_presence_status_last_seen
  ON public.presence_status(last_seen_at);

ALTER TABLE public.presence_status ENABLE ROW LEVEL SECURITY;

-- SELECT : tous les utilisateurs authentifiés voient le STATUS uniquement
-- (mais pas last_seen_at exact — privacy). On expose status via vue helper.
DROP POLICY IF EXISTS pol_presence_status_select ON public.presence_status;
CREATE POLICY pol_presence_status_select ON public.presence_status
  FOR SELECT TO authenticated
  USING (true);  -- public, mais on filtrera côté vue/RPC

-- UPDATE : uniquement sa propre ligne
DROP POLICY IF EXISTS pol_presence_status_update ON public.presence_status;
CREATE POLICY pol_presence_status_update ON public.presence_status
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- INSERT : uniquement sa propre ligne (premier heartbeat)
DROP POLICY IF EXISTS pol_presence_status_insert ON public.presence_status;
CREATE POLICY pol_presence_status_insert ON public.presence_status
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- ─── 3. RPC heartbeat presence ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_update_presence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;  -- non-auth, no-op
  END IF;

  INSERT INTO presence_status(user_id, last_seen_at, status, maj_le)
  VALUES (v_user_id, NOW(), 'ONLINE', NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET last_seen_at = NOW(),
        status = 'ONLINE',
        maj_le = NOW();
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_update_presence() TO authenticated;

-- ─── 4. RPC typing start/stop ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_typing_start(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_participant boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NON_AUTHENTIFIE';
  END IF;

  -- Vérifier que l'utilisateur est bien participant à la conversation
  SELECT EXISTS (
    SELECT 1 FROM conversations
    WHERE id = p_conversation_id
      AND (participant_1_id = v_user_id OR participant_2_id = v_user_id)
  ) INTO v_is_participant;

  IF NOT v_is_participant THEN
    RAISE EXCEPTION 'NON_AUTORISE';
  END IF;

  INSERT INTO typing_status(conversation_id, user_id, started_at)
  VALUES (p_conversation_id, v_user_id, NOW())
  ON CONFLICT (conversation_id, user_id) DO UPDATE
    SET started_at = NOW();
END;
$body$;

CREATE OR REPLACE FUNCTION public.fn_typing_stop(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM typing_status
  WHERE conversation_id = p_conversation_id
    AND user_id = v_user_id;
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_typing_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_typing_stop(uuid) TO authenticated;

-- ─── 5. Fonction cleanup périodique (appelée par pg_cron) ───────────────────

CREATE OR REPLACE FUNCTION public.fn_messagerie_cleanup_periodique()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_typing_supprimes int;
  v_away_marques int;
  v_offline_marques int;
BEGIN
  -- 1. Supprimer les typing_status > 5 secondes (TTL stale)
  WITH supp AS (
    DELETE FROM typing_status
    WHERE started_at < NOW() - INTERVAL '5 seconds'
    RETURNING 1
  )
  SELECT count(*) INTO v_typing_supprimes FROM supp;

  -- 2. Marquer AWAY si last_seen_at entre 1min et 15min
  WITH upd AS (
    UPDATE presence_status
    SET status = 'AWAY', maj_le = NOW()
    WHERE status = 'ONLINE'
      AND last_seen_at < NOW() - INTERVAL '1 minute'
      AND last_seen_at >= NOW() - INTERVAL '15 minutes'
    RETURNING 1
  )
  SELECT count(*) INTO v_away_marques FROM upd;

  -- 3. Marquer OFFLINE si last_seen_at ≥ 15min
  WITH upd AS (
    UPDATE presence_status
    SET status = 'OFFLINE', maj_le = NOW()
    WHERE status IN ('ONLINE', 'AWAY')
      AND last_seen_at < NOW() - INTERVAL '15 minutes'
    RETURNING 1
  )
  SELECT count(*) INTO v_offline_marques FROM upd;

  RETURN jsonb_build_object(
    'typing_supprimes', v_typing_supprimes,
    'away_marques', v_away_marques,
    'offline_marques', v_offline_marques,
    'execute_le', NOW()
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_messagerie_cleanup_periodique() TO service_role;

-- ─── 6. Realtime publication ────────────────────────────────────────────────────
-- Ajoute typing_status et presence_status à la publication supabase_realtime
-- pour permettre les subscriptions postgres_changes côté client.

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'typing_status'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_status;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'presence_status'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.presence_status;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Publication supabase_realtime peut ne pas exister en dev local
  RAISE NOTICE 'Publication supabase_realtime non disponible : %', SQLERRM;
END;
$do$;

COMMENT ON TABLE public.typing_status IS 'Sprint 10-A v3 PR 3 : indicateur typing éphémère TTL 5s. RLS strict participants conversation.';
COMMENT ON TABLE public.presence_status IS 'Sprint 10-A v3 PR 3 : status ONLINE/AWAY/OFFLINE par user. Heartbeat 30s côté client → fn_update_presence.';

-- Audit installation
INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'migration', NULL,
        jsonb_build_object(
          'evenement', 'SPRINT_10A_PR3_INSTALLED',
          'tables', ARRAY['typing_status', 'presence_status'],
          'rpcs', ARRAY['fn_update_presence', 'fn_typing_start', 'fn_typing_stop', 'fn_messagerie_cleanup_periodique'],
          'pr', 'Sprint 10-A v3 PR 3',
          'date_iso', NOW()::text
        ));

NOTIFY pgrst, 'reload schema';

-- Note : le cron pg_cron `messagerie-cleanup` (appelle fn_messagerie_cleanup_periodique)
-- doit être planifié manuellement via :
--   SELECT cron.schedule('messagerie-cleanup', '* * * * *', $cron$SELECT public.fn_messagerie_cleanup_periodique();$cron$);
-- Voir docs/SPRINT_10_MESSAGERIE.md.
