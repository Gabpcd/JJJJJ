import { useState } from 'react';
import { Send, Loader2, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useAuth } from '@/contexts/AuthContext';
import { CaptchaTurnstile, TURNSTILE_REQUIRED } from '@/components/CaptchaTurnstile';

interface Props {
  open: boolean;
  onClose: () => void;
  /** Contexte d'où le message est envoyé (ex. 'aide', page courante). */
  source?: string;
}

/**
 * Modal "Contacter Jolene" : le message est enregistré côté admin (table
 * messages_contact) + relayé par email à support@jolene.app via la RPC
 * fn_envoyer_message_contact.
 */
export function ModalContacterJolene({ open, onClose, source = 'aide' }: Props) {
  const { user } = useAuth();
  const [nom, setNom] = useState('');
  const [email, setEmail] = useState('');
  const [sujet, setSujet] = useState('');
  const [corps, setCorps] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);
  const [captchaKey, setCaptchaKey] = useState(0);

  if (!open) return null;

  const envoyer = async () => {
    if (!sujet.trim() || !corps.trim()) {
      toast.error('Indiquez un sujet et un message.');
      return;
    }
    if (!user && (!nom.trim() || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))) {
      toast.error('Indiquez votre nom et une adresse e-mail valide.');
      return;
    }
    if (!user && TURNSTILE_REQUIRED && !turnstileToken) {
      toast.error('Merci de confirmer que vous n’êtes pas un robot.');
      return;
    }
    setEnvoi(true);
    try {
      const { data, error } = user
        ? await supabase.rpc('fn_envoyer_message_contact' as any, {
            p_sujet: sujet.trim(),
            p_corps: corps.trim(),
            p_source: source,
          })
        : await supabase.functions.invoke('contact-form', {
            body: {
              nom: nom.trim(),
              email: email.trim(),
              sujet: sujet.trim(),
              message: `[Source : ${source}]\n\n${corps.trim()}`,
              hp: '',
              turnstileToken,
            },
          });
      if (error) throw error;
      if ((data as any)?.error) { toast.error((data as any).error); return; }
      toast.success('Message envoyé à l\'équipe Jolene. Nous revenons vers vous au plus vite.');
      setNom(''); setEmail(''); setSujet(''); setCorps(''); setTurnstileToken(null);
      onClose();
    } catch (err: any) {
      toast.error(err?.message || 'Échec de l\'envoi. Réessayez.');
    } finally {
      setEnvoi(false);
      if (!user) {
        setTurnstileToken(null);
        setCaptchaKey((k) => k + 1);
      }
    }
  };

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-label="Contacter Jolene">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onClose} />
      <div className="relative bg-card border border-border rounded-2xl shadow-xl w-full max-w-md p-6 space-y-4 max-h-[calc(100dvh-2rem)] overflow-y-auto">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-foreground">✉️ Contacter Jolene</h2>
          <button onClick={onClose} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer"><X className="h-5 w-5" /></button>
        </div>
        <p className="text-sm text-muted-foreground">
          Une question, un souci, une suggestion ? Écrivez-nous, l'équipe Jolene vous répond directement.
        </p>
        {!user && (
          <div className="grid sm:grid-cols-2 gap-3">
            <div>
              <label htmlFor="contact-modal-nom" className="block text-xs font-medium text-foreground mb-1">Votre nom</label>
              <input id="contact-modal-nom" value={nom} onChange={(e) => setNom(e.target.value)} maxLength={120} className="input-base" autoComplete="name" />
            </div>
            <div>
              <label htmlFor="contact-modal-email" className="block text-xs font-medium text-foreground mb-1">Votre e-mail</label>
              <input id="contact-modal-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} maxLength={160} className="input-base" autoComplete="email" />
            </div>
          </div>
        )}
        <div>
          <label htmlFor="contact-sujet" className="block text-xs font-medium text-foreground mb-1">Sujet</label>
          <input
            id="contact-sujet"
            value={sujet}
            onChange={(e) => setSujet(e.target.value)}
            maxLength={150}
            placeholder="Ex. Problème de pointage, question facturation…"
            className="input-base"
          />
        </div>
        <div>
          <label htmlFor="contact-corps" className="block text-xs font-medium text-foreground mb-1">Votre message</label>
          <textarea
            id="contact-corps"
            value={corps}
            onChange={(e) => setCorps(e.target.value)}
            rows={5}
            maxLength={4000}
            placeholder="Décrivez votre demande…"
            className="input-base resize-none"
          />
        </div>
        {!user && (
          <CaptchaTurnstile
            key={captchaKey}
            className="flex justify-center"
            onVerify={setTurnstileToken}
            onExpire={() => setTurnstileToken(null)}
            onError={() => setTurnstileToken(null)}
          />
        )}
        <div className="flex gap-2 justify-end pt-1">
          <button onClick={onClose} className="btn-secondary text-sm px-4 py-2" disabled={envoi}>Annuler</button>
          <button
            onClick={envoyer}
            disabled={envoi || !sujet.trim() || !corps.trim() || (!user && (!nom.trim() || !email.trim() || (TURNSTILE_REQUIRED && !turnstileToken)))}
            className="btn-primary text-sm px-4 py-2 inline-flex items-center gap-2 disabled:opacity-50"
          >
            {envoi ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Envoyer
          </button>
        </div>
      </div>
    </div>
  );
}

export default ModalContacterJolene;
