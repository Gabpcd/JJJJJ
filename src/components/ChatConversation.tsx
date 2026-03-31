import { useState, useEffect, useRef } from 'react';
import { Send } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { sanitizeText } from '@/lib/sanitize';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import { hapticImpact } from '@/lib/haptics';

interface Message {
  id: string;
  conversation_id: string;
  auteur_id: string;
  contenu: string;
  est_admin: boolean;
  lu: boolean;
  cree_le: string;
}

interface ChatConversationProps {
  missionId: string;
  autreUserId: string;
  /** If the other party is an établissement record ID (not a user ID), set this to true to resolve via RPC */
  isEtablissement?: boolean;
}

/**
 * Chat component that uses conversations + messages_chat tables.
 * Resolves/creates a conversation for a given mission and counterpart,
 * then sends/receives messages via fn_envoyer_message and realtime.
 */
export function ChatConversation({ missionId, autreUserId, isEtablissement }: ChatConversationProps) {
  const { user } = useAuth();
  const [convId, setConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [texte, setTexte] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [loading, setLoading] = useState(true);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Resolve conversation
  useEffect(() => {
    if (!user || !missionId || !autreUserId) return;

    const resolve = async () => {
      let resolvedUserId = autreUserId;

      if (isEtablissement) {
        const { data: uid, error: resolveErr } = await supabase.rpc('fn_user_id_pour_etablissement' as any, { p_etablissement_id: autreUserId });
        if (resolveErr || !uid) {
          logger.error('ChatConversation: cannot resolve etablissement user ID', resolveErr);
          setLoading(false);
          return;
        }
        resolvedUserId = uid as string;
      }

      const { data, error } = await supabase.rpc('fn_obtenir_conversation', {
        p_autre_id: resolvedUserId,
        p_mission_id: missionId,
      });

      if (error || !data) {
        logger.error('ChatConversation: fn_obtenir_conversation error', error);
        setLoading(false);
        return;
      }

      setConvId(data as string);
    };

    resolve();
  }, [user, missionId, autreUserId, isEtablissement]);

  // Load messages when convId is set
  useEffect(() => {
    if (!convId) return;

    const load = async () => {
      const { data } = await supabase
        .from('messages_chat')
        .select('id, conversation_id, auteur_id, contenu, est_admin, lu, cree_le')
        .eq('conversation_id', convId)
        .order('cree_le', { ascending: true })
        .limit(500);

      setMessages((data as Message[]) || []);
      setLoading(false);

      // Mark as read
      supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: convId }).then(() => {});
    };

    load();

    // Realtime
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
          supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: convId }).catch(() => {});
        }
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [convId, user]);

  // Auto-scroll
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages]);

  const envoyer = async () => {
    const contenuBrut = texte.trim();
    if (!contenuBrut || !convId || !user) return;

    const contenu = sanitizeText(contenuBrut);
    if (!contenu) return;

    setEnvoi(true);
    setTexte('');

    const { data, error } = await supabase.rpc('fn_envoyer_message', {
      p_conversation_id: convId,
      p_contenu: contenu,
    });

    if (error || (data && typeof data === 'object' && (data as any).error)) {
      logger.error('ChatConversation: fn_envoyer_message error', error || data);
      toast.error("Impossible d'envoyer le message.");
      setTexte(contenuBrut);
    } else {
      hapticImpact('light');
    }

    setEnvoi(false);
    inputRef.current?.focus();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); envoyer(); }
  };

  if (loading) {
    return (
      <div className="card-base flex items-center justify-center" style={{ height: '400px' }}>
        <p className="text-sm text-muted-foreground">Chargement de la conversation…</p>
      </div>
    );
  }

  if (!convId) {
    return (
      <div className="card-base flex items-center justify-center" style={{ height: '400px' }}>
        <p className="text-sm text-muted-foreground">Impossible de charger la conversation.</p>
      </div>
    );
  }

  return (
    <div className="card-base flex flex-col" style={{ height: '400px' }}>
      <div className="flex items-center justify-between pb-3 border-b border-border mb-3">
        <h3 className="font-semibold text-sm text-foreground">💬 Messagerie</h3>
        <span className="text-[10px] text-muted-foreground">{messages.length} message{messages.length !== 1 ? 's' : ''}</span>
      </div>

      <div ref={scrollRef} className="flex-1 overflow-y-auto space-y-3 pr-1 min-h-0">
        {messages.length === 0 && (
          <div className="flex items-center justify-center h-full">
            <p className="text-sm text-muted-foreground text-center">Aucun message. Envoyez le premier !</p>
          </div>
        )}
        {messages.map(msg => {
          const mine = msg.auteur_id === user?.id;
          return (
            <div key={msg.id} className={`flex ${mine ? 'justify-end' : 'justify-start'}`}>
              <div className={`max-w-[80%] rounded-2xl px-3.5 py-2 ${mine ? 'bg-primary text-primary-foreground rounded-br-md' : 'bg-muted text-foreground rounded-bl-md'}`}>
                <p className="text-sm whitespace-pre-wrap break-words">{msg.contenu}</p>
                <p className={`text-[9px] mt-1 text-right ${mine ? 'text-primary-foreground/60' : 'text-muted-foreground/60'}`}>
                  {format(new Date(msg.cree_le), "HH'h'mm", { locale: fr })}
                </p>
              </div>
            </div>
          );
        })}
      </div>

      <div className="flex items-center gap-2 pt-3 border-t border-border mt-3">
        <input
          ref={inputRef}
          type="text"
          value={texte}
          onChange={e => setTexte(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Votre message…"
          className="input-base flex-1 text-sm py-2"
          maxLength={1000}
          disabled={envoi}
        />
        <button
          onClick={envoyer}
          disabled={envoi || !texte.trim()}
          className="rounded-xl p-2.5 bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-40 transition-colors shrink-0"
          aria-label="Envoyer"
        >
          <Send className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
