/**
 * Code machine-readable retourné par les edge functions ou détecté à partir
 * d'une AuthApiError Supabase / d'une exception réseau. Stable, machine-friendly.
 */
export type CodeErreurInscription =
  | 'USER_ALREADY_REGISTERED'
  | 'EMAIL_RATE_LIMIT'
  | 'INVALID_EMAIL'
  | 'WEAK_PASSWORD'
  | 'RPPS_FORMAT_INVALID'
  | 'RPPS_NOT_FOUND'
  | 'RPPS_TRAITS_MISMATCH'
  | 'RPPS_PROFESSION_MISMATCH'
  | 'RPPS_ALREADY_REGISTERED'
  | 'RPPS_API_UNAVAILABLE'
  | 'SIRET_FORMAT_INVALID'
  | 'SIRET_CHECKSUM_INVALID'
  | 'SIRET_ALREADY_REGISTERED'
  | 'MISSING_REQUIRED_FIELDS'
  | 'UNDERAGE'
  | 'CAPTCHA_FAILED'
  | 'RATE_LIMITED'
  | 'UNAUTHORIZED'
  | 'INVALID_TOKEN'
  | 'ACCOUNT_TYPE_MISMATCH'
  | 'ACCOUNT_ALREADY_REGISTERED'
  | 'ACCOUNT_REGISTRATION_IN_PROGRESS'
  | 'ACCOUNT_PROFILE_CONFLICT'
  | 'ACCOUNT_REGISTRATION_INCOMPLETE'
  | 'ACCOUNT_AUTH_INACTIVE'
  | 'ACCOUNT_RESERVATION_UNAVAILABLE'
  | 'NETWORK_ERROR'
  | 'INTERNAL_ERROR'
  | 'UNKNOWN';

/** Action proposée à l'utilisateur dans le composant ErreurInscription. */
export type ActionErreur =
  | 'reconnexion'
  | 'retry'
  | 'support'
  | 'highlight_rpps'
  | 'highlight_traits'
  | 'highlight_email'
  | 'highlight_password'
  | 'highlight_siret';

export interface ErreurInscriptionMappee {
  code: CodeErreurInscription;
  message: string;
  action?: ActionErreur;
  champs_highlight?: string[];
  details?: Record<string, unknown>;
}

/**
 * Mappe une erreur reçue côté frontend (réponse edge function structurée,
 * AuthApiError Supabase, ou TypeError réseau) en message utilisateur clair
 * + action proposée.
 *
 * Stratégie en cascade :
 *   1. Lire `code` machine-readable (format edge function structurée).
 *   2. Sinon, matcher sur le pattern de message Supabase Auth.
 *   3. Sinon, détecter les erreurs réseau natives (TypeError "Failed to fetch").
 *   4. Fallback générique avec lien support.
 */
