import { useState } from 'react';
import { Loader2, RotateCcw } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { useAuth } from '@/contexts/AuthContext';

/**
 * Bouton "Refaire le tutoriel" pour paramètres soignant + étab.
 *
 * Sprint 6 PR 5 — Fix P1-1 audit Sprint 5.
 *
 * Reset DB (fn_reset_onboarding) + localStorage. Au prochain login,
 * l'OnboardingGuide se réaffiche depuis la première étape.
 */
export function BoutonResetOnboarding() {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(false);

  async function reset() {
    if (!confirm('Refaire le tutoriel ? Vous le verrez à votre prochaine connexion.')) return;
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_reset_onboarding' as any);
    setLoading(false);
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: error?.message || 'Erreur reset.' });
      return;
    }
    if (user?.id) {
      localStorage.removeItem(`onboarding_complete_${user.id}`);
    }
    afficherNotification({
      type: 'succes',
      message: 'Tutoriel réinitialisé. Vous le reverrez à votre prochaine connexion.',
    });
  }

  return (
    <button
      type="button"
      onClick={reset}
      disabled={loading}
      className="btn-secondary text-sm inline-flex items-center gap-2 disabled:opacity-50"
    >
      {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RotateCcw className="h-4 w-4" />}
      Refaire le tutoriel
    </button>
  );
}
