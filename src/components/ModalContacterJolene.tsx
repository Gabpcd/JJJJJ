import { useState } from 'react';
import { Send, Loader2, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

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
  const [sujet, setSujet] = useState('');
  const [corps, setCorps] = useState('');
  const [envoi, setEnvoi] = useState(false);

  if (!open) return null;

  const envoyer = async () => {
    if (!sujet.trim() || !corps.trim()) {
      toast.error('Indiquez un sujet et un message.');
      return;
    }
    setEnvoi(true);
    try {
      const { data, error } = await supabase.rpc('fn_envoyer_message_contact' as any, {
        p_sujet: sujet.trim(),
        p_corps: corps.trim(),
        p_source: source,
      });
      if (error) throw error;
      if ((data as any)?.error) { toast.error((data as any).error); return; }
      toast.success('Message envoyé à l\'équipe Jolene. Nous revenons vers vous au plus vite.');
      setSujet(''); setCorps('');
      onClose();
    } catch (err: any) {
      toast.error(err?.message || 'Échec de l\'envoi. Réessayez.');
    } finally {
      setEnvoi(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-label="Contacter Jolene">
      <div className="absolute inset-0 bg-foreground/50 backdrop-blur-sm" onClick={onClose} />
      <div className="relative bg-card border border-border rounded-2xl shadow-xl w-full max-w-md p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-foreground">✉️ Contacter Jolene</h2>
          <button onClick={onClose} className="p-1 hover:bg-muted rounded-lg" aria-label="Fermer"><X className="h-5 w-5" /></button>
        </div>
        <p className="text-sm text-muted-foreground">
          Une question, un souci, une suggestion ? Écrivez-nous, l'équipe Jolene vous répond directement.
        </p>
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
        <div className="flex gap-2 justify-end pt-1">
          <button onClick={onClose} className="btn-secondary text-sm px-4 py-2" disabled={envoi}>Annuler</button>
          <button
            onClick={envoyer}
            disabled={envoi || !sujet.trim() || !corps.trim()}
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
