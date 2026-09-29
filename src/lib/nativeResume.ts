export const ABSENCE_LONGUE_MS = 30 * 60_000;
let derniereNavigationExterne = 0;

/** Notifications and deep links take priority over the routine resume route. */
export function signalerNavigationNative(): void { derniereNavigationExterne = Date.now(); }
export function navigationNativeRecente(now = Date.now()): boolean { return derniereNavigationExterne > 0 && now >= derniereNavigationExterne && now - derniereNavigationExterne < 10_000; }

export function routeProtegeeAuRetour(pathname: string, search: string, hash: string): boolean {
  return /^\/(auth|connexion|inscription|mot-de-passe|reinitialiser|contrat)(\/|$)/.test(pathname)
    || /(?:callback|stripe|paiement|signature|pointage)/.test(pathname)
    || /(?:code|token|session_id|payment_intent|setup_intent|success|refresh|return)=/.test(search)
    || /(?:access_token|refresh_token|type=recovery)/.test(hash);
}

export function dashboardPourRole(role: unknown, parcours?: { type_compte?: string } | null): string | null {
  if (role === 'SOIGNANT' || (role === 'INCONNU' && parcours?.type_compte === 'SOIGNANT')) return '/soignant/tableau-de-bord';
  if (role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT' || (role === 'INCONNU' && parcours?.type_compte === 'ETABLISSEMENT')) return '/etablissement/tableau-de-bord';
  if (role === 'ADMIN_GROUPE') return '/groupe/tableau-de-bord';
  if (role === 'ADMIN_PLATEFORME' || role === 'ADMIN') return '/admin';
  return null;
}
