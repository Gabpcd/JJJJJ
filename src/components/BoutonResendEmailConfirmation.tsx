import { useState } from 'react';
import { Loader2, Mail, CheckCircle2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

const COOLDOWN_SECONDS = 300; // 5 min rate limit

/**
 * Bouton "Renvoyer l'email de confirmation".
 *
 * Sprint 7 PR 5 — Cosmétique P2 §10.
 *
 * Rate limit côté UI 5 min (l'utilisateur ne peut pas spammer le serveur
 * SMTP) + côté Supabase (rate limit natif sur resend).
 */
export function BoutonResendEmailConfirmation({ email }: { email: string }) {
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(false);
  const [cooldownLeft, setCooldownLeft] = useState(0);
  const [sentOk, setSentOk] = useState(false);

  async function envoyer() {
    if (cooldownLeft > 0) return;
    setLoading(true);
    try {
      // Utilise l'API native Supabase pour renvoyer le mail de confirmation
      const { error } = await supabase.auth.resend({
        type: 'signup',
        email,
      });
      if (error) throw error;

      afficherNotification({
        type: 'succes',
        message: 'Email de confirmation renvoyé. Vérifiez votre boîte mail (et le dossier spam).',
      });
      setSentOk(true);
      setCooldownLeft(COOLDOWN_SECONDS);
      // Timer countdown
      const t = setInterval(() => {
        setCooldownLeft((c) => {
          if (c <= 1) { clearInterval(t); return 0; }
          return c - 1;
        });
      }, 1000);
    } catch (err: any) {
      afficherNotification({
        type: 'erreur',
        message: err?.message?.includes('rate') ? "Trop d'envois récents. Réessayez dans quelques minutes." : 'Erreur envoi email.',
      });
    } finally {
      setLoading(false);
    }
  }

  return (
    <button
      type="button"
      onClick={envoyer}
      disabled={loading || cooldownLeft > 0}
      className="btn-secondary text-sm inline-flex items-center gap-2 disabled:opacity-50"
    >
      {loading
        ? <Loader2 className="h-4 w-4 animate-spin" />
        : sentOk
          ? <CheckCircle2 className="h-4 w-4 text-success" />
          : <Mail className="h-4 w-4" />}
      {cooldownLeft > 0
        ? `Réessayer dans ${Math.floor(cooldownLeft / 60)}:${(cooldownLeft % 60).toString().padStart(2, '0')}`
        : sentOk
          ? 'Renvoyer'
          : "Renvoyer l'email de confirmation"}
    </button>
  );
}
