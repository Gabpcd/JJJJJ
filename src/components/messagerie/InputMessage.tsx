/**
 * `<InputMessage />` — Sprint 10-B PR 3
 *
 * Composant d'entrée pour envoyer un message dans une conversation.
 *
 * Responsabilités :
 *  - Textarea auto-grow (max ~100px hauteur)
 *  - Émet typing event Realtime au focus (fn_typing_start) + stop au blur
 *    ou après 3s d'inactivité (fn_typing_stop)
 *  - Validation côté serveur via edge function messagerie-validate
 *    (Sprint 10-A v3 PR 2) AVANT envoi
 *  - Si retour ANTI_LEAK_REFUSE : ouvre ModaleEducativeAntiLeak (PR 4) sans
 *    effacer le message — l'utilisateur peut l'éditer
 *  - Si retour 200 OK : le message est déjà inséré atomiquement côté serveur
 *  - Indicateur caractères restants si > 3500 (sur 4000 max)
 *  - Disabled si conversation archivée
 *
 * Style Y2K : BoutonY2K primary gradient pour le bouton envoyer.
 */
import { useState, useRef, useEffect, useCallback } from 'react';
import { Send } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { ModaleEducativeAntiLeak, type DetectedType } from './ModaleEducativeAntiLeak';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import { hapticImpact } from '@/lib/haptics';
import { envoyerMessageAvecAntiFuite } from '@/lib/messagerieEnvoi';

const MAX_LENGTH = 4000;
const WARN_THRESHOLD = 3500;
const TYPING_IDLE_MS = 3000;
const TYPING_REFRESH_MS = 2000;

interface Props {
  conversationId: string;
  /** Si true, la conversation est archivée → input désactivé. */
  archived?: boolean;
  /** Callback après envoi réussi (rafraîchir la liste conv côté parent). */
  onSent?: (messageId: string) => void | Promise<void>;
}

export function InputMessage({ conversationId, archived = false, onSent }: Props) {
  const [texte, setTexte] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [modaleAntiLeak, setModaleAntiLeak] = useState<DetectedType | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isTypingRef = useRef(false);
  const lastTypingSentAtRef = useRef(0);
  // Le state React n'est mis à jour qu'au prochain rendu. Ce verrou synchrone
  // empêche donc deux Enter/clics dans le même tick de créer deux messages.
  const envoiRef = useRef(false);

  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 100) + 'px';
  }, [texte]);

  const stopTyping = useCallback(() => {
    if (!isTypingRef.current) return;
    isTypingRef.current = false;
    lastTypingSentAtRef.current = 0;
    supabase.rpc('fn_typing_stop' as any, { p_conversation_id: conversationId })
      .then(
        ({ error }) => { if (error) logger.debug('fn_typing_stop skip', error); },
        (error) => logger.debug('fn_typing_stop skip', error),
      );
  }, [conversationId]);

  const tickTyping = useCallback(() => {
    if (archived) return;
    const maintenant = Date.now();
    if (!isTypingRef.current
        || maintenant - lastTypingSentAtRef.current >= TYPING_REFRESH_MS) {
      isTypingRef.current = true;
      lastTypingSentAtRef.current = maintenant;
      supabase.rpc('fn_typing_start' as any, { p_conversation_id: conversationId })
        .then(
          ({ error }) => { if (error) logger.debug('fn_typing_start skip', error); },
          (error) => logger.debug('fn_typing_start skip', error),
        );
    }
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    typingTimerRef.current = setTimeout(stopTyping, TYPING_IDLE_MS);
  }, [archived, conversationId, stopTyping]);

  useEffect(() => {
    return () => {
      if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
      stopTyping();
    };
  }, [stopTyping]);

  const envoyer = async () => {
    if (archived || envoiRef.current) return;
    const contenuBrut = texte.trim();
    if (!contenuBrut) return;

    const contenu = contenuBrut;

    envoiRef.current = true;
    setEnvoi(true);

    try {
      const resultat = await envoyerMessageAvecAntiFuite(conversationId, contenu);
      if (!resultat.success) {
        if (resultat.error === 'ANTI_LEAK_REFUSE' && resultat.detectedType) {
          setModaleAntiLeak(resultat.detectedType);
        } else if (resultat.error === 'RATE_LIMIT') {
          toast.error('Trop de messages envoyés. Patientez quelques secondes.');
        } else if (resultat.error === 'CONTENT_TOO_LARGE') {
          toast.error('Message trop long.');
        } else if (resultat.error === 'CONVERSATION_ARCHIVEE') {
          toast.error('Cette conversation est archivée.');
        } else {
          logger.error(
            'messagerie-validate atomic send error',
            resultat.transportError || resultat.error,
          );
          toast.error("Impossible d'envoyer le message. Veuillez réessayer.");
        }
        return;
      }

      stopTyping();
      setTexte('');
      hapticImpact('light');
      // Le parent recharge explicitement la ligne confirmée. Le Realtime reste
      // utile pour l'autre interlocuteur, mais n'est pas une garantie d'écho :
      // l'INSERT peut précéder l'état SUBSCRIBED du canal local.
      await onSent?.(resultat.messageId!);
    } finally {
      envoiRef.current = false;
      setEnvoi(false);
      textareaRef.current?.focus();
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      void envoyer();
    }
  };

  const restantes = MAX_LENGTH - texte.length;
  const afficherCompteur = texte.length >= WARN_THRESHOLD;

  if (archived) {
    return (
      <div className="px-4 py-3 bg-muted/40 border-t border-border text-center text-xs text-muted-foreground italic">
        Conversation archivée — lecture seule.
      </div>
    );
  }

  return (
    <>
      <div
        className="flex items-end gap-2 px-3 py-3 border-t border-border bg-card"
        style={{ paddingBottom: 'calc(0.75rem + env(safe-area-inset-bottom))' }}
      >
        <textarea
          ref={textareaRef}
          value={texte}
          onChange={(e) => {
            setTexte(e.target.value.slice(0, MAX_LENGTH));
            tickTyping();
          }}
          onKeyDown={handleKeyDown}
          onFocus={tickTyping}
          onBlur={stopTyping}
          placeholder="Votre message…"
          rows={1}
          maxLength={MAX_LENGTH}
          disabled={envoi}
          className="flex-1 resize-none rounded-2xl border border-border bg-background px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-jolene-rose-400/40 disabled:opacity-50 transition-shadow"
          style={{ maxHeight: 100, minHeight: 40 }}
          aria-label="Saisir un message"
        />
        <BoutonY2K
          variant="primary"
          size="md"
          onClick={envoyer}
          loading={envoi}
          disabled={envoi || !texte.trim()}
          aria-label="Envoyer le message"
          className="!p-2.5 !min-w-0"
        >
          {!envoi && <Send className="h-4 w-4" />}
        </BoutonY2K>
      </div>
      {afficherCompteur && (
        <p className={`text-[10px] text-right pr-4 pb-1 ${restantes < 100 ? 'text-destructive' : 'text-muted-foreground'}`}>
          {restantes} caractères restants
        </p>
      )}
      <ModaleEducativeAntiLeak
        ouvert={modaleAntiLeak !== null}
        onFermer={() => setModaleAntiLeak(null)}
        detectedType={modaleAntiLeak}
      />
    </>
  );
}