export function mapperErreurInscription(err: any): ErreurInscriptionMappee {
  // Cas 1 : réponse edge function avec champ `code` (nouveau format).
  const codeMachine: string | undefined =
    err?.code ?? err?.body?.code ?? err?.context?.code ?? undefined;
  const messageBackend: string | undefined =
    err?.message ?? err?.body?.message ?? err?.body?.error ?? err?.error ?? undefined;
  const detailsBackend = (err?.details ?? err?.body?.details) as Record<string, unknown> | undefined;

  if (codeMachine && estCodeConnu(codeMachine)) {
    return enrichirParCode(codeMachine as CodeErreurInscription, messageBackend, detailsBackend);
  }

  // Cas 2 : AuthApiError Supabase — message texte à matcher.
  const msgRaw: string = String(err?.message ?? err?.error_description ?? err ?? '');
  const msgLower = msgRaw.toLowerCase();

  if (msgLower.includes('user already registered') || msgLower.includes('already registered')) {
    return {
      code: 'USER_ALREADY_REGISTERED',
      message: 'Un compte existe déjà avec cet email. Voulez-vous vous connecter ?',
      action: 'reconnexion',
    };
  }
  if (msgLower.includes('email rate limit') || msgLower.includes('only request this once every')) {
    return {
      code: 'EMAIL_RATE_LIMIT',
      message: 'Trop de tentatives récentes. Veuillez réessayer dans quelques minutes.',
      action: 'retry',
    };
  }
  if (msgLower.includes('invalid email') || msgLower.includes('email_address_invalid')) {
    return {
      code: 'INVALID_EMAIL',
      message: 'L\'adresse email saisie n\'est pas valide.',
      action: 'highlight_email',
      champs_highlight: ['email'],
    };
  }
  const matchPwdLen = msgRaw.match(/Password should be at least (\d+) characters?/i);
  if (matchPwdLen) {
    const n = matchPwdLen[1];
    return {
      code: 'WEAK_PASSWORD',
      message: `Le mot de passe doit contenir au moins ${n} caractères.`,
      action: 'highlight_password',
      champs_highlight: ['motDePasse'],
    };
  }
  if (msgLower.includes('weak_password') || msgLower.includes('password is too short') || msgLower.includes('password should')) {
    return {
      code: 'WEAK_PASSWORD',
      message: 'Mot de passe trop faible. Utilisez au moins 8 caractères avec majuscules, minuscules, chiffres et caractères spéciaux.',
      action: 'highlight_password',
      champs_highlight: ['motDePasse'],
    };
  }
  if (msgLower.includes('captcha')) {
    return {
      code: 'CAPTCHA_FAILED',
      message: 'La vérification anti-bot a échoué. Rafraîchissez la page et réessayez.',
      action: 'retry',
    };
  }

  // Cas 3 : erreur réseau native.
  if (
    msgLower.includes('failed to fetch') ||
    msgLower.includes('networkerror') ||
    msgLower.includes('network request failed') ||
    err?.name === 'TypeError'
  ) {
    return {
      code: 'NETWORK_ERROR',
      message: 'Connexion internet instable. Vérifiez votre connexion et réessayez.',
      action: 'retry',
    };
  }

  // Cas 4 : duplicate key Supabase (409 sur INSERT direct, sans passer par
  // les edge functions — par exemple un RLS qui contient encore un message
  // duplicate key).
  if (msgLower.includes('duplicate key value violates unique constraint')) {
    if (msgLower.includes('email')) {
      return {
        code: 'USER_ALREADY_REGISTERED',
        message: 'Un compte existe déjà avec cet email. Voulez-vous vous connecter ?',
        action: 'reconnexion',
      };
    }
    if (msgLower.includes('siret')) {
      return {
        code: 'SIRET_ALREADY_REGISTERED',
        message: 'Ce numéro SIRET est déjà enregistré.',
        action: 'highlight_siret',
        champs_highlight: ['siret'],
      };
    }
  }

  // Cas 5 : fallback générique.
  if (import.meta.env.DEV && msgRaw) {
    return { code: 'UNKNOWN', message: `Erreur: ${msgRaw}`, action: 'support' };
  }
  return {
    code: 'UNKNOWN',
    message: 'Une erreur inattendue est survenue. Réessayez ou contactez le support.',
    action: 'support',
  };
}

const CODES_CONNUS = new Set<string>([
  'USER_ALREADY_REGISTERED', 'EMAIL_RATE_LIMIT', 'INVALID_EMAIL', 'WEAK_PASSWORD',
  'RPPS_FORMAT_INVALID', 'RPPS_NOT_FOUND', 'RPPS_TRAITS_MISMATCH', 'RPPS_API_UNAVAILABLE',
  'RPPS_ALREADY_REGISTERED', 'RPPS_PROFESSION_MISMATCH',
  'SIRET_FORMAT_INVALID', 'SIRET_CHECKSUM_INVALID', 'SIRET_ALREADY_REGISTERED',
  'MISSING_REQUIRED_FIELDS', 'UNDERAGE', 'CAPTCHA_FAILED', 'RATE_LIMITED',
  'UNAUTHORIZED', 'INVALID_TOKEN', 'NETWORK_ERROR', 'INTERNAL_ERROR',
  'ACCOUNT_TYPE_MISMATCH', 'ACCOUNT_ALREADY_REGISTERED',
  'ACCOUNT_REGISTRATION_IN_PROGRESS', 'ACCOUNT_PROFILE_CONFLICT',
  'ACCOUNT_REGISTRATION_INCOMPLETE', 'ACCOUNT_AUTH_INACTIVE',
  'ACCOUNT_RESERVATION_UNAVAILABLE',
]);

