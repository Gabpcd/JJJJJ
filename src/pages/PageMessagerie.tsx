/**
 * `<PageMessagerie />` — Sprint 10-B PR 1 refonte Meta-grade Y2K
 *
 * Page messagerie standalone (rôles SOIGNANT / ADMIN_ETABLISSEMENT /
 * ADMIN_PLATEFORME), inspirée WhatsApp/Messenger.
 *
 * Layout :
 *  - Mobile : full width, switch list ↔ chat detail
 *  - Desktop : sidebar 380px + chat detail
 *
 * Liste conversations Y2K :
 *  - Header sticky avec titre + recherche local (filtre par nom interlocuteur)
 *  - Tabs "Actives" / "Archivées" (sur conversations.archived_at)
 *  - Items avec avatar + status dot Y2K (vert/butter/gris) + nom +
 *    badge mission tronqué + dernier message tronqué 50 chars +
 *    timestamp intelligent (Maintenant / HH:mm / Hier / Lun / d MMM) +
 *    badge unread gradient rose-mauve
 *  - EmptyState avec Mascotte état "empty"
 *  - Tri last_message_at desc
 *  - Touch targets 44px+
 *
 * Le chat detail panel garde son input inline (l'anti-leak + typing
 * indicators sont déjà disponibles via ChatConversation / InputMessage
 * pour les chats inline mission — refonte panel à venir Sprint 10-C
 * pour ne pas bloquer le merge PR 1).
 */
import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { MessageCircle, Send, ArrowLeft, Shield, Plus, Search, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { resoudreUserIdEtablissement } from '@/hooks/useOuvrirConversation';
import { useAuth } from '@/contexts/AuthContext';
import { sanitizeText } from '@/lib/sanitize';
import { AvatarDisplay } from '@/components/AvatarUpload';
import { LayoutApp } from '@/components/LayoutApp';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { usePageTitle } from '@/hooks/usePageTitle';
import { logger } from '@/lib/logger';
import { handleErrorSilent } from '@/lib/handleError';
import { Mascotte } from '@/components/mascotte/Mascotte';
import { formatDistanceToNowStrict, format, isToday, isYesterday, differenceInDays } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveBody,
} from '@/components/ui/DialogResponsive';
import { Input } from '@/components/ui/input';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

interface Conversation {
  id: string;
  participant_1_id: string;
  participant_2_id: string;
  mission_id: string | null;
  dernier_message_le: string | null;
  cree_le: string;
  archived_at: string | null;
  autre_id: string;
  autre_prenom: string;
  autre_nom: string;
  autre_avatar: string | null;
  dernier_contenu: string | null;
  non_lus: number;
  is_jolene?: boolean;
  mission_intitule?: string | null;
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

function formatTimestampIntelligent(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  const now = new Date();
  const seconds = Math.floor((now.getTime() - d.getTime()) / 1000);
  if (seconds < 60) return 'Maintenant';
  if (isToday(d)) return format(d, 'HH:mm');
  if (isYesterday(d)) return 'Hier';
  const days = differenceInDays(now, d);
  if (days < 7) return format(d, 'EEE', { locale: fr });
  return format(d, 'd MMM', { locale: fr });
}

export default function PageMessagerie({ role }: PageMessagerieProps) {
  usePageTitle('Messagerie');
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
  const [filtre, setFiltre] = useState('');
  const [tab, setTab] = useState<'ACTIVES' | 'ARCHIVEES'>('ACTIVES');
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const [showNewConvModal, setShowNewConvModal] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);

  const isAdminPlateforme = role === 'ADMIN_PLATEFORME';
  const isAdmin = isAdminPlateforme;

