import { useState, useEffect, useRef } from 'react';
import { Send } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useRole } from '@/hooks/useRole';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { sanitizeText } from '@/lib/sanitize';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import { hapticImpact } from '@/lib/haptics';

interface Message {
  id: string;
  auteur_id: string;
  type_auteur: string;
  contenu: string;
  cree_le: string;
  prenom?: string;
}

interface ChatMissionProps {
  missionId: string;
  role: 'SOIGNANT' | 'ETABLISSEMENT';
  prenomUtilisateur: string;
  isAdmin?: boolean;
}

export function ChatMission({ missionId, role, prenomUtilisateur, isAdmin: isAdminProp = false }: ChatMissionProps) {
  const { user } = useAuth();
  const { role: detectedRole } = useRole();
  const isAdmin = isAdminProp || detectedRole === 'ADMIN_PLATEFORME';
  const [messages, setMessages] = useState<Message[]>([]);
  const [texte, setTexte] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Load existing messages
  useEffect(() => {
    if (!missionId) return;

    const charger = async () => {
      const { data } = await supabase
        .from('messages_mission')
        .select('id, auteur_id, type_auteur, contenu, cree_le')
        .eq('mission_id', missionId)
        .order('cree_le', { ascending: true });

      if (data) {
        setMessages(data as Message[]);
      }
    };

    charger();

    // Realtime subscription
    const channel = supabase
      .channel(`chat-mission-${missionId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages_mission',
          filter: `mission_id=eq.${missionId}`,
        },
        (payload) => {
          const nouveau = payload.new as Message;
          setMessages((prev) => {
            // Avoid duplicates
            if (prev.some((m) => m.id === nouveau.id)) return prev;
            return [...prev, nouveau];
          });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [missionId]);

  // Auto-scroll on new messages
  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages]);

  const envoyer = async () => {
    const contenuBrut = texte.trim();
    if (!contenuBrut || !user) return;

    const contenu = sanitizeText(contenuBrut);
    if (!contenu) return;

    setEnvoi(true);
    setTexte('');

    const typeAuteur = isAdmin ? 'ADMIN' : role === 'SOIGNANT' ? 'SOIGNANT' : 'ETABLISSEMENT';

    logger.debug('ChatMission envoi:', { missionId, auteur_id: user.id, type_auteur: typeAuteur, contenu_length: contenu.length });

    const { data, error } = await supabase
      .from('messages_mission')
      .insert({
        mission_id: missionId,
        auteur_id: user.id,
        type_auteur: typeAuteur,
        contenu,
      })
      .select('id, auteur_id, type_auteur, contenu, cree_le')
      .single();

    if (error) {
      logger.error('Erreur envoi message mission', error);
      setTexte(contenuBrut);
      toast.error("Impossible d'envoyer le message. Veuillez réessayer.");
    } else if (data) {
      setMessages((prev) => (prev.some((msg) => msg.id === data.id) ? prev : [...prev, data as Message]));
      hapticImpact('light');
    }

    setEnvoi(false);
    inputRef.current?.focus();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      envoyer();
    }
  };

  const estMonMessage = (msg: Message) => msg.auteur_id === user?.id;

  return (
    <div className="card-base flex flex-col" style={{ height: 'min(400px, 60vh)' }}>
      <div className="flex items-center justify-between pb-3 border-b border-border mb-3">
        <h3 className="font-semibold text-sm text-foreground">💬 Messagerie</h3>
        <span className="text-[10px] text-muted-foreground">{messages.length} message{messages.length !== 1 ? 's' : ''}</span>
      </div>

      {/* Messages area */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto space-y-3 pr-1 min-h-0">
        {messages.length === 0 && (
          <div className="flex items-center justify-center h-full">
            <p className="text-sm text-muted-foreground text-center">
              Aucun message. Envoyez le premier !
            </p>
          </div>
        )}
        {messages.map((msg) => {
          const mine = estMonMessage(msg);
          return (
            <div key={msg.id} className={`flex ${mine ? 'justify-end' : 'justify-start'}`}>
              <div
                className={`max-w-[80%] rounded-2xl px-3.5 py-2 ${
                  mine
                    ? 'bg-primary text-primary-foreground rounded-br-md'
                    : 'bg-muted text-foreground rounded-bl-md'
                }`}
              >
                {!mine && (
                  <div className="flex items-center gap-1.5 mb-0.5">
                    {msg.type_auteur === 'ADMIN' && (
                      <span className="inline-flex items-center gap-1 bg-[hsl(222,47%,11%)] text-white text-[10px] font-semibold px-2 py-0.5 rounded-full">🛡️ Admin Jolene</span>
                    )}
                    {msg.type_auteur === 'SOIGNANT' && (
                      <span className="text-[10px] font-semibold text-muted-foreground">👤 Soignant</span>
                    )}
                    {msg.type_auteur === 'ETABLISSEMENT' && (
                      <span className="text-[10px] font-semibold text-muted-foreground">🏥 Établissement</span>
                    )}
                  </div>
                )}
                <p className="text-sm whitespace-pre-wrap break-words">{msg.contenu}</p>
                <p className={`text-[9px] mt-1 text-right ${mine ? 'text-primary-foreground/60' : 'text-muted-foreground/60'}`}>
                  {format(new Date(msg.cree_le), "HH'h'mm", { locale: fr })}
                </p>
              </div>
            </div>
          );
        })}
      </div>

      {/* Input area */}
      <div className="flex items-center gap-2 pt-3 border-t border-border mt-3">
        <input
          ref={inputRef}
          type="text"
          value={texte}
          onChange={(e) => setTexte(e.target.value)}
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
