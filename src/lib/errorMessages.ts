/**
 * Dictionnaire codes erreur Supabase/Postgres → messages français.
 * Sprint 8 PR 4 (chantier 4.2).
 *
 * Usage :
 *   const message = traduireErreur(err);
 *   afficherNotification({ type: 'erreur', message });
 */

type CodeErreur = string;

/** Map des codes Postgres/PostgREST/Supabase vers messages utilisateur. */
const MESSAGES_PAR_CODE: Record<CodeErreur, string> = {
  // Postgres SQLSTATE
  P0001: '', // raise message direct du raise, géré spécifiquement
  '23505': 'Cette donnée existe déjà.',
  '23503': 'Référence introuvable.',
  '23502': 'Champ obligatoire manquant.',
  '23514': 'Valeur incorrecte.',
  '42501': "Vous n'avez pas les permissions nécessaires pour cette action.",
  '42P01': 'Ressource introuvable.',
  '22P02': 'Format de donnée invalide.',
  '22001': 'Texte trop long.',
  '22003': 'Valeur numérique hors limite.',
  '22007': 'Format de date invalide.',
  // PostgREST
  PGRST116: 'Aucun résultat.',
  PGRST301: 'Session expirée, reconnectez-vous.',
  PGRST302: 'Authentification requise.',
  // Supabase Auth
  invalid_credentials: 'Email ou mot de passe incorrect.',
  email_not_confirmed: 'Email non confirmé. Vérifiez votre boîte de réception.',
  user_already_exists: 'Un compte existe déjà avec cet email.',
  weak_password: 'Mot de passe trop faible. 8 caractères minimum avec majuscule, chiffre, symbole.',
  over_email_send_rate_limit: 'Trop de tentatives. Réessayez dans quelques minutes.',
  // HTTP générique
  '401': 'Session expirée, reconnectez-vous.',
  '403': "Vous n'avez pas les permissions nécessaires.",
  '404': 'Ressource introuvable.',
  '429': 'Trop de tentatives. Attendez quelques minutes avant de réessayer.',
  '500': 'Erreur serveur. Réessayez dans un instant.',
  '502': 'Service temporairement indisponible. Réessayez.',
  '503': 'Connexion impossible. Vérifiez votre réseau et réessayez.',
  '504': 'Temps de réponse dépassé. Réessayez.',
  // Codes métier custom Jolene
  NON_AUTORISE: "Action non autorisée.",
  RESSOURCE_INTROUVABLE: 'Ressource introuvable.',
  ETAT_INVALIDE: "Cette action n'est pas possible dans l'état actuel.",
  DELAI_DEPASSE: 'Le délai pour cette action est dépassé.',
  RATE_LIMITE: 'Trop de tentatives. Réessayez plus tard.',
  CHAMPS_MANQUANTS: 'Champs obligatoires manquants.',
};

const MESSAGE_FALLBACK = 'Une erreur est survenue. Réessayez ou contactez le support.';

/**
 * Erreur Supabase typique :
 * {
 *   code: 'P0001',
 *   message: 'NON_AUTORISE',
 *   details: '...',
 *   hint: '...'
 * }
 *
 * Une erreur réseau :
 * Error('Failed to fetch') | { status: 503 }
 */
export function traduireErreur(erreur: unknown): string {
  if (!erreur) return MESSAGE_FALLBACK;

  const err = erreur as {
    code?: string;
    message?: string;
    error_code?: string;
    status?: number;
    name?: string;
  };

  // 1) error_code custom (RPC Jolene)
  if (err.error_code && MESSAGES_PAR_CODE[err.error_code]) {
    return MESSAGES_PAR_CODE[err.error_code];
  }

  // 2) code Postgres + raise P0001 → utiliser le message direct
  if (err.code === 'P0001' && err.message) {
    // Si le message correspond à un code custom, le traduire
    if (MESSAGES_PAR_CODE[err.message]) {
      return MESSAGES_PAR_CODE[err.message];
    }
    return err.message;
  }

  // 3) code Postgres standard
  if (err.code && MESSAGES_PAR_CODE[err.code]) {
    return MESSAGES_PAR_CODE[err.code];
  }

  // 4) HTTP status
  if (err.status && MESSAGES_PAR_CODE[String(err.status)]) {
    return MESSAGES_PAR_CODE[String(err.status)];
  }

  // 5) Erreur réseau (TypeError: Failed to fetch)
  if (
    err.name === 'TypeError' &&
    err.message &&
    /fetch|network|load failed/i.test(err.message)
  ) {
    return MESSAGES_PAR_CODE['503'];
  }

  // 6) Message brut (en dernier recours, limité)
  if (err.message && typeof err.message === 'string' && err.message.length < 200) {
    return err.message;
  }

  return MESSAGE_FALLBACK;
}

/**
 * Indique si une erreur est de type réseau / 5xx — éligible au retry automatique.
 */
export function estErreurReseau(erreur: unknown): boolean {
  if (!erreur) return false;
  const err = erreur as { status?: number; name?: string; message?: string };
  if (err.status && err.status >= 500 && err.status < 600) return true;
  if (
    err.name === 'TypeError' &&
    err.message &&
    /fetch|network|load failed/i.test(err.message)
  ) {
    return true;
  }
  return false;
}