  const chargerConversations = useCallback(async () => {
    if (!user) return;

    let query = supabase
      .from('conversations')
      .select('id, participant_1_id, participant_2_id, mission_id, dernier_message_le, cree_le, archived_at' as any)
      .order('dernier_message_le', { ascending: false, nullsFirst: false });

    if (!isAdminPlateforme) {
      query = query.or(`participant_1_id.eq.${user.id},participant_2_id.eq.${user.id}`);
    }

    const { data: convsRaw } = await query.limit(100);
    const convs = ((convsRaw || []) as unknown) as Array<{
      id: string;
      participant_1_id: string;
      participant_2_id: string;
      mission_id: string | null;
      dernier_message_le: string | null;
      cree_le: string;
      archived_at: string | null;
    }>;
    if (convs.length === 0) {
      setConversations([]);
      setLoading(false);
      return;
    }

    const otherIds = new Set<string>();
    convs.forEach(c => {
      if (isAdmin) {
        otherIds.add(c.participant_1_id);
        otherIds.add(c.participant_2_id);
      } else {
        otherIds.add(c.participant_1_id === user.id ? c.participant_2_id : c.participant_1_id);
      }
    });

    const ids = Array.from(otherIds);
    const [{ data: soignants }, { data: etabs }] = await Promise.all([
      supabase.from('soignants').select('id, prenom, nom, avatar_url').in('id', ids),
      supabase.from('etablissements').select('id, nom, logo_url').in('id', ids),
    ]);

    const userMap = new Map<string, { prenom: string; nom: string; avatar: string | null }>();
    soignants?.forEach(s => userMap.set(s.id, { prenom: s.prenom, nom: s.nom, avatar: (s as any).avatar_url }));
    etabs?.forEach(e => userMap.set(e.id, { prenom: e.nom, nom: '', avatar: (e as any).logo_url }));

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

    const missionIds = [...new Set(convs.map(c => c.mission_id).filter(Boolean))] as string[];
    const missionMap = new Map<string, string>();
    if (missionIds.length > 0) {
      const { data: missionData } = await supabase.from('missions').select('id, intitule').in('id', missionIds);
      missionData?.forEach(m => missionMap.set(m.id, m.intitule));
    }

    const enriched: Conversation[] = convs.map(c => {
      const autreId = c.participant_1_id === user.id ? c.participant_2_id : c.participant_1_id;
      const info = userMap.get(autreId) || userMap.get(c.participant_1_id) || userMap.get(c.participant_2_id);

      const isJolene = !info;
      let displayPrenom = info?.prenom || 'Jolene';
      let displayNom = info?.nom || '';
      if (isAdmin) {
        displayPrenom = resolveUserName(c.participant_1_id);
        displayNom = `↔ ${resolveUserName(c.participant_2_id)}`;
      }

      return {
        ...c,
        archived_at: (c as any).archived_at || null,
        autre_id: autreId,
        autre_prenom: displayPrenom,
        autre_nom: displayNom,
        autre_avatar: isJolene ? null : (info?.avatar || null),
        dernier_contenu: lastMsgMap.get(c.id) || null,
        non_lus: unreadMap.get(c.id) || 0,
        is_jolene: isJolene,
        mission_intitule: c.mission_id ? missionMap.get(c.mission_id) || null : null,
      };
    });

    setConversations(enriched);
    setLoading(false);
  }, [user, isAdmin, isAdminPlateforme]);

  useEffect(() => { chargerConversations(); }, [chargerConversations]);

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
      setTimeout(() => inputRef.current?.focus(), 100);

      supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: selectedConvId }).then(({ error }) => {
        if (error) {
          logger.error('fn_marquer_messages_lus error', error);
          toast.error('Erreur lors du marquage des messages comme lus.');
          return;
        }
        setConversations(prev => prev.map(c => c.id === selectedConvId ? { ...c, non_lus: 0 } : c));
      });
    };
    load();

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
          supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: selectedConvId })
            .then(undefined, (err) => handleErrorSilent(err, 'PageMessagerie.marquer_messages_lus'));
        }
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [selectedConvId, user]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages]);

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

    if (error || (data && typeof data === 'object' && (data as any).error)) {
      logger.error('fn_envoyer_message error', error || data);
      toast.error("Impossible d'envoyer le message.");
      setTexte(contenuBrut);
    } else {
      chargerConversations().catch(() => { /* non bloquant */ });
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
    if (error || !data) {
      logger.error('fn_obtenir_conversation error:', error);
      toast.error("Impossible de créer la conversation. Veuillez réessayer.");
      return;
    }
    setShowNewConvModal(false);
    setSearchQuery('');
    setSearchResults([]);
    await chargerConversations();
    selectConv(data as string);
  };

  const filteredConvs = useMemo(() => {
    const term = filtre.trim().toLowerCase();
    return conversations.filter(c => {
      if (tab === 'ACTIVES' && c.archived_at) return false;
      if (tab === 'ARCHIVEES' && !c.archived_at) return false;
      if (!term) return true;
      return `${c.autre_prenom} ${c.autre_nom}`.toLowerCase().includes(term)
        || (c.mission_intitule || '').toLowerCase().includes(term)
        || (c.dernier_contenu || '').toLowerCase().includes(term);
    });
  }, [conversations, filtre, tab]);

  const archivedCount = useMemo(
    () => conversations.filter(c => c.archived_at).length,
    [conversations],
  );

  const selectedConv = conversations.find(c => c.id === selectedConvId);
  const showMobileChat = !!selectedConvId;
  const isArchivedSelected = !!selectedConv?.archived_at;

  const layoutRole = role === 'ADMIN_PLATEFORME' ? 'ADMIN_PLATEFORME' : role === 'ADMIN_ETABLISSEMENT' ? 'ADMIN_ETABLISSEMENT' : 'SOIGNANT';

  const contenu = (
    <div className="flex flex-col h-[calc(100dvh-14rem)] md:h-[calc(100dvh-8rem)]">
        <div className="flex flex-1 rounded-2xl border border-jolene-rose-200/40 overflow-hidden bg-card min-h-0 shadow-sm">
          {/* ── Conversation list ── */}
          <div className={`w-full md:w-[380px] md:border-r border-border flex flex-col bg-jolene-lavender-50/30 ${showMobileChat ? 'hidden md:flex' : 'flex'}`}>
            <div className="px-4 pt-4 pb-2 border-b border-border bg-card/85 backdrop-blur-sm sticky top-0 z-10">
              <div className="flex items-center justify-between mb-3">
                <h2 className="font-bold text-foreground flex items-center gap-2 text-base">
                  <MessageCircle className="h-5 w-5 text-jolene-rose-500" />
                  Messagerie
                </h2>
                {isAdmin && (
                  <BoutonY2K size="sm" variant="secondary" onClick={() => setShowNewConvModal(true)} className="rounded-full" iconeGauche={<Plus className="h-4 w-4" />}>
                    Nouvelle
                  </BoutonY2K>
                )}
              </div>
              <div className="relative mb-2">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Rechercher une conversation…"
                  value={filtre}
                  onChange={e => setFiltre(e.target.value)}
                  className="pl-9 rounded-full bg-background h-9"
                />
              </div>
              <div className="flex gap-1 mb-1" role="tablist" aria-label="Filtrer conversations">
                <button
                  type="button"
                  role="tab"
                  aria-selected={tab === 'ACTIVES'}
                  onClick={() => setTab('ACTIVES')}
                  className={`px-3 py-1 rounded-full text-xs font-medium transition-colors min-h-[28px] ${tab === 'ACTIVES' ? 'bg-gradient-hero text-white shadow-sm' : 'text-muted-foreground hover:bg-muted/50'}`}
                >
                  Actives
                </button>
                <button
                  type="button"
                  role="tab"
                  aria-selected={tab === 'ARCHIVEES'}
                  onClick={() => setTab('ARCHIVEES')}
                  className={`px-3 py-1 rounded-full text-xs font-medium transition-colors min-h-[28px] ${tab === 'ARCHIVEES' ? 'bg-gradient-hero text-white shadow-sm' : 'text-muted-foreground hover:bg-muted/50'}`}
                >
                  Archivées {archivedCount > 0 && <span className="ml-1 opacity-70">({archivedCount})</span>}
                </button>
              </div>
            </div>
            <div className="flex-1 overflow-y-auto">
              {loading ? (
                <div className="p-8 text-center text-sm text-muted-foreground">Chargement…</div>
              ) : filteredConvs.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 px-6 text-center gap-3">
                  <Mascotte etat="empty" taille="lg" />
                  <p className="text-sm font-medium text-foreground">
                    {tab === 'ARCHIVEES' ? 'Aucune conversation archivée' : 'Aucune conversation'}
                  </p>
                  <p className="text-xs text-muted-foreground leading-relaxed">
                    {filtre.length > 0
                      ? 'Aucune conversation ne correspond à votre recherche.'
                      : tab === 'ARCHIVEES'
                        ? 'Les conversations sont archivées 30 jours après la fin d\'une mission.'
                        : "Les conversations s'ouvrent automatiquement quand votre candidature est acceptée."}
                  </p>
                </div>
              ) : (
                filteredConvs.map(c => (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => selectConv(c.id)}
                    className={`w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-jolene-rose-50/40 active:bg-jolene-rose-100/40 transition-colors border-b border-border/40 min-h-[64px] ${c.id === selectedConvId ? 'bg-jolene-rose-50/60' : ''}`}
                  >
                    <div className="relative shrink-0">
                      {c.is_jolene ? (
                        <div className="h-12 w-12 rounded-full bg-gradient-hero/10 border border-jolene-rose-200 flex items-center justify-center">
                          <Shield className="h-5 w-5 text-jolene-rose-500" />
                        </div>
                      ) : (
                        <AvatarDisplay src={c.autre_avatar} prenom={c.autre_prenom} nom={c.autre_nom} size={48} rounded="full" />
                      )}
                      {c.non_lus > 0 && (
                        <span className="absolute -top-0.5 -right-0.5 h-5 min-w-[20px] flex items-center justify-center rounded-full bg-gradient-hero text-white text-[10px] font-bold px-1 shadow-sm">
                          {c.non_lus > 99 ? '99+' : c.non_lus}
                        </span>
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2">
                        <span className={`text-sm truncate flex items-center gap-1.5 ${c.non_lus > 0 ? 'font-bold text-foreground' : 'font-semibold text-foreground'}`}>
                          {c.autre_prenom} {c.autre_nom}
                          {c.is_jolene && <Shield className="h-3.5 w-3.5 text-jolene-rose-500 shrink-0" />}
                        </span>
                        {c.dernier_message_le && (
                          <span className={`text-[10px] whitespace-nowrap ${c.non_lus > 0 ? 'text-jolene-rose-500 font-semibold' : 'text-muted-foreground'}`}>
                            {formatTimestampIntelligent(c.dernier_message_le)}
                          </span>
                        )}
                      </div>
                      {c.mission_intitule && (
                        <p className="text-[10px] text-jolene-mauve-600 truncate font-medium">
                          Mission · {c.mission_intitule}
                        </p>
                      )}
                      <p className={`text-xs truncate ${c.non_lus > 0 ? 'text-foreground/80 font-medium' : 'text-muted-foreground'}`}>
                        {c.dernier_contenu ? c.dernier_contenu.slice(0, 60) : 'Aucun message'}
                      </p>
                      {c.archived_at && (
                        <p className="text-[10px] text-muted-foreground/70 italic mt-0.5">Archivée — lecture seule</p>
                      )}
                    </div>
                  </button>
                ))
              )}
            </div>
          </div>

          {/* ── Chat area ── */}
          <div className={`flex-1 flex flex-col ${!showMobileChat ? 'hidden md:flex' : 'flex'}`}>
            {selectedConv ? (
              <>
                <div className="flex items-center gap-3 px-4 py-3 border-b border-border bg-card/85 backdrop-blur-sm">
                  <button
                    type="button"
                    onClick={() => { setSelectedConvId(null); setSearchParams({}); }}
                    className="md:hidden text-muted-foreground hover:text-foreground p-1 -ml-1"
                    aria-label="Retour aux conversations"
                  >
                    <ArrowLeft className="h-5 w-5" />
                  </button>
                  {selectedConv.is_jolene ? (
                    <div className="shrink-0 h-10 w-10 rounded-full bg-gradient-hero/10 border border-jolene-rose-200 flex items-center justify-center">
                      <Shield className="h-5 w-5 text-jolene-rose-500" />
                    </div>
                  ) : (
                    <AvatarDisplay src={selectedConv.autre_avatar} prenom={selectedConv.autre_prenom} nom={selectedConv.autre_nom} size={40} rounded="full" />
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-foreground truncate flex items-center gap-1.5">
                      {selectedConv.autre_prenom} {selectedConv.autre_nom}
                      {selectedConv.is_jolene && <Shield className="h-3.5 w-3.5 text-jolene-rose-500" />}
                    </p>
                    {selectedConv.mission_intitule && (
                      <p className="text-[11px] text-jolene-mauve-600 truncate">Mission · {selectedConv.mission_intitule}</p>
                    )}
                  </div>
                </div>

                <div ref={scrollRef} className="flex-1 overflow-y-auto px-3 py-4 space-y-3 min-h-0 bg-jolene-lavender-50/30">
                  {loadingMessages ? (
                    <div className="text-center text-sm text-muted-foreground py-8">Chargement…</div>
                  ) : messages.length === 0 ? (
                    <div className="flex flex-col items-center justify-center h-full text-center gap-2 text-muted-foreground">
                      <MessageCircle className="h-8 w-8 opacity-40" />
                      <p className="text-sm">Aucun message. Envoyez le premier !</p>
                    </div>
                  ) : (
                    messages.map(msg => {
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
                          <div className={`max-w-[80%] px-3.5 py-2 ${
                            mine
                              ? 'bg-gradient-hero text-white rounded-2xl rounded-br-md shadow-sm'
                              : 'bg-card text-foreground rounded-2xl rounded-bl-md border border-border'
                          }`}>
                            {msg.est_admin && (
                              <p className={`text-[10px] font-bold mb-0.5 flex items-center gap-1 ${mine ? 'text-white/85' : 'text-jolene-rose-500'}`}>
                                <Shield className="h-3 w-3" /> Admin Jolene
                              </p>
                            )}
                            <p className="text-sm whitespace-pre-wrap break-words">{msg.contenu}</p>
                            <p className={`text-[9px] mt-1 text-right ${mine ? 'text-white/70' : 'text-muted-foreground/70'}`}>
                              {format(new Date(msg.cree_le), 'HH:mm')}
                            </p>
                          </div>
                        </div>
                      );
                    })
                  )}
                </div>

                {isArchivedSelected ? (
                  <div className="px-4 py-3 bg-muted/40 border-t border-border text-center text-xs text-muted-foreground italic">
                    Conversation archivée — lecture seule.
                  </div>
                ) : (
                  <div
                    className="flex items-end gap-2 px-3 py-3 border-t border-border bg-card"
                    style={{ paddingBottom: 'calc(0.75rem + env(safe-area-inset-bottom))' }}
                  >
                    <input
                      ref={inputRef}
                      type="text"
                      value={texte}
                      onChange={e => setTexte(e.target.value)}
                      onKeyDown={handleKeyDown}
                      placeholder="Votre message…"
                      className="flex-1 resize-none rounded-2xl border border-border bg-background px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-jolene-rose-400/40 disabled:opacity-50"
                      maxLength={4000}
                      disabled={envoi}
                    />
                    <button
                      type="button"
                      onClick={envoyer}
                      disabled={envoi || !texte.trim()}
                      className="rounded-full p-2.5 bg-gradient-hero text-white shadow-sm hover:opacity-90 disabled:opacity-40 transition-opacity shrink-0 min-h-[44px] min-w-[44px] flex items-center justify-center"
                      aria-label="Envoyer le message"
                    >
                      <Send className="h-4 w-4" />
                    </button>
                  </div>
                )}
              </>
            ) : (
              <div className="flex-1 flex items-center justify-center bg-jolene-lavender-50/30">
                <div className="text-center text-muted-foreground">
                  <Mascotte etat="idle" taille="lg" />
                  <p className="text-sm mt-3">Sélectionnez une conversation</p>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* ── New conversation modal (admin) ── */}
        <DialogResponsive open={showNewConvModal} onOpenChange={setShowNewConvModal}>
          <DialogResponsiveContent maxWidth="md">
            <DialogResponsiveHeader>
              <DialogResponsiveTitle>Nouvelle conversation</DialogResponsiveTitle>
            </DialogResponsiveHeader>
            <DialogResponsiveBody className="space-y-3">
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
                  <button type="button" onClick={() => { setSearchQuery(''); setSearchResults([]); }} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
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
                    type="button"
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
            </DialogResponsiveBody>
          </DialogResponsiveContent>
        </DialogResponsive>
    </div>
  );

  // Admin plateforme : conserver la sidebar admin (LayoutAdmin) au lieu de la
  // barre de navigation soignant/étab (LayoutApp), pour pouvoir naviguer.
  return isAdminPlateforme
    ? <LayoutAdmin>{contenu}</LayoutAdmin>
    : <LayoutApp role={layoutRole}>{contenu}</LayoutApp>;
}
