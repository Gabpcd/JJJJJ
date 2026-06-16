/**
 * Session counter (Session G5).
 *
 * Compteur cumulatif du nombre de sessions de l'utilisateur, persistant dans
 * `localStorage`. Sert à séquencer les prompts non urgents (permission push,
 * bannière d'installation PWA) pour ne PAS les afficher dès la 1re session :
 * on les réserve à partir de la 2e session, quand l'intention d'usage est avérée.
 *
 * Mécanique :
 *  - `localStorage[jolene_session_count]` : compteur cumulatif (persiste entre sessions).
 *  - `sessionStorage[jolene_session_counted]` : drapeau « cette session a déjà été
 *    comptée », pour incrémenter UNE seule fois par session de navigateur (onglet),
 *    même si `App` se remonte (React StrictMode, navigations SPA, HMR).
 *  - Un drapeau module-level protège en plus contre un double appel dans le même
 *    cycle de vie du module.
 */

const COUNT_KEY = 'jolene_session_count';
const COUNTED_FLAG = 'jolene_session_counted';

let countedThisLoad = false;

/** Lecture sûre d'un entier depuis localStorage (0 si absent/illisible). */
function lireCompteur(): number {
  try {
    const brut = localStorage.getItem(COUNT_KEY);
    const n = brut ? parseInt(brut, 10) : 0;
    return Number.isFinite(n) && n >= 0 ? n : 0;
  } catch {
    return 0;
  }
}

/**
 * Incrémente le compteur de sessions au plus une fois par session navigateur.
 * À appeler une fois au démarrage de l'app (cf. LayoutApp).
 * Retourne le compteur courant (après éventuelle incrémentation).
 */
export function incrementerSession(): number {
  if (typeof window === 'undefined') return 0;

  // Déjà compté dans ce cycle de vie du module (StrictMode double-mount, etc.).
  if (countedThisLoad) return lireCompteur();

  try {
    // Déjà compté dans cette session navigateur (onglet) → on ne ré-incrémente pas.
    if (sessionStorage.getItem(COUNTED_FLAG)) {
      countedThisLoad = true;
      return lireCompteur();
    }
    const next = lireCompteur() + 1;
    localStorage.setItem(COUNT_KEY, String(next));
    sessionStorage.setItem(COUNTED_FLAG, '1');
    countedThisLoad = true;
    return next;
  } catch {
    // Stockage indisponible (mode privé strict) → on évite tout crash.
    countedThisLoad = true;
    return lireCompteur();
  }
}

/** Numéro de la session courante (sans incrémenter). */
export function getNumeroSession(): number {
  return lireCompteur();
}

/**
 * True si l'utilisateur en est à sa 2e session ou plus.
 * Garde-fou pour les prompts non urgents qui ne doivent pas s'afficher à la 1re visite.
 */
export function estSessionRecurrente(): boolean {
  return getNumeroSession() >= 2;
}
