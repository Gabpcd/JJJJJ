import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
import { MessageCircle, Send, ArrowLeft, Shield } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { sanitizeText } from '@/lib/sanitize';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { EtatVide, IllustrationBoussole } from '@/components/EtatVide';
import { formatDistanceToNow, format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

interface Conversation {
  id: string;
  participant_1_id: string;
  participant_2_id: string;
  mission_id: string | null;
  dernier_message_le: string | null;
  cree_le: string;
  autre_id: string;
  autre_prenom: string;
  autre_nom: string;
  autre_avatar: string | null;
  dernier_contenu: string | null;
  non_lus: number;
}

interface Message {
  id: string;
  conversation_id: string;
  auteur_id: string;
  contenu: string;
  est_admin: boolean;
  lu: boolean;
  cree_le: string;
}

interface PageMessagerieProps {
  role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' | 'ADMIN_PLATEFORME';
}

export default function PageMessagerie({ role }: PageMessagerieProps) {
  const { user } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const convParam = searchParams.get('conv');

  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedConvId, setSelectedConvId] = useState<string | null>(convParam);
  const [messages, setMessages] = useState<Message[]>([]);
  const [loadingMessages, setLoadingMessages] = useState(false);
  const [texte, setTexte] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const isAdmin = role === 'ADMIN_PLATEFORME';

  // ── Load conversations ──
  const chargerConversations = useCallback(async () => {
    if (!user) return;
    
    let query = supabase
      .from('conversations')
      .select('id, participant_1_id, participant_2_id, mission_id, dernier_message_le, cree_le')
      .order('dernier_message_le', { ascending: false, nullsFirst: false });

    if (!isAdmin) {
      query = query.or(`participant_1_id.eq.${user.id},participant_2_id.eq.${user.id}`);
    }

    const { data: convs } = await query.limit(100);
    if (!convs || convs.length === 0) {
      setConversations([]);
      setLoading(false);
      return;
    }

    // Collect unique other user IDs
    const otherIds = new Set<string>();
    convs.forEach(c => {
      otherIds.add(c.participant_1_id === user.id ? c.participant_2_id : c.participant_1_id);
      if (isAdmin) {
        otherIds.add(c.participant_1_id);
        otherIds.add(c.participant_2_id);
      }
    });

    // Fetch soignants and etablissements info for those IDs
    const ids = Array.from(otherIds);
    const [{ data: soignants }, { data: etabs }] = await Promise.all([
      supabase.from('soignants').select('id, prenom, nom, avatar_url').in('id', ids),
      supabase.from('etablissements').select('id, nom, logo_url').in('id', ids),
    ]);

    const userMap = new Map<string, { prenom: string; nom: string; avatar: string | null }>();
    soignants?.forEach(s => userMap.set(s.id, { prenom: s.prenom, nom: s.nom, avatar: (s as any).avatar_url }));
    etabs?.forEach(e => userMap.set(e.id, { prenom: e.nom, nom: '', avatar: (e as any).logo_url }));

    // Fetch last message per conversation
    const convIds = convs.map(c => c.id);
    const { data: lastMessages } = await supabase
      .from('messages_chat')
      .select('conversation_id, contenu, cree_le')
      .in('conversation_id', convIds)
      .order('cree_le', { ascending: false });

    const lastMsgMap = new Map<string, string>();
    lastMessages?.forEach(m => {
      if (!lastMsgMap.has(m.conversation_id)) lastMsgMap.set(m.conversation_id, m.contenu);
    });

    // Fetch unread counts
    const { data: unreadMessages } = await supabase
      .from('messages_chat')
      .select('conversation_id, id')
      .in('conversation_id', convIds)
      .eq('lu', false)
      .neq('auteur_id', user.id);

    const unreadMap = new Map<string, number>();
    unreadMessages?.forEach(m => {
      unreadMap.set(m.conversation_id, (unreadMap.get(m.conversation_id) || 0) + 1);
    });

    const enriched: Conversation[] = convs.map(c => {
      const autreId = c.participant_1_id === user.id ? c.participant_2_id : c.participant_1_id;
      const info = userMap.get(autreId);
      return {
        ...c,
        autre_id: autreId,
        autre_prenom: info?.prenom || 'Utilisateur',
        autre_nom: info?.nom || '',
        autre_avatar: info?.avatar || null,
        dernier_contenu: lastMsgMap.get(c.id) || null,
        non_lus: unreadMap.get(c.id) || 0,
      };
    });

    setConversations(enriched);
    setLoading(false);
  }, [user, isAdmin]);

  useEffect(() => { chargerConversations(); }, [chargerConversations]);

  // ── Load messages for selected conversation ──
  useEffect(() => {
    if (!selectedConvId) { setMessages([]); return; }

    const load = async () => {
      setLoadingMessages(true);
      const { data } = await supabase
        .from('messages_chat')
        .select('id, conversation_id, auteur_id, contenu, est_admin, lu, cree_le')
        .eq('conversation_id', selectedConvId)
        .order('cree_le', { ascending: true })
        .limit(500);

      setMessages((data as Message[]) || []);
      setLoadingMessages(false);

      // Mark as read
      supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: selectedConvId }).then(({ error }) => {
        if (error) console.error('fn_marquer_messages_lus error:', error);
        setConversations(prev => prev.map(c => c.id === selectedConvId ? { ...c, non_lus: 0 } : c));
      });
    };
    load();

    // Realtime for this conversation
    const channel = supabase
      .channel(`chat-conv-${selectedConvId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages_chat',
        filter: `conversation_id=eq.${selectedConvId}`,
      }, (payload) => {
        const msg = payload.new as Message;
        setMessages(prev => prev.some(m => m.id === msg.id) ? prev : [...prev, msg]);
        // Mark as read immediately if it's the active conversation
        if (msg.auteur_id !== user?.id) {
          supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: selectedConvId });
        }
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [selectedConvId, user]);

  // Auto-scroll
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages]);

  // ── Send message ──
  const envoyer = async () => {
    const contenuBrut = texte.trim();
    if (!contenuBrut || !selectedConvId || !user) return;

    const contenu = sanitizeText(contenuBrut);
    if (!contenu) return;

    setEnvoi(true);
    setTexte('');

    const { data, error } = await supabase.rpc('fn_envoyer_message', {
      p_conversation_id: selectedConvId,
      p_contenu: contenu,
    });

    console.log('fn_envoyer_message result:', { data, error, p_conversation_id: selectedConvId, p_contenu: contenu });

    if (error) {
      console.error('fn_envoyer_message error:', error);
      toast.error("Impossible d'envoyer le message.");
      setTexte(contenuBrut);
    } else if (data && typeof data === 'object' && (data as any).error) {
      console.error('fn_envoyer_message returned error:', data);
      toast.error("Impossible d'envoyer le message.");
      setTexte(contenuBrut);
    }

    setEnvoi(false);
    inputRef.current?.focus();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); envoyer(); }
  };

  const selectConv = (convId: string) => {
    setSelectedConvId(convId);
    setSearchParams({ conv: convId });
  };

  const selectedConv = conversations.find(c => c.id === selectedConvId);
  const showMobileChat = !!selectedConvId;

  return (
    <div className="flex h-[calc(100vh-8rem)] md:h-[calc(100vh-6rem)] rounded-xl border border-border overflow-hidden bg-card">
      {/* ── Conversation list ── */}
      <div className={`w-full md:w-[340px] md:border-r border-border flex flex-col ${showMobileChat ? 'hidden md:flex' : 'flex'}`}>
        <div className="p-4 border-b border-border">
          <h2 className="font-bold text-foreground flex items-center gap-2">
            <MessageCircle className="h-5 w-5 text-primary" />
            Messagerie
          </h2>
        </div>
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-8 text-center text-sm text-muted-foreground">Chargement…</div>
          ) : conversations.length === 0 ? (
            <EtatVide
              illustration={<IllustrationBoussole />}
              titre="Aucune conversation"
              sousTitre="Les conversations s'ouvrent automatiquement quand vous êtes assigné à une mission."
            />
          ) : (
            conversations.map(c => (
              <button
                key={c.id}
                onClick={() => selectConv(c.id)}
                className={`w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-accent/50 transition-colors border-b border-border/50 ${c.id === selectedConvId ? 'bg-accent' : ''}`}
              >
                <AvatarDisplay src={c.autre_avatar} prenom={c.autre_prenom} nom={c.autre_nom} size={40} rounded="full" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-sm font-semibold text-foreground truncate">
                      {c.autre_prenom} {c.autre_nom}
                    </span>
                    {c.dernier_message_le && (
                      <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                        {formatDistanceToNow(new Date(c.dernier_message_le), { addSuffix: false, locale: fr })}
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground truncate">
                    {c.dernier_contenu ? c.dernier_contenu.slice(0, 50) : 'Aucun message'}
                  </p>
                </div>
                {c.non_lus > 0 && (
                  <span className="h-5 min-w-[20px] flex items-center justify-center rounded-full bg-primary text-primary-foreground text-[10px] font-bold px-1">
                    {c.non_lus}
                  </span>
                )}
              </button>
            ))
          )}
        </div>
      </div>

      {/* ── Chat area ── */}
      <div className={`flex-1 flex flex-col ${!showMobileChat ? 'hidden md:flex' : 'flex'}`}>
        {selectedConv ? (
          <>
            {/* Header */}
            <div className="flex items-center gap-3 p-4 border-b border-border">
              <button onClick={() => { setSelectedConvId(null); setSearchParams({}); }} className="md:hidden text-muted-foreground hover:text-foreground">
                <ArrowLeft className="h-5 w-5" />
              </button>
              <AvatarDisplay src={selectedConv.autre_avatar} prenom={selectedConv.autre_prenom} nom={selectedConv.autre_nom} size={36} rounded="full" />
              <div>
                <p className="text-sm font-semibold text-foreground">{selectedConv.autre_prenom} {selectedConv.autre_nom}</p>
              </div>
            </div>

            {/* Messages */}
            <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 space-y-3 min-h-0">
              {loadingMessages ? (
                <div className="text-center text-sm text-muted-foreground py-8">Chargement…</div>
              ) : messages.length === 0 ? (
                <div className="text-center text-sm text-muted-foreground py-8">Aucun message. Envoyez le premier !</div>
              ) : (
                messages.map(msg => {
                  const mine = msg.auteur_id === user?.id;
                  return (
                    <div key={msg.id} className={`flex ${mine ? 'justify-end' : 'justify-start'}`}>
                      <div className={`max-w-[80%] rounded-2xl px-3.5 py-2 ${mine ? 'bg-primary text-primary-foreground rounded-br-md' : 'bg-muted text-foreground rounded-bl-md'}`}>
                        {msg.est_admin && !mine && (
                          <p className="text-[10px] font-bold mb-0.5 flex items-center gap-1 text-primary">
                            <Shield className="h-3 w-3" /> Admin Jolene
                          </p>
                        )}
                        <p className="text-sm whitespace-pre-wrap break-words">{msg.contenu}</p>
                        <p className={`text-[9px] mt-1 text-right ${mine ? 'text-primary-foreground/60' : 'text-muted-foreground/60'}`}>
                          {format(new Date(msg.cree_le), "HH'h'mm", { locale: fr })}
                        </p>
                      </div>
                    </div>
                  );
                })
              )}
            </div>

            {/* Input */}
            <div className="flex items-center gap-2 p-4 border-t border-border">
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
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center">
            <div className="text-center text-muted-foreground">
              <MessageCircle className="h-12 w-12 mx-auto mb-3 opacity-30" />
              <p className="text-sm">Sélectionnez une conversation</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}