/**
 * « Pourquoi 85 ? » de la carte swipe, extrait de `CardMissionSwipe.tsx` pour
 * être partagé avec le port natif (vecteurs golden iOS, lot 4 W0). Règle pure.
 */

/** 7d — clés alignées sur le breakdown v3 (l'ancienne clé `fiabilite` ne
 *  matchait jamais : le backend émet `soignant_fiabilite`). */
export const RAISON_LABELS: Record<string, string> = {
  distance: 'proche de chez toi',
  tarif: 'bien payée vs le marché',
  horaire: 'à tes horaires préférés',
  etablissement: 'établissement bien noté',
  urgence: 'mission urgente',
  soignant_fiabilite: 'ton profil correspond',
  connaissance_etab: 'tu connais cet établissement',
  paiement_rapide: 'paiement rapide ⚡',
};

/** Raisons épinglées en priorité quand elles sont > 0 (bonus forts à faible
 *  valeur numérique — un tri par points les enterrerait). */
export const RAISONS_EPINGLEES = ['connaissance_etab', 'paiement_rapide'];

/** « Pourquoi 85 ? » → les 2 contributeurs les plus parlants, en clair. */
export function raisonsScore(breakdown: Record<string, unknown>): string {
  const b = breakdown || {};
  const epinglees = RAISONS_EPINGLEES.filter(
    (k) => typeof b[k] === 'number' && (b[k] as number) > 0,
  );
  const autres = Object.entries(b)
    .filter(([k, v]) => RAISON_LABELS[k] && !RAISONS_EPINGLEES.includes(k)
      && typeof v === 'number' && (v as number) > 0)
    .sort((a, bb) => (bb[1] as number) - (a[1] as number))
    .map(([k]) => k);
  return [...epinglees, ...autres].slice(0, 2).map((k) => RAISON_LABELS[k]).join(' · ');
}
