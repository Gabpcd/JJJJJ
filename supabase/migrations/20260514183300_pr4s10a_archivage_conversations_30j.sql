-- ╔═══════════════════════════════════════════════════════════════════════════
-- ║ Sprint 10-A v3 PR 4 — Archivage automatique conversations 30j post-mission
-- ╚══════════════════════════════════════════════════════════════════════════
--
-- Décision produit Gabrielle :
--   Conversation archivée 30 jours après fin de mission (statut TERMINEE ou
--   ANNULEE_*). Passe en lecture seule. Pas de hard delete (RGPD : conservation
--   pour litiges éventuels).
--
-- Mécanisme :
--   1. Colonne archived_at sur conversations (nullable)
--   2. RPC fn_archiver_conversations_anciennes appelée par pg_cron quotidien
--   3. RLS messages_chat : INSERT bloqué si conversation.archived_at IS NOT NULL
--
-- Note pg_cron : le scheduling est appliqué via MCP execute_sql post-merge
-- (pg_cron non idempotent dans DDL migrations). Commande à exécuter :
--   SELECT cron.schedule('archiver-conversations-30j', '0 3 * * *',
--     $cron$SELECT public.fn_archiver_conversations_anciennes();$cron$);

-- ─── 1. Colonne archived_at ─────────────────────────────────────────────────

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_conversations_archived_at
  ON public.conversations(archived_at)
  WHERE archived_at IS NOT NULL;

-- ─── 2. RPC fn_archiver_conversations_anciennes ─────────────────────────

CREATE OR REPLACE FUNCTION public.fn_archiver_conversations_anciennes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_archivees int;
BEGIN
  WITH upd AS (
    UPDATE conversations c
    SET archived_at = NOW()
    FROM missions m
    WHERE c.mission_id = m.id
      AND c.archived_at IS NULL
      AND m.statut IN ('TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT', 'EXPIREE')
      AND COALESCE(m.fin_le, m.cree_le) < NOW() - INTERVAL '30 days'
    RETURNING c.id
  )
  SELECT count(*) INTO v_archivees FROM upd;

  -- Audit si > 0 archivées
  IF v_archivees > 0 THEN
    INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'conversations', NULL,
            jsonb_build_object(
              'evenement', 'MESSAGERIE_ARCHIVAGE_AUTO',
              'nombre_archivees', v_archivees,
              'date_iso', NOW()::text
            ));
  END IF;

  RETURN jsonb_build_object(
    'archivees', v_archivees,
    'execute_le', NOW()
  );
END;
$body$;

GRANT EXECUTE ON FUNCTION public.fn_archiver_conversations_anciennes() TO service_role;

-- ─── 3. RLS messages_chat : bloquer INSERT si conversation archivée ──────

DROP POLICY IF EXISTS pol_msg_chat_insert ON public.messages_chat;
CREATE POLICY pol_msg_chat_insert ON public.messages_chat
  FOR INSERT TO authenticated
  WITH CHECK (
    auteur_id = auth.uid()
    AND NOT EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages_chat.conversation_id
        AND c.archived_at IS NOT NULL
    )
  );

COMMENT ON COLUMN public.conversations.archived_at IS
  'Sprint 10-A v3 PR 4 : timestamp archivage automatique 30j post-mission. NULL = active, NOT NULL = lecture seule.';

COMMENT ON FUNCTION public.fn_archiver_conversations_anciennes IS
  'Sprint 10-A v3 PR 4 : archive conversations dont mission terminée + 30j. Appelée par cron pg_cron quotidien 3h.';

-- Audit installation
INSERT INTO public.journaux_audit(acteur_id, type_acteur, action, type_ressource, id_ressource, details)
VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'migration', NULL,
        jsonb_build_object(
          'evenement', 'SPRINT_10A_PR4_INSTALLED',
          'colonne', 'conversations.archived_at',
          'rpc', 'fn_archiver_conversations_anciennes',
          'rls', 'pol_msg_chat_insert (bloque si archivée)',
          'cron_a_planifier', 'archiver-conversations-30j @ 0 3 * * *',
          'pr', 'Sprint 10-A v3 PR 4',
          'date_iso', NOW()::text
        ));

NOTIFY pgrst, 'reload schema';
