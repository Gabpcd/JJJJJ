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
 *  - Si retour 200 OK : appel fn_envoyer_message pour insérer en base
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
import { sanitizeText } from '@/lib/sanitize';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';
import { hapticImpact } from '@/lib/haptics';

const MAX_LENGTH = 4000;
const WARN_THRESHOLD = 3500;
const TYPING_IDLE_MS = 3000;

interface Props {
  conversationId: string;
  /** Si true, la conversation est archivée → input désactivé. */
  archived?: boolean;
  /** Callback après envoi réussi (rafraîchir la liste conv côté parent). */
  onSent?: () => void;
}

export function InputMessage({ conversationId, archived = false, onSent }: Props) {
  const [texte, setTexte] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [modaleAntiLeak, setModaleAntiLeak] = useState<DetectedType | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isTypingRef = useRef(false);

  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 100) + 'px';
  }, [texte]);

  const stopTyping = useCallback(() => {
    if (!isTypingRef.current) return;
    isTypingRef.current = false;
    supabase.rpc('fn_typing_stop' as any, { p_conversation_id: conversationId })
      .then(undefined, (err) => logger.debug('fn_typing_stop skip', err));
  }, [conversationId]);

  const tickTyping = useCallback(() => {
    if (archived) return;
    if (!isTypingRef.current) {
      isTypingRef.current = true;
      supabase.rpc('fn_typing_start' as any, { p_conversation_id: conversationId })
        .then(undefined, (err) => logger.debug('fn_typing_start skip', err));
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
    if (archived) return;
    const contenuBrut = texte.trim();
    if (!contenuBrut) return;

    const contenu = sanitizeText(contenuBrut);
    if (!contenu) return;

    setEnvoi(true);

    try {
      const { data: validateData, error: validateErr } = await supabase.functions.invoke('messagerie-validate', {
        body: { conversation_id: conversationId, content: contenu },
      });

      if (validateErr) {
        const ctx = validateErr.context as { body?: any; status?: number } | undefined;
        const payload = ctx?.body;
        if (payload?.error === 'ANTI_LEAK_REFUSE' && payload?.detected_type) {
          setModaleAntiLeak(payload.detected_type as DetectedType);
          return;
        }
        if (payload?.error === 'RATE_LIMIT') {
          toast.error('Trop de messages envoyés. Patientez quelques secondes.');
          return;
        }
        if (payload?.error === 'CONTENT_TOO_LARGE') {
          toast.error('Message trop long.');
          return;
        }
        logger.error('messagerie-validate error', validateErr);
        toast.error("Validation du message impossible. Veuillez réessayer.");
        return;
      }

      if (validateData && (validateData as any).error === 'ANTI_LEAK_REFUSE') {
        setModaleAntiLeak((validateData as any).detected_type as DetectedType);
        return;
      }

      // 7e-1 (§6.4) : coordonnées MASQUÉES, message envoyé quand même.
      // Pédagogie la 1ʳᵉ fois seulement ; ensuite un simple toast discret.
      if ((validateData as any)?.leak_masque) {
        if (!localStorage.getItem('jolene_antileak_pedagogie_vue')) {
          localStorage.setItem('jolene_antileak_pedagogie_vue', '1');
          setModaleAntiLeak((validateData as any).detected_type as DetectedType);
        } else {
          toast.info('Coordonnées masquées — elles se partagent automatiquement à la confirmation de la mission.');
        }
      }

      const contenuSanitized = (validateData as any)?.sanitized_content || contenu;

      const { data, error } = await supabase.rpc('fn_envoyer_message', {
        p_conversation_id: conversationId,
        p_contenu: contenuSanitized,
      });

      if (error || (data && typeof data === 'object' && (data as any).error)) {
        logger.error('fn_envoyer_message error', error || data);
        toast.error("Impossible d'envoyer le message.");
        return;
      }

      stopTyping();
      setTexte('');
      hapticImpact('light');
      onSent?.();
    } finally {
      setEnvoi(false);
      textareaRef.current?.focus();
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      envoyer();
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
