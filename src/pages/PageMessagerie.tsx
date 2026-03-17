import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { MessageCircle, Send, ArrowLeft, Shield, Plus, Search, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { resoudreUserIdEtablissement } from '@/hooks/useOuvrirConversation';
import { useAuth } from '@/contexts/AuthContext';
import { sanitizeText } from '@/lib/sanitize';
import { AvatarDisplay } from '@/components/AvatarUpload';
import joleneLogo from '@/assets/logo-jolene.png';
import { EtatVide, IllustrationBoussole } from '@/components/EtatVide';
import { formatDistanceToNow, format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';

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
  is_jolene?: boolean;
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

interface SearchResult {
  id: string;
  type: 'soignant' | 'etablissement';
  label: string;
  sub: string;
  avatar: string | null;
}

interface PageMessagerieProps {
  role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' | 'ADMIN_PLATEFORME';
}

export default function PageMessagerie({ role }: PageMessagerieProps) {
  const { user } = useAuth();
  const navigate = useNavigate();
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

  // New conversation modal (admin only)
  const [showNewConvModal, setShowNewConvModal] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);

  const isAdmin = role === 'ADMIN_PLATEFORME';

  const dashboardRoute = isAdmin ? '/admin' : role === 'SOIGNANT' ? '/soignant/tableau-de-bord' : '/etablissement/tableau-de-bord';

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
      if (isAdmin) {
        otherIds.add(c.participant_1_id);
        otherIds.add(c.participant_2_id);
      } else {
        otherIds.add(c.participant_1_id === user.id ? c.participant_2_id : c.participant_1_id);
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

    const resolveUserName = (uid: string) => {
      const info = userMap.get(uid);
      if (info) return `${info.prenom} ${info.nom}`.trim();
      return 'Jolene';
    };

    const enriched: Conversation[] = convs.map(c => {
      const autreId = c.participant_1_id === user.id ? c.participant_2_id : c.participant_1_id;
      const info = userMap.get(autreId) || userMap.get(c.participant_1_id) || userMap.get(c.participant_2_id);
      
      const isJolene = !info; // Not found in soignants or etablissements = admin Jolene
      let displayPrenom = info?.prenom || 'Jolene';
      let displayNom = info?.nom || '';
      if (isAdmin) {
        displayPrenom = resolveUserName(c.participant_1_id);
        displayNom = `↔ ${resolveUserName(c.participant_2_id)}`;
      }

      return {
        ...c,
        autre_id: autreId,
        autre_prenom: displayPrenom,
        autre_nom: displayNom,
        autre_avatar: isJolene ? null : (info?.avatar || null),
        dernier_contenu: lastMsgMap.get(c.id) || null,
        non_lus: unreadMap.get(c.id) || 0,
        is_jolene: isJolene,
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

  // ── Admin: search users for new conversation ──
  const searchUsers = useCallback(async (q: string) => {
    if (q.length < 2) { setSearchResults([]); return; }
    setSearching(true);

    const term = `%${q}%`;
    const [{ data: sData }, { data: eData }] = await Promise.all([
      supabase.from('soignants').select('id, prenom, nom, email, avatar_url').or(`prenom.ilike.${term},nom.ilike.${term},email.ilike.${term}`).limit(10),
      supabase.from('etablissements').select('id, nom, email_contact, logo_url').or(`nom.ilike.${term},email_contact.ilike.${term}`).limit(10),
    ]);

    const results: SearchResult[] = [];
    sData?.forEach(s => results.push({ id: s.id, type: 'soignant', label: `${s.prenom} ${s.nom}`, sub: s.email || '', avatar: (s as any).avatar_url }));
    eData?.forEach(e => results.push({ id: e.id, type: 'etablissement', label: e.nom, sub: e.email_contact || '', avatar: (e as any).logo_url }));
    
    setSearchResults(results);
    setSearching(false);
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => searchUsers(searchQuery), 300);
    return () => clearTimeout(timer);
  }, [searchQuery, searchUsers]);

  const startConversationWith = async (userId: string, type: 'soignant' | 'etablissement') => {
    let resolvedId = userId;
    if (type === 'etablissement') {
      const resolved = await resoudreUserIdEtablissement(userId);
      if (!resolved) {
        toast.error("Impossible de trouver l'interlocuteur de l'établissement.");
        return;
      }
      resolvedId = resolved;
    }
    const { data, error } = await supabase.rpc('fn_obtenir_conversation', { p_autre_id: resolvedId, p_mission_id: null });
    console.log('fn_obtenir_conversation (new conv):', { data, error });
    if (error || !data) {
      console.error('fn_obtenir_conversation error:', error);
      toast.error("Impossible de créer la conversation : " + (error?.message || 'Erreur inconnue'));
      return;
    }
    setShowNewConvModal(false);
    setSearchQuery('');
    setSearchResults([]);
    await chargerConversations();
    selectConv(data as string);
  };

  const selectedConv = conversations.find(c => c.id === selectedConvId);
  const showMobileChat = !!selectedConvId;

  const emptyMessage = isAdmin
    ? "Aucune conversation sur la plateforme pour le moment."
    : "Aucune conversation pour le moment. Les conversations s'ouvrent automatiquement quand vous êtes assigné à une mission.";

  return (
    <div className="flex flex-col h-[calc(100vh-8rem)] md:h-[calc(100vh-6rem)]">
      {/* Back button */}
      <div className="flex items-center gap-2 mb-2">
        <Button variant="ghost" size="sm" onClick={() => navigate(dashboardRoute)}>
          <ArrowLeft className="h-4 w-4 mr-1" />
          Retour au tableau de bord
        </Button>
      </div>

      <div className="flex flex-1 rounded-xl border border-border overflow-hidden bg-card min-h-0">
        {/* ── Conversation list ── */}
        <div className={`w-full md:w-[340px] md:border-r border-border flex flex-col ${showMobileChat ? 'hidden md:flex' : 'flex'}`}>
          <div className="p-4 border-b border-border flex items-center justify-between">
            <h2 className="font-bold text-foreground flex items-center gap-2">
              <MessageCircle className="h-5 w-5 text-primary" />
              Messagerie
            </h2>
            {isAdmin && (
              <Button size="sm" variant="outline" onClick={() => setShowNewConvModal(true)}>
                <Plus className="h-4 w-4 mr-1" />
                Nouvelle
              </Button>
            )}
          </div>
          <div className="flex-1 overflow-y-auto">
            {loading ? (
              <div className="p-8 text-center text-sm text-muted-foreground">Chargement…</div>
            ) : conversations.length === 0 ? (
              <EtatVide
                illustration={<IllustrationBoussole />}
                titre="Aucune conversation"
                sousTitre={emptyMessage}
              />
            ) : (
              conversations.map(c => (
                <button
                  key={c.id}
                  onClick={() => selectConv(c.id)}
                  className={`w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-accent/50 transition-colors border-b border-border/50 ${c.id === selectedConvId ? 'bg-accent' : ''}`}
                >
                  {c.is_jolene ? (
                    <div className="shrink-0 h-10 w-10 rounded-full bg-card border border-border flex items-center justify-center overflow-hidden">
                      <img src={joleneLogo} alt="Jolene" className="h-6 w-6 object-contain" />
                    </div>
                  ) : (
                    <AvatarDisplay src={c.autre_avatar} prenom={c.autre_prenom} nom={c.autre_nom} size={40} rounded="full" />
                  )}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-semibold text-foreground truncate flex items-center gap-1.5">
                        {c.autre_prenom} {c.autre_nom}
                        {c.is_jolene && <Shield className="h-3.5 w-3.5 text-primary shrink-0" />}
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
                {selectedConv.is_jolene ? (
                  <div className="shrink-0 h-9 w-9 rounded-full bg-card border border-border flex items-center justify-center overflow-hidden">
                    <img src={joleneLogo} alt="Jolene" className="h-5 w-5 object-contain" />
                  </div>
                ) : (
                  <AvatarDisplay src={selectedConv.autre_avatar} prenom={selectedConv.autre_prenom} nom={selectedConv.autre_nom} size={36} rounded="full" />
                )}
                <div>
                  <p className="text-sm font-semibold text-foreground flex items-center gap-1.5">{selectedConv.autre_prenom} {selectedConv.autre_nom}{selectedConv.is_jolene && <Shield className="h-3.5 w-3.5 text-primary" />}</p>
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
                          {msg.est_admin && (
                            <p className={`text-[10px] font-bold mb-0.5 flex items-center gap-1 ${mine ? 'text-primary-foreground/80' : 'text-primary'}`}>
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

      {/* ── New conversation modal (admin) ── */}
      <Dialog open={showNewConvModal} onOpenChange={setShowNewConvModal}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Nouvelle conversation</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Rechercher un soignant ou établissement…"
                value={searchQuery}
                onChange={e => setSearchQuery(e.target.value)}
                className="pl-9"
                autoFocus
              />
              {searchQuery && (
                <button onClick={() => { setSearchQuery(''); setSearchResults([]); }} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>
            <div className="max-h-[300px] overflow-y-auto space-y-1">
              {searching && <p className="text-sm text-muted-foreground text-center py-4">Recherche…</p>}
              {!searching && searchQuery.length >= 2 && searchResults.length === 0 && (
                <p className="text-sm text-muted-foreground text-center py-4">Aucun résultat</p>
              )}
              {searchResults.map(r => (
                <button
                  key={r.id}
                  onClick={() => startConversationWith(r.id, r.type)}
                  className="w-full flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-accent/50 transition-colors text-left"
                >
                  <AvatarDisplay src={r.avatar} prenom={r.label} nom="" size={32} rounded="full" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">{r.label}</p>
                    <p className="text-xs text-muted-foreground truncate">{r.type === 'soignant' ? 'Soignant' : 'Établissement'} · {r.sub}</p>
                  </div>
                </button>
              ))}
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
