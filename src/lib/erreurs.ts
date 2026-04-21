/**
 * Intercepte et traduit TOUTES les erreurs Supabase en français.
 */
export function extraireMessageErreur(error: any): string {
  if (!error) return '';
  const msg = error.message || error.details || error.hint || '';

  // Trigger messages in French: surface them directly to the user
  const TRIGGER_PREFIXES = ['Impossible', 'Ce soignant', 'Le taux', 'Pointage trop', 'Le départ', 'Le délai', 'Vous avez', 'En tant que', 'Une pharmacie'];
  for (const prefix of TRIGGER_PREFIXES) {
    if (msg.includes(prefix)) {
      // Extract the meaningful part after any Postgres wrapper
      const clean = msg.replace(/^.*?(?=Impossible|Ce soignant|Le taux|Pointage trop|Le départ|Le délai|Vous avez|En tant que|Une pharmacie)/, '').trim();
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
    'Password should be at least 6 characters': 'Le mot de passe doit contenir au moins 8 caractères.',
    'Email rate limit exceeded': 'Trop de tentatives. Veuillez patienter quelques minutes.',
    'For security purposes, you can only request this once every 60 seconds': 'Pour des raisons de sécurité, veuillez patienter 60 secondes.',
  };

  for (const [en, fr] of Object.entries(traductions)) {
    if (msg.toLowerCase().includes(en.toLowerCase())) return fr;
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
 * Retourne un objet combiné { error, message, ... } ou null si aucun
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

export function estBlocageCodeTravail(error: any): boolean {
  const msg = error?.message || '';
  return msg.includes('[CODE DU TRAVAIL]');
}

export function extraireArticleLoi(error: any): string | null {
  const msg = error?.message || '';
  const match = msg.match(/\(Art\.\s*([^)]+)\)/);
  return match ? `Art. ${match[1]}` : null;
}