function estCodeConnu(code: string): boolean {
  return CODES_CONNUS.has(code);
}

/**
 * Codes d'erreur d'inscription correspondant à un REFUS MÉTIER ATTENDU (saisie
 * utilisateur invalide), PAS à un bug applicatif. L'utilisateur voit déjà un
 * message clair côté UI ; ces cas ne doivent donc PAS créer d'issue d'erreur
 * dans Sentry (sinon le feed se remplit de faux positifs : RPPS introuvable,
 * SIRET déjà pris, captcha oublié, mot de passe trop faible…).
 *
 * Exclus volontairement (= on continue à les remonter, ce sont de vraies
 * anomalies infra/serveur) : RPPS_API_UNAVAILABLE, UNAUTHORIZED, INVALID_TOKEN,
 * NETWORK_ERROR, INTERNAL_ERROR.
 */
export const CODES_REFUS_ATTENDU_INSCRIPTION = new Set<string>([
  'USER_ALREADY_REGISTERED', 'EMAIL_RATE_LIMIT', 'INVALID_EMAIL', 'WEAK_PASSWORD',
  'RPPS_FORMAT_INVALID', 'RPPS_NOT_FOUND', 'RPPS_TRAITS_MISMATCH',
  'RPPS_ALREADY_REGISTERED', 'RPPS_PROFESSION_MISMATCH',
  'SIRET_FORMAT_INVALID', 'SIRET_CHECKSUM_INVALID', 'SIRET_ALREADY_REGISTERED',
  'MISSING_REQUIRED_FIELDS', 'UNDERAGE', 'CAPTCHA_FAILED', 'RATE_LIMITED',
  'ACCOUNT_TYPE_MISMATCH', 'ACCOUNT_ALREADY_REGISTERED',
  'ACCOUNT_REGISTRATION_IN_PROGRESS',
]);

/** True si le code est un refus métier attendu (pas un bug → pas d'issue Sentry). */
export function estRefusInscriptionAttendu(code: unknown): boolean {
  return typeof code === 'string' && CODES_REFUS_ATTENDU_INSCRIPTION.has(code);
}

