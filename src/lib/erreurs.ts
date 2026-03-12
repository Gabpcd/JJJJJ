/**
 * Intercepte et traduit TOUTES les erreurs Supabase en français.
 */
export function extraireMessageErreur(error: any): string {
  if (!error) return '';
  const msg = error.message || error.details || error.hint || '';

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

export function estBlocageCodeTravail(error: any): boolean {
  const msg = error?.message || '';
  return msg.includes('[CODE DU TRAVAIL]');
}

export function extraireArticleLoi(error: any): string | null {
  const msg = error?.message || '';
  const match = msg.match(/\(Art\.\s*([^)]+)\)/);
  return match ? `Art. ${match[1]}` : null;
}
