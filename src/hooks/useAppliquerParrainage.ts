/**
 * useAppliquerParrainage — 7f (Lot 7 v2 §5) : consomme le code parrainage
 * capté à l'entrée (?ref= / ?parrain=) et crée le lien parrain↔filleul.
 *
 * FIX CRITIQUE : depuis le Sprint 17-A le code était capté (sessionStorage +
 * attribution localStorage) mais fn_appliquer_parrainage n'était JAMAIS
 * appelée — aucun parrainage soignant ne se créait, le K-factor était faux.
 *
 * Point de consommation : première session authentifiée (l'inscription passe
 * par la confirmation email, auth.uid() n'existe pas encore au signup).
 * Fenêtre d'attribution : 30 jours (captured_at de l'attribution).
 */
import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';

const CLE_FAIT = 'jolene.parrainage_appliqué';
const FENETRE_JOURS = 30;

function lireCode(): string | null {
  try {
    const session = sessionStorage.getItem('jolene.parrainage_code');
    if (session && !/^ETB-/i.test(session)) return session.toUpperCase();
    // Fallback : attribution localStorage (survit à la confirmation email
    // qui rouvre le navigateur), bornée à 30 jours.
    const raw = localStorage.getItem('jolene.attribution');
    if (raw) {
      const attr = JSON.parse(raw) as { ref_code?: string; captured_at?: string };
      if (attr.ref_code && !/^ETB-/i.test(attr.ref_code) && attr.captured_at
          && Date.now() - new Date(attr.captured_at).getTime() < FENETRE_JOURS * 86_400_000) {
        return attr.ref_code.toUpperCase();
      }
    }
  } catch { /* noop */ }
  return null;
}

export function useAppliquerParrainage(userId: string | undefined | null) {
  useEffect(() => {
    if (!userId || localStorage.getItem(CLE_FAIT)) return;
    const code = lireCode();
    if (!code) return;

    supabase.rpc('fn_appliquer_parrainage' as any, { p_code: code }).then(({ data, error }) => {
      // Quel que soit le résultat, on ne retente pas en boucle : la RPC est
      // définitive (déjà parrainé, code invalide, auto-parrainage…).
      localStorage.setItem(CLE_FAIT, '1');
      try { sessionStorage.removeItem('jolene.parrainage_code'); } catch { /* noop */ }
      if (error) { logger.error('fn_appliquer_parrainage', error); return; }
      const res = data as any;
      if (res?.success) {
        toast.success('🎁 Parrainage activé — vous gagnerez chacun une prime quand tu auras réalisé tes premières missions.');
      } else if (res?.error) {
        logger.debug('parrainage non appliqué', res.error);
      }
    });
  }, [userId]);
}