function enrichirParCode(
  code: CodeErreurInscription,
  messageBackend: string | undefined,
  details: Record<string, unknown> | undefined,
): ErreurInscriptionMappee {
  const champsManquants = Array.isArray(details?.champs_manquants) ? (details!.champs_manquants as string[]) : [];

  switch (code) {
    case 'USER_ALREADY_REGISTERED':
    case 'ACCOUNT_ALREADY_REGISTERED':
      return {
        code,
        message: messageBackend || 'Un compte existe déjà avec cet email. Voulez-vous vous connecter ?',
        action: 'reconnexion',
      };
    case 'ACCOUNT_TYPE_MISMATCH':
      return {
        code,
        message: messageBackend || 'Cette adresse est déjà associée à un autre espace Jolene.',
        action: 'support',
      };
    case 'ACCOUNT_REGISTRATION_IN_PROGRESS':
      return {
        code,
        message: messageBackend || 'Une inscription est déjà en cours. Patientez quelques instants puis réessayez.',
        action: 'retry',
      };
    case 'ACCOUNT_PROFILE_CONFLICT':
    case 'ACCOUNT_REGISTRATION_INCOMPLETE':
      return {
        code,
        message: messageBackend || 'Votre compte nécessite une vérification. Contactez le support Jolene.',
        action: 'support',
      };
    case 'ACCOUNT_AUTH_INACTIVE':
      return {
        code,
        message: messageBackend || 'Ce compte est inactif. Reconnectez-vous ou contactez le support.',
        action: 'reconnexion',
      };
    case 'ACCOUNT_RESERVATION_UNAVAILABLE':
      return {
        code,
        message: messageBackend || 'Inscription momentanément indisponible. Réessayez dans quelques minutes.',
        action: 'retry',
      };
    case 'EMAIL_RATE_LIMIT':
      return {
        code,
        message: messageBackend || 'Trop de tentatives récentes. Veuillez réessayer dans quelques minutes.',
        action: 'retry',
      };
    case 'INVALID_EMAIL':
      return {
        code,
        message: messageBackend || 'L\'adresse email saisie n\'est pas valide.',
        action: 'highlight_email',
        champs_highlight: ['email'],
      };
    case 'WEAK_PASSWORD':
      return {
        code,
        message: messageBackend || 'Mot de passe trop faible. Utilisez au moins 8 caractères.',
        action: 'highlight_password',
        champs_highlight: ['motDePasse'],
      };
    case 'RPPS_FORMAT_INVALID':
      return {
        code,
        message: messageBackend || 'Le numéro RPPS saisi est invalide. Vérifiez qu\'il contient bien 11 chiffres.',
        action: 'highlight_rpps',
        champs_highlight: ['rpps'],
      };
    case 'RPPS_NOT_FOUND':
      return {
        code,
        message: messageBackend || 'Aucun professionnel trouvé avec ce numéro RPPS dans l\'Annuaire Santé.',
        action: 'highlight_rpps',
        champs_highlight: ['rpps'],
      };
    case 'RPPS_TRAITS_MISMATCH':
      return {
        code,
        message: messageBackend || 'Les informations saisies ne correspondent pas au numéro RPPS. Vérifiez votre nom, prénom et date de naissance.',
        action: 'highlight_traits',
        champs_highlight: ['nom', 'prenom', 'dateNaissance'],
      };
    case 'RPPS_ALREADY_REGISTERED':
      return {
        code,
        message: messageBackend || 'Ce numéro RPPS est déjà associé à un compte Jolene. Connectez-vous à ce compte, ou contactez le support si ce n\'est pas vous.',
        action: 'reconnexion',
        champs_highlight: ['rpps'],
      };
    case 'RPPS_PROFESSION_MISMATCH':
      return {
        code,
        message: messageBackend || 'Ce numéro RPPS correspond à une autre profession que celle déclarée. Vérifiez votre RPPS ou la profession choisie.',
        action: 'highlight_rpps',
        champs_highlight: ['rpps', 'profession'],
      };
    case 'RPPS_API_UNAVAILABLE':
      return {
        code,
        message: messageBackend || 'Impossible de vérifier le RPPS pour le moment. Réessayez dans quelques minutes ou contactez le support.',
        action: 'retry',
      };
    case 'SIRET_FORMAT_INVALID':
    case 'SIRET_CHECKSUM_INVALID':
      return {
        code,
        message: messageBackend || 'Le SIRET saisi est invalide.',
        action: 'highlight_siret',
        champs_highlight: ['siret'],
      };
    case 'SIRET_ALREADY_REGISTERED':
      return {
        code,
        message: messageBackend || 'Ce numéro SIRET est déjà enregistré.',
        action: 'highlight_siret',
        champs_highlight: ['siret'],
      };
    case 'MISSING_REQUIRED_FIELDS':
      return {
        code,
        message: messageBackend || 'Certains champs obligatoires sont manquants.',
        action: champsManquants.length > 0 ? 'highlight_traits' : undefined,
        champs_highlight: champsManquants,
      };
    case 'UNDERAGE':
      return {
        code,
        message: messageBackend || 'Vous devez avoir au moins 18 ans pour vous inscrire.',
        action: 'highlight_traits',
        champs_highlight: ['dateNaissance'],
      };
    case 'CAPTCHA_FAILED':
      return {
        code,
        message: messageBackend || 'La vérification anti-bot a échoué. Rafraîchissez la page et réessayez.',
        action: 'retry',
      };
    case 'RATE_LIMITED':
      return {
        code,
        message: messageBackend || 'Trop de tentatives. Réessayez dans quelques minutes.',
        action: 'retry',
      };
    case 'UNAUTHORIZED':
    case 'INVALID_TOKEN':
      return {
        code,
        message: messageBackend || 'Session invalide. Reconnectez-vous et réessayez.',
        action: 'reconnexion',
      };
    case 'INTERNAL_ERROR':
      return {
        code,
        message: messageBackend || 'Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes.',
        action: 'support',
      };
    case 'NETWORK_ERROR':
      return {
        code,
        message: messageBackend || 'Connexion internet instable. Vérifiez votre connexion et réessayez.',
        action: 'retry',
      };
    default:
      return {
        code: 'UNKNOWN',
        message: messageBackend || 'Une erreur inattendue est survenue.',
        action: 'support',
      };
  }
}

