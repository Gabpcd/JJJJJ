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
const REFUS_DEFINITIFS = new Set([
  'Code de parrainage invalide',
  'Vous ne pouvez pas vous parrainer vous-même',
  'Le parrain a atteint la limite de 20 filleuls validés',
  'Vous avez déjà appliqué un code de parrainage',
]);
type Reponse = { data: unknown; error: unknown };
// Partager la requête entre remontages (dont StrictMode), jamais entre comptes.
const enCours = new Map<string, Promise<Reponse>>();

function dejaTraite(cle: string, code: string): boolean {
  try { return localStorage.getItem(cle) === code; } catch { return false; }
}

function lireCode(): string | null {
  try {
    const session = sessionStorage.getItem('jolene.parrainage_code');
    if (session && !/^ETB-/i.test(session)) return session.toUpperCase();
    // Fallback : attribution localStorage (survit à la confirmation email
    // qui rouvre le navigateur), bornée à 30 jours.
    const raw = localStorage.getItem('jolene.attribution');
    if (raw) {
      const attr = JSON.parse(raw) as { ref_code?: string; captured_at?: string };
      const age = attr.captured_at ? Date.now() - new Date(attr.captured_at).getTime() : NaN;
      if (typeof attr.ref_code === 'string' && !/^ETB-/i.test(attr.ref_code)
          && age >= 0 && age < FENETRE_JOURS * 86_400_000) {
        return attr.ref_code.toUpperCase();
      }
    }
  } catch { /* noop */ }
  return null;
}

export function useAppliquerParrainage(userId: string | undefined | null) {
  useEffect(() => {
    if (!userId) return;
    const code = lireCode();
    if (!code) return;
    // L'ancien marqueur global ne désignait aucun compte ni code. On ne peut
    // pas l'utiliser : la RPC confirme elle-même un parrainage déjà enregistré.
    const cle = `${CLE_FAIT}:${userId}`;
    if (dejaTraite(cle, code)) return;
    const cleRequete = `${userId}:${code}`;
    let actif = true;
    let requete = enCours.get(cleRequete);
    if (!requete) {
      requete = Promise.resolve(supabase.rpc('fn_appliquer_parrainage', { p_code: code }));
      enCours.set(cleRequete, requete);
      const terminer = () => { if (enCours.get(cleRequete) === requete) enCours.delete(cleRequete); };
      void requete.then(terminer, terminer);
    }
    const reporterEchec = () => {
      if (!actif) return;
      logger.error('fn_appliquer_parrainage : résultat non confirmé, code conservé');
      toast.warning('Le parrainage n’a pas pu être enregistré. Nous réessaierons à votre prochaine connexion.');
    };
    void requete.then(({ data, error }) => {
      if (!actif) return;
      const res = data as { success?: unknown; error?: unknown } | null;
      const succes = !error && res?.success === true;
      const refusDefinitif = !error && typeof res?.error === 'string' && REFUS_DEFINITIFS.has(res.error);
      if (!succes && !refusDefinitif) { reporterEchec(); return; }
      try {
        localStorage.setItem(cle, code);
        // Ne pas retirer un autre code reçu pendant l'appel.
        if (sessionStorage.getItem('jolene.parrainage_code')?.toUpperCase() === code) {
          sessionStorage.removeItem('jolene.parrainage_code');
        }
      } catch { /* Le stockage indisponible ne bloque pas la navigation. */ }
      if (succes) toast.success('Code de parrainage enregistré.');
    }, reporterEchec);
    return () => { actif = false; };
  }, [userId]);
}
