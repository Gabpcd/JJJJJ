import { PROFESSIONS } from '@/lib/constantes';

interface CriteresRecherchePublique { profession?: string; ville?: string }

export function lireCriteresInscription(params: URLSearchParams) {
  const profession = params.get('profession') || '';
  return {
    profession: PROFESSIONS.some(p => p.valeur === profession) ? profession : '',
    ville: (params.get('ville') || '').trim().slice(0, 120),
  };
}

export interface UtmInscription { source: string; medium: string; campaign: string; content?: string }

/** `campagne` (chaîne) = UTM landing historique ; un objet UtmInscription pose les 4 UTM explicitement. */
export function lienInscriptionRecherche(criteres: CriteresRecherchePublique, campagne?: string | UtmInscription) {
  const params = new URLSearchParams();
  if (criteres.profession) params.set('profession', criteres.profession);
  if (criteres.ville?.trim()) params.set('ville', criteres.ville.trim());
  if (typeof campagne === 'object' && campagne) {
    params.set('utm_source', campagne.source);
    params.set('utm_medium', campagne.medium);
    params.set('utm_campaign', campagne.campaign);
    if (campagne.content) params.set('utm_content', campagne.content);
  } else if (typeof campagne === 'string' && campagne) {
    params.set('utm_source', 'seo');
    params.set('utm_medium', 'landing');
    params.set('utm_campaign', campagne);
  }
  const query = params.toString();
  return `/inscription/soignant${query ? `?${query}` : ''}`;
}

/** Consommé par Explorer après l'inscription ; ne crée aucune alerte. */
export function memoriserRecherchePublique(criteres: CriteresRecherchePublique) {
  try {
    sessionStorage.setItem('jolene.filtres_a_appliquer', JSON.stringify({
      audience: 'SOIGNANT_RECHERCHE_MISSIONS',
      filtres: { profession: criteres.profession || '', villeRecherche: criteres.ville?.trim() || '' },
    }));
  } catch { /* Le lien conserve les critères si le stockage navigateur est indisponible. */ }
}