/**
 * Intercepte et traduit TOUTES les erreurs Supabase en français.
 *
 * NOTE : pour les erreurs d'inscription, préférer mapperErreurInscription()
 * qui retourne aussi un code machine-readable + une action proposée.
 * Cette fonction reste pour les autres flows (paiements, missions, etc.)
 * qui ne dépendent pas de codes structurés.
 */
export function extraireMessageErreur(error: any): string {
  if (!error) return '';
  const msg = error.message || error.details || error.hint || '';

  // Si c'est une erreur structurée d'inscription, déléguer.
  if (error?.code && CODES_CONNUS.has(error.code)) {
    return mapperErreurInscription(error).message;
  }

  // Trigger messages in French: surface them directly to the user
  const TRIGGER_PREFIXES = ['Impossible', 'Ce soignant', 'Le taux', 'Pointage trop', 'Le départ', 'Le délai', 'Vous avez', 'En tant que', 'Une pharmacie', 'La profession', 'Le type d'];
  for (const prefix of TRIGGER_PREFIXES) {
    if (msg.includes(prefix)) {
      const escapedPrefixes = TRIGGER_PREFIXES.map(p => p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|');
      const clean = msg.replace(new RegExp(`^.*?(?=${escapedPrefixes})`, 's'), '').trim();
      return clean;
    }
  }

  if (msg.includes('[CODE DU TRAVAIL]')) {
    const match = msg.match(/\[CODE DU TRAVAIL\]\s*(.+)/);
    return match ? match[1].trim() : msg;
  }

  if (msg.includes('[SÉCURITÉ]')) {
    const match = msg.match(/\[SÉCURITÉ\]\s*(.+)/);
    return match ? match[1].trim() : msg;
  }

  const traductions: Record<string, string> = {
    'Invalid login credentials': 'Email ou mot de passe incorrect.',
    'Email not confirmed': 'Veuillez confirmer votre adresse email avant de vous connecter.',
    'User already registered': 'Un compte existe déjà avec cette adresse email.',
    'Signup requires a valid password': 'Le mot de passe n\'est pas valide.',
    'Password should be at least': 'Mot de passe trop court : il doit contenir au moins 8 caractères.',
    'Password is too short': 'Mot de passe trop court : il doit contenir au moins 8 caractères.',
    'weak_password': 'Mot de passe trop faible. Utilisez au moins 8 caractères avec majuscules, minuscules, chiffres et caractères spéciaux.',
    'Password should contain': 'Mot de passe trop faible : ajoutez majuscules, minuscules, chiffres et caractères spéciaux (8+ caractères).',
    'Password should be one of the following': 'Mot de passe trop faible : ajoutez majuscules, minuscules, chiffres et caractères spéciaux (8+ caractères).',
    'pwned': 'Ce mot de passe a été compromis dans une fuite de données connue. Choisissez-en un autre.',
    'Email rate limit exceeded': 'Trop de tentatives. Veuillez patienter quelques minutes.',
    'For security purposes, you can only request this once every 60 seconds': 'Pour des raisons de sécurité, veuillez patienter 60 secondes.',
    'captcha verification process failed': 'La vérification anti-bot a échoué. Rafraîchissez la page et réessayez.',
    'captcha protection: request disallowed': 'La vérification anti-bot a échoué. Rafraîchissez la page et réessayez.',
  };

  for (const [en, fr] of Object.entries(traductions)) {
    if (msg.toLowerCase().includes(en.toLowerCase())) return fr;
  }

  // Supabase peut renvoyer un code d'erreur structuré
  const errorCode = (error as any)?.code || (error as any)?.error_code || '';
  if (errorCode === 'weak_password' || errorCode === 'invalid_password') {
    return 'Mot de passe trop faible. Utilisez au moins 8 caractères avec majuscules, minuscules, chiffres et caractères spéciaux.';
  }

  if (msg.includes('duplicate key value violates unique constraint')) {
    if (msg.includes('siret')) return 'Ce numéro SIRET est déjà enregistré.';
    if (msg.includes('email')) return 'Cette adresse email est déjà utilisée.';
    if (msg.includes('finess')) return 'Ce numéro FINESS est déjà enregistré.';
    if (msg.includes('numero_rpps')) return 'Ce numéro RPPS est déjà enregistré.';
    return 'Cette valeur existe déjà dans le système.';
  }
  if (msg.includes('violates check constraint')) {
    return 'La valeur saisie est hors des limites autorisées.';
  }
  if (msg.includes('violates foreign key constraint')) {
    return 'Référence vers un élément inexistant.';
  }
  if (msg.includes('new row violates row-level security policy')) {
    return 'Vous n\'avez pas les droits nécessaires pour cette action.';
  }

  if (msg.includes('Failed to fetch') || msg.includes('NetworkError')) {
    return 'Erreur de connexion. Vérifiez votre accès internet.';
  }

  // En dev uniquement, afficher le message brut pour le debug
  if (import.meta.env.DEV && msg) {
    return `Erreur: ${msg}`;
  }

  return 'Une erreur est survenue. Veuillez réessayer.';
}

/**
 * Extrait le payload JSON d'une réponse edge function, même quand la fn
 * a retourné un status HTTP >= 400 (supabase-js v2 met alors `data=null`
 * et `error.context` = Response object avec le body JSON).
 *
 * Retourne un objet combiné { error, message, code, ... } ou null si aucun
 * payload exploitable n'est disponible.
 */
export async function extraireErreurEdgeFn(data: any, error: any): Promise<Record<string, any> | null> {
  if (data && typeof data === 'object') return data;
  if (!error) return null;
  const ctx = (error as any)?.context;
  if (!ctx) return null;
  try {
    if (typeof ctx.json === 'function') {
      return await ctx.clone().json();
    }
    if (typeof ctx.text === 'function') {
      const txt = await ctx.clone().text();
      try { return JSON.parse(txt); } catch { return { message: txt }; }
    }
  } catch {
    /* ignore */
  }
  return null;
}

/**
 * Message d'erreur LISIBLE pour un appel supabase.functions.invoke.
 * Le SDK renvoie un message générique « Edge Function returned a non-2xx status
 * code » quand la fonction répond en 4xx/5xx — le vrai message est dans
 * `error.context` (le body). Ce helper l'extrait et retombe sur un fallback clair.
 * À utiliser partout où on téléverse/vérifie un document.
 */
export async function messageErreurEdgeFn(
  error: any,
  fallback = 'Une erreur est survenue. Veuillez réessayer.',
): Promise<string> {
  const body = await extraireErreurEdgeFn(null, error);
  const msg = body?.error || body?.message || body?.motif;
  if (msg && typeof msg === 'string') return msg;
  const raw = (error as any)?.message || '';
  return raw && !raw.includes('non-2xx') ? raw : fallback;
}

export function estBlocageCodeTravail(error: any): boolean {
  const msg = error?.message || '';
  return msg.includes('[CODE DU TRAVAIL]');
}

export function extraireArticleLoi(error: any): string | null {
  const msg = error?.message || '';
  const match = msg.match(/\(Art\.\s*([^)]+)\)/);
  return match ? `Art. ${match[1]}` : null;
}
