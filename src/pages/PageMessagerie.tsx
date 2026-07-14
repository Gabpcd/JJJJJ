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
 * Le panneau de détail partage InputMessage et useConversationRealtime avec
 * les chats de mission : anti-fuite, saisie et présence ont donc un seul flux.
 */
import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import { MessageCircle, ArrowLeft, Shield, Plus, Search, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { resoudreUserIdEtablissement } from '@/hooks/useOuvrirConversation';
import { useConversationRealtime, type PresenceStatus } from '@/hooks/useConversationRealtime';
import { useAuth } from '@/contexts/AuthContext';
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
import {
  chargerInterlocuteursConversations,
  cleInterlocuteur,
  type InterlocuteurConversation,
} from '@/lib/messagerieInterlocuteurs';
import { InputMessage } from '@/components/messagerie/InputMessage';
import { BloquerUtilisateur } from '@/components/BloquerUtilisateur';

interface Conversation {
  id: string;
  participant_1_id: string;
  participant_2_id: string;
  mission_id: string | null;
  dernier_message_le: string | null;
  cree_le: string;
  archived_at: string | null;
  etablissement_id?: string | null;
  soignant_id?: string | null;
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

function formatPresence(
  presence: PresenceStatus,
  lastSeen: Date | null,
): string {
  if (presence === 'ONLINE') return 'En ligne';
  if (presence === 'AWAY') return 'Absent';
  if (!lastSeen) return 'Hors ligne';
  return `Vu ${formatDistanceToNowStrict(lastSeen, { addSuffix: true, locale: fr })}`;
}

export default function PageMessagerie({ role }: PageMessagerieProps) {
  usePageTitle('Messagerie');
  const { user } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const convParam = searchParams.get('conv');

  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [loading, setLoading] = useState(true);
  // La sélection est dérivée de l'URL : le bouton Retour Android/iOS et les
  // liens de notification restent ainsi synchronisés avec l'interface.
  const selectedConvId = convParam;
  const [messages, setMessages] = useState<Message[]>([]);
  const [loadingMessages, setLoadingMessages] = useState(false);
  const [conversationCibleIntrouvable, setConversationCibleIntrouvable] = useState<string | null>(null);
  const [filtre, setFiltre] = useState('');
  const [tab, setTab] = useState<'ACTIVES' | 'ARCHIVEES'>('ACTIVES');
  const scrollRef = useRef<HTMLDivElement>(null);
  const chargementConversationsRef = useRef(0);

  const [showNewConvModal, setShowNewConvModal] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);

  const isAdminPlateforme = role === 'ADMIN_PLATEFORME';
  const isAdmin = isAdminPlateforme;

  const chargerConversations = useCallback(async () => {
    if (!user) return;
    const numeroChargement = ++chargementConversationsRef.current;

    type ApercuConversation = {
      id: string;
      participant_1_id: string;
      participant_2_id: string;
      mission_id: string | null;
      etablissement_id: string | null;
      soignant_id: string | null;
      dernier_message_le: string | null;
      cree_le: string;
      archived_at: string | null;
      autre_id: string;
      dernier_contenu: string | null;
      non_lus: number | string;
      mission_intitule: string | null;
      ordre_le: string;
    };

    const convs: ApercuConversation[] = [];
    const dejaVues = new Set<string>();
    let avant: string | null = null;
    let avantId: string | null = null;
    let erreurChargement: unknown = null;

    // Pagination keyset : chaque aperçu/non-lu est agrégé côté SQL. On ne
    // télécharge donc jamais tous les messages d'un fil pour calculer la liste.
    for (let page = 0; page < 100; page += 1) {
      const { data, error } = await supabase.rpc(
        'fn_lister_conversations_messagerie' as any,
        {
          p_avant: avant,
          p_avant_id: avantId,
          p_limite: 100,
        } as any,
      );
      if (numeroChargement !== chargementConversationsRef.current) return;
      if (error) {
        erreurChargement = error;
        break;
      }

      const lot = ((data || []) as unknown) as ApercuConversation[];
      lot.forEach((conversation) => {
        if (!dejaVues.has(conversation.id)) {
          dejaVues.add(conversation.id);
          convs.push(conversation);
        }
      });
      if (lot.length < 100) break;

      const derniere = lot[lot.length - 1];
      if (!derniere?.ordre_le || !derniere.id
          || (derniere.ordre_le === avant && derniere.id === avantId)) break;
      avant = derniere.ordre_le;
      avantId = derniere.id;
    }

    if (erreurChargement) {
      logger.error('PageMessagerie.chargerConversations error', erreurChargement);
      setLoading(false);
      return;
    }

    const cibleIntrouvable = !!convParam
      && !convs.some(conversation => conversation.id === convParam);

    if (convs.length === 0) {
      setConversations([]);
      setConversationCibleIntrouvable(cibleIntrouvable ? convParam : null);
      setLoading(false);
      return;
    }

    const convIds = convs.map(c => c.id);
    let interlocuteurs = new Map<string, InterlocuteurConversation>();
    try {
      interlocuteurs = await chargerInterlocuteursConversations(convIds);
    } catch (error) {
      logger.error('fn_interlocuteurs_conversations error', error);
    }

    const resolveUserName = (conversationId: string, uid: string) => {
      const info = interlocuteurs.get(cleInterlocuteur(conversationId, uid));
      if (info) return `${info.prenom} ${info.nom}`.trim();
      return 'Jolene';
    };

    const enriched: Conversation[] = convs.map(c => {
      const autreId = c.autre_id;
      const info = interlocuteurs.get(cleInterlocuteur(c.id, autreId));

      const isJolene = info?.est_jolene ?? true;
      let displayPrenom = info?.prenom || 'Jolene';
      let displayNom = info?.nom || '';
      if (isAdmin) {
        displayPrenom = resolveUserName(c.id, c.participant_1_id);
        displayNom = `↔ ${resolveUserName(c.id, c.participant_2_id)}`;
      }

      return {
        ...c,
        archived_at: c.archived_at || null,
        autre_id: autreId,
        autre_prenom: displayPrenom,
        autre_nom: displayNom,
        autre_avatar: isJolene ? null : (info?.avatar_url || null),
        dernier_contenu: c.dernier_contenu || null,
        non_lus: Number(c.non_lus) || 0,
        is_jolene: isJolene,
        mission_intitule: c.mission_intitule || null,
      };
    });

    if (numeroChargement !== chargementConversationsRef.current) return;
    setConversations(enriched);
    setConversationCibleIntrouvable(cibleIntrouvable ? convParam : null);
    setLoading(false);
  }, [user, isAdmin, convParam]);

  useEffect(() => {
    void chargerConversations();
    return () => { chargementConversationsRef.current += 1; };
  }, [chargerConversations]);

  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel(`messagerie-liste-${user.id}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages_chat',
      }, (payload) => {
        const message = payload.new as Message;
        setConversations((precedentes) => {
          const conversation = precedentes.find(c => c.id === message.conversation_id);
          if (!conversation) return precedentes;
          const entrant = conversation.soignant_id
            ? role === 'ADMIN_ETABLISSEMENT'
              ? message.auteur_id === conversation.soignant_id
              : role === 'SOIGNANT'
                ? message.auteur_id !== conversation.soignant_id
                : message.auteur_id !== user.id
            : message.auteur_id !== user.id;
          return precedentes
            .map(c => c.id === message.conversation_id
              ? {
                  ...c,
                  dernier_contenu: message.contenu,
                  dernier_message_le: message.cree_le,
                  non_lus: entrant && selectedConvId !== c.id
                    ? c.non_lus + 1
                    : c.non_lus,
                }
              : c)
            .sort((a, b) => new Date(
              b.dernier_message_le || b.cree_le,
            ).getTime() - new Date(
              a.dernier_message_le || a.cree_le,
            ).getTime());
        });
      })
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'conversations',
      }, () => { void chargerConversations(); })
      .subscribe();

    return () => { void supabase.removeChannel(channel); };
  }, [chargerConversations, role, selectedConvId, user]);

  useEffect(() => {
    if (!selectedConvId) {
      setMessages([]);
      setLoadingMessages(false);
      return;
    }
    let cancelled = false;
    setMessages([]);
    setLoadingMessages(true);

    const load = async () => {
      const { data, error } = await supabase
        .from('messages_chat')
        .select('id, conversation_id, auteur_id, contenu, est_admin, lu, cree_le')
        .eq('conversation_id', selectedConvId)
        .order('cree_le', { ascending: false })
        .limit(500);

      if (cancelled) return;
      if (error) {
        logger.error('PageMessagerie.chargerMessages error', error);
        setMessages([]);
        setLoadingMessages(false);
        return;
      }

      const messagesRecents = ([...((data as Message[]) || [])]).reverse();
      setMessages(prev => {
        const fusion = new Map(messagesRecents.map(message => [message.id, message]));
        prev
          .filter(message => message.conversation_id === selectedConvId)
          .forEach(message => fusion.set(message.id, message));
        return [...fusion.values()].sort(
          (a, b) => new Date(a.cree_le).getTime() - new Date(b.cree_le).getTime(),
        );
      });
      setLoadingMessages(false);

      supabase.rpc('fn_marquer_messages_lus', { p_conversation_id: selectedConvId }).then(({ error }) => {
        if (cancelled) return;
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
            .then(
              ({ error }) => {
                if (error) handleErrorSilent(error, 'PageMessagerie.marquer_messages_lus');
              },
              (err) => handleErrorSilent(err, 'PageMessagerie.marquer_messages_lus'),
            );
        }
      })
      .subscribe();

    return () => {
      cancelled = true;
      supabase.removeChannel(channel);
    };
  }, [selectedConvId, user]);

  const confirmerMessageEnvoye = useCallback(async (messageId: string) => {
    if (!selectedConvId) return;
    const { data, error } = await supabase
      .from('messages_chat')
      .select('id, conversation_id, auteur_id, contenu, est_admin, lu, cree_le')
      .eq('id', messageId)
      .eq('conversation_id', selectedConvId)
      .maybeSingle();

    if (error || !data) {
      logger.error('PageMessagerie.confirmerMessageEnvoye error', error);
    } else {
      const message = data as Message;
      setMessages(prev => prev.some(item => item.id === message.id)
        ? prev
        : [...prev, message].sort(
          (a, b) => new Date(a.cree_le).getTime() - new Date(b.cree_le).getTime(),
        ));
    }
    await chargerConversations();
  }, [chargerConversations, selectedConvId]);

  const selectConv = (convId: string) => {
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
    sData?.forEach(s => results.push({ id: s.id, type: 'soignant', label: `${s.prenom} ${s.nom}`, sub: s.email || '', avatar: s.avatar_url }));
    eData?.forEach(e => results.push({ id: e.id, type: 'etablissement', label: e.nom, sub: e.email_contact || '', avatar: e.logo_url }));

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
  const showMobileChat = !!selectedConv;
  const isArchivedSelected = !!selectedConv?.archived_at;
  const realtimeAutreId = !isAdminPlateforme && selectedConv && !selectedConv.is_jolene
    ? selectedConv.autre_id
    : null;
  const { typing, presence, lastSeen } = useConversationRealtime({
    conversationId: selectedConv?.id ?? null,
    autreUserId: realtimeAutreId,
  });

  useEffect(() => {
    if (!selectedConvId || conversationCibleIntrouvable !== selectedConvId) return;
    toast.error("Cette conversation n'est plus accessible.");
    setSearchParams({}, { replace: true });
  }, [conversationCibleIntrouvable, selectedConvId, setSearchParams]);

  useEffect(() => {
    scrollRef.current?.scrollTo({
      top: scrollRef.current.scrollHeight,
      behavior: 'smooth',
    });
  }, [messages, typing]);

  const layoutRole = role === 'ADMIN_PLATEFORME' ? 'ADMIN_PLATEFORME' : role === 'ADMIN_ETABLISSEMENT' ? 'ADMIN_ETABLISSEMENT' : 'SOIGNANT';

  const contenu = (
    <div className="flex flex-col h-[calc(100dvh-14rem)] md:h-[calc(100dvh-8rem)]">
        <div className="flex flex-1 rounded-2xl border border-jolene-rose-200/40 overflow-hidden bg-card min-h-0 shadow-sm">
          {/* ── Conversation list ── */}
          <div className={`w-full md:w-[380px] md:border-r border-border flex flex-col bg-jolene-lavender-50/30 ${showMobileChat ? 'hidden md:flex' : 'flex'}`}>
            <div className="px-4 pt-4 pb-2 border-b border-border bg-card/85 backdrop-blur-sm sticky top-0 z-10">
              <div className="flex items-center justify-between mb-3">
                <h1 className="font-bold text-foreground flex items-center gap-2 text-base">
                  <MessageCircle className="h-5 w-5 text-jolene-rose-500" />
                  Messagerie
                </h1>
                {isAdmin && (
                  <BoutonY2K size="sm" variant="secondary" onClick={() => setShowNewConvModal(true)} className="rounded-full" iconeGauche={<Plus className="h-4 w-4" />}>
                    Nouvelle
                  </BoutonY2K>
                )}
              </div>
              <div className="relative mb-2">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  aria-label="Rechercher une conversation"
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
                    onClick={() => setSearchParams({}, { replace: true })}
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
                    {realtimeAutreId && (
                      <p
                        aria-live="polite"
                        className={`text-[11px] truncate ${
                          typing
                            ? 'italic text-jolene-rose-500'
                            : 'text-muted-foreground'
                        }`}
                      >
                        {typing
                          ? "Est en train d'écrire…"
                          : formatPresence(presence, lastSeen)}
                      </p>
                    )}
                  </div>
                  {!selectedConv.is_jolene
                    && selectedConv.autre_id
                    && selectedConv.autre_id !== '00000000-0000-0000-0000-000000000000' && (
                      <BloquerUtilisateur
                        cibleId={selectedConv.autre_id}
                        variant="lien"
                        libelleCible={role === 'SOIGNANT' && selectedConv.etablissement_id
                          ? 'l’établissement'
                          : undefined}
                      />
                    )}
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
                      const mine = msg.est_admin
                        ? msg.auteur_id === user?.id
                        : role === 'ADMIN_ETABLISSEMENT'
                          && selectedConv.soignant_id
                          ? msg.auteur_id !== selectedConv.soignant_id
                          : msg.auteur_id === user?.id;
                      const messageEquipe = !msg.est_admin
                        && mine
                        && msg.auteur_id !== user?.id;
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
                            {messageEquipe && (
                              <p className="text-[10px] font-semibold mb-0.5 text-white/85">
                                Équipe établissement
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
                  {typing && (
                    <div className="flex justify-start" aria-live="polite">
                      <div
                        aria-label="L'interlocuteur écrit"
                        className="inline-flex gap-1 rounded-2xl rounded-bl-md border border-border bg-card px-3 py-2"
                      >
                        <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-jolene-rose-400" style={{ animationDelay: '0ms' }} />
                        <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-jolene-rose-400" style={{ animationDelay: '150ms' }} />
                        <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-jolene-rose-400" style={{ animationDelay: '300ms' }} />
                      </div>
                    </div>
                  )}
                </div>

                <InputMessage
                  key={selectedConv.id}
                  conversationId={selectedConv.id}
                  archived={isArchivedSelected}
                  onSent={confirmerMessageEnvoye}
                />
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
                  aria-label="Rechercher un soignant ou un établissement"
                  placeholder="Rechercher un soignant ou établissement…"
                  value={searchQuery}
                  onChange={e => setSearchQuery(e.target.value)}
                  className="pl-9"
                  autoFocus
                />
                {searchQuery && (
                  <button type="button" aria-label="Effacer la recherche" onClick={() => { setSearchQuery(''); setSearchResults([]); }} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
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
