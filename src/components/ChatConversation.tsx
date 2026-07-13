/**
 * `<ChatConversation />` — Sprint 10-B PR 2 refonte Meta-grade Y2K
 *
 * Composant chat inline pour une mission donnée, inspiré WhatsApp/Messenger.
 *
 * Structure :
 *  - Header : avatar interlocuteur + nom + status text + indicateur typing
 *  - Zone messages avec bulles Y2K :
 *      * Soi (droite) : gradient rose-mauve, white text, rounded-br-md
 *      * Autre (gauche) : bg-cloud-white, midnight text, rounded-bl-md
 *      * Bulle système (centrée italic) : "Conversation ouverte" / archivée
 *      * Groupement temporel : "Aujourd'hui" / "Hier" / "12 mai" entre groupes
 *      * Read receipts : 1 check sent (gris) / 2 checks read (cyan)
 *  - InputMessage (PR 3) avec validation anti-leak + typing event
 *
 * Realtime via useConversationRealtime (PR 5) : presence + typing.
 */
import { useState, useEffect, useRef, useMemo } from 'react';
import { Check, CheckCheck, MessageCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { format, isToday, isYesterday, isSameDay } from 'date-fns';
import { fr } from 'date-fns/locale';
import { logger } from '@/lib/logger';
import { useConversationRealtime } from '@/hooks/useConversationRealtime';
import { InputMessage } from '@/components/messagerie/InputMessage';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { BloquerUtilisateur } from '@/components/BloquerUtilisateur';
import {
  chargerInterlocuteursConversations,
  cleInterlocuteur,
} from '@/lib/messagerieInterlocuteurs';

interface Message {
  id: string;
  conversation_id: string;
  auteur_id: string;
  contenu: string;
  est_admin: boolean;
  lu: boolean;
  cree_le: string;
}

interface AutreInfo {
  prenom: string;
  nom: string;
  avatar: string | null;
}

interface ChatConversationProps {
  missionId: string;
  autreUserId: string;
  isEtablissement?: boolean;
}

function formatGroupLabel(date: Date): string {
  if (isToday(date)) return "Aujourd'hui";
  if (isYesterday(date)) return 'Hier';
  return format(date, 'd MMMM', { locale: fr });
}

function presenceLabel(presence: 'ONLINE' | 'AWAY' | 'OFFLINE', lastSeen: Date | null): string {
  if (presence === 'ONLINE') return 'En ligne';
  if (presence === 'AWAY') return 'Absent';
  if (lastSeen) {
    if (isToday(lastSeen)) return `Vu à ${format(lastSeen, 'HH:mm')}`;
    if (isYesterday(lastSeen)) return `Vu hier`;
    return `Vu le ${format(lastSeen, 'd MMM', { locale: fr })}`;
  }
  return 'Hors ligne';
}

const PRESENCE_DOT_CLASS: Record<'ONLINE' | 'AWAY' | 'OFFLINE', string> = {
  ONLINE: 'bg-green-500',
  AWAY: 'bg-jolene-butter-500',
  OFFLINE: 'bg-muted-foreground/40',
};

export function ChatConversation({ missionId, autreUserId, isEtablissement }: ChatConversationProps) {
  const { user } = useAuth();
  const [convId, setConvId] = useState<string | null>(null);
  const [resolvedAutreId, setResolvedAutreId] = useState<string | null>(null);
  const [autreInfo, setAutreInfo] = useState<AutreInfo | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [archived, setArchived] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const { typing, presence, lastSeen } = useConversationRealtime({
    conversationId: convId,
    autreUserId: resolvedAutreId,
  });

  useEffect(() => {
    if (!user || !missionId || !autreUserId) return;
    let cancelled = false;

    const resolve = async () => {
      let resolvedUserId = autreUserId;

      if (isEtablissement) {
        const { data: uid, error: resolveErr } = await supabase.rpc('fn_user_id_pour_etablissement', { p_etablissement_id: autreUserId });
        if (resolveErr || !uid) {
          logger.error('ChatConversation: cannot resolve etablissement user ID', resolveErr);
          if (!cancelled) setLoading(false);
          return;
        }
        resolvedUserId = uid as string;
      }

      if (cancelled) return;
      setResolvedAutreId(resolvedUserId);

      const { data, error } = await supabase.rpc('fn_obtenir_conversation', {
        p_autre_id: resolvedUserId,
        p_mission_id: missionId,
      });

      if (error || !data) {
        logger.error('ChatConversation: fn_obtenir_conversation error', error);
        if (!cancelled) setLoading(false);
        return;
      }

      if (!cancelled) setConvId(data as string);
    };

    resolve();
    return () => { cancelled = true; };
  }, [user, missionId, autreUserId, isEtablissement]);

  useEffect(() => {
    if (!convId || !resolvedAutreId) return;
    let cancelled = false;
    setAutreInfo(null);

    (async () => {
      try {
        const interlocuteurs = await chargerInterlocuteursConversations([convId]);
        const info = interlocuteurs.get(cleInterlocuteur(convId, resolvedAutreId));
        if (cancelled) return;
        setAutreInfo(info
          ? { prenom: info.prenom, nom: info.nom, avatar: info.avatar_url }
          : { prenom: 'Jolene', nom: '', avatar: null });
      } catch (error) {
        logger.error('ChatConversation: fn_interlocuteurs_conversations error', error);
        if (!cancelled) setAutreInfo({ prenom: 'Jolene', nom: '', avatar: null });
      }
    })();

    return () => { cancelled = true; };
  }, [convId, resolvedAutreId]);

  useEffect(() => {
    if (!convId) return;

    const load = async () => {
      const { data: conv } = await supabase
        .from('conversations')
        .select('archived_at')
        .eq('id', convId)
        .maybeSingle();
      setArchived(!!conv?.archived_at);

      const { data } = await supabase
        .from('messages_chat')
        .select('id, conversation_id, auteur_id, contenu, est_admin, lu, cree_le')
        .eq('conversation_id', convId)
        .order('cree_le', { ascending: true })
        .limit(500);

      setMessages((data as Message[]) || []);
      setLoading(false);

      supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: convId }).then(({ error }) => {
        if (error) logger.error('ChatConversation: fn_marquer_messages_lus error', error);
      });
    };

    load();

    const channel = supabase
      .channel(`chat-conv-inline-${convId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages_chat',
        filter: `conversation_id=eq.${convId}`,
      }, (payload) => {
        const msg = payload.new as Message;
        setMessages(prev => prev.some(m => m.id === msg.id) ? prev : [...prev, msg]);
        if (msg.auteur_id !== user?.id) {
          supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: convId }).then(({ error }) => {
            if (error) logger.error('ChatConversation: fn_marquer_messages_lus error', error);
          });
        }
      })
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'messages_chat',
        filter: `conversation_id=eq.${convId}`,
      }, (payload) => {
        const msg = payload.new as Message;
        setMessages(prev => prev.map(m => m.id === msg.id ? msg : m));
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [convId, user]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages, typing]);

  const groupedMessages = useMemo(() => {
    const groups: Array<{ label: string; date: Date; items: Message[] }> = [];
    for (const m of messages) {
      const d = new Date(m.cree_le);
      const last = groups[groups.length - 1];
      if (!last || !isSameDay(last.date, d)) {
        groups.push({ label: formatGroupLabel(d), date: d, items: [m] });
      } else {
        last.items.push(m);
      }
    }
    return groups;
  }, [messages]);

  if (loading) {
    return (
      <div className="card-base flex items-center justify-center" style={{ height: 'min(500px, 65vh)' }}>
        <p className="text-sm text-muted-foreground">Chargement de la conversation…</p>
      </div>
    );
  }

  if (!convId) {
    return (
      <div className="card-base flex items-center justify-center" style={{ height: 'min(500px, 65vh)' }}>
        <p className="text-sm text-muted-foreground">Impossible de charger la conversation.</p>
      </div>
    );
  }

  const nomComplet = autreInfo ? `${autreInfo.prenom} ${autreInfo.nom}`.trim() : 'Interlocuteur';

  return (
    <div
      className="card-base p-0 flex flex-col overflow-hidden bg-card"
      style={{ height: 'min(560px, 70vh)' }}
    >
      <div className="flex items-center gap-3 px-4 py-3 border-b border-border bg-card/85 backdrop-blur-sm">
        <div className="relative shrink-0">
          <AvatarDisplay src={autreInfo?.avatar || null} prenom={autreInfo?.prenom || ''} nom={autreInfo?.nom || ''} size={40} rounded="full" />
          <span
            className={`absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full border-2 border-card ${PRESENCE_DOT_CLASS[presence]}`}
            aria-label={`Statut : ${presenceLabel(presence, lastSeen)}`}
          />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-foreground truncate">{nomComplet}</p>
          <p className="text-[11px] text-muted-foreground truncate">
            {typing ? (
              <span className="italic text-jolene-rose-500 inline-flex items-center gap-1">
                <span className="inline-flex gap-0.5">
                  <span className="h-1 w-1 bg-jolene-rose-500 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
                  <span className="h-1 w-1 bg-jolene-rose-500 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
                  <span className="h-1 w-1 bg-jolene-rose-500 rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
                </span>
                est en train d'écrire…
              </span>
            ) : (
              presenceLabel(presence, lastSeen)
            )}
          </p>
        </div>
        <div className="flex flex-col items-end gap-1 shrink-0">
          <span className="text-[10px] text-muted-foreground">{messages.length} msg</span>
          {/* Blocage (App Store 1.2 — UGC) : coupe la messagerie dans les 2 sens. */}
          {resolvedAutreId && resolvedAutreId !== '00000000-0000-0000-0000-000000000000' && (
            <BloquerUtilisateur cibleId={resolvedAutreId} variant="lien" />
          )}
        </div>
      </div>

      <div ref={scrollRef} className="flex-1 overflow-y-auto px-3 py-4 space-y-4 min-h-0 bg-jolene-lavender-50/40">
        {messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center gap-2 text-muted-foreground">
            <MessageCircle className="h-8 w-8 opacity-40" />
            <p className="text-sm">Aucun message. Envoyez le premier !</p>
          </div>
        ) : (
          groupedMessages.map((groupe, gi) => (
            <div key={gi} className="space-y-2">
              <div className="flex justify-center">
                <span className="text-[10px] uppercase tracking-wide text-muted-foreground bg-card/80 px-2.5 py-0.5 rounded-full">
                  {groupe.label}
                </span>
              </div>
              {groupe.items.map((msg) => {
                if (msg.est_admin && msg.auteur_id === '00000000-0000-0000-0000-000000000000') {
                  return (
                    <div key={msg.id} className="flex justify-center">
                      <p className="text-[11px] italic text-muted-foreground bg-card/60 px-3 py-1 rounded-full max-w-[85%] text-center">
                        {msg.contenu}
                      </p>
                    </div>
                  );
                }
                const mine = msg.auteur_id === user?.id;
                return (
                  <div key={msg.id} className={`flex ${mine ? 'justify-end' : 'justify-start'}`}>
                    <div
                      className={`max-w-[80%] px-3.5 py-2 ${
                        mine
                          ? 'bg-gradient-hero text-white rounded-2xl rounded-br-md shadow-sm'
                          : 'bg-card text-foreground rounded-2xl rounded-bl-md border border-border'
                      }`}
                    >
                      <p className="text-sm whitespace-pre-wrap break-words">{msg.contenu}</p>
                      <div className={`text-[9px] mt-1 flex items-center justify-end gap-1 ${mine ? 'text-white/70' : 'text-muted-foreground/70'}`}>
                        <span>{format(new Date(msg.cree_le), 'HH:mm')}</span>
                        {mine && (
                          msg.lu ? <CheckCheck className="h-3 w-3 text-jolene-cyan-300" aria-label="Lu" />
                                 : <Check className="h-3 w-3" aria-label="Envoyé" />
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          ))
        )}
        {typing && messages.length > 0 && (
          <div className="flex justify-start">
            <div className="bg-card border border-border rounded-2xl rounded-bl-md px-3 py-2 inline-flex gap-1">
              <span className="h-1.5 w-1.5 bg-jolene-rose-400 rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
              <span className="h-1.5 w-1.5 bg-jolene-rose-400 rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
              <span className="h-1.5 w-1.5 bg-jolene-rose-400 rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
            </div>
          </div>
        )}
      </div>

      <InputMessage conversationId={convId} archived={archived} />
    </div>
  );
}
