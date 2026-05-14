/**
 * `useConversationRealtime` — Sprint 10-B PR 5
 *
 * Hook unifié pour les indicateurs temps réel d'une conversation :
 *  - typing (interlocuteur est-il en train d'écrire ?)
 *  - presence (interlocuteur ONLINE / AWAY / OFFLINE ?)
 *
 * S'abonne aux tables `typing_status` et `presence_status` (Sprint 10-A v3
 * PR 3) via `postgres_changes` filtrées. Émet aussi un heartbeat presence
 * toutes les 30s pour l'utilisateur courant.
 *
 * Usage :
 *   const { typing, presence, lastSeen } = useConversationRealtime({
 *     conversationId,
 *     autreUserId,
 *   });
 *
 *   {typing && <p className="italic">est en train d'écrire…</p>}
 *   <PresenceDot status={presence} />
 *   {presence !== 'ONLINE' && lastSeen && <span>Vu {format(lastSeen)}</span>}
 *
 * Le hook n'envoie PAS de typing pour le user courant — c'est `InputMessage`
 * qui le fait via `fn_typing_start/stop` au focus/blur du textarea.
 */
import { useEffect, useState, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { logger } from '@/lib/logger';

export type PresenceStatus = 'ONLINE' | 'AWAY' | 'OFFLINE';

interface Params {
  conversationId: string | null;
  autreUserId: string | null;
}

interface Result {
  typing: boolean;
  presence: PresenceStatus;
  lastSeen: Date | null;
}

const HEARTBEAT_INTERVAL_MS = 30_000;
const TYPING_STALE_MS = 6_000;

export function useConversationRealtime({ conversationId, autreUserId }: Params): Result {
  const [typing, setTyping] = useState(false);
  const [presence, setPresence] = useState<PresenceStatus>('OFFLINE');
  const [lastSeen, setLastSeen] = useState<Date | null>(null);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!autreUserId) return;
    let cancelled = false;

    const charger = async () => {
      const { data, error } = await supabase
        .from('presence_status' as any)
        .select('status, last_seen_at')
        .eq('user_id', autreUserId)
        .maybeSingle();
      if (cancelled) return;
      if (error) {
        logger.debug('useConversationRealtime.presence initial load skip', error);
        return;
      }
      if (data) {
        setPresence(((data as any).status as PresenceStatus) || 'OFFLINE');
        setLastSeen((data as any).last_seen_at ? new Date((data as any).last_seen_at) : null);
      }
    };
    charger();

    const channel = supabase
      .channel(`presence-${autreUserId}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'presence_status',
        filter: `user_id=eq.${autreUserId}`,
      }, (payload) => {
        const row = payload.new as { status?: PresenceStatus; last_seen_at?: string };
        if (row?.status) setPresence(row.status);
        if (row?.last_seen_at) setLastSeen(new Date(row.last_seen_at));
      })
      .subscribe();

    return () => { cancelled = true; supabase.removeChannel(channel); };
  }, [autreUserId]);

  useEffect(() => {
    if (!conversationId || !autreUserId) return;

    const channel = supabase
      .channel(`typing-${conversationId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'typing_status',
        filter: `conversation_id=eq.${conversationId}`,
      }, (payload) => {
        const row = payload.new as { user_id?: string };
        if (row?.user_id === autreUserId) {
          setTyping(true);
          if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
          typingTimerRef.current = setTimeout(() => setTyping(false), TYPING_STALE_MS);
        }
      })
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'typing_status',
        filter: `conversation_id=eq.${conversationId}`,
      }, (payload) => {
        const row = payload.new as { user_id?: string };
        if (row?.user_id === autreUserId) {
          setTyping(true);
          if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
          typingTimerRef.current = setTimeout(() => setTyping(false), TYPING_STALE_MS);
        }
      })
      .on('postgres_changes', {
        event: 'DELETE',
        schema: 'public',
        table: 'typing_status',
        filter: `conversation_id=eq.${conversationId}`,
      }, (payload) => {
        const row = payload.old as { user_id?: string };
        if (row?.user_id === autreUserId) {
          setTyping(false);
          if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
        }
      })
      .subscribe();

    return () => {
      if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
      supabase.removeChannel(channel);
    };
  }, [conversationId, autreUserId]);

  useEffect(() => {
    const beat = () => {
      supabase.rpc('fn_update_presence' as any).then(undefined, (err) => {
        logger.debug('useConversationRealtime heartbeat skip', err);
      });
    };
    beat();
    const id = setInterval(beat, HEARTBEAT_INTERVAL_MS);
    return () => clearInterval(id);
  }, []);

  return { typing, presence, lastSeen };
}
